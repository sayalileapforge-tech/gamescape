// functions/src/index.ts
import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import {
  onDocumentWritten,
  type FirestoreEvent,
  type Change,
  type DocumentSnapshot,
} from "firebase-functions/v2/firestore";

if (!admin.apps.length) admin.initializeApp();

const db = admin.firestore();

/* ------------------------------ Helpers ------------------------------ */

type RoundingMode = "actual" | "30" | "60";
type PaxMode = "single" | "multi";

/**
 * Compute bill numbers for a session doc:
 * - Reads seat_changes, orders, and seat pricing fields.
 * - Clamps playtime to planned end.
 * - Rounds per roundingMode ("actual" | "30" | "60").
 * - Supports single/multi pricing if present; falls back to ratePerHour.
 */
async function computeBillForSession(args: {
  branchId: string;
  sessionId: string;
  roundingMode?: RoundingMode; // default "actual"
  paxMode?: PaxMode;           // default "single"
  discount?: number;           // ₹
  taxPercent?: number;         // %
}) {
  const {
    branchId,
    sessionId,
    roundingMode = "actual",
    paxMode = "single",
    discount = 0,
    taxPercent = 0,
  } = args;

  const sessRef = db.collection("branches").doc(branchId).collection("sessions").doc(sessionId);
  const sessSnap = await sessRef.get();
  if (!sessSnap.exists) throw new HttpsError("not-found", "Session not found");

  const s = sessSnap.data() as any;

  const start: admin.firestore.Timestamp | undefined = s.startTime;
  const durationMinutes: number = (s.durationMinutes ?? 0) as number;
  const status: string = (s.status ?? "reserved") as string;

  if (!start) throw new HttpsError("failed-precondition", "Session has no start time");
  if (status !== "active" && status !== "completed") {
    // we allow finalizing for overdue-active or already-completed (with zero bill)
  }

  const plannedEndMs = start.toMillis() + durationMinutes * 60 * 1000;
  const nowMs = Date.now();
  const clampTo = (ms: number) => Math.min(ms, plannedEndMs);

  // Build raw seat segments (start → seat_changes → now)
  const changes = await sessRef.collection("seat_changes").orderBy("changedAt").get();

  type Seg = { seatId?: string; fromMs: number; toMs: number };
  const segments: Seg[] = [];
  let fromMs = start.toMillis();
  let seatId: string | undefined = s.seatId;

  if (changes.empty) {
    segments.push({ seatId, fromMs, toMs: clampTo(nowMs) });
  } else {
    for (const ch of changes.docs) {
      const d = ch.data() as any;
      const changedAt: admin.firestore.Timestamp | undefined = d.changedAt;
      if (!changedAt) continue;
      const changeMs = clampTo(changedAt.toMillis());
      segments.push({ seatId, fromMs, toMs: changeMs });
      fromMs = changeMs;
      seatId = d.toSeatId;
    }
    segments.push({ seatId, fromMs, toMs: clampTo(nowMs) });
  }

  // Load orders
  const ordersSnap = await sessRef.collection("orders").get();
  let ordersTotal = 0;
  for (const doc of ordersSnap.docs) {
    const d = doc.data() as any;
    const price: number = Number(d.price ?? 0);
    const qty: number = Math.max(1, Number(d.qty ?? 1));
    const explicitTotal = d.total;
    const lineTotal =
      typeof explicitTotal === "number"
        ? explicitTotal
        : typeof explicitTotal === "string"
          ? Number(explicitTotal) || price * qty
          : price * qty;
    ordersTotal += lineTotal;
  }

  // Reduce segments → seat subtotal
  let playedMinutes = 0;
  let seatSubtotal = 0;

  for (const seg of segments) {
    const minutesActual = Math.max(0, Math.floor((seg.toMs - seg.fromMs) / 60000));
    if (minutesActual <= 0) continue;

    const billedMinutes =
      roundingMode === "30" ? 30 : roundingMode === "60" ? 60 : minutesActual;

    playedMinutes += minutesActual;

    // read seat pricing
    let ratePerHour = 0;
    if (seg.seatId) {
      const seatSnap = await db
        .collection("branches")
        .doc(branchId)
        .collection("seats")
        .doc(seg.seatId)
        .get();
      const sd = seatSnap.data() as any | undefined;

      // Prefer 30/60 single/multi if available
      if (roundingMode === "30") {
        if (paxMode === "multi" && sd?.rate30Multi != null) {
          seatSubtotal += Number(sd.rate30Multi);
          continue;
        }
        if (paxMode === "single" && sd?.rate30Single != null) {
          seatSubtotal += Number(sd.rate30Single);
          continue;
        }
      }
      if (roundingMode === "60") {
        if (paxMode === "multi" && sd?.rate60Multi != null) {
          seatSubtotal += Number(sd.rate60Multi);
          continue;
        }
        if (paxMode === "single" && sd?.rate60Single != null) {
          seatSubtotal += Number(sd.rate60Single);
          continue;
        }
      }

      // Fallback to ratePerHour * (billed/60)
      ratePerHour = Number(sd?.ratePerHour ?? 0);
    }

    seatSubtotal += ratePerHour * (billedMinutes / 60);
  }

  // Totals
  const subtotalBeforeTax = Math.max(0, seatSubtotal + ordersTotal - (discount || 0));
  const taxAmount = subtotalBeforeTax * ((taxPercent || 0) / 100);
  const grandTotal = subtotalBeforeTax + taxAmount;

  return {
    playedMinutes,
    seatSubtotal,
    ordersTotal,
    subtotal: subtotalBeforeTax,
    discount: discount || 0,
    taxPercent: taxPercent || 0,
    taxAmount,
    billAmount: grandTotal,
  };
}

