// FULL FILE: lib/features/dashboard/sections/upcoming_section.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../layout/dashboard_layout.dart';
import '../../bookings/booking_actions_dialog.dart';

class UpcomingSection extends StatefulWidget
    implements DashboardSectionWidget, DashboardHeaderAction {
  final String branchId;

  const UpcomingSection({
    super.key,
    required this.branchId,
  });

  @override
  String get persistentKey => 'upcoming';

  @override
  String get title => 'Upcoming in next 60 minutes';

  @override
  State<UpcomingSection> createState() => UpcomingSectionState();

  @override
  Widget? buildHeaderAction(BuildContext context) {
    // Safely read the typed state via the widget's GlobalKey (if provided)
    final st = (key is GlobalKey<UpcomingSectionState>)
        ? (key as GlobalKey<UpcomingSectionState>).currentState
        : null;

    final isLoading = st?.isLoading == true;

    return IconButton(
      tooltip: isLoading ? 'Refreshing…' : 'Refresh',
      onPressed: isLoading ? null : st?.refresh,
      icon: isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh, color: Colors.white70, size: 18),
      splashRadius: 18,
    );
  }
}

/// Public state class (needed so other files can type the GlobalKey)
class UpcomingSectionState extends State<UpcomingSection> {
  bool _loading = true;
  String? _error;
  List<QueryDocumentSnapshot> _docs = [];

  bool get isLoading => _loading;

  /// Public method other widgets (or the header button) can call.
  Future<void> refresh() => _load();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final nowUtc = DateTime.now().toUtc();
      final oneHourAhead = nowUtc.add(const Duration(minutes: 60));

      final snap = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('sessions')
          .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(nowUtc))
          .get();

      final list = snap.docs.where((d) {
        final m = d.data() as Map<String, dynamic>? ?? {};
        final ts = (m['startTime'] as Timestamp?)?.toDate();
        final status = (m['status'] as String?)?.toLowerCase();
        return status == 'reserved' && ts != null && !ts.isAfter(oneHourAhead);
      }).toList()
        ..sort((a, b) {
          final ma = a.data() as Map<String, dynamic>? ?? {};
          final mb = b.data() as Map<String, dynamic>? ?? {};
          final ta = (ma['startTime'] as Timestamp?)?.toDate() ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final tb = (mb['startTime'] as Timestamp?)?.toDate() ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return ta.compareTo(tb);
        });

      if (!mounted) return;
      setState(() {
        _docs = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load upcoming bookings.';
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Text(
        'Loading upcoming bookings...',
        style: TextStyle(color: Colors.white70),
      );
    }
    if (_error != null) {
      return const Text(
        'Failed to load upcoming bookings.',
        style: TextStyle(color: Colors.redAccent),
      );
    }
    if (_docs.isEmpty) {
      return const Text(
        'No upcoming bookings in the next 60 minutes.',
        style: TextStyle(color: Colors.white70),
      );
    }

    return Column(
      children: _docs.map((doc) {
        final m = doc.data() as Map<String, dynamic>? ?? {};
        final customer = m['customerName']?.toString() ?? 'Walk-in';
        final seat = m['seatLabel']?.toString() ?? 'Seat';
        final ts = (m['startTime'] as Timestamp?)?.toDate();
        final hh = ts?.hour.toString().padLeft(2, '0') ?? '--';
        final mm = ts?.minute.toString().padLeft(2, '0') ?? '--';
        final branchName = m['branchName']?.toString() ?? '';

        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const CircleAvatar(
            backgroundColor: Colors.deepOrange,
            child: Icon(Icons.timer, color: Colors.white),
          ),
          title: Text(customer, style: const TextStyle(color: Colors.white)),
          subtitle: Text(
            '$branchName • Console: $seat • Starts at: $hh:$mm • Yet to start',
            style: const TextStyle(color: Colors.white70),
          ),
          trailing: TextButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => BookingActionsDialog(
                branchId: widget.branchId,
                sessionId: doc.id,
                data: m,
              ),
            ),
            child: const Text('Manage'),
          ),
        );
      }).toList(),
    );
  }
}
