// lib/data/repositories/tv_control_repo.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Repository for sending TV control commands and overlay toasts from the Admin Panel.
///
/// Commands:
///   branches/{branchId}/tvCommands/{commandId}
///     - consumed by the on-prem TV Controller (Node/RasPi) to control TVs.
///
/// Toasts (WebOS on-TV notifications):
///   branches/{branchId}/tvToasts/{toastId}
///     - consumed directly by the WebOS TV overlay app (Firebase JS SDK or similar).
///
/// Pairing (Consumer WebOS Remote API):
///   branches/{branchId}/tvPairing/{tvId}
///     - used for one-time pairing flows (PIN entry or prompt).
class TvControlRepo {
  TvControlRepo._();
  static final TvControlRepo I = TvControlRepo._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Send a low-level TV command (power, input, volume, etc.).
  Future<void> sendCommand({
    required String branchId,
    required String type, // e.g. 'power_on', 'power_off', 'switch_input', 'mute', 'volume_delta'
    String? seatId,
    Map<String, dynamic>? payload,
  }) async {
    final user = _auth.currentUser;
    final now = DateTime.now();

    await _firestore
        .collection('branches')
        .doc(branchId)
        .collection('tvCommands')
        .add({
      'type': type,
      'seatId': seatId,
      'payload': payload ?? <String, dynamic>{},
      'createdAt': Timestamp.fromDate(now),
      'processed': false,
      'processedAt': null,
      'result': null,
      'createdByUid': user?.uid,
      'createdByEmail': user?.email,
      'createdByDisplayName': user?.displayName,
      'source': 'admin-panel',
    });
  }

  /// Send an on-TV toast notification (for WebOS overlay app).
  Future<void> sendToast({
    required String branchId,
    String? seatId,
    required String message,
    String severity = 'info',
    int durationSeconds = 5,
  }) async {
    final user = _auth.currentUser;
    final now = DateTime.now();
    final expiresAt = now.add(Duration(seconds: durationSeconds.clamp(1, 60)));

    await _firestore
        .collection('branches')
        .doc(branchId)
        .collection('tvToasts')
        .add({
      'seatId': seatId,
      'message': message,
      'severity': severity,
      'durationSeconds': durationSeconds,
      'createdAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'dismissedAt': null,
      'createdByUid': user?.uid,
      'createdByEmail': user?.email,
      'createdByDisplayName': user?.displayName,
      'source': 'admin-panel',
    });
  }

  // ---------------------------------------------------------------------------
  // Consumer TV Pairing helpers (WebOS Remote API)
  // ---------------------------------------------------------------------------

  /// Start (or restart) pairing for a specific consumer TV device.
  ///
  /// Creates/overwrites:
  /// branches/{branchId}/tvPairing/{tvId}
  Future<void> startPairing({
    required String branchId,
    required String tvId,
    bool forceRePair = false,
  }) async {
    final user = _auth.currentUser;
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(minutes: 10));

    await _firestore
        .collection('branches')
        .doc(branchId)
        .collection('tvPairing')
        .doc(tvId)
        .set({
      'status': 'waiting_code',
      'pairingCode': null,
      'forceRePair': forceRePair,
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'lastError': null,
      'createdByUid': user?.uid,
      'createdByEmail': user?.email,
      'createdByDisplayName': user?.displayName,
      'source': 'admin-panel',
    }, SetOptions(merge: true));
  }

  /// Submit a PIN pairing code for a consumer WebOS TV.
  ///
  /// Updates:
  /// branches/{branchId}/tvPairing/{tvId}
  Future<void> submitPairingCode({
    required String branchId,
    required String tvId,
    required String pairingCode,
  }) async {
    final user = _auth.currentUser;
    final now = DateTime.now();

    await _firestore
        .collection('branches')
        .doc(branchId)
        .collection('tvPairing')
        .doc(tvId)
        .set({
      'status': 'code_submitted',
      'pairingCode': pairingCode,
      'updatedAt': Timestamp.fromDate(now),
      'lastError': null,
      'updatedByUid': user?.uid,
      'updatedByEmail': user?.email,
      'updatedByDisplayName': user?.displayName,
    }, SetOptions(merge: true));
  }

  /// Clear pairing request doc (optional). Does NOT remove stored clientKey.
  Future<void> clearPairingRequest({
    required String branchId,
    required String tvId,
  }) async {
    await _firestore
        .collection('branches')
        .doc(branchId)
        .collection('tvPairing')
        .doc(tvId)
        .delete();
  }
}
