// FULL FILE: lib/features/reports/reports_screen.dart
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../core/widgets/app_shell.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int _activeCount = 0;
  int _completedCount = 0;

  // filters
  String? _selectedBranchId;
  String _dateRange = 'thisWeek';
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  DateTime _today = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final sessionsQ = FirebaseFirestore.instance.collectionGroup('sessions');
    final ordersQ = FirebaseFirestore.instance.collectionGroup('orders');

    // ✅ Cashbook collectionGroup
    final cashbooksQ = FirebaseFirestore.instance.collectionGroup('cashbooks');

    return AppShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reports',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
          ),
          const SizedBox(height: 16),

          // filters row
          Row(
            children: [
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  value: _dateRange,
                  dropdownColor: const Color(0xFF111827),
                  decoration: const InputDecoration(
                    labelText: 'Date range',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                  items: const [
                    DropdownMenuItem(value: 'thisWeek', child: Text('This Week')),
                    DropdownMenuItem(value: 'thisMonth', child: Text('This Month')),
                    DropdownMenuItem(value: 'last6Months', child: Text('Last 6 Months')),
                    DropdownMenuItem(value: 'custom', child: Text('Custom')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _dateRange = v;
                      if (v != 'custom') {
                        _customStartDate = null;
                        _customEndDate = null;
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              if (_dateRange == 'custom') ...[
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _customStartDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() => _customStartDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today, color: Colors.white70, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          _customStartDate != null
                              ? '${_customStartDate!.day}/${_customStartDate!.month}/${_customStartDate!.year}'
                              : 'Start Date',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _customEndDate ?? DateTime.now(),
                      firstDate: _customStartDate ?? DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() => _customEndDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today, color: Colors.white70, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          _customEndDate != null
                              ? '${_customEndDate!.day}/${_customEndDate!.month}/${_customEndDate!.year}'
                              : 'End Date',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('branches').snapshots(),
                  builder: (context, snap) {
                    final branches = snap.data?.docs ?? [];
                    return DropdownButtonFormField<String>(
                      value: _selectedBranchId,
                      dropdownColor: const Color(0xFF111827),
                      decoration: const InputDecoration(
                        labelText: 'Branch (optional)',
                        labelStyle: TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All branches'),
                        ),
                        ...branches.map((b) {
                          return DropdownMenuItem(
                            value: b.id,
                            child: Text(b['name'] ?? 'Branch'),
                          );
                        }),
                      ],
                      onChanged: (v) {
                        setState(() => _selectedBranchId = v);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              // SINGLE Export button – triggers real CSV download
              Builder(
                builder: (ctx) {
                  return ElevatedButton.icon(
                    onPressed: () async {
                      await _exportCsv();
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Report downloaded as CSV')),
                      );
                    },
                    icon: const Icon(Icons.download),
                    label: const Text('Export CSV'),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 20),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: sessionsQ.snapshots(),
              builder: (context, sessionSnap) {
                return StreamBuilder<QuerySnapshot>(
                  stream: ordersQ.snapshots(),
                  builder: (context, ordersSnap) {
                    if (sessionSnap.connectionState == ConnectionState.waiting ||
                        ordersSnap.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    }

                    final sessions = sessionSnap.data?.docs ?? [];
                    final orders = ordersSnap.data?.docs ?? [];

                    final filteredSessions = _filterSessions(sessions);
                    final activeSessions = filteredSessions
                        .where((d) => (d.data() as Map<String, dynamic>?)?['status'] == 'active')
                        .toList();
                    final completedSessions = filteredSessions
                        .where((d) => (d.data() as Map<String, dynamic>?)?['status'] == 'completed')
                        .toList();

                    _activeCount = activeSessions.length;
                    _completedCount = completedSessions.length;

                    final fnbRevenue = _sumOrdersForSessions(orders, filteredSessions);
                    final sessionRevenue = _sumSessionRevenue(completedSessions);
                    final playtimeRevenue = (sessionRevenue - fnbRevenue);
                    final playtimeRevenueSafe = playtimeRevenue < 0 ? 0 : playtimeRevenue;

                    return StreamBuilder<QuerySnapshot>(
                      stream: cashbooksQ.snapshots(),
                      builder: (context, cashSnap) {
                        final cashbooks = cashSnap.data?.docs ?? [];
                        final filteredCashbooks = _filterCashbooks(cashbooks);

                        final cashSummary = _cashbookSummary(filteredCashbooks);

                        return SingleChildScrollView(
                          child: Column(
                            children: [
                              // top cards
                              Row(
                                children: [
                                  Expanded(
                                    child: _reportCard(
                                      'Active Sessions',
                                      _activeCount.toString(),
                                      Colors.blueAccent,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _reportCard(
                                      'Completed Sessions',
                                      _completedCount.toString(),
                                      Colors.greenAccent,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // revenue split (unchanged)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1F2937),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Revenue split',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _miniRevenueTile(
                                            title: 'Playtime',
                                            amount: playtimeRevenueSafe,
                                            icon: Icons.timer_outlined,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _miniRevenueTile(
                                            title: 'F&B / Inventory',
                                            amount: fnbRevenue,
                                            icon: Icons.fastfood_outlined,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _miniRevenueTile(
                                            title: 'Total',
                                            amount: playtimeRevenueSafe + fnbRevenue,
                                            icon: Icons.currency_rupee,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Note: Playtime is derived as (session bill - F&B), so for older bills it may be approximate.',
                                      style: TextStyle(color: Colors.white38, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              // ✅ Cash Book (POS) report section
                              _buildCashbookReportCard(cashSummary, filteredCashbooks),

                              const SizedBox(height: 16),

                              // staff performance
                              _buildStaffPerformanceCard(filteredSessions),

                              const SizedBox(height: 16),

                              // console utilization (simple)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1F2937),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Console utilization (rough)',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Active sessions right now: $_activeCount',
                                      style: const TextStyle(color: Colors.white70),
                                    ),
                                    Text(
                                      'Completed in selected period: $_completedCount',
                                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                          ),
                        );
                      },
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

  // CSV download for web (HUMAN-READABLE COLUMNS)
  Future<void> _exportCsv() async {
    final snapshot = await FirebaseFirestore.instance.collectionGroup('sessions').get();
    final filtered = _filterSessions(snapshot.docs);

    final csv = _buildCsvFromSessions(filtered);

    final bytes = utf8.encode(csv);
    final blob = html.Blob([bytes], 'text/csv');
    final url = html.Url.createObjectUrlFromBlob(blob);

    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final anchor = html.AnchorElement(href: url)
      ..download = 'gamescape-report-$ts.csv'
      ..click();

    html.Url.revokeObjectUrl(url);
  }

  List<QueryDocumentSnapshot> _filterSessions(List<QueryDocumentSnapshot> sessions) {
    return sessions.where((d) {
      final data = d.data() as Map<String, dynamic>? ?? {};
      final branchId = data['branchId']?.toString();
      final ts = (data['startTime'] as Timestamp?)?.toDate();

      if (_selectedBranchId != null && _selectedBranchId!.isNotEmpty) {
        if (branchId != _selectedBranchId) return false;
      }
      if (ts == null) return true;

      final dateRange = _getDateRange();
      if (dateRange != null) {
        return ts.isAfter(dateRange['start']!) && ts.isBefore(dateRange['end']!.add(const Duration(days: 1)));
      }
      return true;
    }).toList();
  }

  Map<String, DateTime>? _getDateRange() {
    final now = DateTime.now();
    DateTime? start;
    DateTime? end;

    switch (_dateRange) {
      case 'thisWeek':
        final weekday = now.weekday;
        start = now.subtract(Duration(days: weekday - 1));
        start = DateTime(start.year, start.month, start.day);
        end = DateTime(now.year, now.month, now.day);
        break;
      case 'thisMonth':
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month, now.day);
        break;
      case 'last6Months':
        start = DateTime(now.year, now.month - 6, now.day);
        end = DateTime(now.year, now.month, now.day);
        break;
      case 'custom':
        if (_customStartDate != null && _customEndDate != null) {
          start = _customStartDate;
          end = _customEndDate;
        }
        break;
      default:
        return null;
    }

    if (start != null && end != null) {
      return {'start': start, 'end': end};
    }
    return null;
  }

  // ✅ Cashbooks filter (openedAt based)
  List<QueryDocumentSnapshot> _filterCashbooks(List<QueryDocumentSnapshot> cashbooks) {
    return cashbooks.where((d) {
      final data = d.data() as Map<String, dynamic>? ?? {};

      final branchId = (data['branchId']?.toString()) ??
          d.reference.parent.parent?.id; // fallback derive

      final ts = (data['openedAt'] as Timestamp?)?.toDate();

      if (_selectedBranchId != null && _selectedBranchId!.isNotEmpty) {
        if (branchId != _selectedBranchId) return false;
      }
      if (ts == null) return true;

      final dateRange = _getDateRange();
      if (dateRange != null) {
        return ts.isAfter(dateRange['start']!) && ts.isBefore(dateRange['end']!.add(const Duration(days: 1)));
      }
      return true;
    }).toList();
  }

  Map<String, dynamic> _cashbookSummary(List<QueryDocumentSnapshot> cashbooks) {
    int open = 0;
    int closed = 0;
    num openingTotal = 0;
    num closingTotal = 0;

    for (final d in cashbooks) {
      final m = d.data() as Map<String, dynamic>? ?? {};
      final status = (m['status'] ?? '').toString().toLowerCase();
      final opening = m['openingCash'];
      final closing = m['closingCash'];

      if (status == 'open') open++;
      if (status == 'closed') closed++;

      if (opening is num) openingTotal += opening;
      if (opening is String) openingTotal += num.tryParse(opening) ?? 0;

      if (closing is num) closingTotal += closing;
      if (closing is String) closingTotal += num.tryParse(closing) ?? 0;
    }

    return {
      'open': open,
      'closed': closed,
      'openingTotal': openingTotal,
      'closingTotal': closingTotal,
    };
  }

  num _sumOrdersForSessions(
    List<QueryDocumentSnapshot> orders,
    List<QueryDocumentSnapshot> filteredSessions,
  ) {
    final allowedSessionIds = filteredSessions.map((s) => s.id).toSet();
    num total = 0;
    for (final o in orders) {
      final sessionId = o.reference.parent.parent?.id;
      if (sessionId == null) continue;
      if (!allowedSessionIds.contains(sessionId)) continue;

      final data = o.data() as Map<String, dynamic>? ?? {};
      final rawTotal = data['total'];
      if (rawTotal is num) {
        total += rawTotal;
      } else if (rawTotal is String) {
        total += num.tryParse(rawTotal) ?? 0;
      }
    }
    return total;
  }

  num _sumSessionRevenue(List<QueryDocumentSnapshot> sessions) {
    num total = 0;
    for (final s in sessions) {
      final data = s.data() as Map<String, dynamic>? ?? {};
      final raw = data['billAmount'];
      if (raw is num) {
        total += raw;
      } else if (raw is String) {
        total += num.tryParse(raw) ?? 0;
      }
    }
    return total;
  }

  Widget _reportCard(String title, String value, Color accent) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 26,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniRevenueTile({
    required String title,
    required num amount,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                Text(
                  '₹${amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCashbookReportCard(
    Map<String, dynamic> summary,
    List<QueryDocumentSnapshot> cashbooks,
  ) {
    // recent 10 (by openedAt desc)
    final sorted = [...cashbooks];
    sorted.sort((a, b) {
      final am = a.data() as Map<String, dynamic>? ?? {};
      final bm = b.data() as Map<String, dynamic>? ?? {};
      final at = (am['openedAt'] as Timestamp?)?.toDate();
      final bt = (bm['openedAt'] as Timestamp?)?.toDate();
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    final recent = sorted.take(10).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cash Book (POS)',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(child: _miniStat('Open', '${summary['open'] ?? 0}')),
              const SizedBox(width: 12),
              Expanded(child: _miniStat('Closed', '${summary['closed'] ?? 0}')),
              const SizedBox(width: 12),
              Expanded(child: _miniStat('Opening Total', '₹${(summary['openingTotal'] ?? 0).toString()}')),
              const SizedBox(width: 12),
              Expanded(child: _miniStat('Closing Total', '₹${(summary['closingTotal'] ?? 0).toString()}')),
            ],
          ),
          const SizedBox(height: 12),

          if (recent.isEmpty)
            const Text(
              'No cashbook entries found for this filter.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            )
          else
            Column(
              children: recent.map((d) {
                final m = d.data() as Map<String, dynamic>? ?? {};
                final branchName = (m['branchName'] ?? '').toString();
                final staffName = (m['staffName'] ?? m['staffUserId'] ?? '').toString();
                final status = (m['status'] ?? '').toString();
                final openedAt = (m['openedAt'] as Timestamp?)?.toDate();
                final closedAt = (m['closedAt'] as Timestamp?)?.toDate();
                final opening = m['openingCash'];
                final closing = m['closingCash'];

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111827),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${branchName.isNotEmpty ? branchName : 'Branch'} • $staffName',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            color: status.toLowerCase() == 'open' ? const Color(0xFF22C55E) : Colors.white70,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          'Open: ₹${_num(opening)}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Close: ₹${_num(closing)}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          openedAt != null ? openedAt.toLocal().toString() : '—',
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          closedAt != null ? closedAt.toLocal().toString() : '',
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  String _num(dynamic v) {
    if (v == null) return '0';
    if (v is num) return v.toStringAsFixed(0);
    final p = num.tryParse(v.toString());
    return (p ?? 0).toStringAsFixed(0);
  }

  Widget _buildStaffPerformanceCard(List<QueryDocumentSnapshot> filteredSessions) {
    final Map<String, int> createdMap = {};
    final Map<String, int> closedMap = {};

    for (final s in filteredSessions) {
      final data = s.data() as Map<String, dynamic>? ?? {};
      final createdByName = (data['createdByName'] ?? data['createdBy'] ?? '') as String;
      final closedByName = (data['closedByName'] ?? data['closedBy'] ?? '') as String;

      if (createdByName.isNotEmpty) {
        createdMap[createdByName] = (createdMap[createdByName] ?? 0) + 1;
      }
      if (closedByName.isNotEmpty) {
        closedMap[closedByName] = (closedMap[closedByName] ?? 0) + 1;
      }
    }

    var topCreators = createdMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    var topClosers = closedMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    topCreators = topCreators.take(5).toList();
    topClosers = topClosers.take(5).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Staff performance',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          if (topCreators.isEmpty && topClosers.isEmpty)
            const Text(
              'No staff data found for this filter.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            )
          else
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Top creators', style: TextStyle(color: Colors.white70)),
                      const SizedBox(height: 6),
                      ...topCreators.map((e) => Text(
                            '${e.key} – ${e.value} sessions',
                            style: const TextStyle(color: Colors.white),
                          )),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Top closers', style: TextStyle(color: Colors.white70)),
                      const SizedBox(height: 6),
                      ...topClosers.map((e) => Text(
                            '${e.key} – ${e.value} bills',
                            style: const TextStyle(color: Colors.white),
                          )),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // HUMAN-READABLE CSV (no hashes)
  String _buildCsvFromSessions(List<QueryDocumentSnapshot> sessions) {
    final buffer = StringBuffer();
    buffer.writeln(
      [
        'InvoiceNo',
        'Date',
        'Branch',
        'Seat',
        'SeatType',
        'CustomerName',
        'CustomerPhone',
        'Status',
        'PaymentStatus',
        'Pax',
        'ItemsOnly',
        'OrdersSubtotal',
        'SeatSubtotal',
        'Discount',
        'Tax(%)',
        'TaxAmount',
        'BillAmount',
        'PlayedMinutes',
        'CreatedBy',
        'ClosedBy',
        'Notes',
      ].join(','),
    );

    for (final s in sessions) {
      final d = s.data() as Map<String, dynamic>? ?? {};
      final ts = (d['startTime'] as Timestamp?)?.toDate();

      final row = [
        _csv(d['invoiceNumber']),
        _csv(ts != null ? ts.toIso8601String() : ''),
        _csv(d['branchName']),
        _csv(d['seatLabel']),
        _csv(d['seatType']),
        _csv(d['customerName']),
        _csv(d['customerPhone']),
        _csv(d['status']),
        _csv(d['paymentStatus']),
        _csv((d['pax'] ?? '').toString()),
        _csv((d['itemsOnly'] == true) ? 'Yes' : 'No'),
        _numCsv(d['ordersSubtotal']),
        _numCsv(_seatSubtotalFromSegments(d['seatSegments'])),
        _numCsv(d['discount']),
        _numCsv(d['taxPercent']),
        _numCsv(d['taxAmount']),
        _numCsv(d['billAmount']),
        _csv((d['playedMinutes'] ?? '').toString()),
        _csv(d['createdByName'] ?? d['createdBy']),
        _csv(d['closedByName'] ?? d['closedBy']),
        _csv(d['notes']),
      ];
      buffer.writeln(row.join(','));
    }
    return buffer.toString();
  }

  // Helpers for CSV formatting
  String _csv(dynamic v) {
    final s = (v ?? '').toString();
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  String _numCsv(dynamic v) {
    if (v == null) return '0';
    if (v is num) return v.toStringAsFixed(2);
    final p = num.tryParse(v.toString());
    return (p ?? 0).toStringAsFixed(2);
  }

  num _seatSubtotalFromSegments(dynamic segs) {
    if (segs is! List) return 0;
    num total = 0;
    for (final s in segs) {
      final amt = s is Map<String, dynamic> ? s['billedAmount'] : null;
      if (amt is num) total += amt;
      if (amt is String) total += num.tryParse(amt) ?? 0;
    }
    return total;
  }
}
