import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../layout/dashboard_layout.dart';
import '../../bookings/add_booking_dialog.dart';
import '../../bookings/booking_actions_dialog.dart';
import '../../bookings/booking_close_bill_dialog.dart';
import '../../bookings/quick_shop_dialog.dart';

class QuickActionsSection extends StatelessWidget implements DashboardSectionWidget {
  final String role;
  final List<String> allowedBranchIds;
  final String selectedBranchId;

  const QuickActionsSection({
    super.key,
    required this.role,
    required this.allowedBranchIds,
    required this.selectedBranchId,
  });

  @override
  String get persistentKey => 'quick_actions';

  @override
  String get title => 'Quick Actions';

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _QuickActionButton(
          icon: Icons.person_add_alt_1,
          label: 'New Walk-in',
          onTap: () {
            if (selectedBranchId.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please select a branch first')),
              );
              return;
            }
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => AddBookingDialog(
                allowedBranchIds: allowedBranchIds,
                initialBranchId: selectedBranchId,
              ),
            );
          },
        ),
        _QuickActionButton(
          icon: Icons.event_note_outlined,
          label: 'View Bookings',
          onTap: () async {
            await _openSessionPickerAndThen(
              context: context,
              branchId: selectedBranchId,
              allowSingleAutoPick: false,
              onPickList: (docs) {
                _openListDialog(context, docs);
              },
            );
          },
        ),
        _QuickActionButton(
          icon: Icons.fastfood_outlined,
          label: 'Add F&B Order',
          onTap: () async {
            await _openSessionPickerAndThen(
              context: context,
              branchId: selectedBranchId,
              onSessionSelected: (branchId, sessionId, data) {
                showDialog(
                  context: context,
                  builder: (_) => BookingActionsDialog(
                    branchId: branchId,
                    sessionId: sessionId,
                    data: data,
                  ),
                );
              },
            );
          },
        ),
        _QuickActionButton(
          icon: Icons.payments_outlined,
          label: 'Quick Checkout',
          onTap: () async {
            await _openSessionPickerAndThen(
              context: context,
              branchId: selectedBranchId,
              onSessionSelected: (branchId, sessionId, data) {
                showDialog(
                  context: context,
                  builder: (_) => BookingCloseBillDialog(
                    branchId: branchId,
                    sessionId: sessionId,
                    data: data,
                  ),
                );
              },
            );
          },
        ),

        // ✅ NEW: Quick Shop moved here (Dashboard Quick Actions)
        _QuickActionButton(
          icon: Icons.store_mall_directory_outlined,
          label: 'Quick Shop',
          onTap: () async {
            if (selectedBranchId.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please select a branch first')),
              );
              return;
            }

            final ok = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (_) => QuickShopDialog(branchId: selectedBranchId),
            );

            if (ok == true && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Quick Shop saved')),
              );
            }
          },
        ),
      ],
    );
  }

  Future<void> _openSessionPickerAndThen({
    required BuildContext context,
    required String branchId,
    bool allowSingleAutoPick = true,
    void Function(String branchId, String sessionId, Map<String, dynamic> data)? onSessionSelected,
    void Function(List<QueryDocumentSnapshot> docs)? onPickList,
  }) async {
    if (branchId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a branch first')),
      );
      return;
    }

    final now = DateTime.now();
    final startUtc = Timestamp.fromDate(DateTime(now.year, now.month, now.day).toUtc());
    final endUtc = Timestamp.fromDate(
      DateTime(now.year, now.month, now.day).add(const Duration(days: 1)).toUtc(),
    );

    final sessionsSnap = await FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('sessions')
        .where('startTime', isGreaterThanOrEqualTo: startUtc)
        .where('startTime', isLessThan: endUtc)
        .get();

    bool _isActiveNow(Map<String, dynamic> m, DateTime now) {
      final status = (m['status'] as String?)?.toLowerCase();
      if (status == 'cancelled' || status == 'completed') return false;
      final start = (m['startTime'] as Timestamp?)?.toDate();
      final dur = (m['durationMinutes'] as num?)?.toInt() ?? 60;
      if (start == null) return false;
      final end = start.add(Duration(minutes: dur));
      return start.isBefore(now) && end.isAfter(now);
    }

    final activeDocs = sessionsSnap.docs
        .where((doc) => _isActiveNow(doc.data() as Map<String, dynamic>, now))
        .toList();

    if (onPickList != null) {
      onPickList(activeDocs);
      return;
    }

    if (activeDocs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active sessions for this branch')),
      );
      return;
    }

    if (allowSingleAutoPick && activeDocs.length == 1 && onSessionSelected != null) {
      final s = activeDocs.first;
      onSessionSelected(branchId, s.id, s.data() as Map<String, dynamic>);
      return;
    }

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF111827),
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Select session',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.white),
              ),
              const SizedBox(height: 12),
              ...activeDocs.map((doc) {
                final data = (doc.data() as Map<String, dynamic>?) ?? {};
                final customer = data['customerName']?.toString() ?? 'Walk-in';
                final seat = data['seatLabel']?.toString() ?? 'Seat';
                final ts = (data['startTime'] as Timestamp?)?.toDate();
                final timeString = ts != null
                    ? '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}'
                    : '—';
                return ListTile(
                  title: Text(customer, style: const TextStyle(color: Colors.white)),
                  subtitle: Text(
                    'Console: $seat | Start: $timeString',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    if (onSessionSelected != null) {
                      onSessionSelected(branchId, doc.id, data);
                    }
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _openListDialog(BuildContext context, List<QueryDocumentSnapshot> docs) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF111827),
        child: Container(
          width: 520,
          padding: const EdgeInsets.all(16),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 12),
            itemBuilder: (context, i) {
              final d = docs[i];
              final m = d.data() as Map<String, dynamic>? ?? {};
              final name = m['customerName']?.toString() ?? 'Walk-in';
              final seat = m['seatLabel']?.toString() ?? '-';
              final ts = (m['startTime'] as Timestamp?)?.toDate();
              final timeStr = ts != null
                  ? '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}'
                  : '—';
              final status = (m['status'] as String?) ?? '';
              return ListTile(
                leading: const Icon(Icons.event, color: Colors.white70),
                title: Text(name, style: const TextStyle(color: Colors.white)),
                subtitle: Text('Seat $seat • $status', style: const TextStyle(color: Colors.white60)),
                trailing: Text(timeStr, style: const TextStyle(color: Colors.white70)),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 32,
              width: 32,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
