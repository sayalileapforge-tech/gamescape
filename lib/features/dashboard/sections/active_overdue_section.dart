// lib/features/dashboard/sections/active_overdue_section.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../layout/dashboard_layout.dart';
import '../../bookings/booking_actions_dialog.dart';

class ActiveOverdueSection extends StatelessWidget implements DashboardSectionWidget {
  final String branchId;
  const ActiveOverdueSection({super.key, required this.branchId});

  @override
  String get persistentKey => 'activeOverdue';
  @override
  String get title => "Today's Active Sessions";

  @override
  Widget build(BuildContext context) {
    final startLocal = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final q = FirebaseFirestore.instance
        .collection('branches').doc(branchId).collection('sessions')
        .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startLocal.toUtc()))
        .where('startTime', isLessThan: Timestamp.fromDate(startLocal.add(const Duration(days: 1)).toUtc()));

    return StreamBuilder<QuerySnapshot>(
      stream: q.snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final now = DateTime.now();
        final active = <QueryDocumentSnapshot>[];
        final overdue = <QueryDocumentSnapshot>[];

        for (final d in docs) {
          final m = d.data() as Map<String, dynamic>? ?? {};
          final status = ((m['status'] as String?) ?? '').toLowerCase();
          if (status == 'cancelled' || status == 'completed') continue;
          final st = (m['startTime'] as Timestamp?)?.toDate();
          final dur = (m['durationMinutes'] as num?)?.toInt() ?? 60;
          if (st == null) continue;
          final et = st.add(Duration(minutes: dur));
          if (st.isBefore(now) && et.isAfter(now)) {
            active.add(d);
          } else if (now.isAfter(et)) {
            overdue.add(d);
          }
        }

        if (active.isEmpty && overdue.isEmpty) {
          return const Text('No active sessions right now.', style: TextStyle(color: Colors.white70));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...active.map((d) {
              final m = d.data() as Map<String, dynamic>? ?? {};
              final nm = m['customerName']?.toString() ?? 'Walk-in';
              final seat = m['seatLabel']?.toString() ?? 'Seat';
              final ts = (m['startTime'] as Timestamp?)?.toDate();
              final t = ts != null ? '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}' : '—';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(backgroundColor: Colors.black, child: Icon(Icons.chair_outlined, color: Colors.white)),
                title: Text(nm, style: const TextStyle(color: Colors.white)),
                subtitle: Text('Console: $seat | Started: $t', style: const TextStyle(color: Colors.white70)),
                trailing: ElevatedButton(
                  onPressed: () => showDialog(context: context, builder: (_) => BookingActionsDialog(branchId: branchId, sessionId: d.id, data: m)),
                  child: const Text('View'),
                ),
              );
            }),
            if (overdue.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Overdue sessions', style: TextStyle(color: Colors.redAccent.shade100, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ...overdue.map((d) {
                final m = d.data() as Map<String, dynamic>? ?? {};
                final nm = m['customerName']?.toString() ?? 'Walk-in';
                final seat = m['seatLabel']?.toString() ?? 'Seat';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(backgroundColor: Colors.redAccent, child: Icon(Icons.warning_amber, color: Colors.white)),
                  title: Text(nm, style: const TextStyle(color: Colors.white)),
                  subtitle: const Text('Should be closed', style: TextStyle(color: Colors.white70)),
                  trailing: ElevatedButton(
                    onPressed: () => showDialog(context: context, builder: (_) => BookingActionsDialog(branchId: branchId, sessionId: d.id, data: m)),
                    child: const Text('Close now'),
                  ),
                );
              }),
            ],
          ],
        );
      },
    );
  }
}
