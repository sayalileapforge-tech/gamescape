import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../layout/dashboard_layout.dart';

class ConsoleMapSection extends StatelessWidget implements DashboardSectionWidget {
  final String branchId;
  const ConsoleMapSection({super.key, required this.branchId});

  @override
  String get persistentKey => 'console_map';

  @override
  String get title => 'Console Map (Live)';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(20),
      ),
      child: _BranchConsoleGrid(branchId: branchId),
    );
  }
}

class _SeatSession {
  final String id;
  final String status;
  final String customerName;
  final DateTime? start;
  final DateTime? end;

  _SeatSession({
    required this.id,
    required this.status,
    required this.customerName,
    required this.start,
    required this.end,
  });
}

class _BranchConsoleGrid extends StatelessWidget {
  final String branchId;
  const _BranchConsoleGrid({required this.branchId});

  // Natural sort key for labels like C1, C2, C10, PC-1, etc.
  List _labelKey(String label) {
    final match = RegExp(r'^([A-Za-z\-_\s]*)(\d+)$').firstMatch(label.trim());
    if (match != null) {
      final prefix = match.group(1)!.toUpperCase();
      final numPart = int.tryParse(match.group(2)!) ?? 0;
      return [prefix, numPart];
    }
    return [label.toUpperCase(), 0];
  }

