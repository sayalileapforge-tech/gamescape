// FULL FILE: lib/features/dashboard/notification_panel_v2.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../bookings/booking_actions_dialog.dart';

class NotificationPanelV2 extends StatefulWidget {
  final String userId;
  final String branchId;
  final String branchName;

  const NotificationPanelV2({
    super.key,
    required this.userId,
    required this.branchId,
    required this.branchName,
  });

  @override
  State<NotificationPanelV2> createState() => _NotificationPanelV2State();
}

// ───────────────────────── Local helpers ─────────────────────────
String _statusOf(Map<String, dynamic> m) =>
    ((m['status'] as String?) ?? '').toLowerCase();
String _readPaymentStatus(Map<String, dynamic> m) =>
    ((m['paymentStatus'] as String?) ?? (m['status'] as String?) ?? '')
        .toLowerCase();

class _NotificationPanelV2State extends State<NotificationPanelV2> {
  int _tabIndex = 0; // 0=All, 1=Archived (visual only)
  bool _marking = false;

  static const Map<String, bool> _defaults = {
    'endingSoon': true,
    'upcoming': true,
    'overdue': true,
    'lowStock': true,
    'pendingDues': true,
    'newBookings': true,
  };

  Future<void> _markAllRead() async {
    setState(() => _marking = true);
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    setState(() => _marking = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All notifications marked as read')),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Friendly empty state to avoid "document path must be non-empty" on first open.
    if (widget.userId.isEmpty) {
      return _panelFrame(
        headerActions: _headerActions(),
        child: _emptyState('Sign in to view notifications'),
      );
    }
    if (widget.branchId.isEmpty) {
      return _panelFrame(
        headerActions: _headerActions(),
        child: _emptyState('Select a branch to view notifications'),
      );
    }

    final userDoc =
        FirebaseFirestore.instance.collection('users').doc(widget.userId);

    return StreamBuilder<DocumentSnapshot>(
      stream: userDoc.snapshots(),
      builder: (context, snap) {
        Map<String, dynamic> data = {};
        if (snap.hasData && snap.data?.data() != null) {
          data = snap.data!.data() as Map<String, dynamic>;
        }
        final prefsDyn = (data['notificationPrefs'] as Map?) ?? {};
        final prefs = <String, bool>{
          ..._defaults,
          ...prefsDyn.map((k, v) => MapEntry(k.toString(), v == true)),
        };

        return _panelFrame(
          headerActions: _headerActions(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tabs
              Container(
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    _tabButton('All', 0),
                    _tabButton('Archived', 1),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Preferences',
                      onPressed: () => _openPrefs(prefs),
                      icon: const Icon(Icons.tune, color: Colors.white70, size: 20),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // List
              Expanded(
                child: _tabIndex == 0
                    ? _AllNotificationsList(
                        prefs: prefs, branchId: widget.branchId)
                    : const _ArchivedPlaceholder(),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _headerActions() => [
        TextButton(
          onPressed: _marking ? null : _markAllRead,
          child: _marking
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Mark all as read'),
        ),
      ];

  Widget _tabButton(String label, int index) {
    final selected = _tabIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tabIndex = index),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Colors.white.withOpacity(0.06) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  void _openPrefs(Map<String, bool> initial) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF111827),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: _PrefsEditor(userId: widget.userId, initialPrefs: initial),
        ),
      ),
    );
  }
}

// Outer chrome (header + container)
Widget _panelFrame({required List<Widget> headerActions, required Widget child}) {
  return Container(
    decoration: BoxDecoration(
      color: const Color(0xFF111827),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white12),
      boxShadow: const [
        BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 8))
      ],
    ),
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: const Icon(Icons.notifications, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Notifications',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            ...headerActions,
          ],
        ),
        const SizedBox(height: 10),
        Expanded(child: child),
      ],
    ),
  );
}

Widget _emptyState(String msg) {
  return Container(
    decoration: BoxDecoration(
      color: const Color(0xFF0F172A),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white10),
    ),
    alignment: Alignment.center,
    child: Padding(
      padding: const EdgeInsets.all(24.0),
      child: Text(
        msg,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white70),
      ),
    ),
  );
}