/**
 * Finalize a session bill (write the computed fields + close metadata).
 * Safe to call on active-overdue or completed-without-bill sessions.
 */
async function finalizeSessionBilling(args: {
  branchId: string;
  sessionId: string;
  roundingMode?: RoundingMode;
  paxMode?: PaxMode;
  discount?: number;
  taxPercent?: number;
  paymentStatus?: "pending" | "paid";
  closedByUid?: string;
}) {
  const {
    branchId,
    sessionId,
    roundingMode,
    paxMode,
    discount,
    taxPercent,
    paymentStatus = "pending",
    closedByUid,
  } = args;

  const totals = await computeBillForSession({
    branchId,
    sessionId,
    roundingMode,
    paxMode,
    discount,
    taxPercent,
  });

  const sessRef = db.collection("branches").doc(branchId).collection("sessions").doc(sessionId);

  const invoiceNumber = (() => {
    const now = new Date();
    const pad2 = (n: number) => String(n).padStart(2, "0");
    const tail = String(now.getTime() % 100000).padStart(5, "0");
    return `INV-${now.getFullYear()}${pad2(now.getMonth() + 1)}${pad2(now.getDate())}-${tail}`;
  })();

  const update: Record<string, any> = {
    status: "completed",
    paymentStatus,
    closedAt: admin.firestore.FieldValue.serverTimestamp(),
    invoiceNumber,
    playedMinutes: totals.playedMinutes,
    subtotal: totals.subtotal,
    discount: totals.discount,
    taxPercent: totals.taxPercent,
    taxAmount: totals.taxAmount,
    billAmount: totals.billAmount,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (closedByUid) {
    update["closedBy"] = closedByUid;
  }

  await sessRef.set(update, { merge: true });
  return totals;
}

/* --------------------- 1) Scheduler: auto-close + bill --------------------- */
export const autoCloseOverdueSessions = onSchedule(
  { schedule: "every 10 minutes", timeZone: "Asia/Kolkata", region: "asia-south1" },
  async () => {
    const now = admin.firestore.Timestamp.now();
    const snap = await db.collectionGroup("sessions").where("status", "==", "active").get();

    for (const doc of snap.docs) {
      const data = doc.data() as any;
      const start = data.startTime as admin.firestore.Timestamp | undefined;
      const mins = Number(data.durationMinutes ?? 0);
      if (!start) continue;

      const endMs = start.toMillis() + mins * 60 * 1000;
      if (now.toMillis() <= endMs) continue;

      // derive branchId/sessionId from path: branches/{branchId}/sessions/{sessionId}
      const parts = doc.ref.path.split("/");
      const branchIdx = parts.indexOf("branches");
      const sessionsIdx = parts.indexOf("sessions");
      if (branchIdx === -1 || sessionsIdx === -1) continue;

      const branchId = parts[branchIdx + 1];
      const sessionId = parts[sessionsIdx + 1];

      // finalize with defaults: rounding "actual", pax "single", no tax/discount
      await finalizeSessionBilling({
        branchId,
        sessionId,
        roundingMode: "actual",
        paxMode: "single",
        paymentStatus: "pending",
      });
    }
  }
);

/* ------------------------- 2) Callable: finalize bill ---------------------- */
/**
 * Client can explicitly finalize any session (e.g., for a manual “Close & Bill” fallback
 * or to repair zero-₹ bills from older auto-closes).
 *
 * data: { branchId, sessionId, roundingMode?, paxMode?, discount?, taxPercent?, paymentStatus? }
 */
export const finalizeSessionBill = onCall(
  { region: "asia-south1" },
  async (req: CallableRequest) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign-in required");

    const {
      branchId,
      sessionId,
      roundingMode,
      paxMode,
      discount,
      taxPercent,
      paymentStatus,
    } = (req.data || {}) as {
      branchId?: string;
      sessionId?: string;
      roundingMode?: RoundingMode;
      paxMode?: PaxMode;
      discount?: number;
      taxPercent?: number;
      paymentStatus?: "pending" | "paid";
    };

    if (!branchId || !sessionId) {
      throw new HttpsError("invalid-argument", "branchId and sessionId are required");
    }

    const totals = await finalizeSessionBilling({
      branchId,
      sessionId,
      roundingMode,
      paxMode,
      discount,
      taxPercent,
      paymentStatus,
      closedByUid: uid,
    });

    return { ok: true, totals };
  }
);

