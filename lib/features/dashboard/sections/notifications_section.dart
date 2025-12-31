// FULL FILE: lib/features/dashboard/sections/notifications_section.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../layout/dashboard_layout.dart';
import '../../bookings/booking_actions_dialog.dart';

class NotificationsSection extends StatelessWidget
    implements DashboardSectionWidget {
  final String userId;
  final String role;
  final String branchId;
  final String branchName;
  final Map<String, bool>? roleTabVisibility;

  const NotificationsSection({
    super.key,
    required this.userId,
    required this.role,
    required this.branchId,
    required this.branchName,
    this.roleTabVisibility,
  });

  @override
  String get persistentKey => 'notifications';
  @override
  String get title => 'Notifications';

  bool _tabVisible(String key) =>
      roleTabVisibility == null ||
      roleTabVisibility![key] == null ||
      roleTabVisibility![key] == true;

  @override
  Widget build(BuildContext context) {
    if (branchId.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10),
        ),
        child: const Text(
          'Select a branch to see notifications.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    final tabs = <({String key, String label, Widget body})>[
      if (_tabVisible('all'))
        (key: 'all', label: 'All', body: _AllTab(branchId: branchId)),
      if (_tabVisible('alerts'))
        (key: 'alerts', label: 'Alerts', body: _AlertsTab(branchId: branchId)),
      if (_tabVisible('payments'))
        (key: 'payments', label: 'Payments', body: _PaymentsTab(branchId: branchId)),
      if (_tabVisible('stock'))
        (key: 'stock', label: 'Stock', body: _StockTab(branchId: branchId)),
      if (_tabVisible('system'))
        (key: 'system', label: 'System', body: _SystemTab(branchId: branchId)),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10),
            ),
            child: TabBar(
              isScrollable: true,
              indicator: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              labelStyle: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(
                  color: Colors.white70, fontWeight: FontWeight.w500),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: tabs.map((t) => Tab(text: t.label)).toList(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 420,
            child: TabBarView(
              children: tabs.map((t) => t.body).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Tabs ─────────────────────────

class _AllTab extends StatelessWidget {
  final String branchId;
  const _AllTab({required this.branchId});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _EndingSoonTile(branchId: branchId),
        const SizedBox(height: 8),
        _OverdueTile(branchId: branchId),
        const SizedBox(height: 8),
        _UpcomingTile(branchId: branchId),
        const SizedBox(height: 8),
        _PendingDuesTodayTile(branchId: branchId),
        const SizedBox(height: 8),
        _LowStockTile(branchId: branchId),
        const SizedBox(height: 8),
        _NewBookingsTodayTile(branchId: branchId),
      ],
    );
  }
}

class _AlertsTab extends StatelessWidget {
  final String branchId;
  const _AlertsTab({required this.branchId});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _EndingSoonTile(branchId: branchId),
        const SizedBox(height: 8),
        _OverdueTile(branchId: branchId),
        const SizedBox(height: 8),
        _UpcomingTile(branchId: branchId),
      ],
    );
  }
}

class _PaymentsTab extends StatelessWidget {
  final String branchId;
  const _PaymentsTab({required this.branchId});

  @override
  Widget build(BuildContext context) {
    return ListView(children: [
      _PendingDuesTodayTile(branchId: branchId),
    ]);
  }
}

class _StockTab extends StatelessWidget {
  final String branchId;
  const _StockTab({required this.branchId});

  @override
  Widget build(BuildContext context) {
    return ListView(children: [
      _LowStockTile(branchId: branchId),
    ]);
  }
}

class _SystemTab extends StatelessWidget {
  final String branchId;
  const _SystemTab({required this.branchId});

  @override
  Widget build(BuildContext context) {
    return ListView(children: [
      _NewBookingsTodayTile(branchId: branchId),
    ]);
  }
}

// ───────────────────────── Tiles ─────────────────────────

Timestamp _startUtcToday() {
  final now = DateTime.now();
  final startLocal = DateTime(now.year, now.month, now.day);
  return Timestamp.fromDate(startLocal.toUtc());
}

Timestamp _endUtcToday() {
  final now = DateTime.now();
  final endLocal = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  return Timestamp.fromDate(endLocal.toUtc());
}

String _statusOf(Map<String, dynamic> m) =>
    ((m['status'] as String?) ?? '').toLowerCase();
String _payStatusOf(Map<String, dynamic> m) =>
    ((m['paymentStatus'] as String?) ?? (m['status'] as String?) ?? '')
        .toLowerCase();

/// Read duration (minutes) robustly: supports `durationMinutes`, `durationMins`,
/// or computes from `startTime`/`endTime` if present.
int _readDurationMins(Map<String, dynamic> m) {
  final n = (m['durationMinutes'] ?? m['durationMins']) as num?;
  if (n != null) return n.toInt();
  final st = (m['startTime'] as Timestamp?)?.toDate();
  final et = (m['endTime'] as Timestamp?)?.toDate();
  if (st != null && et != null) return et.difference(st).inMinutes;
  return 0;
}

