import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../layout/dashboard_layout.dart';

class CashBookSection extends StatelessWidget implements DashboardSectionWidget {
  final String branchId;
  final String branchName;
  final String staffUserId;
  final String staffName;

  const CashBookSection({
    super.key,
    required this.branchId,
    required this.branchName,
    required this.staffUserId,
    required this.staffName,
  });

  @override
  String get persistentKey => 'cashbook';

  @override
  String get title => 'Cash Book (POS)';

  CollectionReference<Map<String, dynamic>> _cashbooksRef() {
    return FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('cashbooks');
  }

  /// ✅ Deterministic "open" document per staff, so transaction can safely read/write.
  DocumentReference<Map<String, dynamic>> _openDocRef() {
    return _cashbooksRef().doc('open_$staffUserId');
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _openDocStream() {
    return _openDocRef().snapshots();
  }

  Future<num?> _askAmountDialog(
    BuildContext context, {
    required String title,
    required String hint,
    required String actionText,
  }) async {
    final ctrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showDialog<num>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Amount',
              hintStyle: TextStyle(color: Colors.white38),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white70),
              ),
            ),
            validator: (v) {
              final raw = (v ?? '').trim();
              if (raw.isEmpty) return 'Required';
              final n = num.tryParse(raw);
              if (n == null) return 'Enter a valid number';
              if (n < 0) return 'Must be >= 0';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              final n = num.tryParse(ctrl.text.trim()) ?? 0;
              Navigator.of(context).pop(n);
            },
            child: Text(actionText),
          ),
        ],
      ),
    );
  }

  Future<void> _startCashbook(BuildContext context) async {
    final opening = await _askAmountDialog(
      context,
      title: 'Start Cash Book',
      hint: 'Opening cash (₹)',
      actionText: 'Start',
    );
    if (opening == null) return;

    final docRef = _openDocRef();

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(docRef);

        // If already open, do nothing.
        if (snap.exists) {
          final data = snap.data() ?? {};
          final status = (data['status'] ?? '').toString().toLowerCase();
          if (status == 'open') return;
        }

        // (Re)start / overwrite the open doc
        tx.set(docRef, {
          'branchId': branchId,
          'branchName': branchName,
          'staffUserId': staffUserId,
          'staffName': staffName,
          'status': 'open',
          'openingCash': opening,
          'closingCash': null,
          'openedAt': FieldValue.serverTimestamp(),
          'closedAt': null,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'source': 'admin-panel',
        }, SetOptions(merge: false));
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cash book started')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start cash book: $e')),
        );
      }
    }
  }

  Future<void> _closeAndLogout(BuildContext context, DocumentReference<Map<String, dynamic>> openRef) async {
    final closing = await _askAmountDialog(
      context,
      title: 'Close & Logout',
      hint: 'Closing cash (₹)',
      actionText: 'Close',
    );
    if (closing == null) return;

    try {
      await openRef.set({
        'status': 'closed',
        'closingCash': closing,
        'closedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await FirebaseAuth.instance.signOut();
      if (context.mounted) context.go('/login');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to close cash book: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final docRef = _openDocRef();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _openDocStream(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final status = (data['status'] ?? '').toString().toLowerCase();
        final isOpen = snap.hasData && snap.data!.exists && status == 'open';

        final openedAt = (data['openedAt'] as Timestamp?)?.toDate();
        final openingCash = data['openingCash'] as num?;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isOpen ? 'Status: OPEN' : 'Status: CLOSED',
                style: TextStyle(
                  color: isOpen ? const Color(0xFF22C55E) : Colors.white54,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text('Branch: $branchName', style: const TextStyle(color: Colors.white70)),
              Text('Staff: $staffName', style: const TextStyle(color: Colors.white70)),
              if (isOpen) ...[
                const SizedBox(height: 6),
                Text(
                  'Opened: ${openedAt?.toLocal().toString() ?? '—'}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                Text(
                  'Opening cash: ₹${(openingCash ?? 0).toStringAsFixed(0)}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  if (!isOpen)
                    ElevatedButton.icon(
                      onPressed: () => _startCashbook(context),
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('Start Cash Book'),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: () => _closeAndLogout(context, docRef),
                      icon: const Icon(Icons.logout),
                      label: const Text('Close & Logout'),
                    ),
                  const SizedBox(width: 12),
                  if (snap.connectionState == ConnectionState.waiting)
                    const Text('Loading...', style: TextStyle(color: Colors.white38)),
                  if (snap.hasError)
                    const Text('Error', style: TextStyle(color: Colors.redAccent)),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Tip: Staff must start cash book at shift start and close it at logout.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }
}