class _ArchivedPlaceholder extends StatelessWidget {
  const _ArchivedPlaceholder();

  @override
  Widget build(BuildContext context) {
    return _emptyState('No archived notifications yet');
  }
}

class _AllNotificationsList extends StatelessWidget {
  final Map<String, bool> prefs;
  final String branchId;
  const _AllNotificationsList({required this.prefs, required this.branchId});

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[];

    if (prefs['lowStock'] == true) tiles.add(_LowStockTile(branchId: branchId));
    if (prefs['pendingDues'] == true) tiles.add(_PendingDuesTile(branchId: branchId));
    if (prefs['overdue'] == true) tiles.add(_OverdueTile(branchId: branchId));
    if (prefs['endingSoon'] == true) tiles.add(_EndingSoonTile(branchId: branchId));
    if (prefs['upcoming'] == true) tiles.add(_UpcomingTile(branchId: branchId));
    if (prefs['newBookings'] == true) tiles.add(_NewBookingsTile(branchId: branchId));

    return ScrollConfiguration(
      behavior: const _NoGlowBehavior(),
      child: ListView.separated(
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => tiles[i],
      ),
    );
  }
}

class _NoGlowBehavior extends ScrollBehavior {
  const _NoGlowBehavior();
  @override
  Widget buildViewportChrome(BuildContext context, Widget child, AxisDirection axisDirection) {
    return child;
  }
}

// ───────────────────────── Tiles ─────────────────────────

class _EndingSoonTile extends StatelessWidget {
  final String branchId;
  const _EndingSoonTile({required this.branchId});

  @override
  Widget build(BuildContext context) {
    final col = FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('sessions');
    return StreamBuilder<QuerySnapshot>(
      stream: col.snapshots(),
      builder: (context, snap) {
        final now = DateTime.now();
        final soon = now.add(const Duration(minutes: 10));
        int count = 0;
        QueryDocumentSnapshot? example;
        if (snap.hasData) {
          for (final d in snap.data!.docs) {
            final m = d.data() as Map<String, dynamic>? ?? {};
            if ((m['status'] ?? '').toString().toLowerCase() != 'active') continue;
            final st = (m['startTime'] as Timestamp?)?.toDate();
            final dur = (m['durationMinutes'] as num?)?.toInt() ?? 0;
            if (st == null) continue;
            final end = st.add(Duration(minutes: dur));
            if (end.isAfter(now) && !end.isAfter(soon)) {
              count++;
              example ??= d;
            }
          }
        }
        return _tile(
          context,
          icon: Icons.hourglass_bottom,
          iconBg: const Color(0xFF312E81),
          title: 'Sessions ending soon',
          meta: '≤10 mins • Sessions',
          count: count,
          primaryCta: example == null
              ? null
              : () {
                  final m = example!.data() as Map<String, dynamic>? ?? {};
                  showDialog(
                    context: context,
                    builder: (_) => BookingActionsDialog(
                      branchId: branchId,
                      sessionId: example!.id,
                      data: m,
                    ),
                  );
                },
          primaryLabel: 'Open',
        );
      },
    );
  }
}

class _UpcomingTile extends StatelessWidget {
  final String branchId;
  const _UpcomingTile({required this.branchId});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final inOneHour = now.add(const Duration(minutes: 60));
    final col = FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('sessions')
        .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(now));

    return StreamBuilder<QuerySnapshot>(
      stream: col.snapshots(),
      builder: (context, snap) {
        final items = <QueryDocumentSnapshot>[];
        if (snap.hasData) {
          for (final d in snap.data!.docs) {
            final m = d.data() as Map<String, dynamic>? ?? {};
            final ts = (m['startTime'] as Timestamp?)?.toDate();
            if ((m['status'] == 'reserved') && ts != null && !ts.isAfter(inOneHour)) {
              items.add(d);
            }
          }
        }
        return _tile(
          context,
          icon: Icons.schedule,
          iconBg: const Color(0xFF064E3B),
          title: 'Upcoming reservations',
          meta: '≤60 mins • Reservations',
          count: items.length,
          primaryCta: items.isEmpty ? null : () => context.go('/bookings'),
          primaryLabel: 'Go to Bookings',
        );
      },
    );
  }
}

