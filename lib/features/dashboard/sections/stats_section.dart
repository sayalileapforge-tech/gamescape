import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../layout/dashboard_layout.dart';

/// Stats section (Today’s bookings, Active, Revenue, Pending)
class StatsSection extends StatelessWidget implements DashboardSectionWidget {
  final String selectedBranchId;

  /// Accepts whatever your dashboard passes (we expect an object with
  /// `startUtc` and `endUtc` Timestamps). Using `dynamic` keeps it compatible
  /// with your private `_DayRangeUtc` type from the screen.
  final dynamic todayRangeUtc;

  /// ✅ Bug 1: revenue is now explicitly gated (default: hidden)
  final bool showRevenue;

  const StatsSection({
    super.key,
    required this.selectedBranchId,
    required this.todayRangeUtc,
    this.showRevenue = false,
  });

  @override
  String get persistentKey => 'stats';

  @override
  String get title => 'Today at a glance';

  Timestamp get _startUtc =>
      (todayRangeUtc?.startUtc is Timestamp) ? todayRangeUtc.startUtc as Timestamp : _fallbackStartUtc();

  Timestamp get _endUtc =>
      (todayRangeUtc?.endUtc is Timestamp) ? todayRangeUtc.endUtc as Timestamp : _fallbackEndUtc();

  Timestamp _fallbackStartUtc() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).toUtc();
    return Timestamp.fromDate(start);
  }

  Timestamp _fallbackEndUtc() {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day).add(const Duration(days: 1)).toUtc();
    return Timestamp.fromDate(end);
  }

  @override
  Widget build(BuildContext context) {
    final sessionsTodayRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(selectedBranchId)
        .collection('sessions')
        .where('startTime', isGreaterThanOrEqualTo: _startUtc)
        .where('startTime', isLessThan: _endUtc);

    final invoicesRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(selectedBranchId)
        .collection('invoices')
        .where('createdAt', isGreaterThanOrEqualTo: _startUtc)
        .where('createdAt', isLessThan: _endUtc);

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        const _StatCard(title: 'Total Branches', streamBasedCount: _BranchesCountStream()),
        _TodayStatsCards(sessionsQuery: sessionsTodayRef),

        // ✅ Bug 1: Revenue tiles are now gated (default OFF)
        if (showRevenue)
          _TodayInvoiceStatsCards(
            invoicesQuery: invoicesRef,
            fallbackSessionsQuery: FirebaseFirestore.instance
                .collection('branches')
                .doc(selectedBranchId)
                .collection('sessions')
                .where('closedAt', isGreaterThanOrEqualTo: _startUtc)
                .where('closedAt', isLessThan: _endUtc),
          ),
      ],
    );
  }
}

/// Generic stat card that can show a constant value or consume a loader.
class _StatCard extends StatelessWidget {
  final String title;
  final String? value;
  final Stream<int>? countStream;
  const _StatCard({
    required this.title,
    this.value,
    this.countStream,
    this.streamBasedCount,
  });

  /// Alternate way: pass a little stream builder helper
  final _StreamCountProvider? streamBasedCount;

  @override
  Widget build(BuildContext context) {
    final base = Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          Text(
            value ?? '—',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 22,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (streamBasedCount != null) {
      return StreamBuilder<int>(
        stream: streamBasedCount!.stream(),
        builder: (context, snap) {
          final v = snap.data ?? 0;
          return _StatCard(title: title, value: '$v');
        },
      );
    }

    if (countStream != null) {
      return StreamBuilder<int>(
        stream: countStream,
        builder: (context, snap) {
          final v = snap.data ?? 0;
          return _StatCard(title: title, value: '$v');
        },
      );
    }

    return base;
  }
}

abstract class _StreamCountProvider {
  Stream<int> stream();
}

/// Total branches
class _BranchesCountStream implements _StreamCountProvider {
  const _BranchesCountStream();
  @override
  Stream<int> stream() {
    return FirebaseFirestore.instance.collection('branches').snapshots().map((s) => s.docs.length);
  }
}

/// Today’s bookings + Active now
class _TodayStatsCards extends StatelessWidget {
  final Query sessionsQuery;
  const _TodayStatsCards({required this.sessionsQuery});