/* ---------------------- 3) User management (unchanged) --------------------- */
const ALLOWED_ROLES = new Set(["staff", "manager", "admin", "superadmin"]);
function generateTempPassword(length = 12): string {
  const upper = "ABCDEFGHJKLMNPQRSTUVWXYZ";
  const lower = "abcdefghijkmnpqrstuvwxyz";
  const digits = "23456789";
  const symbols = "!@#$%*?";
  const all = upper + lower + digits + symbols;
  const pick = (s: string) => s[Math.floor(Math.random() * s.length)];
  let out = pick(upper) + pick(lower) + pick(digits) + pick(symbols);
  for (let i = out.length; i < length; i++) out += pick(all);
  return out.split("").sort(() => Math.random() - 0.5).join("");
}

export const createConsoleUser = onCall(
  { region: "asia-south1" },
  async (req: CallableRequest) => {
    const callerUid = req.auth?.uid;
    if (!callerUid) throw new HttpsError("unauthenticated", "Sign-in required");

    const caller = await db.collection("users").doc(callerUid).get();
    const callerRole = (caller.get("role") as string) || "staff";
    if (callerRole !== "superadmin" && callerRole !== "admin") {
      throw new HttpsError("permission-denied", "Only admin/superadmin can create users");
    }

    const { email, name, role, branchIds, tempPassword } = (req.data || {}) as {
      email?: string; name?: string; role?: string; branchIds?: string[]; tempPassword?: string;
    };

    if (!email || !name || !role) {
      throw new HttpsError("invalid-argument", "Missing fields: email, name, role");
    }

    const normalizedRole = String(role).toLowerCase();
    if (!ALLOWED_ROLES.has(normalizedRole)) {
      throw new HttpsError("invalid-argument", `Invalid role: ${role}`);
    }

    try {
      await admin.auth().getUserByEmail(email);
      throw new HttpsError("already-exists", "A user with this email already exists");
    } catch (e: any) {
      if (e?.code !== "auth/user-not-found") throw e;
    }

    const branchList = Array.isArray(branchIds) ? branchIds.filter(Boolean) : [];
    
    // If admin provided a password, use it; otherwise generate one
    const password = tempPassword && tempPassword.trim() ? tempPassword.trim() : generateTempPassword(12);

    const userRecord = await admin.auth().createUser({ email, password, displayName: name });
    await admin.auth().setCustomUserClaims(userRecord.uid, { role: normalizedRole, branchIds: branchList });

    await db.collection("users").doc(userRecord.uid).set({
      name,
      email,
      role: normalizedRole,
      branchIds: branchList,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: callerUid,
    });

    return { uid: userRecord.uid, email, tempPassword: password };
  }
);

/* -------- users/{uid} trigger — resync custom claims when details change ---- */
export const onUserDocWriteSyncClaims = onDocumentWritten(
  "users/{uid}",
  async (
    event: FirestoreEvent<Change<DocumentSnapshot> | undefined, { uid: string }>
  ) => {
    const uid = event.params.uid;
    const afterSnap = event.data?.after;
    if (!afterSnap) return;

    const after = afterSnap.data() as Record<string, unknown>;
    const before = event.data?.before?.data() as Record<string, unknown> | undefined;

    const role = (after?.["role"] as string) || "staff";
    const branchIds = (after?.["branchIds"] as string[]) || [];

    const beforeRole = (before?.["role"] as string) ?? undefined;
    const beforeBranches = (before?.["branchIds"] as string[]) ?? [];

    const changed =
      beforeRole !== role ||
      JSON.stringify(beforeBranches) !== JSON.stringify(branchIds);

    if (changed) {
      await admin.auth().setCustomUserClaims(uid, { role, branchIds });
    }
  }
);

/* ------------------------- 5) Admin set temp password ---------------------- */
export const adminSetTempPassword = onCall(
  { region: "asia-south1" },
  async (req: CallableRequest) => {
    const callerUid = req.auth?.uid;
    if (!callerUid) throw new HttpsError("unauthenticated", "Sign-in required");

    const callerRole = (await db.collection("users").doc(callerUid).get()).get("role");
    if (callerRole !== "superadmin" && callerRole !== "admin") {
      throw new HttpsError("permission-denied", "Only admin/superadmin");
    }

    const { uid, tempPassword } = (req.data || {}) as { uid?: string; tempPassword?: string };
    if (!uid || !tempPassword || tempPassword.length < 8) {
      throw new HttpsError("invalid-argument", "uid and tempPassword (>=8) required");
    }

    await admin.auth().updateUser(uid, { password: tempPassword });
    await db.collection("users").doc(uid).set(
      {

        passwordResetBy: callerUid,
        passwordResetAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return { ok: true };
  }
);