class _OverdueTile extends StatelessWidget {
  final String branchId;
  const _OverdueTile({required this.branchId});

  @override
  Widget build(BuildContext context) {
    final col = FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('sessions');
    return StreamBuilder<QuerySnapshot>(
      stream: col.snapshots(),
      builder: (context, snap) {
        int count = 0;
        QueryDocumentSnapshot? example;
        if (snap.hasData) {
          final now = DateTime.now();
          for (final d in snap.data!.docs) {
            final m = d.data() as Map<String, dynamic>? ?? {};
            final st = (m['startTime'] as Timestamp?)?.toDate();
            final dur = (m['durationMinutes'] as num?)?.toInt() ?? 0;
            final status = (m['status'] ?? '').toString().toLowerCase();
            if (st == null) continue;
            final end = st.add(Duration(minutes: dur));
            final cancelled = status == 'cancelled' || status == 'completed';
            if (!cancelled && now.isAfter(end)) {
              count++;
              example ??= d;
            }
          }
        }
        return _tile(
          context,
          icon: Icons.warning_amber_outlined,
          iconBg: const Color(0xFF4A1F1A),
          title: 'Overdue sessions',
          meta: 'Action needed • Sessions',
          count: count,
          primaryCta: example == null
              ? null
              : () {
                  final m = example!.data() as Map<String, dynamic>? ?? {};
                  showDialog(
                    context: context,
                    builder: (_) => BookingActionsDialog(
                      branchId: branchId,
                      sessionId: example!.id,
                      data: m,
                    ),
                  );
                },
          primaryLabel: 'Close',
        );
      },
    );
  }
}

class _LowStockTile extends StatelessWidget {
  final String branchId;
  const _LowStockTile({required this.branchId});

  @override
  Widget build(BuildContext context) {
    final col = FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('inventory');
    return StreamBuilder<QuerySnapshot>(
      stream: col.snapshots(),
      builder: (context, snap) {
        final low = <QueryDocumentSnapshot>[];
        if (snap.hasData) {
          for (final d in snap.data!.docs) {
            final m = d.data() as Map<String, dynamic>? ?? {};
            final active = (m['active'] as bool?) ?? true;
            final qty = (m['stockQty'] as num?)?.toDouble() ?? 0;
            final thr = (m['reorderThreshold'] as num?)?.toDouble() ?? -1;
            if (active && thr >= 0 && qty <= thr) low.add(d);
          }
        }
        return _tile(
          context,
          icon: Icons.inventory_2_outlined,
          iconBg: const Color(0xFF312E81),
          title: 'Low stock',
          meta: 'Inventory • Items',
          count: low.length,
          primaryCta:
              low.isEmpty ? null : () => context.go('/inventory-unified'),
          primaryLabel: 'Go to Inventory',
        );
      },
    );
  }
}

class _PendingDuesTile extends StatelessWidget {
  final String branchId;
  const _PendingDuesTile({required this.branchId});

  @override
  Widget build(BuildContext context) {
    final range = _todayIstToUtc();
    final col = FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('sessions')
        .where('closedAt', isGreaterThanOrEqualTo: range.startUtc)
        .where('closedAt', isLessThan: range.endUtc);

    return StreamBuilder<QuerySnapshot>(
      stream: col.snapshots(),
      builder: (context, snap) {
        int pendingCount = 0;
        if (snap.hasData) {
          for (final d in snap.data!.docs) {
            final m = d.data() as Map<String, dynamic>? ?? {};
            if ((_statusOf(m) == 'completed') &&
                (_readPaymentStatus(m) == 'pending')) {
              pendingCount++;
            }
          }
        }
        return _tile(
          context,
          icon: Icons.payments_outlined,
          iconBg: const Color(0xFF3B2F0B),
          title: 'Pending dues (today)',
          meta: 'Billing • Sessions',
          count: pendingCount,
          primaryCta: pendingCount == 0 ? null : () => context.go('/invoices'),
          primaryLabel: 'Go to Invoices',
        );
      },
    );
  }
}

