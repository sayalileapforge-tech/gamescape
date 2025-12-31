import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/app_shell.dart';
import '../bookings/booking_actions_dialog.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  String _search = '';
  _CustFilter _filter = _CustFilter.all;
  String? _selectedKey; // key = 'phone:<phone>' or 'name:<name>'

  @override
  Widget build(BuildContext context) {
    return AppShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Customers',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
          ),
          const SizedBox(height: 16),
          // Search + Filter chips
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search by name or phone',
                    hintStyle: TextStyle(color: Colors.white54),
                    prefixIcon: Icon(Icons.search, color: Colors.white54),
                    border: OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                  onChanged: (v) =>
                      setState(() => _search = v.trim().toLowerCase()),
                ),
              ),
              const SizedBox(width: 12),
              _chip('All', _CustFilter.all),
              const SizedBox(width: 6),
              _chip('High Spender', _CustFilter.high),
              const SizedBox(width: 6),
              _chip('Frequent', _CustFilter.frequent),
              const SizedBox(width: 6),
              _chip('At-Risk', _CustFilter.atRisk),
              const SizedBox(width: 6),
              _chip('Dormant', _CustFilter.dormant),
              const SizedBox(width: 6),
              _chip('Pending Due', _CustFilter.pending),
              const SizedBox(width: 6),
              _chip('Pay at Counter', _CustFilter.counter),
            ],
          ),
          const SizedBox(height: 16),

          // Split Pane with branch-name cache stream
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream:
                  FirebaseFirestore.instance.collection('branches').snapshots(),
              builder: (context, branchesSnap) {
                // Build a cache: branchId -> branchName
                final Map<String, String> branchNameById = {};
                for (final d in (branchesSnap.data?.docs ?? [])) {
                  final m = (d.data() as Map<String, dynamic>?) ?? {};
                  final name = (m['name'] ?? d.id).toString().trim();
                  branchNameById[d.id] = name.isEmpty ? d.id : name;
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collectionGroup('sessions')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Failed to load customers\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      );
                    }

                    final now = DateTime.now();
                    final ninetyDaysAgo =
                        now.subtract(const Duration(days: 90));
                    final docs = snapshot.data?.docs ?? [];

                    final Map<String, _CustomerAgg> map = {};

                    for (final d in docs) {
                      final m = (d.data() as Map<String, dynamic>?) ?? {};
                      final status = (m['status'] as String?) ?? '';
                      final phone =
                          (m['customerPhone'] ?? '').toString().trim();
                      final name =
                          (m['customerName'] ?? '').toString().trim();
                      final billAmount = (m['billAmount'] as num?) ?? 0;
                      final start = (m['startTime'] as Timestamp?)?.toDate();
                      final paymentStatus =
                          (m['paymentStatus'] as String?) ?? '';
                      final key = phone.isNotEmpty
                          ? 'phone:$phone'
                          : (name.isNotEmpty ? 'name:$name' : '');

                      if (key.isEmpty) continue;

                      final agg = map.putIfAbsent(
                        key,
                        () => _CustomerAgg(
                          key: key,
                          name: name.isNotEmpty ? name : 'Walk-in',
                          phone: phone,
                        ),
                      );

                      // Sessions count
                      agg.lifetimeVisits += 1;

                      // Completed session contributes to spend
                      if (status == 'completed') {
                        agg.lifetimeSpend += billAmount;
                        if (start != null && start.isAfter(ninetyDaysAgo)) {
                          agg.spendLast90d += billAmount;
                        }
                      }

                      // Check for counter payment
                      final paymentMode = m['paymentMode'];
                      final payments = m['payments'];
                      if (paymentMode == 'counter') {
                        agg.hasCounterPayment = true;
                      } else if (payments is List) {
                        for (final p in payments) {
                          if (p is Map && p['mode'] == 'counter') {
                            agg.hasCounterPayment = true;
                            break;
                          }
                        }
                      }

                      // Visit windows
                      if (start != null && start.isAfter(ninetyDaysAgo)) {
                        agg.visitsLast90d += 1;
                      }

                      // First/Last visit
                      if (start != null) {
                        if (agg.firstVisitAt == null ||
                            start.isBefore(agg.firstVisitAt!)) {
                          agg.firstVisitAt = start;
                        }
                        if (agg.lastVisitAt == null ||
                            start.isAfter(agg.lastVisitAt!)) {
                          agg.lastVisitAt = start;
                        }
                      }

                      // Pending due **only for completed sessions that are still unpaid**
                      if (status == 'completed' &&
                          paymentStatus == 'pending' &&
                          billAmount > 0) {
                        agg.hasPendingDue = true;
                      }

                      // -------- recent sessions (with reliable branch name) --------
                      final branchId = d.reference.parent.parent?.id ?? '';
                      final rawBranchName =
                          (m['branchName'] as String?)?.trim() ?? '';
                      // Prefer session.branchName; else resolve from cache; else show short id
                      final branchName = rawBranchName.isNotEmpty
                          ? rawBranchName
                          : (branchNameById[branchId] ?? branchId);

                      agg.recentSessions.add(
                        _CustomerSessionBrief(
                          branchId: branchId,
                          sessionId: d.id,
                          branchName: branchName,
                          seatLabel: (m['seatLabel'] as String?) ?? '-',
                          status: status,
                          billAmount: billAmount,
                          startTime: start,
                        ),
                      );
                    }

                    // Finish derived fields: stats + tags + sort recent sessions
                    for (final c in map.values) {
                      if (c.lifetimeVisits > 0) {
                        c.avgSpend = c.lifetimeSpend / c.lifetimeVisits;
                      }
                      c.tags = _computeCustomerTags(c);

                      c.recentSessions.sort((a, b) {
                        final aa = a.startTime ??
                            DateTime.fromMillisecondsSinceEpoch(0);
                        final bb = b.startTime ??
                            DateTime.fromMillisecondsSinceEpoch(0);
                        return bb.compareTo(aa);
                      });
                      if (c.recentSessions.length > 20) {
                        c.recentSessions
                            .removeRange(20, c.recentSessions.length);
                      }
                    }

                    // To list
                    var list = map.values.toList();

                    // Search
                    if (_search.isNotEmpty) {
                      list = list.where((c) {
                        return c.name.toLowerCase().contains(_search) ||
                            c.phone.toLowerCase().contains(_search);
                      }).toList();
                    }

                    // Filter
                    list = list.where((c) => _matchesFilter(c, _filter)).toList();

                    // Sort: by lifetime spend desc
                    list.sort((a, b) =>
                        b.lifetimeSpend.compareTo(a.lifetimeSpend));

                    // Maintain selection
                    if (list.isNotEmpty) {
                      _selectedKey ??= list.first.key;
                      if (!list.any((e) => e.key == _selectedKey)) {
                        _selectedKey = list.first.key;
                      }
                    } else {
                      _selectedKey = null;
                    }

                    final selected = list.firstWhere(
                      (e) => e.key == _selectedKey,
                      orElse: () => _CustomerAgg.empty(),
                    );

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // LEFT: table
                        Expanded(
                          flex: 4,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1F2937),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: _CustomersTable(
                              customers: list,
                              selectedKey: _selectedKey,
                              onSelect: (k) =>
                                  setState(() => _selectedKey = k),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // RIGHT: details
                        Expanded(
                          flex: 6,
                          child: _CustomerDetailsPane(
                            customer:
                                _selectedKey == null ? null : selected,
                            onCreateBooking: (c) =>
                                _openAddBookingPrefilled(context, c),
                            onViewInvoices: (c) =>
                                _openInvoicesFor(context, c),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---- helpers ----

  Widget _chip(String label, _CustFilter f) {
    final selected = _filter == f;
    return InkWell(
      onTap: () => setState(() => _filter = f),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  bool _matchesFilter(_CustomerAgg c, _CustFilter f) {
    final now = DateTime.now();
    final daysSinceLast =
        c.lastVisitAt == null ? 9999 : now.difference(c.lastVisitAt!).inDays;

    switch (f) {
      case _CustFilter.all:
        return true;
      case _CustFilter.high:
        return c.spendLast90d >= 20000 ||
            c.lifetimeSpend >= 50000 ||
            c.spendLast90d >= 10000 ||
            c.lifetimeSpend >= 20000 ||
            c.spendLast90d >= 5000 ||
            c.lifetimeSpend >= 10000;
      case _CustFilter.frequent:
        return c.visitsLast90d >= 12 || c.visitsLast90d >= 6;
      case _CustFilter.atRisk:
        return daysSinceLast >= 30 && daysSinceLast < 60;
      case _CustFilter.dormant:
        return daysSinceLast >= 60;
      case _CustFilter.pending:
        return c.hasPendingDue;
      case _CustFilter.counter:
        return c.hasCounterPayment;
    }
  }

  void _openAddBookingPrefilled(BuildContext context, _CustomerAgg c) {
    final qp = Uri(queryParameters: {
      if (c.name.isNotEmpty) 'prefillName': c.name,
      if (c.phone.isNotEmpty) 'prefillPhone': c.phone,
    }).query;
    context.go('/bookings${qp.isNotEmpty ? '?$qp' : ''}');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Opening Bookings… customer details prefilled'),
      ),
    );
  }

  void _openInvoicesFor(BuildContext context, _CustomerAgg c) {
    final qp = Uri(queryParameters: {
      if (c.phone.isNotEmpty) 'customerPhone': c.phone,
      if (c.name.isNotEmpty) 'customerName': c.name,
    }).query;
    context.go('/invoices${qp.isNotEmpty ? '?$qp' : ''}');
  }
}

// ===================== Models & Tagging =====================

enum _CustFilter { all, high, frequent, atRisk, dormant, pending, counter }

class _CustomerAgg {
  final String key;
  final String name;
  final String phone;

  num lifetimeSpend;
  num spendLast90d;
  int lifetimeVisits;
  int visitsLast90d;
  DateTime? firstVisitAt;
  DateTime? lastVisitAt;
  num avgSpend;
  bool hasPendingDue;
  bool hasCounterPayment;
  final List<_CustomerSessionBrief> recentSessions;
  List<_Tag> tags;

  _CustomerAgg({
    required this.key,
    required this.name,
    required this.phone,
    this.lifetimeSpend = 0,
    this.spendLast90d = 0,
    this.lifetimeVisits = 0,
    this.visitsLast90d = 0,
    this.firstVisitAt,
    this.lastVisitAt,
    this.avgSpend = 0,
    this.hasPendingDue = false,
    this.hasCounterPayment = false,
    List<_CustomerSessionBrief>? recentSessions,
    List<_Tag>? tags,
  })  : recentSessions = recentSessions ?? <_CustomerSessionBrief>[],
        tags = tags ?? <_Tag>[];

  factory _CustomerAgg.empty() =>
      _CustomerAgg(key: '', name: '', phone: '');
}

class _CustomerSessionBrief {
  final String branchId;
  final String sessionId;
  final String branchName;
  final String seatLabel;
  final String status;
  final num billAmount;
  final DateTime? startTime;

  _CustomerSessionBrief({
    required this.branchId,
    required this.sessionId,
    required this.branchName,
    required this.seatLabel,
    required this.status,
    required this.billAmount,
    required this.startTime,
  });
}

class _Tag {
  final String label;
  final Color color;
  _Tag(this.label, this.color);
}

List<_Tag> _computeCustomerTags(_CustomerAgg c) {
  final now = DateTime.now();
  final daysSinceLast =
      c.lastVisitAt == null ? 9999 : now.difference(c.lastVisitAt!).inDays;
  final tags = <_Tag>[];

  // High Spender tiers
  if (c.spendLast90d >= 20000 || c.lifetimeSpend >= 50000) {
    tags.add(_Tag('Gold High-Spender', Colors.amberAccent));
  } else if (c.spendLast90d >= 10000 || c.lifetimeSpend >= 20000) {
    tags.add(_Tag('Silver High-Spender', Colors.lightBlueAccent));
  } else if (c.spendLast90d >= 5000 || c.lifetimeSpend >= 10000) {
    tags.add(_Tag('Bronze High-Spender', Colors.tealAccent));
  }

  // Frequency
  if (c.visitsLast90d >= 12) {
    tags.add(_Tag('Super Regular', Colors.greenAccent));
  } else if (c.visitsLast90d >= 6) {
    tags.add(_Tag('Regular', Colors.lightGreenAccent));
  }

  // Lifecycle
  if (c.firstVisitAt != null &&
      now.difference(c.firstVisitAt!).inDays <= 30) {
    tags.add(_Tag('New', Colors.white70));
  }
  if (daysSinceLast >= 60) {
    tags.add(_Tag('Dormant', Colors.orangeAccent));
  } else if (daysSinceLast >= 30) {
    tags.add(_Tag('At-Risk', Colors.deepOrangeAccent));
  }

  if (c.hasPendingDue) {
    tags.add(_Tag('Pending Due', Colors.redAccent));
  }

  return tags;
}

// ===================== Left Pane: Table =====================

class _CustomersTable extends StatelessWidget {
  final List<_CustomerAgg> customers;
  final String? selectedKey;
  final ValueChanged<String> onSelect;

  const _CustomersTable({
    required this.customers,
    required this.selectedKey,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (customers.isEmpty) {
      return const Center(
        child: Text(
          'No customers found.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(10),
      itemCount: customers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final c = customers[i];
        final selected = c.key == selectedKey;

        return InkWell(
          onTap: () => onSelect(c.key),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color:
                  selected ? const Color(0xFF243044) : const Color(0xFF111827),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? Colors.white24 : Colors.white10,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.white12,
                  child: Text(
                    c.name.isNotEmpty ? c.name[0].toUpperCase() : 'C',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        c.phone.isNotEmpty ? c.phone : 'No phone',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: -6,
                        children:
                            c.tags.take(3).map((t) => _TagChip(t)).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${c.lifetimeSpend.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${c.lifetimeVisits} visits',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TagChip extends StatelessWidget {
  final _Tag tag;
  const _TagChip(this.tag);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tag.color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tag.color.withOpacity(0.6)),
      ),
      child: Text(
        tag.label,
        style: TextStyle(
          color: tag.color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ===================== Right Pane: Details =====================

class _CustomerDetailsPane extends StatelessWidget {
  final _CustomerAgg? customer;
  final ValueChanged<_CustomerAgg> onCreateBooking;
  final ValueChanged<_CustomerAgg> onViewInvoices;

  const _CustomerDetailsPane({
    required this.customer,
    required this.onCreateBooking,
    required this.onViewInvoices,
  });

  Future<void> _openBookingDialogForSession(
      BuildContext context, _CustomerSessionBrief s) async {
    if (s.branchId.isEmpty || s.sessionId.isEmpty) return;

    final doc = await FirebaseFirestore.instance
        .collection('branches')
        .doc(s.branchId)
        .collection('sessions')
        .doc(s.sessionId)
        .get();

    if (!doc.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking not found')),
      );
      return;
    }

    final data = doc.data() as Map<String, dynamic>? ?? {};

    // ignore: use_build_context_synchronously
    showDialog(
      context: context,
      builder: (_) => BookingActionsDialog(
        branchId: s.branchId,
        sessionId: s.sessionId,
        data: data,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (customer == null || customer!.key.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text(
            'Select a customer from the list',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    final c = customer!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header + tags
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.white12,
                child: Text(
                  c.name.isNotEmpty ? c.name[0].toUpperCase() : 'C',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      c.phone.isNotEmpty ? c.phone : 'No phone',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: -6,
                      children: c.tags.map((t) => _TagChip(t)).toList(),
                    ),
                  ],
                ),
              ),
              // Quick actions
              Wrap(
                spacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => onCreateBooking(c),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Create Booking'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => onViewInvoices(c),
                    icon: const Icon(
                      Icons.receipt_long,
                      size: 16,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'View Invoices',
                      style: TextStyle(color: Colors.white),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Stats
          Row(
            children: [
              _statCard(
                'Lifetime Spend',
                '₹${c.lifetimeSpend.toStringAsFixed(0)}',
              ),
              const SizedBox(width: 8),
              _statCard(
                'Spend (90d)',
                '₹${c.spendLast90d.toStringAsFixed(0)}',
              ),
              const SizedBox(width: 8),
              _statCard('Visits (90d)', '${c.visitsLast90d}'),
              const SizedBox(width: 8),
              _statCard(
                'Avg Spend',
                '₹${c.avgSpend.toStringAsFixed(0)}',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Recent sessions
          const Text(
            'Recent Sessions',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: c.recentSessions.isEmpty
                ? const Center(
                    child: Text(
                      'No recent sessions',
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : ListView.separated(
                    itemCount: c.recentSessions.length.clamp(0, 8),
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white12, height: 16),
                    itemBuilder: (context, i) {
                      final s = c.recentSessions[i];
                      return InkWell(
                        onTap: () => _openBookingDialogForSession(context, s),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${s.branchName} • ${s.seatLabel}',
                                style: const TextStyle(
                                  color: Colors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              s.status,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              s.billAmount > 0
                                  ? '₹${s.billAmount.toStringAsFixed(0)}'
                                  : '',
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
