// lib/features/bookings/booking_timeline_view.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;

// ==== High-contrast palette (stronger than before) ====
const kGridHour = Color(0xFF3A4A6A); // strong hour
const kGridQuarter = Color(0xFF2E3E5A); // strong quarter
const kGridMinor = Color(0xFF223247); // visible minor
const kGridRow = Color(0xFF1F2B3E); // horizontal row lines

const kNowLine = Color(0xFFFFB020); // current-time line

const kActive = Color(0xFF38BDF8); // sky-400
const kOverdue = Color(0xFFFFB020); // amber-500
const kCompleted = Color(0xFF22C55E); // green-500
const kReserved = Color(0xFFA78BFA); // violet-400
const kCancelled = Color(0xFFF87171); // red-400

// ===== filter keys =====
const _kFilterActive = 'active';
const _kFilterOverdue = 'overdue';
const _kFilterCompleted = 'completed';
const _kFilterReserved = 'reserved';
const _kFilterCancelled = 'cancelled';

class BookingTimelineView extends StatefulWidget {
  final List<QueryDocumentSnapshot> bookings;
  final DateTime date;
  final String? branchId;

  const BookingTimelineView({
    super.key,
    required this.bookings,
    required this.date,
    this.branchId,
  });

  @override
  State<BookingTimelineView> createState() => _BookingTimelineViewState();
}

class _BookingTimelineViewState extends State<BookingTimelineView> {
  // ==== Base config (we will AUTO-EXPAND windowMinutes to fill viewport) ====
  static const int _minSpanMinutes = 120; // baseline
  static const int _cellMinutes = 5; // big squares: 5-min grid
  static const double _cellWidth5Min = 28;
  static const double _minuteWidth = _cellWidth5Min / _cellMinutes; // px per minute

  // Layout tokens
  static const double _leftRailWidth = 220;
  static const double _rowHeight = 44;
  static const double _headerHeight = 54;
  static const double _seatPillHeight = 40;

  // Controllers (synced)
  final _hBody = ScrollController();
  final _hHeader = ScrollController();
  final _vRail = ScrollController();
  final _vBody = ScrollController();

  bool _syncingH = false;
  bool _syncingV = false;

  Timer? _ticker;

  // Seat metadata
  Map<String, String> _seatLabelById = {};
  Map<String, Color> _seatColorById = {};
  String? _branchLoadedFor;

  // Filters state (persisted)
  Map<String, bool> _filters = const {
    _kFilterActive: true,
    _kFilterOverdue: true,
    _kFilterCompleted: true,
    _kFilterReserved: true,
    _kFilterCancelled: true,
  };

