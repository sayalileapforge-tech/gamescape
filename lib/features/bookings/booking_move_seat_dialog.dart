import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class BookingMoveSeatDialog extends StatefulWidget {
  final String branchId;
  final String sessionId;
  final String currentSeatId;

  const BookingMoveSeatDialog({
    super.key,
    required this.branchId,
    required this.sessionId,
    required this.currentSeatId,
  });

  @override
  State<BookingMoveSeatDialog> createState() => _BookingMoveSeatDialogState();
}

class _BookingMoveSeatDialogState extends State<BookingMoveSeatDialog> {
  String? _newSeatId;
  String? _newSeatLabel;

  /// what to bill for the segment that is ending now
  /// values: 'actual', '30', '60'
  String _billCurrentAs = 'actual';

  // High-contrast tokens for dark UI
  static const _bg = Color(0xFF0F172A);     // slate-900
  static const _card = Color(0xFF111827);   // slate-800
  static const _text = Colors.white;
  static const _textWeak = Color(0xFFCBD5E1);
  static const _textMute = Color(0xFF94A3B8);
  static const _border = Color(0xFF334155);
  static const _accent = Color(0xFFFFB020);

  @override
  Widget build(BuildContext context) {
    final seatsQuery = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('seats')
        .where('active', isEqualTo: true);

    return Dialog(
      backgroundColor: _bg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _border),
          ),
          padding: const EdgeInsets.all(18),
          child: StreamBuilder<QuerySnapshot>(
            stream: seatsQuery.snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 140,
                  child: Center(child: CircularProgressIndicator(color: _text)),
                );
              }
              if (snapshot.hasError) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Failed to load seats',
                      style: TextStyle(color: Colors.redAccent)),
                );
              }

              final allDocs = snapshot.data?.docs ?? const <QueryDocumentSnapshot>[];
              // Exclude current seat to avoid moving to the same one
              final docs = allDocs.where((d) => d.id != widget.currentSeatId).toList();

              return DefaultTextStyle(
                style: const TextStyle(color: _text, height: 1.15),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Move to another seat',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: _text),
                    ),
                    const SizedBox(height: 14),

                    // Seat picker
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Select new seat',
                          style: const TextStyle(color: _textWeak, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B1220),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _border),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: DropdownButtonFormField<String>(
                        value: _newSeatId,
                        isExpanded: true,
                        dropdownColor: _card,
                        iconEnabledColor: _textWeak,
                        style: const TextStyle(color: _text, fontWeight: FontWeight.w600),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Select new seat',
                          hintStyle: TextStyle(color: _textMute),
                        ),
                        items: docs.map((d) {
                          final m = (d.data() as Map<String, dynamic>? ?? {});
                          final label = (m['label'] ?? d.id).toString();
                          final type = (m['type'] ?? '').toString();
                          final rate = (m['ratePerHour'] ?? '').toString();
                          final sub = [
                            if (type.isNotEmpty) type,
                            if (rate.isNotEmpty) '₹$rate/hr',
                          ].join(' • ');
                          return DropdownMenuItem(
                            value: d.id,
                            child: Row(
                              children: [
                                const Icon(Icons.chair, size: 18, color: _textWeak),
                                const SizedBox(width: 8),
                                Expanded(child: Text(label)),
                                if (sub.isNotEmpty)
                                  Text(sub, style: const TextStyle(color: _textMute, fontSize: 11)),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (v) {
                          setState(() {
                            _newSeatId = v;
                            if (v == null) {
                              _newSeatLabel = null;
                            } else {
                              final doc = docs.firstWhere((e) => e.id == v);
                              final data = (doc.data() as Map<String, dynamic>? ?? {});
                              _newSeatLabel = (data['label'] ?? '').toString();
                            }
                          });
                        },
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Billing mode – more legible with strong labels
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Bill time spent on current seat as:',
                        style: const TextStyle(color: _textWeak, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _BillTile(
                      title: 'Actual minutes (auto)',
                      subtitle: 'Compute the exact time spent until now.',
                      value: 'actual',
                      groupValue: _billCurrentAs,
                      onChanged: (v) => setState(() => _billCurrentAs = v!),
                    ),
                    _BillTile(
                      title: '30 minutes',
                      subtitle: 'Bill a flat 30 minutes on current seat.',
                      value: '30',
                      groupValue: _billCurrentAs,
                      onChanged: (v) => setState(() => _billCurrentAs = v!),
                    ),
                    _BillTile(
                      title: '1 hour',
                      subtitle: 'Bill a flat 60 minutes on current seat.',
                      value: '60',
                      groupValue: _billCurrentAs,
                      onChanged: (v) => setState(() => _billCurrentAs = v!),
                    ),

                    const SizedBox(height: 16),

                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: ElevatedButton(
                              onPressed: (_newSeatId == null) ? null : _move,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _accent,
                                foregroundColor: Colors.black,
                                disabledBackgroundColor: const Color(0xFF263047),
                                disabledForegroundColor: _textMute,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Move', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _move() async {
    if (_newSeatId == null || _newSeatId == widget.currentSeatId) return;

    final now = DateTime.now();
    final currentUser = FirebaseAuth.instance.currentUser;

    final fs = FirebaseFirestore.instance;
    final branchRef = fs.collection('branches').doc(widget.branchId);
    final sessionRef = branchRef.collection('sessions').doc(widget.sessionId);

    // Read the FROM seat label for correct history
    String? fromSeatLabel;
    try {
      final fromSeat = await branchRef.collection('seats').doc(widget.currentSeatId).get();
      fromSeatLabel = (fromSeat.data()?['label'] ?? widget.currentSeatId).toString();
    } catch (_) {
      fromSeatLabel = widget.currentSeatId;
    }

    // 1) update session seat (current)
    await sessionRef.update({
      'seatId': _newSeatId,
      'seatLabel': _newSeatLabel,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 2) log seat change + how to bill that segment
    await sessionRef.collection('seat_changes').add({
      'fromSeatId': widget.currentSeatId,
      'fromSeatLabel': fromSeatLabel,
      'toSeatId': _newSeatId,
      'toSeatLabel': _newSeatLabel,
      'changedAt': Timestamp.fromDate(now),
      'billSegmentAs': _billCurrentAs, // 'actual' | '30' | '60'
      if (currentUser != null) 'changedBy': currentUser.uid,
    });

    if (mounted) Navigator.of(context).pop();
  }
}

class _BillTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String value;
  final String groupValue;
  final ValueChanged<String?> onChanged;

  const _BillTile({
    required this.title,
    this.subtitle,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  static const _card = Color(0xFF0B1220);
  static const _border = Color(0xFF334155);
  static const _accent = Color(0xFFFFB020);
  static const _text = Colors.white;
  static const _textMute = Color(0xFF94A3B8);

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: selected ? _accent : _border),
      ),
      child: RadioListTile<String>(
        value: value,
        groupValue: groupValue,
        onChanged: onChanged,
        controlAffinity: ListTileControlAffinity.leading,
        dense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        activeColor: _accent,
        title: Text(
          title,
          style: const TextStyle(color: _text, fontWeight: FontWeight.w700),
        ),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!, style: const TextStyle(color: _textMute)),
      ),
    );
  }
}