  bool _isActiveNow(Map<String, dynamic> m, DateTime now) {
    final status = (m['status'] as String?)?.toLowerCase();
    if (status == 'cancelled' || status == 'completed') return false;
    final start = (m['startTime'] as Timestamp?)?.toDate();
    final dur = (m['durationMinutes'] as num?)?.toInt() ?? 60;
    if (start == null) return false;
    final end = start.add(Duration(minutes: dur));
    return start.isBefore(now) && end.isAfter(now);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: sessionsQuery.snapshots(),
      builder: (context, snap) {
        int todaysBookings = 0;
        int activeNow = 0;

        if (snap.hasData) {
          final now = DateTime.now();
          final docs = snap.data!.docs;
          todaysBookings = docs.length;
          activeNow = docs.where((d) {
            final m = d.data() as Map<String, dynamic>? ?? {};
            return _isActiveNow(m, now);
          }).length;
        }

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _StatCard(title: 'Today’s Bookings', value: snap.hasError ? '—' : '$todaysBookings'),
            _StatCard(title: 'Active Bookings', value: snap.hasError ? '—' : '$activeNow'),
          ],
        );
      },
    );
  }
}

/// Revenue & Pending (prefers invoices, falls back to sessions)
class _TodayInvoiceStatsCards extends StatelessWidget {
  final Query invoicesQuery;
  final Query fallbackSessionsQuery;
  const _TodayInvoiceStatsCards({
    required this.invoicesQuery,
    required this.fallbackSessionsQuery,
  });

  double _amount(dynamic v) {
    if (v is int) return v.toDouble();
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return 0.0;
  }

  String _pay(Map<String, dynamic> m) =>
      ((m['paymentStatus'] ?? m['status'] ?? '') as String).toLowerCase();

  String _status(Map<String, dynamic> m) => ((m['status'] ?? '') as String).toLowerCase();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: invoicesQuery.snapshots(),
      builder: (context, invSnap) {
        final noInvoices = invSnap.hasError || !(invSnap.hasData && invSnap.data!.docs.isNotEmpty);
        if (!noInvoices) {
          double revenue = 0.0, pending = 0.0;
          for (final d in invSnap.data!.docs) {
            final m = d.data() as Map<String, dynamic>? ?? {};
            final amt = _amount(m['grandTotal'] ?? m['total'] ?? m['amount'] ?? m['billAmount'] ?? 0);
            final p = _pay(m);
            if (p == 'paid') revenue += amt;
            if (p == 'pending') pending += amt;
          }
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _StatCard(title: 'Today Revenue', value: '₹${revenue.toStringAsFixed(0)}'),
              _StatCard(title: 'Pending Payments', value: '₹${pending.toStringAsFixed(0)}'),
            ],
          );
        }

        // Fallback from sessions
        return StreamBuilder<QuerySnapshot>(
          stream: fallbackSessionsQuery.snapshots(),
          builder: (context, sesSnap) {
            double revenue = 0.0, pending = 0.0;
            if (sesSnap.hasData) {
              for (final d in sesSnap.data!.docs) {
                final m = d.data() as Map<String, dynamic>? ?? {};
                final amt = _amount(m['grandTotal'] ?? m['total'] ?? m['amount'] ?? m['billAmount'] ?? 0);
                final p = _pay(m);
                final s = _status(m);
                if (s == 'completed' && p == 'paid') revenue += amt;
                if (s == 'completed' && p == 'pending') pending += amt;
              }
            }
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _StatCard(title: 'Today Revenue', value: '₹${revenue.toStringAsFixed(0)}'),
                _StatCard(title: 'Pending Payments', value: '₹${pending.toStringAsFixed(0)}'),
              ],
            );
          },
        );
      },
    );
  }
}
