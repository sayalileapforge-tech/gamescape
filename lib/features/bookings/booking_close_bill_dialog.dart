// lib/features/bookings/booking_close_bill_dialog.dart
import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class BookingCloseBillDialog extends StatefulWidget {
  final String branchId;
  final String sessionId;
  final Map<String, dynamic> data;

  const BookingCloseBillDialog({
    super.key,
    required this.branchId,
    required this.sessionId,
    required this.data,
  });

  @override
  State<BookingCloseBillDialog> createState() => _BookingCloseBillDialogState();
}

class _BookingCloseBillDialogState extends State<BookingCloseBillDialog> {
  bool _loading = true;
  bool _closing = false;

  // Totals
  num _ordersTotal = 0;
  num _sessionTotal = 0;
  num _grandTotal = 0;

  // Play time
  int _playedMinutes = 0;

  // Pax (for single/multiplayer pricing)
  int _pax = 1;

  // Orders list for display
  List<Map<String, dynamic>> _orders = [];

  // Adjustments
  final TextEditingController _discountCtrl = TextEditingController(text: '0');
  final TextEditingController _taxPercentCtrl = TextEditingController(text: '0');

  // Billing segments (seat moves etc.)
  final List<_SeatSegment> _segments = [];

  // Items-only flag (Quick Shop style – no playtime charge)
  bool _itemsOnly = false;

  // Pay at Counter flag
  bool _payAtCounter = false;

  // Permission check
  bool _canUsePayAtCounter = false;

  late final DateTime? _startTime;
  late final int _plannedDuration; // minutes
  late final DateTime? _plannedEnd;
  late final String _paymentType; // prepaid / postpaid

  @override
  void initState() {
    super.initState();
    final s = widget.data;
    _startTime = (s['startTime'] as Timestamp?)?.toDate();
    _plannedDuration = (s['durationMinutes'] as num?)?.toInt() ?? 0;
    _plannedEnd =
        _startTime == null ? null : _startTime!.add(Duration(minutes: _plannedDuration));
    _paymentType = (s['paymentType'] ?? 'postpaid').toString().toLowerCase();
    _pax = (s['pax'] is num)
        ? (s['pax'] as num).toInt()
        : int.tryParse('${s['pax'] ?? 1}') ?? 1;
    if (_pax <= 0) _pax = 1;

    // Respect items-only when re-opening
    final existingItemsOnly = widget.data['itemsOnly'];
    if (existingItemsOnly is bool && existingItemsOnly == true) {
      _itemsOnly = true;
    }

    _loadUserPermissions();
    _loadBill();
  }

  // -------- LOAD USER PERMISSIONS --------
  Future<void> _loadUserPermissions() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (!userDoc.exists) return;

      final data = userDoc.data() as Map<String, dynamic>? ?? {};
      final permissions = data['permissions'] as Map<String, dynamic>? ?? {};

