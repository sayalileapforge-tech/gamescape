// FULL FILE: lib/features/bookings/bookings_screen.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/app_shell.dart';
import 'add_booking_dialog.dart';
import 'booking_actions_dialog.dart';
import 'booking_timeline_view.dart';
import 'booking_close_bill_dialog.dart';

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  String? _selectedBranchId;
  String? _selectedBranchName;
  bool _hasInitializedBranch = false;

  // ui state
  bool _showTimeline = false;
  String _statusFilter = 'all'; // all / active / completed / cancelled / upcoming
  bool _hideOverdue = false;

  // Upcoming window is ONLY meaningful when statusFilter == 'upcoming'
  int _upcomingWindowMins = 0;

  // NEW: global selected date for Bookings (default today). Applies to table + timeline.
  DateTime _selectedDate = DateTime.now();

  // prefill from /bookings?prefillName=&prefillPhone=
  String? _initialPrefillName;
  String? _initialPrefillPhone;
  bool _prefillDialogOpened = false;

  // NEW: lightweight UI ticker so rows switch to "Actions" exactly at 0:00
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Rebuild rows once per second; cheap and keeps status perfectly synced with countdown.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _endOfDayExclusive(DateTime d) => DateTime(d.year, d.month, d.day).add(const Duration(days: 1));

  @override
  Widget build(BuildContext context) {
    final branchesCol = FirebaseFirestore.instance.collection('branches');
    final user = FirebaseAuth.instance.currentUser;

    // Capture query params once (for customer → bookings flow)
    final uri = GoRouterState.of(context).uri;
    _initialPrefillName ??= uri.queryParameters['prefillName'];
    _initialPrefillPhone ??= uri.queryParameters['prefillPhone'];

    final dayStart = _startOfDay(_selectedDate);
    final dayEnd = _endOfDayExclusive(_selectedDate);

    return AppShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Bookings',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              Row(
                children: [
                  // Date picker (global for Bookings)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() {
                          _selectedDate = picked;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, color: Colors.white70, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            '${dayStart.day.toString().padLeft(2, '0')} ${_monthShort(dayStart.month)} ${dayStart.year}',
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  DropdownButton<String>(
                    value: _statusFilter,
                    dropdownColor: const Color(0xFF111827),
                    style: const TextStyle(color: Colors.white),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All')),
                      // DropdownMenuItem(value: 'active', child: Text('Active')),
                      DropdownMenuItem(value: 'completed', child: Text('Completed')),
                      DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
                      DropdownMenuItem(value: 'upcoming', child: Text('Upcoming')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _statusFilter = v;

                        // IMPORTANT: upcoming window applies ONLY to Upcoming.
                        if (_statusFilter != 'upcoming') {
                          _upcomingWindowMins = 0;
                        }
                      });
                    },
                  ),
                  const SizedBox(width: 12),

                  // table <-> timeline toggle
                  Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        _segBtn(
                          selected: !_showTimeline,
                          icon: Icons.table_chart,
                          label: 'Table',
                          onTap: () => setState(() => _showTimeline = false),
                        ),
                        _segBtn(
                          selected: _showTimeline,
                          icon: Icons.timeline,
                          label: 'Timeline',
                          onTap: () => setState(() => _showTimeline = true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // branch + new booking + hide overdue
          Row(
            children: [
              Expanded(
                child: StreamBuilder<DocumentSnapshot>(
                  stream: user != null 
                    ? FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots()
                    : null,
                  builder: (context, userSnap) {
                    final userData = userSnap.data?.data() as Map<String, dynamic>? ?? {};
                    final role = (userData['role'] ?? 'staff').toString();
                    final List<dynamic> branchIdsDyn = (userData['branchIds'] as List<dynamic>?) ?? [];
                    final allowedBranchIds = branchIdsDyn.map((e) => e.toString()).toList();
                    
                    return StreamBuilder<QuerySnapshot>(
                      stream: branchesCol.snapshots(),
                      builder: (context, snapshot) {
                        final allItems = snapshot.data?.docs ?? [];
                        // Filter branches: ONLY superadmin sees all, everyone else filtered by branchIds
                        final items = (role == 'superadmin')
                            ? allItems
                            : allItems.where((b) => allowedBranchIds.contains(b.id)).toList();

                        if (!_hasInitializedBranch && items.isNotEmpty && userSnap.hasData) {
                          _hasInitializedBranch = true;
                          
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            
                            final lastSelectedBranchId = userData['lastSelectedBranchId'] as String?;
                            String? initialBranch;
                            String? initialBranchName;
                            
                            if (lastSelectedBranchId != null &&
                                items.any((b) => b.id == lastSelectedBranchId)) {
                              initialBranch = lastSelectedBranchId;
                              final doc = items.firstWhere((b) => b.id == lastSelectedBranchId);
                              initialBranchName = (doc.data() as Map<String, dynamic>?)?['name']?.toString();
                            } else {
                              initialBranch = items.first.id;
                              initialBranchName = (items.first.data() as Map<String, dynamic>?)?['name']?.toString();
                            }
                            
                            setState(() {
                              _selectedBranchId = initialBranch;
                              _selectedBranchName = initialBranchName;
                            });
                          });
                        }

                        // If we came from Customers with prefill → open dialog once
                        if (!_prefillDialogOpened &&
                            _selectedBranchId != null &&
                            ((_initialPrefillName?.isNotEmpty ?? false) ||
                                (_initialPrefillPhone?.isNotEmpty ?? false))) {
                          _prefillDialogOpened = true;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            showDialog(
                              context: context,
                              builder: (_) => AddBookingDialog(
                                initialBranchId: _selectedBranchId,
                                allowedBranchIds: null,
                                prefillName: _initialPrefillName,
                                prefillPhone: _initialPrefillPhone,
                              ),
                            );
                          });
                        }

                        return DropdownButtonFormField<String>(
                          value: _selectedBranchId,
                          dropdownColor: const Color(0xFF111827),
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Select branch',
                            labelStyle: TextStyle(color: Colors.white54),
                            border: OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.white24),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.white),
                            ),
                          ),
                          items: items
                              .map(
                                (d) => DropdownMenuItem(
                                  value: d.id,
                                  child: Text(
                                    (d['name'] ?? 'Branch').toString(),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) async {
                            setState(() {
                              _selectedBranchId = v;
                              if (v != null) {
                                final doc = items.firstWhere((e) => e.id == v);
                                _selectedBranchName = (doc['name'] ?? '').toString();
                              } else {
                                _selectedBranchName = null;
                              }
                            });
                            
                            if (v != null && user != null) {
                              try {
                                final branchDoc = items.firstWhere((b) => b.id == v);
                                final branchName = (branchDoc.data() as Map<String, dynamic>?)?['name']?.toString() ?? v;
                                await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(user.uid)
                                    .set({
                                  'lastSelectedBranchId': v,
                                  'lastSelectedBranchName': branchName,
                                }, SetOptions(merge: true));
                              } catch (e) {
                                // Silently fail
                              }
                            }
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _selectedBranchId == null
                    ? null
                    : () {
                        showDialog(
                          context: context,
                          builder: (_) => AddBookingDialog(
                            initialBranchId: _selectedBranchId,
                            allowedBranchIds: null,
                          ),
                        );
                      },
                icon: const Icon(Icons.add),
                label: const Text('New Booking'),
              ),
              const SizedBox(width: 12),
              Row(
                children: [
                  const Text('Hide overdue', style: TextStyle(color: Colors.white70)),
                  Switch(
                    value: _hideOverdue,
                    onChanged: (v) => setState(() => _hideOverdue = v),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Upcoming chips (ONLY when Upcoming filter is selected)
          if (_statusFilter == 'upcoming') ...[
            Row(
              children: [
                const Text('Upcoming:', style: TextStyle(color: Colors.white70)),
                const SizedBox(width: 8),
                _upcomingChip('Off', 0),
                _upcomingChip('Next 60m', 60),
                _upcomingChip('Next 120m', 120),
                _upcomingChip('Next 180m', 180),
              ],
            ),
            const SizedBox(height: 16),
          ] else ...[
            const SizedBox(height: 4),
            const SizedBox(height: 16),
          ],

          // main
          Expanded(
            child: _selectedBranchId == null
                ? const Center(
                    child: Text(
                      'Select a branch to view bookings',
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : StreamBuilder<QuerySnapshot>(
                    // Only fetch sessions for selected day (keeps "All means all for that day")
                    stream: FirebaseFirestore.instance
                        .collection('branches')
                        .doc(_selectedBranchId)
                        .collection('sessions')
                        .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
                        .where('startTime', isLessThan: Timestamp.fromDate(dayEnd))
                        .orderBy('startTime', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final allDocs = snapshot.data?.docs.toList() ?? [];
                      final now = DateTime.now();

                      // Status filtering rules:
                      // - all: show everything for the selected day EXCEPT active (to avoid "live sessions" in bookings list)
                      // - active: show only active
                      // - completed/cancelled: show only those
                      // - upcoming: show only reserved + future within the selected day (+ optional window)
                      List<QueryDocumentSnapshot> filteredDocs = allDocs.where((d) {
                        final data = d.data() as Map<String, dynamic>;
                        final status = (data['status'] ?? 'active').toString();

                        if (_statusFilter == 'all') {
                          // Explicitly exclude live/active sessions from Bookings "All"
                          return status != 'active';
                        }
                        if (_statusFilter == 'upcoming') {
                          // handled in next step (needs startTime + window)
                          return true;
                        }
                        return status == _statusFilter;
                      }).toList();

                      // Upcoming logic (only when Upcoming filter is selected)
                      if (_statusFilter == 'upcoming') {
                        filteredDocs = filteredDocs.where((d) {
                          final data = d.data() as Map<String, dynamic>;
                          final status = (data['status'] ?? 'active').toString();
                          final ts = data['startTime'] as Timestamp?;
                          if (status != 'reserved' || ts == null) return false;

                          final start = ts.toDate();

                          // upcoming must be in the future relative to "now"
                          if (!start.isAfter(now)) return false;

                          if (_upcomingWindowMins == 0) return true;

                          final limit = now.add(Duration(minutes: _upcomingWindowMins));
                          return start.isBefore(limit);
                        }).toList();
                      }

                      // ---- TIMELINE VIEW (always render, even with 0 bookings) ----
                      if (_showTimeline) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '${_selectedBranchName ?? ''} – Timeline',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  '${dayStart.day.toString().padLeft(2, '0')} ${_monthShort(dayStart.month)}',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: BookingTimelineView(
                                bookings: filteredDocs,
                                date: dayStart,
                                branchId: _selectedBranchId, // <-- LEFT-JOIN seats → show all consoles
                              ),
                            ),
                          ],
                        );
                      }

                      // ---- TABLE VIEW ----
                      if (filteredDocs.isEmpty) {
                        return const Center(
                          child: Text(
                            'No bookings found',
                            style: TextStyle(color: Colors.white38),
                          ),
                        );
                      }

                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: 1100,
                          child: ListView(
                            shrinkWrap: true,
                            children: [
                              _tableHeader(),
                              const SizedBox(height: 6),
                              for (int i = 0; i < filteredDocs.length; i++) _buildRow(filteredDocs[i], i),
                              const SizedBox(height: 40),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // row ----------------------------------------------------------------
  Widget _buildRow(QueryDocumentSnapshot d, int index) {
    final data = d.data() as Map<String, dynamic>? ?? {};
    final seatLabel = (data['seatLabel'] ?? '').toString();
    final cust = (data['customerName'] ?? '').toString();
    final status = (data['status'] ?? 'active').toString();
    final paymentType = (data['paymentType'] ?? 'postpaid').toString();
    final startTs = data['startTime'] as Timestamp?;
    final start = startTs?.toDate();
    final durationMins = (data['durationMinutes'] ?? 0) as int;

    final bookingLabel = [
      if (cust.isNotEmpty) cust,
      if (seatLabel.isNotEmpty) seatLabel,
    ].join(' – ');

    String dateStr = '—';
    String timeStr = '—';
    if (start != null) {
      dateStr = '${start.day.toString().padLeft(2, '0')} ${_monthShort(start.month)}';
      timeStr = '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    }

    bool isOverdue = false;
    if (status == 'active' && start != null) {
      final end = start.add(Duration(minutes: durationMins));
      isOverdue = DateTime.now().isAfter(end);
    }
    if (_hideOverdue && isOverdue) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _cell(40, Text('#${index + 1}', style: const TextStyle(color: Colors.white))),
          _cell(160, Text(bookingLabel, style: const TextStyle(color: Colors.white))),
          _cell(120, Text(seatLabel, style: const TextStyle(color: Colors.white))),
          _cell(110, Text(dateStr, style: const TextStyle(color: Colors.white70))),
          _cell(90, Text(timeStr, style: const TextStyle(color: Colors.white70))),
          _cell(
            160,
            Builder(builder: (context) {
              if (status == 'reserved') {
                return const Text('Yet to start', style: TextStyle(color: Colors.orangeAccent));
              }
              if (status == 'active' && start != null) {
                return BookingCountdown(endTime: start.add(Duration(minutes: durationMins)));
              }
              if (status == 'cancelled' || status == 'canceled') {
                return const Text('cancelled', style: TextStyle(color: Colors.redAccent));
              }
              return Text(status, style: const TextStyle(color: Colors.white70));
            }),
          ),
          _cell(110, _PaymentChip(paymentType: paymentType)),
          _cell(110, _StatusChip(status: status)),
          _cell(
            180,
            Builder(builder: (context) {
              // completed / cancelled → view details
              if (status == 'completed' || status == 'cancelled' || status == 'canceled') {
                return Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          if (_selectedBranchId == null) return;
                          showDialog(
                            context: context,
                            builder: (_) => BookingActionsDialog(
                              branchId: _selectedBranchId!,
                              sessionId: d.id,
                              data: data,
                            ),
                          );
                        },
                        child: const Text('View details', style: TextStyle(color: Colors.white70)),
                      ),
                    ),
                  ],
                );
              }

              // RESERVED
              if (status == 'reserved') {
                return Row(
                  children: [
                    IconButton(
                      tooltip: 'Start now',
                      onPressed: () async {
                        if (_selectedBranchId == null) return;
                        await FirebaseFirestore.instance
                            .collection('branches')
                            .doc(_selectedBranchId!)
                            .collection('sessions')
                            .doc(d.id)
                            .update({
                          'status': 'active',
                          'startTime': Timestamp.fromDate(DateTime.now()),
                        });
                      },
                      icon: const Icon(Icons.play_arrow, color: Colors.greenAccent),
                    ),
                    IconButton(
                      tooltip: 'Cancel booking',
                      onPressed: () async {
                        if (_selectedBranchId == null) return;
                        await FirebaseFirestore.instance
                            .collection('branches')
                            .doc(_selectedBranchId!)
                            .collection('sessions')
                            .doc(d.id)
                            .update({'status': 'cancelled'});
                      },
                      icon: const Icon(Icons.close, color: Colors.redAccent),
                    ),
                    IconButton(
                      tooltip: 'Details',
                      onPressed: () {
                        if (_selectedBranchId == null) return;
                        showDialog(
                          context: context,
                          builder: (_) => BookingActionsDialog(
                            branchId: _selectedBranchId!,
                            sessionId: d.id,
                            data: data,
                          ),
                        );
                      },
                      icon: const Icon(Icons.info_outline, color: Colors.white70),
                    ),
                  ],
                );
              }

              // ACTIVE
              if (status == 'active' && isOverdue) {
                // Overdue → explicit Actions + Close options
                return Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        if (_selectedBranchId == null) return;
                        showDialog(
                          context: context,
                          builder: (_) => BookingActionsDialog(
                            branchId: _selectedBranchId!,
                            sessionId: d.id,
                            data: data,
                          ),
                        );
                      },
                      child: const Text('Actions', style: TextStyle(color: Colors.white70)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        if (_selectedBranchId == null) return;
                        showDialog(
                          context: context,
                          builder: (_) => BookingCloseBillDialog(
                            branchId: _selectedBranchId!,
                            sessionId: d.id,
                            data: data,
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Close'),
                    ),
                  ],
                );
              }

              // ACTIVE → normal full actions
              if (status == 'active') {
                return Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          if (_selectedBranchId == null) return;
                          showDialog(
                            context: context,
                            builder: (_) => BookingActionsDialog(
                              branchId: _selectedBranchId!,
                              sessionId: d.id,
                              data: data,
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                        ),
                        child: const Text('Actions'),
                      ),
                    ),
                  ],
                );
              }

              // fallback
              return const SizedBox.shrink();
            }),
          ),
        ],
      ),
    );
  }

  // helpers ------------------------------------------------------------
  Widget _cell(double width, Widget child) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: child,
      ),
    );
  }

  Widget _tableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: const [
          _HeaderCell(width: 40, label: '#'),
          _HeaderCell(width: 160, label: 'Booking'),
          _HeaderCell(width: 120, label: 'Seat'),
          _HeaderCell(width: 110, label: 'Date'),
          _HeaderCell(width: 90, label: 'Start'),
          _HeaderCell(width: 160, label: 'Time / Status'),
          _HeaderCell(width: 110, label: 'Payment'),
          _HeaderCell(width: 110, label: 'Status'),
          _HeaderCell(width: 180, label: 'Actions'),
        ],
      ),
    );
  }

  Widget _upcomingChip(String label, int minutes) {
    final selected = _upcomingWindowMins == minutes;
    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: InkWell(
        onTap: () => setState(() => _upcomingWindowMins = minutes),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _segBtn({
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        height: 34,
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: selected ? Colors.black : Colors.white70),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.black : Colors.white70,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _monthShort(int m) {
    const arr = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return arr[m];
  }
}

// header cell ----------------------------------------------------------
class _HeaderCell extends StatelessWidget {
  final double width;
  final String label;
  const _HeaderCell({required this.width, required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// payment chip --------------------------------------------------------
class _PaymentChip extends StatelessWidget {
  final String paymentType;
  const _PaymentChip({required this.paymentType});

  @override
  Widget build(BuildContext context) {
    final isPrepaid = paymentType == 'prepaid';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (isPrepaid ? Colors.blue : Colors.green).withOpacity(0.2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isPrepaid ? 'Prepaid' : 'Postpaid',
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
  }
}

// status chip ---------------------------------------------------------
class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color c = Colors.white12;
    String label = status;

    if (status == 'cancelled' || status == 'canceled') {
      c = Colors.red.withOpacity(0.25);
      label = 'Cancelled';
    } else if (status == 'completed') {
      c = Colors.grey.withOpacity(0.25);
      label = 'Completed';
    } else if (status == 'reserved') {
      c = Colors.orange.withOpacity(0.25);
      label = 'Reserved';
    } else if (status == 'active') {
      c = Colors.blue.withOpacity(0.25);
      label = 'Active';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
  }
}

// countdown ------------------------------------------------------------
class BookingCountdown extends StatefulWidget {
  final DateTime endTime;
  const BookingCountdown({super.key, required this.endTime});

  @override
  State<BookingCountdown> createState() => _BookingCountdownState();
}

class _BookingCountdownState extends State<BookingCountdown> {
  Timer? _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = widget.endTime.difference(DateTime.now());
    _startTimer();
  }

  void _startTimer() {
    if (_remaining.isNegative) {
      _remaining = Duration.zero;
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      final diff = widget.endTime.difference(DateTime.now());
      if (!mounted) return;
      setState(() {
        _remaining = diff.isNegative ? Duration.zero : diff;
      });
      if (diff.isNegative) {
        t.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmt(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final d = _remaining.isNegative ? Duration.zero : _remaining;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);

    return Text(
      'Time left: ${_fmt(h)}:${_fmt(m)}:${_fmt(s)}',
      style: TextStyle(
        color: d.inMinutes <= 1 ? Colors.redAccent : Colors.greenAccent,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
