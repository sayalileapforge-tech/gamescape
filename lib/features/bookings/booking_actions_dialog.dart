import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/billing/billing_utils.dart'; // ⬅ for robust extend
import 'add_order_dialog.dart';
import 'booking_move_seat_dialog.dart';
import 'booking_close_bill_dialog.dart';

enum SessionState {
  activeLive,
  activeOverdue,
  reservedFuture,
  reservedPast,
  completed,
  cancelled,
}

DateTime _tsUtc(dynamic ts) =>
    (ts is Timestamp ? ts.toDate() : (ts as DateTime?))?.toUtc() ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

int _asInt(dynamic v, {int fallback = 0}) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? fallback;
  return fallback;
}

SessionState _stateOf(Map<String, dynamic> s) {
  final now = DateTime.now().toUtc();
  final status = (s['status'] as String?) ?? 'reserved';
  final start = _tsUtc(s['startTime']);
  final durationMins = _asInt(s['durationMinutes']);
  final endAt = start.add(Duration(minutes: durationMins));

  if (status == 'completed') return SessionState.completed;
  if (status == 'cancelled') return SessionState.cancelled;

  if (status == 'active') {
    return now.isBefore(endAt) ? SessionState.activeLive : SessionState.activeOverdue;
  }

  if (status == 'reserved') {
    return start.isAfter(now) ? SessionState.reservedFuture : SessionState.reservedPast;
  }

  return SessionState.cancelled;
}

/// Checks if the session [sessionId] on [seatId] can have endTime = start + newDuration
/// without colliding with ANY other active/reserved session on that seat.
Future<bool> _canUpdateEndWithoutOverlap({
  required String branchId,
  required String sessionId,
  required String seatId,
  required DateTime startUtc,
  required int newDurationMinutes,
}) async {
  final fs = FirebaseFirestore.instance;
  final sessionsCol = fs.collection('branches').doc(branchId).collection('sessions');

  final proposedEndUtc = startUtc.add(Duration(minutes: newDurationMinutes));

  // Simple query: all sessions on this seat (no composite index needed)
  final snap = await sessionsCol
      .where('seatId', isEqualTo: seatId)
      .get();

  for (final doc in snap.docs) {
    if (doc.id == sessionId) continue;

    final data = doc.data() as Map<String, dynamic>;
    final status = (data['status'] ?? '').toString();
    if (status != 'active' && status != 'reserved') continue;

    final otherStartUtc = _tsUtc(data['startTime']);
    final otherDur = _asInt(data['durationMinutes']);
    final otherEndUtc = otherStartUtc.add(Duration(minutes: otherDur));

    // Overlap test: [startUtc, proposedEndUtc) intersects [otherStartUtc, otherEndUtc)
    final overlaps = otherStartUtc.isBefore(proposedEndUtc) && otherEndUtc.isAfter(startUtc);
    if (overlaps) {
      return false;
    }
  }

  return true;
}

class BookingActionsDialog extends StatefulWidget {
  final String branchId;
  final String sessionId;
  final Map<String, dynamic> data;

  const BookingActionsDialog({
    super.key,
    required this.branchId,
    required this.sessionId,
    required this.data,
  });

  @override
  State<BookingActionsDialog> createState() => _BookingActionsDialogState();
}

