// FULL FILE: lib/features/seats/seats_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/seat_model.dart';

class SeatsScreen extends StatelessWidget {
  final String branchId;
  final String branchName;
  const SeatsScreen({
    super.key,
    required this.branchId,
    required this.branchName,
  });

  @override
  Widget build(BuildContext context) {
    final seatsCol = FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('seats');

    return Dialog(
      child: Container(
        width: 640,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Seats – $branchName',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textStrong,
                  ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => AddEditSeatDialog(branchId: branchId),
                  );
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Seat'),
              ),
            ),
            const SizedBox(height: 14),
            StreamBuilder<QuerySnapshot>(
              stream: seatsCol.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text('No seats yet.', style: TextStyle(color: AppTheme.textMute)),
                  );
                }

                // Convert + natural sort on label (C1 < C2 < C10)
                final seats = snapshot.data!.docs
                    .map((d) => SeatModel.fromMap(d.id, d.data() as Map<String, dynamic>))
                    .toList()
                  ..sort((a, b) => _naturalCompare(a.label, b.label));

                return SizedBox(
                  height: 420,
                  child: ListView.separated(
                    itemCount: seats.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final seat = seats[index];
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.bg2,
                          border: Border.all(color: AppTheme.outlineSoft),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: AppTheme.bg0,
                              child: Text(
                                seat.label.isNotEmpty ? seat.label[0].toUpperCase() : '?',
                                style: const TextStyle(color: AppTheme.textStrong),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    seat.label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: AppTheme.textStrong,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${seat.type} • ₹${seat.ratePerHour}/hr'
                                    '${(seat.rate30Single != null || seat.rate60Single != null || seat.rate30Multi != null || seat.rate60Multi != null) ? ' • Adv. rates' : ''}'
                                    '${seat.supportsMultiplayer ? ' • Multiplayer' : ''}',
                                    style: const TextStyle(color: AppTheme.textMed),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: seat.active ? Colors.green.withOpacity(0.12) : Colors.red.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                seat.active ? 'Active' : 'Inactive',
                                style: TextStyle(
                                  color: seat.active ? Colors.green.shade300 : Colors.red.shade300,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Edit seat',
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (_) => AddEditSeatDialog(
                                    branchId: branchId,
                                    existing: seat,
                                  ),
                                );
                              },
                              icon: const Icon(Icons.edit, color: AppTheme.textStrong),
                            ),
                            IconButton(
                              tooltip: 'Delete seat',
                              onPressed: () async {
                                await seatsCol.doc(seat.id).delete();
                              },
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Natural compare for labels like "C1", "C10", "PC-2"
int _naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final ma = re.allMatches(a);
  final mb = re.allMatches(b);
  final n = ma.length < mb.length ? ma.length : mb.length;

  for (var i = 0; i < n; i++) {
    final sa = ma.elementAt(i).group(0)!;
    final sb = mb.elementAt(i).group(0)!;
    final na = int.tryParse(sa);
    final nb = int.tryParse(sb);
    if (na != null && nb != null) {
      if (na != nb) return na.compareTo(nb);
    } else {
      final cmp = sa.compareTo(sb);
      if (cmp != 0) return cmp;
    }
  }
  return ma.length.compareTo(mb.length);
}

class AddEditSeatDialog extends StatefulWidget {
  final String branchId;
  final SeatModel? existing;
  const AddEditSeatDialog({
    super.key,
    required this.branchId,
    this.existing,
  });

  @override
  State<AddEditSeatDialog> createState() => _AddEditSeatDialogState();
}

class _AddEditSeatDialogState extends State<AddEditSeatDialog> {
  final _labelCtrl = TextEditingController();
  final _typeCtrl = TextEditingController(text: 'Standard');
  final _rateCtrl = TextEditingController(text: '0');
  bool _active = true;

  final _rate30SingleCtrl = TextEditingController();
  final _rate60SingleCtrl = TextEditingController();
  final _rate30MultiCtrl = TextEditingController();
  final _rate60MultiCtrl = TextEditingController();
  bool _supportsMultiplayer = false;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final s = widget.existing!;
      _labelCtrl.text = s.label;
      _typeCtrl.text = s.type;
      _rateCtrl.text = s.ratePerHour.toString();
      _active = s.active;
      if (s.rate30Single != null) _rate30SingleCtrl.text = s.rate30Single!.toString();
      if (s.rate60Single != null) _rate60SingleCtrl.text = s.rate60Single!.toString();
      if (s.rate30Multi != null) _rate30MultiCtrl.text = s.rate30Multi!.toString();
      if (s.rate60Multi != null) _rate60MultiCtrl.text = s.rate60Multi!.toString();
      _supportsMultiplayer = s.supportsMultiplayer;
    }
  }

  num? _numOrNull(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return num.tryParse(t);
  }

  Future<void> _save() async {
    if (_labelCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final seatsCol = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('seats');

    final rate = num.tryParse(_rateCtrl.text.trim()) ?? 0;

    final payload = <String, dynamic>{
      'label': _labelCtrl.text.trim(),
      'type': _typeCtrl.text.trim(),
      'ratePerHour': rate,
      'active': _active,
      if (_numOrNull(_rate30SingleCtrl.text) != null) 'rate30Single': _numOrNull(_rate30SingleCtrl.text),
      if (_numOrNull(_rate60SingleCtrl.text) != null) 'rate60Single': _numOrNull(_rate60SingleCtrl.text),
      if (_supportsMultiplayer && _numOrNull(_rate30MultiCtrl.text) != null)
        'rate30Multi': _numOrNull(_rate30MultiCtrl.text),
      if (_supportsMultiplayer && _numOrNull(_rate60MultiCtrl.text) != null)
        'rate60Multi': _numOrNull(_rate60MultiCtrl.text),
      'supportsMultiplayer': _supportsMultiplayer,
    };

    if (widget.existing == null) {
      payload['createdAt'] = FieldValue.serverTimestamp();
      await seatsCol.add(payload);
    } else {
      payload['updatedAt'] = FieldValue.serverTimestamp();
      await seatsCol.doc(widget.existing!.id).update(payload);
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final multiplayerEnabled = _supportsMultiplayer;

    return Dialog(
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.existing == null ? 'Add Seat' : 'Edit Seat',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _labelCtrl,
                decoration: const InputDecoration(labelText: 'Seat label (e.g. C1 / PC-01)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _typeCtrl,
                decoration: const InputDecoration(labelText: 'Type (e.g. PC / Console / VIP)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _rateCtrl,
                decoration: const InputDecoration(labelText: 'Rate per hour (₹)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                title: const Text('Active'),
                contentPadding: EdgeInsets.zero,
              ),

              const SizedBox(height: 6),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                initiallyExpanded: widget.existing != null &&
                    (_rate30SingleCtrl.text.isNotEmpty ||
                        _rate60SingleCtrl.text.isNotEmpty ||
                        _rate30MultiCtrl.text.isNotEmpty ||
                        _rate60MultiCtrl.text.isNotEmpty),
                leading: const Icon(Icons.tune, size: 18),
                title: const Text(
                  'Advanced pricing (optional)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                children: [
                  const SizedBox(height: 6),
                  SwitchListTile(
                    value: _supportsMultiplayer,
                    onChanged: (v) => setState(() => _supportsMultiplayer = v),
                    title: const Text('Supports multiplayer pricing'),
                    subtitle: const Text('Enable if this seat can be billed as multiplayer (2+ players per seat).'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 6),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Single player rates',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: AppTheme.textMed,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _rate30SingleCtrl,
                          decoration: const InputDecoration(labelText: '30 mins (₹)'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _rate60SingleCtrl,
                          decoration: const InputDecoration(labelText: '60 mins (₹)'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Multiplayer rates',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: multiplayerEnabled ? AppTheme.textMed : AppTheme.textFaint,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _rate30MultiCtrl,
                          enabled: multiplayerEnabled,
                          decoration: const InputDecoration(labelText: '30 mins (₹)'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _rate60MultiCtrl,
                          enabled: multiplayerEnabled,
                          decoration: const InputDecoration(labelText: '60 mins (₹)'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
              ),

              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2))
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
