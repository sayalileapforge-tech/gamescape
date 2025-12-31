import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall } from "firebase-functions/v2/https";
import { onDocumentWritten } from "firebase-functions/v2/firestore";

if (!admin.apps.length) {
  admin.initializeApp();
}

// -----------------------------------------------------------------------------
// 1) Scheduled: autoCloseOverdueSessions (UNCHANGED LOGIC)
// -----------------------------------------------------------------------------
export const autoCloseOverdueSessions = onSchedule(
  {
    schedule: "every 10 minutes",
    timeZone: "Asia/Kolkata",
  },
  async () => {
    const now = admin.firestore.Timestamp.now();
    const db = admin.firestore();

    const snap = await db
      .collectionGroup("sessions")
      .where("status", "==", "active")
      .get();

    const batch = db.batch();
    snap.docs.forEach((doc) => {
      const data = doc.data();
      const startTime = data["startTime"] as admin.firestore.Timestamp | undefined;
      const durationMinutes = (data["durationMinutes"] as number) ?? 0;

      if (!startTime) return;
      const endMillis = startTime.toMillis() + durationMinutes * 60 * 1000;
      const nowMillis = now.toMillis();

      if (nowMillis > endMillis) {
        batch.update(doc.ref, {
          status: "completed",
          autoClosed: true,
          closedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    });

    await batch.commit();
  }
);

// -----------------------------------------------------------------------------
// Utils
// -----------------------------------------------------------------------------
function generateTempPassword(length = 12): string {
  const upper = "ABCDEFGHJKLMNPQRSTUVWXYZ";
  const lower = "abcdefghijkmnpqrstuvwxyz";
  const digits = "23456789";
  const symbols = "!@#$%*?";
  const all = upper + lower + digits + symbols;

  const pick = (set: string) => set[Math.floor(Math.random() * set.length)];
  // ensure complexity
  let out = pick(upper) + pick(lower) + pick(digits) + pick(symbols);
  for (let i = out.length; i < length; i++) out += pick(all);
  return out.split("").sort(() => Math.random() - 0.5).join("");
}

const ALLOWED_ROLES = new Set(["staff", "manager", "admin", "superadmin"]);

// -----------------------------------------------------------------------------
// 2) Callable: createConsoleUser (superadmin only)
//  - creates Auth user with STRONG temp password
//  - writes Firestore user doc with mustChangePassword:true
//  - sets custom claims { role, branchIds }
//  - RETURNS the temp password (so superadmin can share it securely)
// -----------------------------------------------------------------------------
export const createConsoleUser = onCall(async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) throw new Error("Unauthenticated");

  const db = admin.firestore();
  const callerDoc = await db.collection("users").doc(callerUid).get();
  const callerRole = callerDoc.get("role");

  if (callerRole !== "superadmin") {
    throw new Error("Only superadmin can create users");
  }

  const { email, name, role, branchIds } = (request.data || {}) as {
    email?: string;
    name?: string;
    role?: string;
    branchIds?: string[];
  };

  if (!email || !name || !role) {
    throw new Error("Missing fields: email, name, role");
  }

  const normalizedRole = String(role).toLowerCase();
  if (!ALLOWED_ROLES.has(normalizedRole)) {
    throw new Error(`Invalid role: ${role}`);
  }

  const branchList = Array.isArray(branchIds) ? branchIds.filter(Boolean) : [];

  // prevent duplicate Auth users
  let exists: admin.auth.UserRecord | null = null;
  try {
    exists = await admin.auth().getUserByEmail(email);
  } catch {
    exists = null;
  }
  if (exists) throw new Error("A user with this email already exists");

  // >>> THIS IS WHERE THE TEMP PASSWORD IS SET <<<
  const tempPassword = generateTempPassword(12);

  const userRecord = await admin.auth().createUser({
    email,
    password: tempPassword, // <-- temp password set here
    displayName: name,
  });

  await admin.auth().setCustomUserClaims(userRecord.uid, {
    role: normalizedRole,
    branchIds: branchList,
  });

  await db.collection("users").doc(userRecord.uid).set({
    name,
    email,
    role: normalizedRole,
    branchIds: branchList,
    mustChangePassword: true,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    createdBy: callerUid,
  });

  return { uid: userRecord.uid, email, tempPassword };
});

// -----------------------------------------------------------------------------
// 3) Callable: clearMustChangePassword (user calls after updating password)
//  - requires authentication
//  - only allows the CURRENT USER to clear their own flag
//  - updates Firestore and returns ok:true
// -----------------------------------------------------------------------------
export const clearMustChangePassword = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new Error("Unauthenticated");

  const db = admin.firestore();
  const ref = db.collection("users").doc(uid);

  await ref.set(
    {
      mustChangePassword: false,
      passwordUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  // Note: client should force-refresh ID token after password update:
  // await currentUser.getIdToken(true);

  return { ok: true };
});

// -----------------------------------------------------------------------------
// 4) Firestore v2 Trigger: on /users/{uid} write -> auto-sync custom claims
//  - On create OR when role/branchIds changed, re-apply claims
// -----------------------------------------------------------------------------
export const onUserDocWriteSyncClaims = onDocumentWritten("users/{uid}", async (event) => {
  const uid = event.params.uid as string;
  const before = event.data?.before?.data() || null;
  const after = event.data?.after?.data() || null;

  if (!after) return; // deleted: ignore

  const role = (after.role as string) || "staff";
  const branchIds = (after.branchIds as string[]) || [];

  const changed =
    !before ||
    before.role !== role ||
    JSON.stringify(before.branchIds || []) !== JSON.stringify(branchIds);

  if (!changed) return;

  await admin.auth().setCustomUserClaims(uid, { role, branchIds });
});
