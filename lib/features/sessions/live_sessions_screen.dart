import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/app_shell.dart';
import '../bookings/booking_actions_dialog.dart';
import '../bookings/booking_close_bill_dialog.dart';

enum SessionState { activeLive, activeOverdue, reservedFuture, reservedPast, completed, cancelled }

DateTime _tsUtc(dynamic ts) =>
    (ts is Timestamp ? ts.toDate() : (ts as DateTime?))?.toUtc() ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

SessionState getSessionState(Map<String, dynamic> s, DateTime nowUtc) {
  final status = (s['status'] as String?) ?? 'reserved';
  final start = _tsUtc(s['startTime']);
  final durationMins = (s['durationMinutes'] as num?)?.toInt() ?? 0;
  final endAt = start.add(Duration(minutes: durationMins));
  if (status == 'completed') return SessionState.completed;
  if (status == 'cancelled') return SessionState.cancelled;
  if (status == 'active') return nowUtc.isBefore(endAt) ? SessionState.activeLive : SessionState.activeOverdue;
  if (status == 'reserved') return start.isAfter(nowUtc) ? SessionState.reservedFuture : SessionState.reservedPast;
  return SessionState.cancelled;
}

class LiveSessionsScreen extends StatefulWidget {
  const LiveSessionsScreen({super.key});
  @override
  State<LiveSessionsScreen> createState() => _LiveSessionsScreenState();
}

class _LiveSessionsScreenState extends State<LiveSessionsScreen> {
  bool _showMap = false;
  String? _selectedBranchId;
  bool _hasInitializedBranch = false;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return AppShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(
              'Live Sessions',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
            ),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1F2937),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(children: [
                _ToggleChip(label: 'List', selected: !_showMap, onTap: () => setState(() => _showMap = false)),
                _ToggleChip(label: 'Map', selected: _showMap, onTap: () => setState(() => _showMap = true)),
              ]),
            ),
          ]),
          const SizedBox(height: 16),

          if (user == null)
            const Text('Not logged in', style: TextStyle(color: Colors.white70))
          else
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
              builder: (context, userSnap) {
                final userData = userSnap.data?.data() as Map<String, dynamic>? ?? {};
                final role = (userData['role'] ?? 'staff').toString();
                final List<dynamic> branchIdsDyn = (userData['branchIds'] as List<dynamic>?) ?? [];
                final allowedBranchIds = branchIdsDyn.map((e) => e.toString()).toList();

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('branches').snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 4.0),
                        child: LinearProgressIndicator(color: Colors.white),
                      );
                    }

                    final allBranches = snap.data?.docs ?? [];
                    final visibleBranches = (role == 'superadmin' || allowedBranchIds.isEmpty)
                        ? allBranches
                        : allBranches.where((b) => allowedBranchIds.contains(b.id)).toList();

                    if (visibleBranches.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text('No branches assigned.', style: TextStyle(color: Colors.white70)),
                      );
                    }

                    if (!_hasInitializedBranch && visibleBranches.isNotEmpty && userSnap.hasData) {
                      _hasInitializedBranch = true;
                      
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        
                        final lastSelectedBranchId = userData['lastSelectedBranchId'] as String?;
                        String? initialBranch;
                        
                        if (lastSelectedBranchId != null &&
                            visibleBranches.any((b) => b.id == lastSelectedBranchId)) {
                          initialBranch = lastSelectedBranchId;
                        } else {
                          initialBranch = visibleBranches.first.id;
                        }
                        
                        setState(() {
                          _selectedBranchId = initialBranch;
                        });
                      });
                    }

                    final value = _selectedBranchId ?? visibleBranches.first.id;

                    return Row(children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: value,
                          dropdownColor: const Color(0xFF111827),
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Select branch',
                            labelStyle: TextStyle(color: Colors.white70),
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                          ),
                          items: visibleBranches
                              .map((b) => DropdownMenuItem(
                                    value: b.id,
                                    child: Text(((b.data() as Map<String, dynamic>?) ?? {})['name']?.toString() ?? b.id),
                                  ))
                              .toList(),
                          onChanged: (v) async {
                            setState(() => _selectedBranchId = v);
                            
                            if (v != null && user != null) {
                              try {
                                final branchDoc = visibleBranches.firstWhere((b) => b.id == v);
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
                        ),
                      ),
                    ]);
                  },
                );
              },
            ),
          const SizedBox(height: 16),

          Expanded(
            child: _selectedBranchId == null
                ? const Center(child: Text('No branches found.', style: TextStyle(color: Colors.white70)))
                : _showMap
                    ? _LiveSessionsMapView(branchId: _selectedBranchId!)
                    : _LiveSessionsListView(branchId: _selectedBranchId!),
          ),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ToggleChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: selected ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(30)),
        child: Text(label, style: TextStyle(color: selected ? Colors.black : Colors.white, fontWeight: FontWeight.w500)),
      ),
    );
  }
}