      setState(() {
        _canUsePayAtCounter = permissions['cashInCounter'] == true;
      });
    } catch (e) {
      // If error, default to false (no permission)
      setState(() {
        _canUsePayAtCounter = false;
      });
    }
  }

  // -------- LOAD BILL DATA --------
  Future<void> _loadBill() async {
    final fs = FirebaseFirestore.instance;
    final sessRef = fs
        .collection('branches')
        .doc(widget.branchId)
        .collection('sessions')
        .doc(widget.sessionId);

    // 1) Load orders, sum robustly
    final ordersSnap = await sessRef.collection('orders').get();
    num ordersTotal = 0;
    final ordersList = <Map<String, dynamic>>[];

    for (final doc in ordersSnap.docs) {
      final d = doc.data();
      num price = _asNum(d['price']);
      int qty = (_asNum(d['qty']).toInt());
      if (qty <= 0) qty = 1;

      num lineTotal;
      final rawTotal = d['total'];
      if (rawTotal is num) {
        lineTotal = rawTotal;
      } else if (rawTotal is String) {
        lineTotal = num.tryParse(rawTotal) ?? (price * qty);
      } else {
        lineTotal = price * qty;
      }

      ordersTotal += lineTotal;
      ordersList.add({
        'itemName': (d['itemName'] ?? '').toString(),
        'qty': qty,
        'price': price,
        'total': lineTotal,
      });
    }

    // 2) Build seat segments from start → seat_changes → now
    final now = DateTime.now();

    // Load seat_changes ordered
    final scSnap = await sessRef.collection('seat_changes').orderBy('changedAt').get();
    final scDocs = scSnap.docs;

    // Initial seat: use first change’s fromSeatId if present; else session.seatId
    String? initialSeatId = scDocs.isNotEmpty
        ? (scDocs.first.data()['fromSeatId'] as String?)
        : (widget.data['seatId'] as String?);

    // Safety: if initialSeatId still null, try current seat
    initialSeatId ??= (widget.data['seatId'] as String?);

    final rawSegments = <_RawSeg>[];
    if (_startTime != null) {
      DateTime from = _startTime!;
      String? seatId = initialSeatId;

      if (scDocs.isEmpty) {
        // Always create at least one segment for entire play window
        rawSegments.add(_RawSeg(
          seatId: seatId,
          from: from,
          to: _clampToPlanned(now),
          billAs: 'actual', // default
        ));
      } else {
        for (final sc in scDocs) {
          final data = sc.data();
          final changedAt = (data['changedAt'] as Timestamp?)?.toDate();
          final toSeat = data['toSeatId'] as String?;
          final billAs = (data['billSegmentAs'] ?? 'actual')
              .toString(); // 'actual'|'30'|'60'|'90'|'120'|'150'|'180'...
          if (changedAt != null) {
            rawSegments.add(_RawSeg(
              seatId: seatId,
              from: from,
              to: _clampToPlanned(changedAt),
              billAs: billAs,
            ));
            from = changedAt;
            seatId = toSeat;
          }
        }
        // Tail segment up to now
        rawSegments.add(_RawSeg(
          seatId: seatId,
          from: from,
          to: _clampToPlanned(now),
          billAs: 'actual',
        ));
      }
    }

    // 3) Resolve labels/rates and compute minutes + charges
    int totalPlayed = 0;
    final segmentsFinal = <_SeatSegment>[];

    for (final raw in rawSegments) {
      if (!raw.to.isAfter(raw.from)) continue; // guard

      // Resolve seat meta
      num ratePerHour = 0;
      String seatLabel = 'Seat';
      String seatType = '';
      num? rate30Single, rate60Single, rate30Multi, rate60Multi;
      bool supportsMultiplayer = false;

      if (raw.seatId != null && raw.seatId!.isNotEmpty) {
        final seatSnap = await fs
            .collection('branches')
            .doc(widget.branchId)
            .collection('seats')
            .doc(raw.seatId!)
            .get();

        if (seatSnap.exists) {
          final sd = seatSnap.data()!;
          ratePerHour = _asNum(sd['ratePerHour']);
          seatLabel = (sd['label'] ?? raw.seatId).toString();
          seatType = (sd['type'] ?? '').toString();
          rate30Single = _asNumOrNull(sd['rate30Single']);
          rate60Single = _asNumOrNull(sd['rate60Single']);
          rate30Multi = _asNumOrNull(sd['rate30Multi']);
          rate60Multi = _asNumOrNull(sd['rate60Multi']);
          supportsMultiplayer = (sd['supportsMultiplayer'] == true) ||
              sd['rate30Multi'] != null ||
              sd['rate60Multi'] != null;
        }
      }

      // Fallbacks if seat doc missing fields
      if (ratePerHour == 0) {
        ratePerHour = _asNum(widget.data['seatRatePerHour']);
      }
      if (seatLabel == 'Seat') {
        seatLabel = (widget.data['seatLabel'] ?? raw.seatId ?? 'Seat').toString();
      }

      // Exclude multiplayer on Couch/Racing rigs
      final t = seatType.toLowerCase();
      final isExcludedType = t.contains('couch') || t.contains('racing');
      if (isExcludedType) supportsMultiplayer = false;

      // Minutes (clamped to planned end)
      final actual = raw.to.difference(raw.from).inMinutes;
      final actualClamped = max(0, actual);
      totalPlayed += actualClamped;

      // ✅ Chips mean “bill that bracket”
      int billedMinutes = _billedMinutesFromBillAs(
        billAs: raw.billAs,
        actualMinutes: actualClamped,
        plannedDuration: _plannedDuration,
      );

      // Effective hourly rate fallback if zero → derive from 30/60 prices
      final isMulti = _pax > 1 && supportsMultiplayer;
      num effectiveRatePerHour = ratePerHour;
      if (effectiveRatePerHour == 0) {
        num? base;
        if (isMulti) {
          if (rate60Multi != null && rate60Multi > 0) {
            base = rate60Multi;
          } else if (rate30Multi != null && rate30Multi > 0) {
            base = rate30Multi * 2;
          }
        } else {
          if (rate60Single != null && rate60Single > 0) {
            base = rate60Single;
          } else if (rate30Single != null && rate30Single > 0) {
            base = rate30Single * 2;
          }
        }
        if (base != null) {
          effectiveRatePerHour = base;
        }
      }

      final priced = _priceForMinutes(
        minutes: billedMinutes,
        ratePerHour: effectiveRatePerHour,
        rate30Single: rate30Single,
        rate60Single: rate60Single,
        rate30Multi: rate30Multi,
        rate60Multi: rate60Multi,
        pax: _pax,
        supportsMultiplayer: supportsMultiplayer,
      );

      segmentsFinal.add(_SeatSegment(
        seatId: raw.seatId,
        seatLabel: seatLabel,
        seatType: seatType,
        from: raw.from,
        to: raw.to,
        billAs: raw.billAs,
        actualMinutes: actualClamped,
        billedMinutes: billedMinutes,
        ratePerHour: effectiveRatePerHour,
        rate30Single: rate30Single,
        rate60Single: rate60Single,
        rate30Multi: rate30Multi,
        rate60Multi: rate60Multi,
        supportsMultiplayer: supportsMultiplayer,
        pricingNote: _pricingNoteForMinutes(
          minutes: billedMinutes,
          pax: _pax,
          supportsMultiplayer: supportsMultiplayer,
          rate30Single: rate30Single,
          rate60Single: rate60Single,
          rate30Multi: rate30Multi,
          rate60Multi: rate60Multi,
          seatType: seatType,
        ),
        billedAmount: priced.amount,
      ));
    }

    setState(() {
      _ordersTotal = ordersTotal;
      _orders = ordersList;
      _segments
        ..clear()
        ..addAll(segmentsFinal);
      _playedMinutes = totalPlayed;
      _sessionTotal = _calcSessionTotal();
      _loading = false;
      _grandTotal = _calcGrandTotal();
    });
  }

  DateTime _clampToPlanned(DateTime candidate) {
    if (_plannedEnd == null) return candidate;
    return candidate.isAfter(_plannedEnd!) ? _plannedEnd! : candidate;
  }

  int _billedMinutesFromBillAs({
    required String billAs,
    required int actualMinutes,
    required int plannedDuration,
  }) {
    // plannedDuration can be 0 for walk-ins; in that case don’t cap.
    int cap(int v) => plannedDuration > 0 ? min(v, plannedDuration) : v;

    switch (billAs) {
      case '30':
        return cap(30);
      case '60':
        return cap(60);
      case '90':
        return cap(90);
      case '120':
        return cap(120);
      case '150':
        return cap(150);
      case '180':
        return cap(180);
      case 'actual':
      default:
        return cap(max(0, actualMinutes));
    }
  }

  // -------- PRICING HELPERS --------

  _Amount _priceForMinutes({
    required int minutes,
    required num ratePerHour,
    num? rate30Single,
    num? rate60Single,
    num? rate30Multi,
    num? rate60Multi,
    required int pax,
    required bool supportsMultiplayer,
  }) {
    final isMulti = pax > 1 && supportsMultiplayer;

    // Items can end up in weird minute counts; keep safe.
    if (minutes <= 0) return _Amount(0);

    // If not a 30-min step, fallback to prorate (keeps old behavior safe)
    if (minutes % 30 != 0) {
      return _Amount(ratePerHour * (minutes / 60));
    }

    // Resolve canonical 60-min and 30-min prices for this seat + pax mode.
    // Priority:
    //  - explicit rate60 / rate30
    //  - derive 30 from 60/2
    //  - fallback to hourly (ratePerHour) and hourly/2
    num? price60;
    num? price30;

    if (isMulti) {
      if (rate60Multi != null && rate60Multi > 0) price60 = rate60Multi;
      if (rate30Multi != null && rate30Multi > 0) price30 = rate30Multi;
    } else {
      if (rate60Single != null && rate60Single > 0) price60 = rate60Single;
      if (rate30Single != null && rate30Single > 0) price30 = rate30Single;
    }

    // Fallback to hourly if 60 missing
    if (price60 == null || price60 <= 0) {
      if (ratePerHour > 0) price60 = ratePerHour;
    }

    // Derive 30 if missing
    if (price30 == null || price30 <= 0) {
      if (price60 != null && price60 > 0) {
        price30 = price60 / 2;
      } else if (ratePerHour > 0) {
        price30 = ratePerHour / 2;
      }
    }

    // If we still can't determine pricing, keep old safe fallback (will likely be 0).
    if ((price60 == null || price60 <= 0) && (price30 == null || price30 <= 0)) {
      return _Amount(ratePerHour * (minutes / 60));
    }

    // ✅ Generic slab computation:
    // fullHours * 1hrPrice + (remaining30 ? 30minPrice : 0)
    final fullHours = minutes ~/ 60;
    final remaining = minutes % 60;

    num total = 0;
    if (fullHours > 0) {
      total += (price60 ?? 0) * fullHours;
    }
    if (remaining == 30) {
      total += (price30 ?? 0);
    }

    // If something odd happens, final fallback to prorate
    if (total <= 0) {
      return _Amount(ratePerHour * (minutes / 60));
    }

    return _Amount(total);
  }

  String _pricingNoteForMinutes({
    required int minutes,
    required int pax,
    required bool supportsMultiplayer,
    num? rate30Single,
    num? rate60Single,
    num? rate30Multi,
    num? rate60Multi,
    String? seatType,
  }) {
    final isMulti = pax > 1 && supportsMultiplayer;
    final t = (seatType ?? '').toLowerCase();
    final isExcludedType = t.contains('couch') || t.contains('racing');
    final forcedSuffix = isExcludedType ? ' (forced for $seatType)' : '';
    final base = isMulti ? 'Multiplayer' : 'Single';

    // Keep existing special notes for 30/60 for clarity
    if (minutes == 30) {
      if (isMulti && rate30Multi != null) return '30m • Multiplayer';
      if (!isMulti && rate30Single != null) return '30m • $base$forcedSuffix';
    }
    if (minutes == 60) {
      if (isMulti && rate60Multi != null) return '60m • Multiplayer';
      if (!isMulti && rate60Single != null) return '60m • $base$forcedSuffix';
    }

    // Generic slab note for any multiple of 30 (90/120/150/...)
    if (minutes > 60 && minutes % 30 == 0) {
      final fullHours = minutes ~/ 60;
      final remaining = minutes % 60;
      if (remaining == 30) {
        return '${minutes}m • $base (${fullHours}h + 30m)$forcedSuffix';
      }
      return '${minutes}m • $base (${fullHours}h)$forcedSuffix';
    }

    return isExcludedType
        ? 'Prorated @ hourly • Single (forced for $seatType)'
        : 'Prorated @ hourly';
  }

  // -------- CALC HELPERS --------

  // When items-only is enabled, treat seat charges as 0
  num _calcSessionTotal() {
    if (_itemsOnly) return 0;
    return _segments.fold<num>(0, (prev, s) => prev + s.billedAmount);
  }

  num _calcGrandTotal() {
    final discount = num.tryParse(_discountCtrl.text.trim()) ?? 0;
    final taxPercent = num.tryParse(_taxPercentCtrl.text.trim()) ?? 0;
    final sessionTotal = _calcSessionTotal();
    final subTotal = sessionTotal + _ordersTotal;
    final afterDiscount = (subTotal - discount);
    final nonNegative = afterDiscount < 0 ? 0 : afterDiscount;
    final taxAmount = nonNegative * (taxPercent / 100);
    return nonNegative + taxAmount;
  }

  void _recalcAll() {
    setState(() {
      if (!_itemsOnly) {
        for (var i = 0; i < _segments.length; i++) {
          final seg = _segments[i];
          final billed = seg.billedMinutes;
          final amt = _priceForMinutes(
            minutes: billed,
            ratePerHour: seg.ratePerHour,
            rate30Single: seg.rate30Single,
            rate60Single: seg.rate60Single,
            rate30Multi: seg.rate30Multi,
            rate60Multi: seg.rate60Multi,
            pax: _pax,
            supportsMultiplayer: seg.supportsMultiplayer,
          );
          _segments[i] = seg.copyWith(
            billedAmount: amt.amount,
            pricingNote: _pricingNoteForMinutes(
              minutes: billed,
              pax: _pax,
              supportsMultiplayer: seg.supportsMultiplayer,
              rate30Single: seg.rate30Single,
              rate60Single: seg.rate60Single,
              rate30Multi: seg.rate30Multi,
              rate60Multi: seg.rate60Multi,
              seatType: seg.seatType,
            ),
          );
        }
      }
      _sessionTotal = _calcSessionTotal();
      _grandTotal = _calcGrandTotal();
    });
  }

  // -------- CLOSE SESSION --------
  Future<void> _closeSession() async {
    if (_closing) return;
    setState(() => _closing = true);

    try {
      final discount = num.tryParse(_discountCtrl.text.trim()) ?? 0;
      final taxPercent = num.tryParse(_taxPercentCtrl.text.trim()) ?? 0;

      final sessionTotal = _calcSessionTotal();
      final rawSubTotal = (sessionTotal + _ordersTotal) - discount;
      final subtotal = rawSubTotal < 0 ? 0 : rawSubTotal;
      final taxAmount = subtotal * (taxPercent / 100);
      final grandTotal = subtotal + taxAmount;

      final paymentStatus = _paymentType == 'prepaid' ? 'paid' : 'pending';

      final now = DateTime.now();
      final invoiceNumber =
          'INV-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${(now.millisecondsSinceEpoch % 100000).toString().padLeft(5, '0')}';

      final fs = FirebaseFirestore.instance;
      final sessRef = fs
          .collection('branches')
          .doc(widget.branchId)
          .collection('sessions')
          .doc(widget.sessionId);

      final currentUser = FirebaseAuth.instance.currentUser;
      String? closedByName;
      if (currentUser != null) {
        final uDoc = await fs.collection('users').doc(currentUser.uid).get();
        if (uDoc.exists) {
          closedByName = (uDoc.data()?['name'] as String?) ?? currentUser.email;
        }
      }

      // Build seat segments payload (respect items-only)
      final seatSegmentPayload = _segments.map((s) {
        final effectiveBilledAmount = _itemsOnly ? 0 : s.billedAmount;
        final effectiveNote = _itemsOnly
            ? ((s.pricingNote?.isNotEmpty ?? false)
                ? '${s.pricingNote} • Seat not charged (items-only bill)'
                : 'Seat not charged (items-only bill)')
            : s.pricingNote;

        return {
          'seatId': s.seatId,
          'seatLabel': s.seatLabel,
          'seatType': s.seatType,
          'from': Timestamp.fromDate(s.from),
          'to': Timestamp.fromDate(s.to),
          'billAs': s.billAs, // 'actual'|'30'|'60'|'90'|'120'|'150'|'180'...
          'actualMinutes': s.actualMinutes,
          'billedMinutes': s.billedMinutes,
          'billedAmount': effectiveBilledAmount,
          'pricingNote': effectiveNote,
        };
      }).toList();

      await sessRef.update({
        'status': 'completed',
        'paymentStatus': paymentStatus,
        'closedAt': FieldValue.serverTimestamp(),
        'invoiceNumber': invoiceNumber,
        'playedMinutes': _playedMinutes,
        'seatSegments': seatSegmentPayload,
        'ordersSubtotal': _ordersTotal,
        'subtotal': subtotal,
        'taxPercent': taxPercent,
        'taxAmount': taxAmount,
        'billAmount': grandTotal,
        'discount': discount,
        'pax': _pax,
        'itemsOnly': _itemsOnly,
        if (currentUser != null) 'closedBy': currentUser.uid,
        if (closedByName != null) 'closedByName': closedByName,
        if (_payAtCounter) 'paymentMode': 'counter',
        if (_payAtCounter) 'payments': [
          {
            'mode': 'counter',
            'amount': grandTotal,
            'timestamp': Timestamp.now(),
          }
        ],
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Session closed')));

      // Customer aggregates — fire-and-forget
      final custName = (widget.data['customerName'] ?? '').toString().trim();
      final custPhone = (widget.data['customerPhone'] ?? '').toString().trim();
      if (custName.isNotEmpty || custPhone.isNotEmpty) {
        final custId = custPhone.isNotEmpty ? 'phone:$custPhone' : 'name:$custName';
        final custRef = fs.collection('customers').doc(custId);

        unawaited(fs.runTransaction((tx) async {
          final snap = await tx.get(custRef);
          final existing = snap.data() ?? {};
          final num prevSpend = (existing['lifetimeSpend'] ?? 0) as num;
          final int prevVisits = (existing['lifetimeVisits'] ?? 0) as int;
          final num prevSpend90 = (existing['spendLast90d'] ?? 0) as num;

          tx.set(
            custRef,
            {
              'name': custName,
              'phone': custPhone,
              'lifetimeSpend': prevSpend + grandTotal,
              'lifetimeVisits': prevVisits + 1,
              'avgSpend': (prevSpend + grandTotal) /
                  ((prevVisits + 1) == 0 ? 1 : (prevVisits + 1)),
              'spendLast90d': prevSpend90 + grandTotal,
              'lastVisitAt': FieldValue.serverTimestamp(),
              'firstVisitAt': existing['firstVisitAt'] ?? FieldValue.serverTimestamp(),
              'hasPendingDue': paymentStatus == 'pending',
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }).catchError((_) {}));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to close: $e')));
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  // -------- UI --------
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1F2937),
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(18),
        child: _loading
            ? const SizedBox(
                height: 120, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: DefaultTextStyle(
                  style: const TextStyle(color: Colors.white),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Close & Bill',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: Text('Duration: ${_plannedDuration} minutes')),
                          Expanded(child: Text('Played: $_playedMinutes minutes')),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Players: $_pax', style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 12),
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 8),
                      const Text('Seat Billing'),
                      const SizedBox(height: 6),

                      // ITEMS ONLY toggle
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111827),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: _itemsOnly,
                              onChanged: (v) {
                                setState(() {
                                  _itemsOnly = (v ?? false);
                                  _sessionTotal = _calcSessionTotal();
                                  _grandTotal = _calcGrandTotal();
                                });
                              },
                              activeColor: Colors.white,
                              checkColor: Colors.black,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Items only (no playtime charge)',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (_segments.isEmpty)
                        const Text('No seat usage recorded',
                            style: TextStyle(color: Colors.white70))
                      else
                        Column(
                          children: _segments.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final seg = entry.value;

                            // Disable 30m chip ONLY if THIS segment's actual time > 40 mins (policy)
                            final disable30 = seg.actualMinutes > 40;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${seg.seatLabel ?? "Seat"}'
                                      '  •  ${seg.seatType?.isNotEmpty == true ? seg.seatType : "Type"}'
                                      '  •  base ₹${_fmt(seg.ratePerHour)}/hr'),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _RoundChip(
                                        label: 'Actual',
                                        selected: seg.billAs == 'actual',
                                        onTap: _itemsOnly
                                            ? null
                                            : () => _setRound(idx, seg, 'actual'),
                                        disabled: _itemsOnly,
                                      ),
                                      _RoundChip(
                                        label: '30',
                                        selected: seg.billAs == '30',
                                        onTap: (_itemsOnly || disable30)
                                            ? null
                                            : () => _setRound(idx, seg, '30'),
                                        disabled: _itemsOnly || disable30,
                                      ),
                                      _RoundChip(
                                        label: '60',
                                        selected: seg.billAs == '60',
                                        onTap:
                                            _itemsOnly ? null : () => _setRound(idx, seg, '60'),
                                        disabled: _itemsOnly,
                                      ),
                                      _RoundChip(
                                        label: '90',
                                        selected: seg.billAs == '90',
                                        onTap:
                                            _itemsOnly ? null : () => _setRound(idx, seg, '90'),
                                        disabled: _itemsOnly,
                                      ),
                                      _RoundChip(
                                        label: '120',
                                        selected: seg.billAs == '120',
                                        onTap:
                                            _itemsOnly ? null : () => _setRound(idx, seg, '120'),
                                        disabled: _itemsOnly,
                                      ),
                                      _RoundChip(
                                        label: '150',
                                        selected: seg.billAs == '150',
                                        onTap:
                                            _itemsOnly ? null : () => _setRound(idx, seg, '150'),
                                        disabled: _itemsOnly,
                                      ),
                                      _RoundChip(
                                        label: '180',
                                        selected: seg.billAs == '180',
                                        onTap:
                                            _itemsOnly ? null : () => _setRound(idx, seg, '180'),
                                        disabled: _itemsOnly,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text('Rounded Played   ${seg.billedMinutes} minutes'),
                                  if ((seg.pricingNote ?? '').isNotEmpty)
                                    Text(seg.pricingNote!,
                                        style: const TextStyle(
                                            color: Colors.white70, fontSize: 12)),
                                  Text(
                                    _itemsOnly
                                        ? 'Seat Subtotal    ₹0 (items-only: seat not charged)'
                                        : 'Seat Subtotal    ₹${_fmt(seg.billedAmount)}',
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),

                      const SizedBox(height: 6),
                      Text(_itemsOnly
                          ? 'Seat Subtotal: ₹0 (items-only)'
                          : 'Seat Subtotal: ₹${_fmt(_sessionTotal)}'),
                      const SizedBox(height: 12),
                      const Divider(color: Colors.white24),

                      const SizedBox(height: 8),
                      const Text('F&B / Orders'),
                      const SizedBox(height: 6),
                      if (_orders.isEmpty)
                        const Text('No items added', style: TextStyle(color: Colors.white70))
                      else
                        Column(
                          children: _orders
                              .map((o) => Row(
                                    children: [
                                      Expanded(
                                          child: Text('${(o['itemName'] ?? 'Item')} x${o['qty']}')),
                                      Text('₹${_fmt(_asNum(o['total']))}'),
                                    ],
                                  ))
                              .toList(),
                        ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Spacer(),
                          Text('Orders Subtotal   ₹${_fmt(_ordersTotal)}'),
                        ],
                      ),

                      const SizedBox(height: 12),
                      const Divider(color: Colors.white24),

                      const Text('Bill Summary'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _discountCtrl,
                              onChanged: (_) => _recalcAll(),
                              keyboardType: TextInputType.number,
                              decoration: _darkInput('Discount (₹)'),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _taxPercentCtrl,
                              onChanged: (_) => _recalcAll(),
                              keyboardType: TextInputType.number,
                              decoration: _darkInput('Tax (%)'),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _KV(
                        'Subtotal (Seat + Orders − Discount)',
                        '₹${_fmt((_calcSessionTotal() + _ordersTotal) - (num.tryParse(_discountCtrl.text.trim()) ?? 0))}',
                      ),
                      _KV(
                        'Tax Amount',
                        '₹${_fmt((_calcGrandTotal() - ((_calcSessionTotal() + _ordersTotal) - (num.tryParse(_discountCtrl.text.trim()) ?? 0)).clamp(0, double.infinity)))}',
                      ),
                      const SizedBox(height: 6),
                      _KVStrong('Total Payable', '₹${_fmt(_grandTotal)}'),
                      const SizedBox(height: 16),

                      // Pay at Counter checkbox (only if user has permission)
                      if (_canUsePayAtCounter)
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF111827),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Row(
                            children: [
                              Checkbox(
                                value: _payAtCounter,
                                onChanged: (v) {
                                  setState(() {
                                    _payAtCounter = (v ?? false);
                                  });
                                },
                                activeColor: Colors.white,
                                checkColor: Colors.black,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Pay at Counter',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_canUsePayAtCounter) const SizedBox(height: 16),

                      Row(
                        children: [
                          TextButton(
                            onPressed: _closing ? null : () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          const Spacer(),
                          ElevatedButton.icon(
                            onPressed: _closing ? null : _closeSession,
                            icon: const Icon(Icons.lock_outline),
                            label: _closing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Close Session'),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  void _setRound(int idx, _SeatSegment seg, String v) {
    int billed = _billedMinutesFromBillAs(
      billAs: v,
      actualMinutes: seg.actualMinutes,
      plannedDuration: _plannedDuration,
    );

    final amt = _priceForMinutes(
      minutes: billed,
      ratePerHour: seg.ratePerHour,
      rate30Single: seg.rate30Single,
      rate60Single: seg.rate60Single,
      rate30Multi: seg.rate30Multi,
      rate60Multi: seg.rate60Multi,
      pax: _pax,
      supportsMultiplayer: seg.supportsMultiplayer,
    );

    setState(() {
      _segments[idx] = seg.copyWith(
        billAs: v,
        billedMinutes: billed,
        billedAmount: amt.amount,
        pricingNote: _pricingNoteForMinutes(
          minutes: billed,
          pax: _pax,
          supportsMultiplayer: seg.supportsMultiplayer,
          rate30Single: seg.rate30Single,
          rate60Single: seg.rate60Single,
          rate30Multi: seg.rate30Multi,
          rate60Multi: seg.rate60Multi,
          seatType: seg.seatType,
        ),
      );
      _sessionTotal = _calcSessionTotal();
      _grandTotal = _calcGrandTotal();
    });
  }

  InputDecoration _darkInput(String label) => const InputDecoration(
        border: OutlineInputBorder(),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
      ).copyWith(labelText: label, labelStyle: const TextStyle(color: Colors.white70));
}

// ===== Internal raw segment =====
class _RawSeg {
  final String? seatId;
  final DateTime from;
  final DateTime to;
  final String billAs; // 'actual'|'30'|'60'|'90'|'120'|'150'|'180'...
  _RawSeg({required this.seatId, required this.from, required this.to, required this.billAs});
}

// ===== Models & helpers =====
class _SeatSegment {
  final String? seatId;
  final String? seatLabel;
  final String? seatType;
  final DateTime from;
  final DateTime to;
  final String billAs; // 'actual' | '30' | '60' | '90' | '120' | ...
  final int actualMinutes;
  final int billedMinutes;
  final num ratePerHour;

  // Pricing variants
  final num? rate30Single;
  final num? rate60Single;
  final num? rate30Multi;
  final num? rate60Multi;
  final bool supportsMultiplayer;

  final String? pricingNote;
  final num billedAmount;

  _SeatSegment({
    required this.seatId,
    this.seatLabel,
    this.seatType,
    required this.from,
    required this.to,
    this.billAs = 'actual',
    this.actualMinutes = 0,
    this.billedMinutes = 0,
    this.ratePerHour = 0,
    this.rate30Single,
    this.rate60Single,
    this.rate30Multi,
    this.rate60Multi,
    this.supportsMultiplayer = false,
    this.pricingNote,
    this.billedAmount = 0,
  });

  _SeatSegment copyWith({
    String? seatId,
    String? seatLabel,
    String? seatType,
    DateTime? from,
    DateTime? to,
    String? billAs,
    int? actualMinutes,
    int? billedMinutes,
    num? ratePerHour,
    num? rate30Single,
    num? rate60Single,
    num? rate30Multi,
    num? rate60Multi,
    bool? supportsMultiplayer,
    String? pricingNote,
    num? billedAmount,
  }) {
    return _SeatSegment(
      seatId: seatId ?? this.seatId,
      seatLabel: seatLabel ?? this.seatLabel,
      seatType: seatType ?? this.seatType,
      from: from ?? this.from,
      to: to ?? this.to,
      billAs: billAs ?? this.billAs,
      actualMinutes: actualMinutes ?? this.actualMinutes,
      billedMinutes: billedMinutes ?? this.billedMinutes,
      ratePerHour: ratePerHour ?? this.ratePerHour,
      rate30Single: rate30Single ?? this.rate30Single,
      rate60Single: rate60Single ?? this.rate60Single,
      rate30Multi: rate30Multi ?? this.rate30Multi,
      rate60Multi: rate60Multi ?? this.rate60Multi,
      supportsMultiplayer: supportsMultiplayer ?? this.supportsMultiplayer,
      pricingNote: pricingNote ?? this.pricingNote,
      billedAmount: billedAmount ?? this.billedAmount,
    );
  }
}

class _Amount {
  num amount;
  bool usedCombo;
  _Amount(this.amount) : usedCombo = false;
}

Widget _KV(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(k, style: const TextStyle(color: Colors.white70))),
        Text(v, style: const TextStyle(color: Colors.white)),
      ]),
    );

Widget _KVStrong(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(
            child:
                Text(k, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
        Text(v, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ]),
    );

class _RoundChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool disabled;
  const _RoundChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveOnTap = disabled ? null : onTap;
    return InkWell(
      onTap: effectiveOnTap,
      borderRadius: BorderRadius.circular(999),
      child: Opacity(
        opacity: disabled ? 0.4 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(label, style: TextStyle(color: selected ? Colors.black : Colors.white)),
        ),
      ),
    );
  }
}

num _asNum(dynamic v, {num fallback = 0}) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? fallback;
  return fallback;
}

num? _asNumOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  if (v is String) return num.tryParse(v);
  return null;
}

String _fmt(num v) => v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