  @override
  Widget build(BuildContext context) {
    final seatsRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('seats');

    final sessionsRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('sessions');

    return StreamBuilder<QuerySnapshot>(
      stream: seatsRef.snapshots(),
      builder: (context, seatsSnap) {
        final seats = seatsSnap.data?.docs ?? [];

        // sort seats by natural label order (C1, C2, …, C10)
        final sortedSeats = seats.toList()
          ..sort((a, b) {
            final ad = (a.data() as Map<String, dynamic>? ?? {});
            final bd = (b.data() as Map<String, dynamic>? ?? {});
            final al = (ad['label']?.toString() ?? a.id);
            final bl = (bd['label']?.toString() ?? b.id);
            final ak = _labelKey(al);
            final bk = _labelKey(bl);
            final c1 = (ak[0] as String).compareTo(bk[0] as String);
            if (c1 != 0) return c1;
            return (ak[1] as int).compareTo(bk[1] as int);
          });

        return StreamBuilder<QuerySnapshot>(
          stream: sessionsRef.snapshots(),
          builder: (context, sessionsSnap) {
            if ((seatsSnap.connectionState == ConnectionState.waiting &&
                    seatsSnap.data == null)) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(color: Colors.white),
              );
            }
            if (seatsSnap.hasError || sessionsSnap.hasError) {
              return const Text('Failed to load consoles.',
                  style: TextStyle(color: Colors.white70));
            }
            if (sortedSeats.isEmpty) {
              return const Text('No consoles/seats found for this branch.',
                  style: TextStyle(color: Colors.white70));
            }

            final sessions = sessionsSnap.data?.docs ?? [];
            final Map<String, List<_SeatSession>> sessionsBySeat = {};
            for (final s in sessions) {
              final sData = s.data() as Map<String, dynamic>? ?? {};
              final seatId = sData['seatId']?.toString();
              if (seatId == null) continue;

              final statusRaw = sData['status']?.toString() ?? 'active';
              final status = statusRaw.toLowerCase();
              if (status == 'cancelled' || status == 'completed') continue;

              final start = (sData['startTime'] as Timestamp?)?.toDate();
              final dur = (sData['durationMinutes'] as num?)?.toInt() ?? 60;
              final end = start != null ? start.add(Duration(minutes: dur)) : null;

              sessionsBySeat.putIfAbsent(seatId, () => []).add(
                    _SeatSession(
                      id: s.id,
                      status: statusRaw,
                      customerName:
                          sData['customerName']?.toString() ?? 'Walk-in',
                      start: start,
                      end: end,
                    ),
                  );
            }

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: sortedSeats.length,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.15,
              ),
              itemBuilder: (context, index) {
                final seatDoc = sortedSeats[index];
                final seatId = seatDoc.id;
                final data =
                    seatDoc.data() as Map<String, dynamic>? ?? {};
                final label =
                    data['label']?.toString() ?? 'Seat ${index + 1}';
                final type = data['type']?.toString() ?? 'console';
                final isActive = (data['active'] as bool?) ?? true;

                final seatSessions = (sessionsBySeat[seatId] ?? []).toList()
                  ..sort((a, b) {
                    final aStart =
                        a.start ?? DateTime.fromMillisecondsSinceEpoch(0);
                    final bStart =
                        b.start ?? DateTime.fromMillisecondsSinceEpoch(0);
                    return aStart.compareTo(bStart);
                  });

                String status = 'free';
                bool hasActiveNow = false;
                bool hasReservedFuture = false;
                bool hasFutureAny = false;

                for (final s in seatSessions) {
                  final start = s.start;
                  final end = s.end;
                  if (start == null || end == null) continue;
                  final now = DateTime.now();
                  if (now.isAfter(start) && now.isBefore(end)) {
                    hasActiveNow = true;
                  }
                  if (s.status.toLowerCase() == 'reserved' &&
                      start.isAfter(now)) {
                    hasReservedFuture = true;
                  }
                  if (start.isAfter(now)) {
                    hasFutureAny = true;
                  }
                }

                if (hasActiveNow) {
                  status = 'in_use';
                } else if (hasReservedFuture) {
                  status = 'reserved';
                } else if (hasFutureAny) {
                  status = 'booked';
                }

                bool hasOverlap = false;
                for (var i = 0; i < seatSessions.length; i++) {
                  final a = seatSessions[i];
                  if (a.start == null || a.end == null) continue;
                  for (var j = i + 1; j < seatSessions.length; j++) {
                    final b = seatSessions[j];
                    if (b.start == null || b.end == null) continue;
                    final overlap =
                        a.start!.isBefore(b.end!) &&
                            b.start!.isBefore(a.end!);
                    if (overlap) {
                      hasOverlap = true;
                      break;
                    }
                  }
                  if (hasOverlap) break;
                }

                return _ConsoleTile(
                  label: label,
                  type: type,
                  isActive: isActive,
                  status: status,
                  sessions: seatSessions,
                  hasOverlap: hasOverlap,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ConsoleTile extends StatelessWidget {
  final String label;
  final String type;
  final bool isActive;
  final String status; // 'free' | 'in_use' | 'booked' | 'reserved'
  final List<_SeatSession> sessions;
  final bool hasOverlap;

  const _ConsoleTile({
    required this.label,
    required this.type,
    required this.isActive,
    required this.status,
    required this.sessions,
    required this.hasOverlap,
  });

  Color _statusColor() {
    switch (status) {
      case 'in_use':
        return Colors.grey.shade300;
      case 'booked':
        return Colors.amberAccent;
      case 'reserved':
        return Colors.orangeAccent;
      default:
        return Colors.greenAccent;
    }
  }

  Color _statusBg() {
    switch (status) {
      case 'in_use':
        return const Color(0xFF374151);
      case 'booked':
        return const Color(0xFF3B2F0B);
      case 'reserved':
        return const Color(0xFF4A1F1A);
      default:
        return const Color(0xFF064E3B);
    }
  }

  String _statusTextLabel() {
    // Renamed to avoid any `_statusText` duplicate in file.
    switch (status) {
      case 'in_use':
        return 'In use';
      case 'booked':
        return 'Booked';
      case 'reserved':
        return 'Reserved';
      default:
        return 'Free';
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
      onTap: sessions.isEmpty
          ? null
          : () {
              showDialog(
                context: context,
                builder: (_) => Dialog(
                  backgroundColor: const Color(0xFF111827),
                  child: DefaultTextStyle(
                    style: const TextStyle(color: Colors.white),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      width: 360,
                      color: const Color(0xFF111827),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 16)),
                          const SizedBox(height: 8),
                          Text('Status: ${_statusTextLabel()}'),
                          if (!isActive)
                            const Text('Console is marked inactive',
                                style: TextStyle(
                                    color: Colors.redAccent, fontSize: 12)),
                          const SizedBox(height: 12),
                          if (hasOverlap)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8.0),
                              child: Text(
                                '⚠ Overlapping bookings detected on this console.',
                                style: TextStyle(
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          const Text('Bookings for this console',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(height: 8),
                          if (sessions.isEmpty)
                            const Text('No bookings found.',
                                style: TextStyle(color: Colors.white70)),
                          if (sessions.isNotEmpty)
                            ...sessions.map((s) {
                              final st = s.start;
                              final et = s.end;
                              final stStr = st != null
                                  ? '${st.hour.toString().padLeft(2, '0')}:${st.minute.toString().padLeft(2, '0')}'
                                  : '—';
                              final etStr = et != null
                                  ? '${et.hour.toString().padLeft(2, '0')}:${et.minute.toString().padLeft(2, '0')}'
                                  : '—';
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4.0),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                          color: Colors.white10,
                                          borderRadius:
                                              BorderRadius.circular(999)),
                                      child: Text(s.status,
                                          style: const TextStyle(fontSize: 10)),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        s.customerName,
                                        style: const TextStyle(
                                            fontSize: 13, color: Colors.white),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text('$stStr–$etStr',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.white70)),
                                  ],
                                ),
                              );
                            }),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Close',
                                  style: TextStyle(color: Colors.white70)),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
      child: Container(
        decoration: BoxDecoration(
          color: _statusBg(),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _statusColor(), width: 3),
        ),
        padding: const EdgeInsets.all(10),
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_iconForType(), color: Colors.white, size: 30),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  isActive ? type : '$type (inactive)',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                if (sessions.length > 1)
                  const Padding(
                    padding: EdgeInsets.only(top: 4.0),
                    child: Text('Multiple bookings',
                        style:
                            TextStyle(color: Colors.white70, fontSize: 10)),
                  ),
              ],
            ),
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _statusColor().withOpacity(0.2),
                  border: Border.all(color: _statusColor()),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusTextLabel(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