enum LiveFilter { all, live, overdue }

class _LiveSessionsListView extends StatefulWidget {
  final String branchId;
  const _LiveSessionsListView({required this.branchId});
  @override
  State<_LiveSessionsListView> createState() => _LiveSessionsListViewState();
}

class _LiveSessionsListViewState extends State<_LiveSessionsListView> {
  LiveFilter _filter = LiveFilter.all;

  @override
  Widget build(BuildContext context) {
    final sessionsRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('sessions');

    return StreamBuilder<QuerySnapshot>(
      stream: sessionsRef.snapshots(),
      builder: (context, sessionSnap) {
        if (sessionSnap.hasError) {
          return Center(
            child: Text('Could not load sessions.\n${sessionSnap.error}',
                style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center),
          );
        }
        if (sessionSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }

        final allDocs = List<QueryDocumentSnapshot>.from(sessionSnap.data?.docs ?? <QueryDocumentSnapshot>[]);
        allDocs.sort((a, b) {
          final am = (a.data() as Map<String, dynamic>? ?? {});
          final bm = (b.data() as Map<String, dynamic>? ?? {});
          return _tsUtc(am['startTime']).compareTo(_tsUtc(bm['startTime']));
        });

        final nowUtc = DateTime.now().toUtc();

        final filtered = allDocs.where((d) {
          final m = (d.data() as Map<String, dynamic>?) ?? {};
          final st = getSessionState(m, nowUtc);
          switch (_filter) {
            case LiveFilter.all:
              return st == SessionState.activeLive || st == SessionState.activeOverdue;
            case LiveFilter.live:
              return st == SessionState.activeLive;
            case LiveFilter.overdue:
              return st == SessionState.activeOverdue;
          }
        }).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FiltersBar(filter: _filter, onChange: (f) => setState(() => _filter = f)),
            const SizedBox(height: 10),
            if (filtered.isEmpty)
              const Expanded(child: Center(child: Text('No sessions found for this filter.', style: TextStyle(color: Colors.white70))))
            else ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: const Color(0xFF1F2937), borderRadius: BorderRadius.circular(12)),
                child: Row(children: const [
                  Expanded(flex: 2, child: Text('Customer', style: TextStyle(color: Colors.white70))),
                  Expanded(flex: 1, child: Text('Console', style: TextStyle(color: Colors.white70))),
                  Expanded(flex: 1, child: Text('Time In', style: TextStyle(color: Colors.white70))),
                  Expanded(flex: 1, child: Text('Time Out', style: TextStyle(color: Colors.white70))),
                  Expanded(flex: 1, child: Text('Time Left', style: TextStyle(color: Colors.white70))),
                  Expanded(flex: 1, child: Text('Payment', style: TextStyle(color: Colors.white70))),
                  SizedBox(width: 120, child: Text('Actions', style: TextStyle(color: Colors.white70))),
                ]),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final doc = filtered[i];
                    final m = doc.data() as Map<String, dynamic>? ?? {};
                    final customer = m['customerName']?.toString() ?? 'Walk-in';
                    final seat = m['seatLabel']?.toString() ?? 'Seat';
                    final startUtc = _tsUtc(m['startTime']);
                    final dur = (m['durationMinutes'] as num?)?.toInt() ?? 60;
                    final endUtc = startUtc.add(Duration(minutes: dur));
                    final payType = m['paymentType']?.toString() ?? 'postpaid';
                    final st = getSessionState(m, DateTime.now().toUtc());

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(color: const Color(0xFF1F2937), borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        Expanded(
                          flex: 2,
                          child: Row(children: [
                            _StateBadge(state: st),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                customer,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ]),
                        ),
                        Expanded(flex: 1, child: Text(seat, style: const TextStyle(color: Colors.white70))),
                        Expanded(flex: 1, child: Text(_hhmmLocal(startUtc), style: const TextStyle(color: Colors.white70))),
                        Expanded(flex: 1, child: Text(_hhmmLocal(endUtc), style: const TextStyle(color: Colors.white70))),
                        // ✅ Only this widget ticks; the row/list stays stable
                        Expanded(
                          flex: 1,
                          child: _TimeLeftCell(
                            startUtc: startUtc,
                            durationMinutes: dur,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            (payType == 'prepaid') ? 'Prepaid' : 'Postpaid',
                            style: TextStyle(color: (payType == 'prepaid') ? Colors.blueAccent : Colors.greenAccent),
                          ),
                        ),
                        SizedBox(
                          width: 120,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _ActionsMenu(branchId: widget.branchId, sessionId: doc.id, data: m, state: st),
                          ),
                        ),
                      ]),
                    );
                  },
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  static String _hhmmLocal(DateTime utc) {
    final dt = utc.toLocal();
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _FiltersBar extends StatelessWidget {
  final LiveFilter filter;
  final ValueChanged<LiveFilter> onChange;
  const _FiltersBar({required this.filter, required this.onChange});
  @override
  Widget build(BuildContext context) {
    Widget chip(String label, LiveFilter f) => ChoiceChip(
          label: Text(label),
          selected: filter == f,
          onSelected: (_) => onChange(f),
          selectedColor: Colors.white,
          labelStyle: TextStyle(color: filter == f ? Colors.black : Colors.white),
          backgroundColor: const Color(0xFF1F2937),
        );
    return Wrap(
      spacing: 8,
      children: [chip('All', LiveFilter.all), chip('Live', LiveFilter.live), chip('Overdue', LiveFilter.overdue)],
    );
  }
}

class _TimeLeftCell extends StatefulWidget {
  final DateTime startUtc;
  final int durationMinutes;
  const _TimeLeftCell({required this.startUtc, required this.durationMinutes});

  @override
  State<_TimeLeftCell> createState() => _TimeLeftCellState();
}

class _TimeLeftCellState extends State<_TimeLeftCell> {
  late DateTime _endUtc;
  late Timer _timer;
  Duration _left = Duration.zero;

  @override
  void initState() {
    super.initState();
    _endUtc = widget.startUtc.add(Duration(minutes: widget.durationMinutes));
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(_TimeLeftCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.durationMinutes != widget.durationMinutes ||
        oldWidget.startUtc != widget.startUtc) {
      _endUtc = widget.startUtc.add(Duration(minutes: widget.durationMinutes));
      _tick();
    }
  }

  void _tick() {
    final nowUtc = DateTime.now().toUtc();
    setState(() {
      _left = _endUtc.difference(nowUtc);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final negative = _left.isNegative;
    final d = negative ? _left.abs() : _left;
    final hh = d.inHours.toString().padLeft(2, '0');
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final txt = '${negative ? '-' : ''}$hh:$mm:$ss';
    final color = negative ? Colors.redAccent : (_left.inMinutes <= 10 ? Colors.amberAccent : Colors.greenAccent);
    return Text(txt, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12));
  }
}

class _StateBadge extends StatelessWidget {
  final SessionState state;
  const _StateBadge({required this.state});
  @override
  Widget build(BuildContext context) {
    String label;
    Color c;
    switch (state) {
      case SessionState.activeLive:
        label = 'LIVE';
        c = Colors.greenAccent;
        break;
      case SessionState.activeOverdue:
        label = 'OVERDUE';
        c = Colors.redAccent;
        break;
      case SessionState.reservedFuture:
        label = 'RESERVED';
        c = Colors.blueAccent;
        break;
      case SessionState.reservedPast:
        label = 'EXPIRED';
        c = Colors.orangeAccent;
        break;
      case SessionState.completed:
        label = 'DONE';
        c = Colors.white54;
        break;
      case SessionState.cancelled:
        label = 'CANCELLED';
        c = Colors.white30;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c),
      ),
      child: Text(label, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

class _ActionsMenu extends StatelessWidget {
  final String branchId;
  final String sessionId;
  final Map<String, dynamic> data;
  final SessionState state;
  const _ActionsMenu({required this.branchId, required this.sessionId, required this.data, required this.state});
  @override
  Widget build(BuildContext context) {
    final isActive = state == SessionState.activeLive || state == SessionState.activeOverdue;
    final isOverdue = state == SessionState.activeOverdue;
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      onSelected: (v) {
        switch (v) {
          case 'extend':
          case 'addOrder':
          case 'move':
            showDialog(context: context, builder: (_) => BookingActionsDialog(branchId: branchId, sessionId: sessionId, data: data));
            break;
          case 'close':
            showDialog(context: context, builder: (_) => BookingCloseBillDialog(branchId: branchId, sessionId: sessionId, data: data));
            break;
          case 'startNow':
          case 'cancel':
            showDialog(context: context, builder: (_) => BookingActionsDialog(branchId: branchId, sessionId: sessionId, data: data));
            break;
        }
      },
      itemBuilder: (ctx) {
        final items = <PopupMenuEntry<String>>[];
        if (isActive) {
          items.add(const PopupMenuItem(value: 'extend', child: Text('Extend by 30 mins')));
          if (!isOverdue) {
            items.add(const PopupMenuItem(value: 'addOrder', child: Text('Add F&B')));
            items.add(const PopupMenuItem(value: 'move', child: Text('Move Seat')));
          }
          items.add(const PopupMenuDivider());
          items.add(PopupMenuItem(value: 'close', child: Text(isOverdue ? 'Close (Overdue)' : 'Close & Bill')));
        }
        if (state == SessionState.reservedFuture) {
          items.add(const PopupMenuItem(value: 'startNow', child: Text('Start Now')));
          items.add(const PopupMenuItem(value: 'cancel', child: Text('Cancel Reservation')));
        }
        if (items.isEmpty) items.add(const PopupMenuItem(value: 'noop', enabled: false, child: Text('No actions')));
        return items;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.more_horiz, size: 16, color: Colors.white),
          SizedBox(width: 6),
          Text('Actions', style: TextStyle(color: Colors.white, fontSize: 12)),
        ]),
      ),
    );
  }
}