class _EndingSoonTile extends StatelessWidget {
  final String branchId;
  const _EndingSoonTile({required this.branchId});

  @override
  Widget build(BuildContext context) {
    final col = FirebaseFirestore.instance
        .collection('branches').doc(branchId)
        .collection('sessions');

    return StreamBuilder<QuerySnapshot>(
      stream: col.snapshots(),
      builder: (context, snap) {
        final now = DateTime.now();
        final soon = now.add(const Duration(minutes: 10));
        int count = 0;
        QueryDocumentSnapshot? sample;

        if (snap.hasData) {
          for (final d in snap.data!.docs) {
            final m = d.data() as Map<String, dynamic>? ?? {};
            if (_statusOf(m) != 'active') continue;
            final st = (m['startTime'] as Timestamp?)?.toDate();
            final dur = _readDurationMins(m);
            if (st == null) continue;
            final end = st.add(Duration(minutes: dur));
            if (end.isAfter(now) && !end.isAfter(soon)) {
              count++; sample ??= d;
            }
          }
        }

        return _tile(
          icon: Icons.hourglass_bottom,
          title: 'Sessions ending soon',
          meta: '≤10 mins • Sessions',
          count: count,
          ctaLabel: 'Open',
          onTap: sample == null
              ? null
              : () {
                  final m = sample!.data() as Map<String, dynamic>? ?? {};
                  showDialog(
                    context: context,
                    builder: (_) => BookingActionsDialog(
                      branchId: branchId,
                      sessionId: sample!.id,
                      data: m,
                    ),
                  );
                },
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
        .collection('branches').doc(branchId)
        .collection('sessions');

    return StreamBuilder<QuerySnapshot>(
      stream: col.snapshots(),
      builder: (context, snap) {
        final now = DateTime.now();
        int count = 0;
        QueryDocumentSnapshot? sample;

        if (snap.hasData) {
          for (final d in snap.data!.docs) {
            final m = d.data() as Map<String, dynamic>? ?? {};
            final st = (m['startTime'] as Timestamp?)?.toDate();
            final dur = _readDurationMins(m);
            if (st == null) continue;
            final end = st.add(Duration(minutes: dur));
            final status = _statusOf(m);
            if (status != 'cancelled' && status != 'completed' && now.isAfter(end)) {
              count++; sample ??= d;
            }
          }
        }

        return _tile(
          icon: Icons.warning_amber_outlined,
          title: 'Overdue sessions',
          meta: 'Action needed • Sessions',
          count: count,
          ctaLabel: 'Close',
          onTap: sample == null
              ? null
              : () {
                  final m = sample!.data() as Map<String, dynamic>? ?? {};
                  showDialog(
                    context: context,
                    builder: (_) => BookingActionsDialog(
                      branchId: branchId,
                      sessionId: sample!.id,
                      data: m,
                    ),
                  );
                },
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
    final nowUtc = DateTime.now().toUtc();
    final inOneHour = nowUtc.add(const Duration(minutes: 60));
    final col = FirebaseFirestore.instance
        .collection('branches').doc(branchId)
        .collection('sessions')
        .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(nowUtc))
        .orderBy('startTime');

    return StreamBuilder<QuerySnapshot>(
      stream: col.snapshots(),
      builder: (context, snap) {
        final list = <QueryDocumentSnapshot>[];
        if (snap.hasData) {
          for (final d in snap.data!.docs) {
            final m = d.data() as Map<String, dynamic>? ?? {};
            final ts = (m['startTime'] as Timestamp?)?.toDate();
            final s = _statusOf(m);
            final isReserved = (s == 'reserved' || s == 'upcoming');
            if (isReserved && ts != null && !ts.isAfter(inOneHour)) {
              list.add(d);
            }
          }
        }

        return _tile(
          icon: Icons.schedule,
          title: 'Upcoming reservations',
          meta: '≤60 mins • Reservations',
          count: list.length,
          ctaLabel: 'View',
          onTap: list.isEmpty
              ? null
              : () => _openListDialog(context, 'Upcoming (≤60 mins)', branchId, list),
        );
      },
    );
  }
}

class _PendingDuesTodayTile extends StatelessWidget {
  final String branchId;
  const _PendingDuesTodayTile({required this.branchId});

  @override
  Widget build(BuildContext context) {
    final col = FirebaseFirestore.instance
        .collection('branches').doc(branchId)
        .collection('sessions')
        .where('closedAt', isGreaterThanOrEqualTo: _startUtcToday())
        .where('closedAt', isLessThan: _endUtcToday());

    return StreamBuilder<QuerySnapshot>(
      stream: col.snapshots(),
      builder: (context, snap) {
        final list = <QueryDocumentSnapshot>[];
        if (snap.hasData) {
          for (final d in snap.data!.docs) {
            final m = d.data() as Map<String, dynamic>? ?? {};
            final pay = _payStatusOf(m);
            final isPending = (pay == 'pending' || pay == 'partial');
            if (_statusOf(m) == 'completed' && isPending) {
              list.add(d);
            }
          }
        }

        return _tile(
          icon: Icons.payments_outlined,
          title: 'Pending dues (today)',
          meta: 'Billing • Sessions',
          count: list.length,
          ctaLabel: 'Settle',
          onTap: list.isEmpty
              ? null
              : () => _openListDialog(context, 'Pending dues (today)', branchId, list),
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
        .collection('branches').doc(branchId)
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
          icon: Icons.inventory_2_outlined,
          title: 'Low stock',
          meta: 'Inventory • Items',
          count: low.length,
          ctaLabel: 'Open',
          onTap: low.isEmpty ? null : () => _openInventoryList(context, low),
        );
      },
    );
  }
}

class _NewBookingsTodayTile extends StatelessWidget {
  final String branchId;
  const _NewBookingsTodayTile({required this.branchId});

  @override
  Widget build(BuildContext context) {
    final col = FirebaseFirestore.instance
        .collection('branches').doc(branchId)
        .collection('sessions')
        .where('startTime', isGreaterThanOrEqualTo: _startUtcToday())
        .where('startTime', isLessThan: _endUtcToday())
        .orderBy('startTime');

    return StreamBuilder<QuerySnapshot>(
      stream: col.snapshots(),
      builder: (context, snap) {
        final all = snap.data?.docs ?? [];
        final list = all.where((d) {
          final m = d.data() as Map<String, dynamic>? ?? {};
          return _statusOf(m) != 'cancelled';
        }).toList();

        return _tile(
          icon: Icons.add_alert_outlined,
          title: 'New bookings (today)',
          meta: 'Today • Sessions',
          count: list.length,
          ctaLabel: 'View',
          onTap: list.isEmpty
              ? null
              : () => _openListDialog(context, 'Today’s bookings', branchId, list),
        );
      },
    );
  }
}

// ───────────────────────── Shared UI helpers ─────────────────────────

Widget _tile({
  required IconData icon,
  required String title,
  required String meta,
  required int count,
  String ctaLabel = 'View',
  VoidCallback? onTap,
}) {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF0F172A),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white10),
    ),
    child: Row(
      children: [
        Container(
          height: 36,
          width: 36,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(meta, style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ],
          ),
        ),
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
        if (onTap != null) TextButton(onPressed: onTap, child: Text(ctaLabel)),
      ],
    ),
  );
}