  bool get _isToday {
    final d = widget.date, n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  DateTime get _dayStart =>
      DateTime(widget.date.year, widget.date.month, widget.date.day);

  /// Window start minute from day start (snapped) for today, else 0.
  int _windowStartMinute(int windowMinutes) {
    if (!_isToday) return 0;

    final minsNow = DateTime.now().difference(_dayStart).inMinutes;
    final snapped = (minsNow ~/ _cellMinutes) * _cellMinutes;

    final maxStart = (24 * 60) - windowMinutes;
    return snapped.clamp(0, maxStart);
  }

  /// NEW: choose a window size that fills the viewport.
  /// - At least 120 mins
  /// - At least wideEnough for the current viewport
  /// - Rounded up to 60-minute blocks (clean hour labels)
  /// - Clamp to 24h
  int _computeWindowMinutes(double availableWidthPx) {
    final minPx = _minSpanMinutes * _minuteWidth;
    final targetPx = availableWidthPx.isFinite && availableWidthPx > 0
        ? availableWidthPx
        : minPx;

    final neededMinutes = (targetPx / _minuteWidth).ceil();
    final base = neededMinutes < _minSpanMinutes ? _minSpanMinutes : neededMinutes;

    // round to nearest 60-min block so hour labels and grid feel consistent
    int rounded = ((base + 59) ~/ 60) * 60;

    // keep sensible upper limit (full day)
    rounded = rounded.clamp(_minSpanMinutes, 24 * 60);
    return rounded;
  }

  @override
  void initState() {
    super.initState();

    _hBody.addListener(() {
      if (_syncingH) return;
      _syncingH = true;
      if (_hHeader.hasClients) _hHeader.jumpTo(_hBody.offset);
      _syncingH = false;
    });

    _vBody.addListener(() {
      if (_syncingV) return;
      _syncingV = true;
      if (_vRail.hasClients) _vRail.jumpTo(_vBody.offset);
      _syncingV = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToNow();
      _loadSeatMetaIfNeeded();
      _loadFiltersFromUserDoc();
    });

    _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && _isToday) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant BookingTimelineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.date != widget.date) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToNow());
    }
    _loadSeatMetaIfNeeded();

    if (oldWidget.branchId != widget.branchId) {
      _loadFiltersFromUserDoc();
    }
  }

  @override
  void dispose() {
    _hBody.dispose();
    _hHeader.dispose();
    _vRail.dispose();
    _vBody.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  // ===== persistence via users/{uid}.timelineFilters =====
  Future<void> _loadFiltersFromUserDoc() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final uref = FirebaseFirestore.instance.collection('users').doc(uid);
      final snap = await uref.get();
      final data = snap.data() as Map<String, dynamic>?;
      final raw = (data?['timelineFilters'] as Map?)
          ?.map((k, v) => MapEntry(k.toString(), v == true));
      if (raw == null) return;

      final next = Map<String, bool>.from(_filters);
      for (final k in [
        _kFilterActive,
        _kFilterOverdue,
        _kFilterCompleted,
        _kFilterReserved,
        _kFilterCancelled
      ]) {
        if (raw.containsKey(k) && raw[k] is bool) next[k] = raw[k]!;
      }
      if (!mounted) return;
      setState(() => _filters = next);
    } catch (_) {}
  }

  Future<void> _saveFiltersToUserDoc() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final uref = FirebaseFirestore.instance.collection('users').doc(uid);
      await uref.set({'timelineFilters': _filters}, SetOptions(merge: true));
    } catch (_) {}
  }

  void _toggleFilter(String key, bool value) {
    setState(() {
      _filters = Map<String, bool>.from(_filters)..[key] = value;
    });
    _saveFiltersToUserDoc();
  }

  void _selectAll(bool value) {
    setState(() {
      _filters = {
        _kFilterActive: value,
        _kFilterOverdue: value,
        _kFilterCompleted: value,
        _kFilterReserved: value,
        _kFilterCancelled: value,
      };
    });
    _saveFiltersToUserDoc();
  }

  void _scrollToNow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_hBody.hasClients) _hBody.jumpTo(0);
      if (_hHeader.hasClients) _hHeader.jumpTo(0);
    });
  }

  Future<void> _loadSeatMetaIfNeeded() async {
    if (widget.branchId != null) return;

    if (widget.bookings.isEmpty) return;
    final parent = widget.bookings.first.reference.parent.parent;
    final branchId = parent?.id;
    if (branchId == null || branchId.isEmpty) return;
    if (_branchLoadedFor == branchId) return;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('seats')
          .get();

      final labels = <String, String>{};
      final colors = <String, Color>{};
      for (final d in snap.docs) {
        final m = d.data();
        final raw = m['label'];
        final String lbl = raw == null ? '' : raw.toString().trim();
        labels[d.id] = lbl.isNotEmpty ? lbl : d.id;

        Color? c;
        if (m['uiColor'] is int) c = Color(m['uiColor']);
        if (c == null && m['colorHex'] is String) c = _hex(m['colorHex']);
        colors[d.id] = c ?? const Color(0xFF334155);
      }

      if (!mounted) return;
      setState(() {
        _seatLabelById = labels;
        _seatColorById = colors;
        _branchLoadedFor = branchId;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (widget.branchId != null) {
      final seatsRef = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('seats')
          .where('active', isEqualTo: true);

      return StreamBuilder<QuerySnapshot>(
        stream: seatsRef.snapshots(),
        builder: (context, seatsSnap) {
          final seatDocs = seatsSnap.data?.docs ?? <QueryDocumentSnapshot>[];

          final labels = <String, String>{};
          final colors = <String, Color>{};
          for (final d in seatDocs) {
            final m = d.data() as Map<String, dynamic>? ?? {};
            final raw = m['label'];
            final String lbl = raw == null ? '' : raw.toString().trim();
            labels[d.id] = lbl.isNotEmpty ? lbl : d.id;

            Color? c;
            if (m['uiColor'] is int) c = Color(m['uiColor']);
            if (c == null && m['colorHex'] is String) c = _hex(m['colorHex']);
            colors[d.id] = c ?? const Color(0xFF334155);
          }

          _seatLabelById = labels;
          _seatColorById = colors;
          _branchLoadedFor = widget.branchId;

          return _buildTimeline(seatDocs: seatDocs);
        },
      );
    }

    return _buildTimeline(seatDocs: const []);
  }

  String _displayStatusFor(Map<String, dynamic> m) {
    final status = (m['status'] ?? 'active').toString().toLowerCase();
    if (status == 'completed') return _kFilterCompleted;
    if (status == 'reserved') return _kFilterReserved;
    if (status == 'cancelled' || status == 'canceled') return _kFilterCancelled;

    final ts = m['startTime'] as Timestamp?;
    final st = ts?.toDate();
    final dur = (m['durationMinutes'] as num?)?.toInt() ?? 60;
    if (st == null) return _kFilterActive;
    final end = st.add(Duration(minutes: dur));
    if (DateTime.now().isAfter(end)) return _kFilterOverdue;
    return _kFilterActive;
  }

  Widget _buildTimeline({required List<QueryDocumentSnapshot> seatDocs}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // available width for the timeline canvas area
        final availableCanvasWidth = (constraints.maxWidth - _leftRailWidth).clamp(320.0, 100000.0);

        final windowMinutes = _computeWindowMinutes(availableCanvasWidth);
        final winStart = _windowStartMinute(windowMinutes);
        final winEnd = winStart + windowMinutes;
        final dayStart = _dayStart;

        final buckets = <_SeatBucket>[];
        final byKey = <String, _SeatBucket>{};

        if (seatDocs.isNotEmpty) {
          for (final s in seatDocs) {
            final data = s.data() as Map<String, dynamic>? ?? {};
            final seatId = s.id;
            final seatDocLabel = (data['label']?.toString().trim() ?? '');
            final label = _labelFor(seatId, seatDocLabel);
            final color = _colorFor(seatId);
            final key = '$label|$seatId';
            byKey.putIfAbsent(key, () {
              final b = _SeatBucket(label, color)..seatId = seatId;
              buckets.add(b);
              return b;
            });
          }
        }

        for (final d in widget.bookings) {
          final m = d.data() as Map<String, dynamic>;
          final ts = m['startTime'] as Timestamp?;
          if (ts == null) continue;
          final st = ts.toDate();
          if (st.year != dayStart.year ||
              st.month != dayStart.month ||
              st.day != dayStart.day) continue;

          final disp = _displayStatusFor(m);
          if (_filters[disp] != true) continue;

          final seatId = (m['seatId']?.toString().trim() ?? '');
          final seatDocLabel = (m['seatLabel']?.toString().trim() ?? '');
          final label = _labelFor(seatId, seatDocLabel);
          final color = _colorFor(seatId);

          final key = '$label|$seatId';
          final bucket = byKey.putIfAbsent(key, () {
            final b = _SeatBucket(label, color)..seatId = seatId;
            buckets.add(b);
            return b;
          });
          bucket.docs.add(d);
        }

        buckets.sort((a, b) {
          final cmp = _naturalCompare(a.label, b.label);
          if (cmp != 0) return cmp;
          return (a.seatId ?? '').compareTo(b.seatId ?? '');
        });

        for (final b in buckets) {
          b.rows = _rowsNeededWindow(b.docs, dayStart, winStart, winEnd);
          b.height = (b.rows * _rowHeight).clamp(_rowHeight, 1200);
        }

        final totalWidth = windowMinutes * _minuteWidth;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LegendFilterBar(
              filters: _filters,
              onChanged: _toggleFilter,
              onSelectAll: _selectAll,
            ),
            const SizedBox(height: 10),
            _HeaderRow2h(
              headerHeight: _headerHeight,
              leftRailWidth: _leftRailWidth,
              totalWidth: totalWidth,
              minuteWidth: _minuteWidth,
              windowStartMinute: winStart,
              controller: _hHeader,
              dayStart: dayStart,
              windowMinutes: windowMinutes,
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: _leftRailWidth,
                    child: Scrollbar(
                      controller: _vRail,
                      thumbVisibility: true,
                      thickness: 8,
                      radius: const Radius.circular(8),
                      child: ListView.builder(
                        controller: _vRail,
                        itemCount: buckets.length,
                        itemBuilder: (_, i) {
                          final b = buckets[i];
                          final status = _seatStatusNow(b.docs, dayStart);
                          return SizedBox(
                            height: b.height,
                            child: Center(
                              child: _SeatPill(
                                label: b.label,
                                seatColor: b.color,
                                status: status,
                                height: _seatPillHeight,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Expanded(
                    child: Scrollbar(
                      controller: _hBody,
                      notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
                      thumbVisibility: true,
                      thickness: 8,
                      radius: const Radius.circular(8),
                      child: SingleChildScrollView(
                        controller: _hBody,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: totalWidth,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Scrollbar(
                                  controller: _vBody,
                                  thumbVisibility: true,
                                  thickness: 8,
                                  radius: const Radius.circular(8),
                                  child: ListView.builder(
                                    controller: _vBody,
                                    itemCount: buckets.length,
                                    itemBuilder: (_, i) {
                                      final b = buckets[i];
                                      return SizedBox(
                                        height: b.height,
                                        child: Stack(
                                          children: [
                                            Positioned.fill(
                                              child: CustomPaint(
                                                painter: _GridPainter2h(
                                                  minuteWidth: _minuteWidth,
                                                  windowMinutes: windowMinutes,
                                                  rowHeight: _rowHeight,
                                                ),
                                              ),
                                            ),
                                            _LaneBlocks2h(
                                              docs: b.docs,
                                              dayStart: dayStart,
                                              minuteWidth: _minuteWidth,
                                              rowHeight: _rowHeight,
                                              windowStartMinute: winStart,
                                              windowEndMinute: winEnd,
                                            ),
                                            const Positioned(
                                              bottom: 0,
                                              left: 0,
                                              right: 0,
                                              child: Divider(height: 1, color: Colors.white12),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              if (_isToday)
                                _NowLine2h(
                                  dayStart: dayStart,
                                  minuteWidth: _minuteWidth,
                                  windowStartMinute: winStart,
                                  windowMinutes: windowMinutes,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _labelFor(String seatId, String docLabel) {
    if (docLabel.isNotEmpty) return docLabel;
    if (seatId.isEmpty) return 'Unknown';
    return _seatLabelById[seatId] ?? seatId;
  }

  Color _colorFor(String seatId) => _seatColorById[seatId] ?? const Color(0xFF334155);

  _SeatStatus _seatStatusNow(List<QueryDocumentSnapshot> docs, DateTime dayStart) {
    final now = DateTime.now();

    for (final d in docs) {
      final m = d.data() as Map<String, dynamic>;
      final ts = m['startTime'] as Timestamp?;
      if (ts == null) continue;
      final st = ts.toDate();
      final dur = (m['durationMinutes'] as num?)?.toInt() ?? 60;
      final end = st.add(Duration(minutes: dur));
      final status = (m['status'] ?? 'active').toString();

      if (status == 'cancelled' || status == 'canceled' || status == 'completed') continue;

      final overlapsNow = !now.isBefore(st) && now.isBefore(end);
      if (overlapsNow) {
        if (status == 'active' && end.isBefore(DateTime.now())) return _SeatStatus.overdue;
        return _SeatStatus.occupied;
      }
    }

    final horizon = now.add(const Duration(minutes: 60));
    for (final d in docs) {
      final m = d.data() as Map<String, dynamic>;
      final ts = m['startTime'] as Timestamp?;
      if (ts == null) continue;
      final st = ts.toDate();
      final status = (m['status'] ?? '').toString().toLowerCase();
      if (status == 'reserved' && st.isAfter(now) && st.isBefore(horizon)) {
        return _SeatStatus.reserved;
      }
    }

    return _SeatStatus.free;
  }

  int _rowsNeededWindow(
    List<QueryDocumentSnapshot> docs,
    DateTime dayStart,
    int windowStart,
    int windowEnd,
  ) {
    final ivs = <_Iv>[];
    for (final d in docs) {
      final m = d.data() as Map<String, dynamic>;
      final ts = m['startTime'] as Timestamp?;
      if (ts == null) continue;
      final st = ts.toDate();
      final dur = (m['durationMinutes'] as num?)?.toInt() ?? 60;
      final sAbs = st.difference(dayStart).inMinutes;
      final eAbs = sAbs + dur;

      final s = sAbs.clamp(windowStart, windowEnd);
      final e = eAbs.clamp(windowStart, windowEnd);
      if (e <= s) continue;

      ivs.add(_Iv(s - windowStart, e - windowStart));
    }

    ivs.sort((a, b) => a.s.compareTo(b.s));

    final rows = <List<_Iv>>[];
    for (final iv in ivs) {
      var placed = false;
      for (final r in rows) {
        final last = r.last;
        final overlap = iv.s < last.e && last.s < iv.e;
        if (!overlap) {
          r.add(iv);
          placed = true;
          break;
        }
      }
      if (!placed) rows.add([iv]);
    }
    return rows.isEmpty ? 1 : rows.length;
  }

  int _naturalCompare(String a, String b) {
    final re = RegExp(r'^([^\d]*)(\d+)$');
    final ma = re.firstMatch(a);
    final mb = re.firstMatch(b);
    if (ma != null && mb != null) {
      final pa = ma.group(1) ?? '';
      final pb = mb.group(1) ?? '';
      final ca = pa.compareTo(pb);
      if (ca != 0) return ca;
      final na = int.tryParse(ma.group(2) ?? '') ?? 0;
      final nb = int.tryParse(mb.group(2) ?? '') ?? 0;
      return na.compareTo(nb);
    }
    return a.compareTo(b);
  }

  static Color _hex(String s) {
    var h = s.trim();
    if (h.startsWith('#')) h = h.substring(1);
    if (h.length == 6) h = 'FF$h';
    return Color(int.tryParse(h, radix: 16) ?? 0xFF334155);
  }
}

// ===== Header (hour labels aligned to true hour boundaries) =====
class _HeaderRow2h extends StatelessWidget {
  final double headerHeight;
  final double leftRailWidth;
  final double totalWidth;
  final double minuteWidth;
  final int windowStartMinute;
  final ScrollController controller;
  final DateTime dayStart;
  final int windowMinutes;

  const _HeaderRow2h({
    required this.headerHeight,
    required this.leftRailWidth,
    required this.totalWidth,
    required this.minuteWidth,
    required this.windowStartMinute,
    required this.controller,
    required this.dayStart,
    required this.windowMinutes,
  });

  String _hh(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h';
  }

  String _ampm(DateTime d) => d.hour >= 12 ? 'PM' : 'AM';

  @override
  Widget build(BuildContext context) {
    final windowStart = dayStart.add(Duration(minutes: windowStartMinute));
    final windowEnd = windowStart.add(Duration(minutes: windowMinutes));

    DateTime firstHour = DateTime(windowStart.year, windowStart.month, windowStart.day, windowStart.hour, 0);
    if (firstHour.isBefore(windowStart)) {
      firstHour = firstHour.add(const Duration(hours: 1));
    }

    final hourMarks = <DateTime>[];
    var t = firstHour;
    while (!t.isAfter(windowEnd)) {
      hourMarks.add(t);
      t = t.add(const Duration(hours: 1));
    }

    return SizedBox(
      height: headerHeight,
      child: Row(
        children: [
          SizedBox(
            width: leftRailWidth,
            child: const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Seats',
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: controller,
              notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
              thumbVisibility: true,
              thickness: 8,
              radius: const Radius.circular(8),
              child: SingleChildScrollView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: totalWidth,
                  height: headerHeight,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        top: 0,
                        bottom: 24,
                        child: Stack(
                          children: [
                            for (final mark in hourMarks)
                              Positioned(
                                left: (mark.difference(windowStart).inMinutes * minuteWidth)
                                    .toDouble()
                                    .clamp(0, totalWidth),
                                top: 0,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      _hh(mark),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _ampm(mark),
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: 24,
                        child: _MinuteTicksRow(
                          minuteWidth: minuteWidth,
                          windowStartMinute: windowStartMinute,
                          dayStart: dayStart,
                          windowMinutes: windowMinutes,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MinuteTicksRow extends StatelessWidget {
  final double minuteWidth;
  final int windowStartMinute;
  final DateTime dayStart;
  final int windowMinutes;

  const _MinuteTicksRow({
    required this.minuteWidth,
    required this.windowStartMinute,
    required this.dayStart,
    required this.windowMinutes,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: List.generate(windowMinutes ~/ 5, (i) {
        final localMin = i * 5;
        final absMin = windowStartMinute + localMin;
        final dt = dayStart.add(Duration(minutes: absMin));
        final mm = dt.minute;

        final isHour = mm == 0;
        final isQuarter = (mm % 15 == 0);

        final color = isHour
            ? Colors.white70
            : (isQuarter ? Colors.white : Colors.white30);

        return Positioned(
          left: localMin * minuteWidth,
          child: SizedBox(
            width: 5 * minuteWidth,
            child: Text(
              mm.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ===== Legend / filters (Wrap to avoid overflow) =====
class _LegendFilterBar extends StatelessWidget {
  final Map<String, bool> filters;
  final void Function(String key, bool value) onChanged;
  final void Function(bool value) onSelectAll;

  const _LegendFilterBar({
    required this.filters,
    required this.onChanged,
    required this.onSelectAll,
  });

  @override
  Widget build(BuildContext context) {
    Widget item({
      required String key,
      required Color color,
      required String label,
    }) {
      final checked = filters[key] == true;
      return InkWell(
        onTap: () => onChanged(key, !checked),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Theme(
                data: Theme.of(context).copyWith(
                  checkboxTheme: CheckboxThemeData(
                    fillColor: WidgetStateProperty.resolveWith<Color?>(
                      (states) => states.contains(WidgetState.selected)
                          ? Colors.white
                          : Colors.transparent,
                    ),
                    checkColor: WidgetStateProperty.all(const Color(0xFF111827)),
                    side: const BorderSide(color: Colors.white70, width: 1.4),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                  ),
                ),
                child: Checkbox(
                  value: checked,
                  onChanged: (v) => onChanged(key, v ?? true),
                ),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
            ],
          ),
        ),
      );
    }

    final allChecked = filters.values.every((v) => v);
    final noneChecked = filters.values.every((v) => !v);

    Widget chipBtn(String text, VoidCallback onTap) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(
            text,
            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          item(key: _kFilterActive, color: kActive, label: 'Active'),
          item(key: _kFilterOverdue, color: kOverdue, label: 'Overdue'),
          item(key: _kFilterCompleted, color: kCompleted, label: 'Completed'),
          item(key: _kFilterReserved, color: kReserved, label: 'Reserved'),
          item(key: _kFilterCancelled, color: kCancelled, label: 'Cancelled'),
          chipBtn(allChecked ? 'All' : 'Select All', () => onSelectAll(true)),
          chipBtn(noneChecked ? 'None' : 'Clear All', () => onSelectAll(false)),
          const SizedBox(width: 6),
          const Text('Seat legend:', style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w800)),
          _SeatLegendPill(color: const Color(0xFF10B981), label: 'Free'),
          _SeatLegendPill(color: const Color(0xFF3B82F6), label: 'Occupied'),
          _SeatLegendPill(color: const Color(0xFF8B5CF6), label: 'Reserved'),
          _SeatLegendPill(color: const Color(0xFFFF8C00), label: 'Overdue'),
        ],
      ),
    );
  }
}

class _SeatLegendPill extends StatelessWidget {
  final Color color;
  final String label;
  const _SeatLegendPill({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800)),
      const SizedBox(width: 10),
    ]);
  }
}

// ===== Grid painter (NOW draws BOTH vertical + horizontal lines) =====
class _GridPainter2h extends CustomPainter {
  final double minuteWidth;
  final int windowMinutes;
  final double rowHeight;

  _GridPainter2h({
    required this.minuteWidth,
    required this.windowMinutes,
    required this.rowHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final hour = Paint()
      ..color = kGridHour
      ..strokeWidth = 1.6;

    final quarter = Paint()
      ..color = kGridQuarter
      ..strokeWidth = 1.2;

    final minor = Paint()
      ..color = kGridMinor
      ..strokeWidth = 1.0;

    final rowPaint = Paint()
      ..color = kGridRow
      ..strokeWidth = 1.0;

    // vertical lines (5-min)
    for (int m = 0; m <= windowMinutes; m += 5) {
      final x = m * minuteWidth;
      if (m % 60 == 0) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), hour);
      } else if (m % 15 == 0) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), quarter);
      } else {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), minor);
      }
    }

    // horizontal lines (rows)
    // draw at row boundaries so the grid actually “reads”
    for (double y = 0; y <= size.height; y += rowHeight) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter2h old) =>
      old.minuteWidth != minuteWidth ||
      old.windowMinutes != windowMinutes ||
      old.rowHeight != rowHeight;
}

// ===== Blocks =====
class _LaneBlocks2h extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final DateTime dayStart;
  final double minuteWidth;
  final double rowHeight;
  final int windowStartMinute;
  final int windowEndMinute;

  const _LaneBlocks2h({
    required this.docs,
    required this.dayStart,
    required this.minuteWidth,
    required this.rowHeight,
    required this.windowStartMinute,
    required this.windowEndMinute,
  });

  @override
  Widget build(BuildContext context) {
    final items = <_Block>[];

    for (final d in docs) {
      final m = d.data() as Map<String, dynamic>;
      final ts = m['startTime'] as Timestamp?;
      if (ts == null) continue;
      final st = ts.toDate();
      final dur = (m['durationMinutes'] as num?)?.toInt() ?? 60;

      final sAbs = st.difference(dayStart).inMinutes;
      final eAbs = sAbs + dur;

      final s = sAbs.clamp(windowStartMinute, windowEndMinute);
      final e = eAbs.clamp(windowStartMinute, windowEndMinute);
      if (e <= s) continue;

      items.add(_Block(m, s - windowStartMinute, e - windowStartMinute, 0));
    }

    items.sort((a, b) => a.s.compareTo(b.s));

    final rows = <List<_Block>>[];
    final laid = <_Block>[];
    for (final it in items) {
      var r = 0;
      while (true) {
        if (r >= rows.length) {
          rows.add([it]);
          laid.add(it.copyWith(r: r));
          break;
        }
        final last = rows[r].last;
        final overlap = it.s < last.e && last.s < it.e;
        if (!overlap) {
          rows[r].add(it);
          laid.add(it.copyWith(r: r));
          break;
        }
        r++;
      }
    }

    return Stack(
      children: [
        for (final b in laid)
          Positioned(
            top: b.r * rowHeight + 5,
            left: b.s * minuteWidth,
            width: (b.e - b.s) * minuteWidth,
            height: rowHeight - 10,
            child: _BlockChip(data: b.m),
          ),
      ],
    );
  }
}

class _BlockChip extends StatelessWidget {
  final Map<String, dynamic> data;
  const _BlockChip({required this.data});

  @override
  Widget build(BuildContext context) {
    final status = (data['status'] ?? 'active').toString();
    final name = (data['customerName'] ?? '').toString();
    final ts = data['startTime'] as Timestamp?;
    final start = ts?.toDate() ?? DateTime.now();
    final dur = (data['durationMinutes'] as num?)?.toInt() ?? 60;
    final end = start.add(Duration(minutes: dur));
    final overdue = status == 'active' && end.isBefore(DateTime.now());

    Color bg;
    switch (status) {
      case 'cancelled':
      case 'canceled':
        bg = kCancelled;
        break;
      case 'completed':
        bg = kCompleted;
        break;
      case 'reserved':
        bg = kReserved;
        break;
      default:
        bg = overdue ? kOverdue : kActive;
    }

    String hhmm(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white30),
      ),
      child: Text(
        '${name.isEmpty ? "—" : name}  •  ${hhmm(start)}–${hhmm(end)} (${dur}m)',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 10,
          height: 1.1,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SeatPill extends StatelessWidget {
  final String label;
  final Color seatColor;
  final _SeatStatus status;
  final double height;

  const _SeatPill({
    required this.label,
    required this.seatColor,
    required this.status,
    required this.height,
  });

  Color get _statusColor => switch (status) {
        _SeatStatus.free => const Color(0xFF10B981),
        _SeatStatus.occupied => const Color(0xFF3B82F6),
        _SeatStatus.reserved => const Color(0xFF8B5CF6),
        _SeatStatus.overdue => const Color(0xFFFF8C00),
      };

  String get _statusText => switch (status) {
        _SeatStatus.free => 'Free',
        _SeatStatus.occupied => 'Occupied',
        _SeatStatus.reserved => 'Reserved',
        _SeatStatus.overdue => 'Overdue',
      };

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$label • $_statusText',
      child: Container(
        height: height,
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: seatColor.withOpacity(.28),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: seatColor.withOpacity(.95), width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _statusColor,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _statusText,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NowLine2h extends StatelessWidget {
  final DateTime dayStart;
  final double minuteWidth;
  final int windowStartMinute;
  final int windowMinutes;

  const _NowLine2h({
    required this.dayStart,
    required this.minuteWidth,
    required this.windowStartMinute,
    required this.windowMinutes,
  });

  @override
  Widget build(BuildContext context) {
    final minsAbs = DateTime.now().difference(dayStart).inMinutes.clamp(0, 24 * 60);
    final minsLocal = (minsAbs - windowStartMinute).clamp(0, windowMinutes);
    final left = minsLocal * minuteWidth;

    return Positioned(
      left: left.toDouble(),
      top: 0,
      bottom: 0,
      child: Container(width: 2.5, color: kNowLine),
    );
  }
}

// ===== models =====
enum _SeatStatus { free, occupied, reserved, overdue }

class _SeatBucket {
  _SeatBucket(this.label, this.color);
  final String label;
  final Color color;
  final List<QueryDocumentSnapshot> docs = [];
  String? seatId;
  int rows = 1;
  double height = 44.0;
}

class _Iv {
  final int s, e;
  _Iv(this.s, this.e);
}

class _Block {
  final Map<String, dynamic> m;
  final int s, e, r;
  _Block(this.m, this.s, this.e, this.r);
  _Block copyWith({int? r}) => _Block(m, s, e, r ?? this.r);
}