class _LiveSessionsMapView extends StatelessWidget {
  final String branchId;
  const _LiveSessionsMapView({required this.branchId});
  @override
  Widget build(BuildContext context) {
    final branchRef = FirebaseFirestore.instance.collection('branches').doc(branchId);
    final seatsRef = branchRef.collection('seats');
    final sessionsRef = branchRef.collection('sessions');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1F2937), borderRadius: BorderRadius.circular(20)),
      child: StreamBuilder<QuerySnapshot>(
        stream: seatsRef.snapshots(),
        builder: (context, seatsSnap) {
          return StreamBuilder<QuerySnapshot>(
            stream: sessionsRef.snapshots(),
            builder: (context, sessionsSnap) {
              if (seatsSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Colors.white));
              }
              final seats = seatsSnap.data?.docs ?? [];
              final sessions = sessionsSnap.data?.docs ?? [];
              if (seats.isEmpty) {
                return const Center(child: Text('No consoles/seats in this branch.', style: TextStyle(color: Colors.white70)));
              }
              final nowUtc = DateTime.now().toUtc();

              return GridView.builder(
                itemCount: seats.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.15,
                ),
                itemBuilder: (context, index) {
                  final seatDoc = seats[index];
                  final seatId = seatDoc.id;
                  final seatData = seatDoc.data() as Map<String, dynamic>? ?? {};
                  final label = seatData['label']?.toString() ?? 'Seat ${index + 1}';
                  final type = seatData['type']?.toString() ?? 'console';

                  String badge = 'Free';
                  Map<String, dynamic>? activeData;
                  String? sessionId;

                  for (final s in sessions) {
                    final sData = s.data() as Map<String, dynamic>? ?? {};
                    if (sData['seatId'] != seatId) continue;
                    final st = getSessionState(sData, nowUtc);
                    if (st == SessionState.activeLive) {
                      badge = 'Active';
                      activeData = sData;
                      sessionId = s.id;
                      break;
                    }
                    if (st == SessionState.activeOverdue) {
                      badge = 'Overdue';
                      activeData = sData;
                      sessionId = s.id;
                      break;
                    }
                    if (st == SessionState.reservedFuture && badge == 'Free') {
                      badge = 'Reserved';
                    }
                  }

                  return _ConsoleTileCompact(
                    label: label,
                    type: type,
                    statusBadge: badge,
                    onTap: (badge == 'Active' || badge == 'Overdue')
                        ? () {
                            showDialog(
                              context: context,
                              builder: (_) => BookingActionsDialog(
                                branchId: branchId,
                                sessionId: sessionId!,
                                data: activeData!,
                              ),
                            );
                          }
                        : null,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _ConsoleTileCompact extends StatelessWidget {
  final String label;
  final String type;
  final String statusBadge;
  final VoidCallback? onTap;
  const _ConsoleTileCompact({required this.label, required this.type, required this.statusBadge, this.onTap});

  Color _statusBorder() {
    switch (statusBadge) {
      case 'Active':
        return Colors.greenAccent;
      case 'Overdue':
        return Colors.redAccent;
      case 'Reserved':
        return Colors.blueAccent;
      default:
        return Colors.white24;
    }
  }

  Color _statusBg() {
    switch (statusBadge) {
      case 'Active':
        return const Color(0xFF064E3B);
      case 'Overdue':
        return const Color(0xFF4A1F1A);
      case 'Reserved':
        return const Color(0xFF0B3556);
      default:
        return const Color(0xFF111827);
    }
  }

  IconData _iconForType() {
    final lower = type.toLowerCase();
    if (lower.contains('pc')) return Icons.computer;
    if (lower.contains('console')) return Icons.sports_esports;
    if (lower.contains('recliner')) return Icons.chair_alt;
    return Icons.chair;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: _statusBg(),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _statusBorder(), width: 2),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(_iconForType(), color: Colors.white, size: 28),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(statusBadge, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ]),
      ),
    );
  }
}