class _NewBookingsTile extends StatelessWidget {
  final String branchId;
  const _NewBookingsTile({required this.branchId});

  @override
  Widget build(BuildContext context) {
    final range = _todayIstToUtc();
    final col = FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('sessions')
        .where('startTime', isGreaterThanOrEqualTo: range.startUtc)
        .where('startTime', isLessThan: range.endUtc)
        .where('status', isNotEqualTo: 'cancelled');

    return StreamBuilder<QuerySnapshot>(
      stream: col.snapshots(),
      builder: (context, snap) {
        final list = snap.data?.docs ?? [];
        return _tile(
          context,
          icon: Icons.add_alert_outlined,
          iconBg: const Color(0xFF0B1220),
          title: 'New bookings (today)',
          meta: 'Today • Sessions',
          count: list.length,
          primaryCta: list.isEmpty ? null : () => context.go('/bookings'),
          primaryLabel: 'Go to Bookings',
        );
      },
    );
  }
}

// Pretty tile composer with FIXED trailing CTA width for consistent layout
Widget _tile(
  BuildContext context, {
  required IconData icon,
  required Color iconBg,
  required String title,
  required String meta,
  required int count,
  String primaryLabel = 'View',
  VoidCallback? primaryCta,
}) {
  const double trailingWidth = 140; // reserve space to avoid row jumps

  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF0F172A),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 36,
          width: 36,
          decoration: BoxDecoration(
            color: iconBg.withOpacity(0.45),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(meta,
                  style:
                      const TextStyle(color: Colors.white60, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white12,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white24),
          ),
          child: Text('$count', style: const TextStyle(color: Colors.white)),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: trailingWidth,
          child: Align(
            alignment: Alignment.centerRight,
            // Keep width even if CTA is null to avoid layout shift.
            child: primaryCta == null
                ? Opacity(
                    opacity: 0.0,
                    child: TextButton(onPressed: () {}, child: Text(primaryLabel)),
                  )
                : TextButton(onPressed: primaryCta, child: Text(primaryLabel)),
          ),
        ),
      ],
    ),
  );
}

// ───────────────────────── Small helpers ─────────────────────────

class _DayRangeUtc {
  final Timestamp startUtc;
  final Timestamp endUtc;
  const _DayRangeUtc(this.startUtc, this.endUtc);
}

_DayRangeUtc _todayIstToUtc() {
  final nowLocal = DateTime.now();
  final startLocal = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
  final endLocal = startLocal.add(const Duration(days: 1));
  return _DayRangeUtc(
    Timestamp.fromDate(startLocal.toUtc()),
    Timestamp.fromDate(endLocal.toUtc()),
  );
}

class _PrefsEditor extends StatefulWidget {
  final String userId;
  final Map<String, bool> initialPrefs;
  const _PrefsEditor({required this.userId, required this.initialPrefs});

  @override
  State<_PrefsEditor> createState() => _PrefsEditorState();
}

class _PrefsEditorState extends State<_PrefsEditor> {
  late Map<String, bool> _prefs;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _prefs = Map<String, bool>.from(widget.initialPrefs);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final userDoc =
        FirebaseFirestore.instance.collection('users').doc(widget.userId);
    await userDoc.set({'notificationPrefs': _prefs}, SetOptions(merge: true));
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notification preferences saved')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Notification Preferences',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              const SizedBox(height: 12),
              _toggle('Sessions ending in ≤10 mins', 'endingSoon'),
              _toggle('Upcoming reservations in ≤60 mins', 'upcoming'),
              _toggle('Overdue sessions', 'overdue'),
              _toggle('Low stock items', 'lowStock'),
              _toggle('Pending dues (today)', 'pendingDues'),
              _toggle('New bookings (today)', 'newBookings'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const CircularProgressIndicator()
                          : const Text('Save'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggle(String label, String key) {
    return SwitchListTile(
      value: _prefs[key] == true,
      onChanged: (v) => setState(() => _prefs[key] = v),
      contentPadding: EdgeInsets.zero,
      activeColor: Colors.white,
      title: Text(label, style: const TextStyle(color: Colors.white)),
    );
  }
}
