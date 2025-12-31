import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../layout/dashboard_layout.dart';
import '../../bookings/booking_timeline_view.dart';

class TimelineSection extends StatelessWidget implements DashboardSectionWidget {
  final String branchId;
  const TimelineSection({super.key, required this.branchId});

  @override
  String get persistentKey => 'timeline';
  @override
  String get title => 'Today’s Timeline (All Consoles)';

  @override
  Widget build(BuildContext context) {
    final startLocal = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final range = (Timestamp.fromDate(startLocal.toUtc()), Timestamp.fromDate(startLocal.add(const Duration(days: 1)).toUtc()));
    final q = FirebaseFirestore.instance
        .collection('branches').doc(branchId).collection('sessions')
        .where('startTime', isGreaterThanOrEqualTo: range.$1).where('startTime', isLessThan: range.$2);

    return SizedBox(
      height: 420,
      child: StreamBuilder<QuerySnapshot>(
        stream: q.snapshots(),
        builder: (context, snap) {
          final docs = snap.data?.docs ?? const <QueryDocumentSnapshot>[];
          // Pass branchId to enable left-join + filters + persistence inside the timeline widget
          return BookingTimelineView(bookings: docs, date: DateTime.now(), branchId: branchId);
        },
      ),
    );
  }
}