class _BookingActionsDialogState extends State<BookingActionsDialog> {
  bool _busy = false;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Robust extend from any state (including negative overrun)
  Future<void> _extendBy(int minutes) async {
    setState(() => _busy = true);

    final docRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('sessions')
        .doc(widget.sessionId);

    try {
      // Read once to compute proposed end + do overlap guard
      final snap = await docRef.get();
      final current = (snap.data() ?? {}) as Map<String, dynamic>;

      final seatId = (current['seatId'] ?? '').toString();
      if (seatId.isEmpty) {
        setState(() => _busy = false);
        _toast('Cannot extend: seat not found for this session.');
        return;
      }

      final startUtc = _tsUtc(current['startTime']);
      final scheduled = _asInt(current['durationMinutes']);

      final proposedDuration = extendByMinutes(
        startUtc: startUtc,
        scheduledMinutes: scheduled,
        addMinutes: minutes,
        nowUtc: DateTime.now().toUtc(),
      );

      final ok = await _canUpdateEndWithoutOverlap(
        branchId: widget.branchId,
        sessionId: widget.sessionId,
        seatId: seatId,
        startUtc: startUtc,
        newDurationMinutes: proposedDuration,
      );

      if (!ok) {
        if (mounted) {
          setState(() => _busy = false);
          _toast('Cannot extend: it will overlap with another booking on this seat.');
        }
        return;
      }

      // Commit update (transaction keeps things consistent with concurrent writes)
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap2 = await tx.get(docRef);
        final cur2 = (snap2.data() ?? {}) as Map<String, dynamic>;

        final startUtc2 = _tsUtc(cur2['startTime']);
        final scheduled2 = _asInt(cur2['durationMinutes']);

        final newDuration = extendByMinutes(
          startUtc: startUtc2,
          scheduledMinutes: scheduled2,
          addMinutes: minutes,
          nowUtc: DateTime.now().toUtc(),
        );

        tx.update(docRef, {
          'durationMinutes': newDuration,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (mounted) {
        setState(() => _busy = false);
        _toast('Extended by $minutes minutes');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _toast('Failed to extend: $e');
      }
    }
  }

  Future<void> _startNow() async {
    setState(() => _busy = true);
    final docRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('sessions')
        .doc(widget.sessionId);

    await docRef.update({
      'status': 'active',
      'startTime': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      setState(() => _busy = false);
      Navigator.of(context).pop();
      _toast('Session started');
    }
  }

  Future<void> _cancelReservation() async {
    setState(() => _busy = true);
    final docRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('sessions')
        .doc(widget.sessionId);

    await docRef.update({
      'status': 'cancelled',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      setState(() => _busy = false);
      Navigator.of(context).pop();
      _toast('Reservation cancelled');
    }
  }

  // Always open billing dialog
  Future<void> _openCloseDialogAlways() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => BookingCloseBillDialog(
        branchId: widget.branchId,
        sessionId: widget.sessionId,
        data: widget.data,
      ),
    );
    if (res == true && mounted) {
      Navigator.of(context).pop();
      _toast('Session closed. Pending/paid invoice created.');
    }
  }

  // Adjust time dialog for active/overdue (walk-in buffer etc.)
  Future<void> _openAdjustTime() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _AdjustTimeDialog(
        branchId: widget.branchId,
        sessionId: widget.sessionId,
        onExtended: (m) => _toast('Extended by $m minutes'),
        onStartSetToNow: () => _toast('Start time set to Now'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cust = widget.data['customerName'] ?? '';
    final seatId = widget.data['seatId'] ?? '';
    final seat = widget.data['seatLabel'] ?? '';
    final duration = _asInt(widget.data['durationMinutes']);
    final state = _stateOf(widget.data);

    return Dialog(
      backgroundColor: const Color(0xFF1F2937),
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Booking Actions',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.white),
              ),
              const SizedBox(height: 10),
              Text('Customer: $cust', style: const TextStyle(color: Colors.white)),
              Text('Seat: $seat', style: const TextStyle(color: Colors.white70)),
              Text('Duration: $duration mins', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),

              if (state == SessionState.activeLive) ...[
                _actionBtn(
                  icon: Icons.av_timer_outlined,
                  label: 'Adjust Time',
                  onTap: _openAdjustTime,
                ),
                const SizedBox(height: 10),
                _actionBtn(
                  icon: Icons.add_alarm,
                  label: _busy ? 'Extending...' : 'Extend by 30 mins',
                  onTap: _busy ? null : () => _extendBy(30),
                ),
                const SizedBox(height: 10),
                _actionBtn(
                  icon: Icons.add_shopping_cart_outlined,
                  label: 'Add Order',
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => AddOrderDialog(
                      branchId: widget.branchId,
                      sessionId: widget.sessionId,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _actionBtn(
                  icon: Icons.chair_outlined,
                  label: 'Move Seat',
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => BookingMoveSeatDialog(
                      branchId: widget.branchId,
                      sessionId: widget.sessionId,
                      currentSeatId: seatId.toString(),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _actionBtn(
                  icon: Icons.payments_outlined,
                  label: _busy ? 'Closing...' : 'Close & Bill',
                  onTap: _busy ? null : _openCloseDialogAlways,
                ),
              ] else if (state == SessionState.activeOverdue) ...[
                _actionBtn(
                  icon: Icons.av_timer_outlined,
                  label: 'Adjust Time',
                  onTap: _openAdjustTime,
                ),
                const SizedBox(height: 10),
                _actionBtn(
                  icon: Icons.add_alarm,
                  label: _busy ? 'Extending...' : 'Extend by 30 mins',
                  onTap: _busy ? null : () => _extendBy(30),
                ),
                const SizedBox(height: 10),
                _actionBtn(
                  icon: Icons.add_shopping_cart_outlined,
                  label: 'Add Order',
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => AddOrderDialog(
                      branchId: widget.branchId,
                      sessionId: widget.sessionId,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _actionBtn(
                  icon: Icons.payments_outlined,
                  label: _busy ? 'Closing...' : 'Close (Overdue)',
                  onTap: _busy ? null : _openCloseDialogAlways,
                ),
              ] else if (state == SessionState.reservedFuture) ...[
                _actionBtn(
                  icon: Icons.play_circle_outline,
                  label: _busy ? 'Starting...' : 'Start Now',
                  onTap: _busy ? null : _startNow,
                ),
                const SizedBox(height: 10),
                _actionBtn(
                  icon: Icons.event,
                  label: 'Reschedule',
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => _EditBookingDetailsDialog(
                        branchId: widget.branchId,
                        sessionId: widget.sessionId,
                        initialData: widget.data,
                        enableReschedule: true,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                _actionBtn(
                  icon: Icons.cancel_outlined,
                  label: _busy ? 'Cancelling...' : 'Cancel Reservation',
                  onTap: _busy ? null : _cancelReservation,
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Text(
                    'No actions available for this session state.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],

              const SizedBox(height: 16),
              _actionBtn(
                icon: Icons.info_outline,
                label: 'View / Edit details',
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => _EditBookingDetailsDialog(
                      branchId: widget.branchId,
                      sessionId: widget.sessionId,
                      initialData: widget.data,
                      enableReschedule: false,
                    ),
                  );
                },
              ),

              const SizedBox(height: 12),
              const Text(
                'Close & Bill will always show charge options (Actual / 30 / 60 mins, etc.).',
                style: TextStyle(fontSize: 11, color: Colors.white38),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 42,
      child: ElevatedButton.icon(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF111827),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          elevation: 0,
        ),
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

// ---------------- EDIT BOOKING DETAILS (unchanged UI; overlap check hardened) ----------------
class _EditBookingDetailsDialog extends StatefulWidget {
  final String branchId;
  final String sessionId;
  final Map<String, dynamic> initialData;
  final bool enableReschedule;

  const _EditBookingDetailsDialog({
    required this.branchId,
    required this.sessionId,
    required this.initialData,
    required this.enableReschedule,
  });

  @override
  State<_EditBookingDetailsDialog> createState() => _EditBookingDetailsDialogState();
}

class _EditBookingDetailsDialogState extends State<_EditBookingDetailsDialog> {
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _paxCtrl;
  late TextEditingController _gamePrefCtrl;
  late TextEditingController _notesCtrl;

  String _paymentType = 'postpaid';
  int _durationMinutes = 60;
  bool _saving = false;

  late DateTime _date;
  late TimeOfDay _time;

  final List<int> _durationOptions = [30, 60, 90, 120, 150, 180, 240, 300];

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;

    _nameCtrl = TextEditingController(text: (d['customerName'] ?? '').toString());
    _phoneCtrl = TextEditingController(text: (d['customerPhone'] ?? '').toString());
    _paxCtrl = TextEditingController(text: d['pax'] != null ? d['pax'].toString() : '');
    _gamePrefCtrl = TextEditingController(text: (d['gamePreference'] ?? '').toString());
    _notesCtrl = TextEditingController(text: (d['notes'] ?? '').toString());

    _paymentType = (d['paymentType'] ?? 'postpaid').toString();
    _durationMinutes = _asInt(d['durationMinutes'], fallback: _durationMinutes);

    final DateTime start = (d['startTime'] as Timestamp?)?.toDate() ?? DateTime.now();
    _date = DateTime(start.year, start.month, start.day);
    _time = TimeOfDay(hour: start.hour, minute: start.minute);

    if (!_durationOptions.contains(_durationMinutes)) {
      _durationOptions.add(_durationMinutes);
      _durationOptions.sort();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _paxCtrl.dispose();
    _gamePrefCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canReschedule = widget.enableReschedule;

    return Dialog(
      backgroundColor: const Color(0xFF1F2937),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(18),
        child: SingleChildScrollView(
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Booking Details',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _nameCtrl,
                  decoration: _darkInput('Customer name'),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _phoneCtrl,
                  decoration: _darkInput('Customer phone'),
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _paxCtrl,
                  decoration: _darkInput('Pax (optional)'),
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _gamePrefCtrl,
                  decoration: _darkInput('Game preference (optional)'),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 10),

                DropdownButtonFormField<String>(
                  value: _paymentType,
                  dropdownColor: const Color(0xFF111827),
                  style: const TextStyle(color: Colors.white),
                  decoration: _darkInput('Payment type'),
                  items: const [
                    DropdownMenuItem(value: 'prepaid', child: Text('Prepaid')),
                    DropdownMenuItem(value: 'postpaid', child: Text('Postpaid')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _paymentType = v);
                  },
                ),
                const SizedBox(height: 10),

                DropdownButtonFormField<int>(
                  value: _durationMinutes,
                  dropdownColor: const Color(0xFF111827),
                  style: const TextStyle(color: Colors.white),
                  decoration: _darkInput('Duration'),
                  items: _durationOptions
                      .map((m) => DropdownMenuItem(
                            value: m,
                            child: Text('$m minutes'),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _durationMinutes = v);
                  },
                ),
                const SizedBox(height: 10),

                if (canReschedule) ...[
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _pickDate,
                          child: InputDecorator(
                            decoration: _darkInput('New date'),
                            child: Text(
                              '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: _pickTime,
                          child: InputDecorator(
                            decoration: _darkInput('New time'),
                            child: Text(_time.format(context)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Text(
                      'Reschedule updates the start time & duration for this reservation. '
                      'We’ll block overlaps on the current seat.',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                TextField(
                  controller: _notesCtrl,
                  decoration: _darkInput('Notes'),
                  style: const TextStyle(color: Colors.white),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: ElevatedButton(
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const CircularProgressIndicator()
                              : Text(canReschedule ? 'Save & Reschedule' : 'Save changes'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _darkInput(String label) {
    return const InputDecoration(
      labelText: null,
      border: OutlineInputBorder(),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white24),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white),
      ),
    ).copyWith(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      initialDate: _date,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;

    setState(() => _saving = true);

    final docRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('sessions')
        .doc(widget.sessionId);

    int? pax;
    if (_paxCtrl.text.trim().isNotEmpty) {
      pax = int.tryParse(_paxCtrl.text.trim());
    }

    final baseUpdate = {
      'customerName': _nameCtrl.text.trim(),
      'customerPhone': _phoneCtrl.text.trim(),
      'pax': pax,
      'gamePreference': _gamePrefCtrl.text.trim(),
      'notes': _notesCtrl.text.trim(),
      'paymentType': _paymentType,
      'durationMinutes': _durationMinutes,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (widget.enableReschedule) {
      final startLocal = DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
      final endLocal = startLocal.add(Duration(minutes: _durationMinutes));

      final currentSnap = await docRef.get();
      final current = (currentSnap.data() ?? {}) as Map<String, dynamic>;
      final seatId = (current['seatId'] ?? '').toString();

      if (seatId.isNotEmpty) {
        final fs = FirebaseFirestore.instance;
        final sessionsCol = fs.collection('branches').doc(widget.branchId).collection('sessions');

        final seatSessionsSnap = await sessionsCol.where('seatId', isEqualTo: seatId).get();

        bool hasOverlap = false;
        for (final doc in seatSessionsSnap.docs) {
          if (doc.id == widget.sessionId) continue;
          final data = doc.data() as Map<String, dynamic>;
          final status = (data['status'] ?? '').toString();
          if (status != 'active' && status != 'reserved') continue;

          final otherStart = (data['startTime'] as Timestamp?)?.toDate();
          final otherDur = _asInt(data['durationMinutes']);
          if (otherStart == null) continue;

          final otherEnd = otherStart.add(Duration(minutes: otherDur));
          final overlaps = otherStart.isBefore(endLocal) && otherEnd.isAfter(startLocal);
          if (overlaps) {
            hasOverlap = true;
            break;
          }
        }

        if (hasOverlap) {
          if (mounted) {
            setState(() => _saving = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Overlap detected with another booking on this seat.')),
            );
          }
          return;
        }
      }

      baseUpdate['startTime'] = Timestamp.fromDate(startLocal);
      baseUpdate['status'] = 'reserved';
    }

    await docRef.update(baseUpdate);

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(widget.enableReschedule ? 'Reservation rescheduled' : 'Booking details updated'),
    ));
  }
}

// ===== Adjust Time dialog (for active/overdue) =====
class _AdjustTimeDialog extends StatefulWidget {
  final String branchId;
  final String sessionId;
  final void Function(int minutes) onExtended;
  final VoidCallback onStartSetToNow;

  const _AdjustTimeDialog({
    required this.branchId,
    required this.sessionId,
    required this.onExtended,
    required this.onStartSetToNow,
  });

  @override
  State<_AdjustTimeDialog> createState() => _AdjustTimeDialogState();
}

class _AdjustTimeDialogState extends State<_AdjustTimeDialog> {
  bool _busy = false;

  void _toastLocal(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _setStartNow() async {
    setState(() => _busy = true);
    final docRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('sessions')
        .doc(widget.sessionId);

    await docRef.update({
      'startTime': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pop();
    widget.onStartSetToNow();
  }

  Future<void> _extend(int minutes) async {
    if (minutes <= 0) return;
    setState(() => _busy = true);

    final docRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('sessions')
        .doc(widget.sessionId);

    try {
      // Read once for overlap guard
      final snap = await docRef.get();
      final current = (snap.data() ?? {}) as Map<String, dynamic>;

      final seatId = (current['seatId'] ?? '').toString();
      if (seatId.isEmpty) {
        setState(() => _busy = false);
        _toastLocal('Cannot extend: seat not found for this session.');
        return;
      }

      final startUtc = _tsUtc(current['startTime']);
      final scheduled = _asInt(current['durationMinutes']);

      final proposedDuration = extendByMinutes(
        startUtc: startUtc,
        scheduledMinutes: scheduled,
        addMinutes: minutes,
        nowUtc: DateTime.now().toUtc(),
      );

      final ok = await _canUpdateEndWithoutOverlap(
        branchId: widget.branchId,
        sessionId: widget.sessionId,
        seatId: seatId,
        startUtc: startUtc,
        newDurationMinutes: proposedDuration,
      );

      if (!ok) {
        if (mounted) {
          setState(() => _busy = false);
          _toastLocal('Cannot extend: it will overlap with another booking on this seat.');
        }
        return;
      }

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap2 = await tx.get(docRef);
        final cur2 = (snap2.data() ?? {}) as Map<String, dynamic>;
        final startUtc2 = _tsUtc(cur2['startTime']);
        final scheduled2 = _asInt(cur2['durationMinutes']);

        final newDuration = extendByMinutes(
          startUtc: startUtc2,
          scheduledMinutes: scheduled2,
          addMinutes: minutes,
          nowUtc: DateTime.now().toUtc(),
        );

        tx.update(docRef, {
          'durationMinutes': newDuration,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;
      setState(() => _busy = false);
      Navigator.of(context).pop();
      widget.onExtended(minutes);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toastLocal('Failed to extend: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1F2937),
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Adjust Time',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 12),
            const Text(
              'Use these quick actions to avoid customers losing minutes during check-in.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 14),

            // Set Start = Now
            SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _setStartNow,
                icon: const Icon(Icons.schedule),
                label: const Text('Set Start = Now (keep duration)'),
              ),
            ),
            const SizedBox(height: 10),

            // ✅ Only +5 and +10
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _busy ? null : () => _extend(5),
                    child: const Text('+5 min'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _busy ? null : () => _extend(10),
                    child: const Text('+10 min'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