void _openListDialog(
  BuildContext context,
  String title,
  String branchId,
  List<QueryDocumentSnapshot> docs,
) {
  showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: const Color(0xFF111827),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 12),
              if (docs.isEmpty)
                const Text('Nothing here.', style: TextStyle(color: Colors.white70))
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 12),
                    itemBuilder: (_, i) {
                      final d = docs[i];
                      final m = d.data() as Map<String, dynamic>? ?? {};
                      final name = (m['customerName'] ?? 'Walk-in').toString();
                      final seat = (m['seatLabel'] ?? '-').toString();
                      final ts = (m['startTime'] as Timestamp?)?.toDate();
                      final timeStr = ts != null
                          ? '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}'
                          : '—';
                      return ListTile(
                        leading: const Icon(Icons.event, color: Colors.white70),
                        title: Text(name, style: const TextStyle(color: Colors.white)),
                        subtitle: Text('Seat $seat • $timeStr',
                            style: const TextStyle(color: Colors.white60)),
                        trailing: TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            showDialog(
                              context: context,
                              builder: (_) => BookingActionsDialog(
                                branchId: branchId,
                                sessionId: d.id,
                                data: m,
                              ),
                            );
                          },
                          child: const Text('Manage'),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close')),
              )
            ],
          ),
        ),
      ),
    ),
  );
}

void _openInventoryList(BuildContext context, List<QueryDocumentSnapshot> docs) {
  showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: const Color(0xFF111827),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Low stock items',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 12),
              if (docs.isEmpty)
                const Text('No low-stock items.', style: TextStyle(color: Colors.white70))
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 12),
                    itemBuilder: (_, i) {
                      final d = docs[i];
                      final m = d.data() as Map<String, dynamic>? ?? {};
                      final name = (m['name'] ?? 'Item').toString();
                      final qty = (m['stockQty'] ?? '-').toString();
                      final thr = (m['reorderThreshold'] ?? '-').toString();
                      return ListTile(
                        leading: const Icon(Icons.inventory_2_outlined, color: Colors.white70),
                        title: Text(name, style: const TextStyle(color: Colors.white)),
                        subtitle: Text('Qty: $qty • Threshold: $thr',
                            style: const TextStyle(color: Colors.white60)),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close')),
              )
            ],
          ),
        ),
      ),
    ),
  );
}
