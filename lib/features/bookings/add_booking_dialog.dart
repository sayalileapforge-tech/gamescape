import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AddBookingDialog extends StatefulWidget {
  final List<String>? allowedBranchIds;
  final String? initialBranchId;

  // Prefill from Customers → Bookings flow
  final String? prefillName;
  final String? prefillPhone;

  const AddBookingDialog({
    super.key,
    this.allowedBranchIds,
    this.initialBranchId,
    this.prefillName,
    this.prefillPhone,
  });

  @override
  State<AddBookingDialog> createState() => _AddBookingDialogState();
}

class _AddBookingDialogState extends State<AddBookingDialog> {
  final _formKey = GlobalKey<FormState>();

  String? _selectedBranchId;
  String? _selectedBranchName;

  // Seat filtering & selection
  String? _selectedSeatType; // filter value ("All" or a type)
  String _seatSearch = '';
  final Map<String, _SelectedSeat> _selectedSeats = {}; // seatId -> selection

  final _customerNameCtrl = TextEditingController();
  final _customerPhoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  final _paxCtrl = TextEditingController(text: '1');
  final _gamePrefCtrl = TextEditingController();
  String _paymentType = 'postpaid';

  // Duration options
  final List<int> _durationOptions = const [30, 60, 90, 120, 150, 180, 240, 300];
  int _selectedDuration = 60;

  // Group pax mode (kept for back-compat; we also store per-seat seatPaxMode)
  String _paxMode = 'single'; // 'single' | 'multi'

  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedBranchId = widget.initialBranchId;

    if ((widget.prefillName ?? '').isNotEmpty) {
      _customerNameCtrl.text = widget.prefillName!;
    }
    if ((widget.prefillPhone ?? '').isNotEmpty) {
      _customerPhoneCtrl.text = widget.prefillPhone!;
    }
  }

  DateTime get _startDateTime => DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );

  DateTime get _endDateTime => _startDateTime.add(Duration(minutes: _selectedDuration));

  @override
  Widget build(BuildContext context) {
    final branchesCol = FirebaseFirestore.instance.collection('branches');

    return Dialog(
      backgroundColor: const Color(0xFF1F2937),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: SingleChildScrollView(
            child: DefaultTextStyle(
              style: const TextStyle(color: Colors.white),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Create Booking',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                    ),
                    const SizedBox(height: 12),

                    // ── Row: Branch + Date/Time ────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: StreamBuilder<QuerySnapshot>(
                            stream: branchesCol.snapshots(),
                            builder: (context, snapshot) {
                              final all = snapshot.hasData ? snapshot.data!.docs : <QueryDocumentSnapshot>[];
                              final items = (widget.allowedBranchIds == null || widget.allowedBranchIds!.isEmpty)
                                  ? all
                                  : all.where((d) => widget.allowedBranchIds!.contains(d.id)).toList();

                              if (_selectedBranchId == null && items.isNotEmpty) {
                                _selectedBranchId = items.first.id;
                                _selectedBranchName =
                                    (items.first.data() as Map<String, dynamic>? ?? {})['name']?.toString();
                              }

                              return DropdownButtonFormField<String>(
                                value: _selectedBranchId,
                                dropdownColor: const Color(0xFF111827),
                                style: const TextStyle(color: Colors.white),
                                decoration: _darkInput('Branch'),
                                items: items.map((d) {
                                  final name =
                                      (d.data() as Map<String, dynamic>? ?? {})['name']?.toString() ?? 'Branch';
                                  return DropdownMenuItem(
                                    value: d.id,
                                    child: Text(name),
                                  );
                                }).toList(),
                                onChanged: (v) {
                                  setState(() {
                                    _selectedBranchId = v;
                                    if (v != null && items.isNotEmpty) {
                                      final doc = items.firstWhere(
                                        (e) => e.id == v,
                                        orElse: () => items.first,
                                      );
                                      _selectedBranchName =
                                          ((doc.data() as Map<String, dynamic>? ?? {})['name'])?.toString() ?? '';
                                    } else {
                                      _selectedBranchName = null;
                                    }
                                    _selectedSeatType = null;
                                    _seatSearch = '';
                                    _selectedSeats.clear();
                                  });
                                },
                                validator: (v) => (v == null || v.isEmpty) ? 'Select a branch' : null,
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: _pickDate,
                            child: InputDecorator(
                              decoration: _darkInput('Date'),
                              child: Text(
                                '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: _pickTime,
                            child: InputDecorator(
                              decoration: _darkInput('Time'),
                              child: Text(_selectedTime.format(context)),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // ── Seat picker block (with real-time "occupied at that time" filtering) ──
                    if (_selectedBranchId != null)
                      _OverlappingSeatFilter(
                        branchId: _selectedBranchId!,
                        start: _startDateTime,
                        end: _endDateTime,
                        builder: (context, occupiedSeatIds) {
                          return _SeatPickerBlock(
                            branchId: _selectedBranchId!,
                            currentFilter: _selectedSeatType ?? 'All',
                            onFilterChanged: (v) => setState(() => _selectedSeatType = v),
                            search: _seatSearch,
                            onSearchChanged: (v) => setState(() => _seatSearch = v.trim()),
                            selected: _selectedSeats,
                            // Hide any seats that are occupied/reserved overlapping this time
                            excludedSeatIds: occupiedSeatIds,
                          );
                        },
                      ),

                    const SizedBox(height: 14),

                    // ── Customer & meta ───────────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _customerPhoneCtrl,
                            decoration: _darkTextField('Customer phone'),
                            style: const TextStyle(color: Colors.white),
                            keyboardType: TextInputType.phone,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            validator: (v) {
                              final normalized = _normalizePhone(v ?? '');
                              if (normalized.isEmpty) return 'Enter phone number';
                              if (normalized.length != 10) {
                                return 'Enter 10-digit phone';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _customerNameCtrl,
                            decoration: _darkTextField('Customer name'),
                            style: const TextStyle(color: Colors.white),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter customer name' : null,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _paxMode,
                            dropdownColor: const Color(0xFF111827),
                            style: const TextStyle(color: Colors.white),
                            decoration: _darkInput('Group mode'),
                            items: const [
                              DropdownMenuItem(value: 'single', child: Text('Single')),
                              DropdownMenuItem(value: 'multi', child: Text('Multiplayer')),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() {
                                _paxMode = v;
                                // Fill pax sensibly if empty
                                if ((_paxCtrl.text.trim().isEmpty) ||
                                    (int.tryParse(_paxCtrl.text.trim()) ?? 0) <= 0) {
                                  _paxCtrl.text = v == 'single' ? '1' : '2';
                                }
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _paxCtrl,
                            decoration: _darkTextField('Number of people'),
                            style: const TextStyle(color: Colors.white),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Enter number of people';
                              }
                              final n = int.tryParse(v.trim());
                              if (n == null || n <= 0) {
                                return 'Pax must be at least 1';
                              }
                              if (_paxMode == 'multi' && n < 2) {
                                return 'For Multiplayer, pax must be ≥ 2';
                              }
                              if (n > 99) return 'Pax out of range';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _gamePrefCtrl,
                            decoration: _darkTextField('Game preference (optional)'),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
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
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // ── Duration (dropdown only) ──────────────────────────────
                    DropdownButtonFormField<int>(
                      value: _selectedDuration,
                      dropdownColor: const Color(0xFF111827),
                      style: const TextStyle(color: Colors.white),
                      decoration: _darkInput('Duration'),
                      items: _durationOptions.map((m) => DropdownMenuItem(value: m, child: Text('$m minutes'))).toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedDuration = v);
                      },
                    ),

                    const SizedBox(height: 12),

                    TextField(
                      controller: _notesCtrl,
                      decoration: _darkTextField('Notes'),
                      style: const TextStyle(color: Colors.white),
                      maxLines: 2,
                    ),

                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: ElevatedButton(
                              onPressed: _saving ? null : _onSubmit,
                              child: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('Create'),
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
        ),
      ),
    );
  }

  InputDecoration _darkInput(String label) {
    return const InputDecoration(
      labelText: null,
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

  InputDecoration _darkTextField(String label) => _darkInput(label);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      initialDate: _selectedDate,
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showBookingDeniedDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1F2937),
          title: const Text(
            'Booking denied',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          content: const Text(
            'One or more seats are already booked for the selected time range.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _onSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    await _save();
  }

  String _normalizePhone(String raw) {
    var s = raw.replaceAll(RegExp(r'\D'), ''); // keep digits
    if (s.startsWith('91') && s.length == 12) {
      s = s.substring(2);
    }
    if (s.startsWith('0') && s.length == 11) {
      s = s.substring(1);
    }
    return s;
  }

  Future<void> _save() async {
    if (_selectedBranchId == null) {
      _toast('Select a branch');
      return;
    }

    if (_selectedSeats.isEmpty) {
      _toast('Select at least one seat');
      return;
    }

    final normalizedPhone = _normalizePhone(_customerPhoneCtrl.text);
    if (normalizedPhone.isEmpty || normalizedPhone.length != 10) {
      _toast('Enter a valid 10-digit phone');
      return;
    }
    if (_customerNameCtrl.text.trim().isEmpty) {
      _toast('Enter customer name');
      return;
    }
    if (_paxCtrl.text.trim().isEmpty || (int.tryParse(_paxCtrl.text.trim()) ?? 0) <= 0) {
      _toast('Enter number of people');
      return;
    }

    final pax = int.tryParse(_paxCtrl.text.trim()) ?? 1;

    setState(() => _saving = true);

    try {
      final start = _startDateTime;
      final end = _endDateTime;
      final now = DateTime.now();
      final isFuture = start.isAfter(now);

      final fs = FirebaseFirestore.instance;
      final sessionsCol = fs.collection('branches').doc(_selectedBranchId).collection('sessions');
      final seatsCol = fs.collection('branches').doc(_selectedBranchId).collection('seats');

      // Load current user name for createdByName
      String? createdByName;
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        final userDoc = await fs.collection('users').doc(currentUser.uid).get();
        if (userDoc.exists) {
          createdByName = (userDoc.data()?['name'] as String?) ?? currentUser.email;
        }
      }

      // Preload seat state + overlap check (server truth before commit)
      final Map<String, Map<String, dynamic>> seatDataMap = {};
      final Map<String, String> seatStatusMap = {};

      for (final sel in _selectedSeats.values) {
        final seatRef = seatsCol.doc(sel.seatId);

        final seatSnap = await seatRef.get();
        final seatData = seatSnap.data() ?? {};
        final seatStatus = (seatData['status'] ?? 'free').toString();

        seatDataMap[sel.seatId] = seatData;
        seatStatusMap[sel.seatId] = seatStatus;

        // Overlap check on server snapshot (robust duration parse)
        final seatSessionsSnap = await sessionsCol.where('seatId', isEqualTo: sel.seatId).get();

        bool hasOverlap = false;
        for (final doc in seatSessionsSnap.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final status = (data['status'] ?? '').toString();
          if (status != 'active' && status != 'reserved') continue;

          final otherStart = (data['startTime'] as Timestamp?)?.toDate();
          final otherDuration = _asInt(data['durationMinutes']);
          if (otherStart == null) continue;

          final otherEnd = otherStart.add(Duration(minutes: otherDuration));
          final overlaps = otherStart.isBefore(end) && otherEnd.isAfter(start);
          if (overlaps) {
            hasOverlap = true;
            break;
          }
        }

        if (hasOverlap) {
          setState(() => _saving = false);
          await _showBookingDeniedDialog();
          return;
        }
      }

      final batch = fs.batch();

      for (final sel in _selectedSeats.values) {
        final seatRef = seatsCol.doc(sel.seatId);
        final seatData = seatDataMap[sel.seatId] ?? {};
        final seatStatus = seatStatusMap[sel.seatId] ?? 'free';

        // Decide new seat status without corrupting currentSessionId for future reservations
        String newSeatStatus;
        bool setCurrentSessionOnSeat;
        if (isFuture) {
          newSeatStatus = (seatStatus == 'in-use') ? 'in-use' : 'reserved';
          setCurrentSessionOnSeat = false;
        } else {
          newSeatStatus = 'in-use';
          setCurrentSessionOnSeat = true;
        }

        final sessionRef = sessionsCol.doc();

        final payload = <String, dynamic>{
          'customerName': _customerNameCtrl.text.trim(),
          'customerPhone': normalizedPhone,
          'branchId': _selectedBranchId,
          'branchName': _selectedBranchName,
          'seatId': sel.seatId,
          'seatLabel': sel.seatLabel,
          'startTime': Timestamp.fromDate(start),
          'durationMinutes': _selectedDuration,
          'pax': pax,
          'paxMode': _paxMode, // group-level (legacy/analytics)
          'seatPaxMode': sel.mode, // per-seat mode
          'gamePreference': _gamePrefCtrl.text.trim(),
          'paymentType': _paymentType,
          'status': isFuture ? 'reserved' : 'active',
          'paymentStatus': 'pending',
          'notes': _notesCtrl.text.trim(),
          // snapshot useful seat fields in case rates change later
          'seatType': sel.seatType,
          'seatRatePerHour': seatData['ratePerHour'],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          if (currentUser != null) 'createdBy': currentUser.uid,
          if (createdByName != null) 'createdByName': createdByName,
        };

        batch.set(sessionRef, payload);
        batch.update(seatRef, {
          'status': newSeatStatus,
          'currentSessionId': setCurrentSessionOnSeat ? sessionRef.id : (seatData['currentSessionId'] ?? null),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      if (!mounted) return;
      Navigator.of(context).pop(true);
      _toast(_selectedSeats.length > 1 ? 'Group booking created (${_selectedSeats.length} seats)' : 'Booking created');
    } catch (e) {
      if (!mounted) return;
      _toast('Failed to create booking: $e');
      setState(() => _saving = false);
    }
  }
}

// ───────────────────────────────────────────────────────────────────────────────
// Compute seats that are OCCUPIED/RESERVED overlapping the requested window,
// then pass them to the picker to HIDE from selection.
// ───────────────────────────────────────────────────────────────────────────────
class _OverlappingSeatFilter extends StatelessWidget {
  final String branchId;
  final DateTime start;
  final DateTime end;
  final Widget Function(BuildContext, Set<String> occupiedSeatIds) builder;

  const _OverlappingSeatFilter({
    required this.branchId,
    required this.start,
    required this.end,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final sessionsQ = FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('sessions')
        // coarse window so we can compute overlap client-side
        .where('startTime', isLessThan: Timestamp.fromDate(end));

    return StreamBuilder<QuerySnapshot>(
      stream: sessionsQ.snapshots(),
      builder: (context, snap) {
        final occupied = <String>{};
        final docs = snap.data?.docs ?? [];
        for (final d in docs) {
          final m = d.data() as Map<String, dynamic>? ?? {};
          final status = (m['status'] ?? '').toString();
          if (status != 'active' && status != 'reserved') continue;

          final otherStart = (m['startTime'] as Timestamp?)?.toDate();
          final otherDur = _asInt(m['durationMinutes']);
          if (otherStart == null) continue;
          final otherEnd = otherStart.add(Duration(minutes: otherDur));

          final overlaps = otherStart.isBefore(end) && otherEnd.isAfter(start);
          if (overlaps) {
            final seatId = (m['seatId'] ?? '').toString();
            if (seatId.isNotEmpty) occupied.add(seatId);
          }
        }
        return builder(context, occupied);
      },
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────────
// Seat picker block with filter/search, checkbox list, and per-seat mode toggle
// ───────────────────────────────────────────────────────────────────────────────
class _SeatPickerBlock extends StatelessWidget {
  final String branchId;
  final String currentFilter; // 'All' or type
  final ValueChanged<String> onFilterChanged;
  final String search;
  final ValueChanged<String> onSearchChanged;

  /// Selected map is mutated by parent via callbacks on checkbox/mode change.
  final Map<String, _SelectedSeat> selected;

  /// These seats are **hidden** (occupied/reserved overlapping requested time).
  final Set<String> excludedSeatIds;

  const _SeatPickerBlock({
    required this.branchId,
    required this.currentFilter,
    required this.onFilterChanged,
    required this.search,
    required this.onSearchChanged,
    required this.selected,
    required this.excludedSeatIds,
  });

  bool _typeDisallowsMulti(String type) {
    final t = type.toLowerCase();
    return t.contains('couch') || t.contains('racing');
  }

  @override
  Widget build(BuildContext context) {
    final seatsQuery = FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('seats')
        .where('active', isEqualTo: true);

    return StreamBuilder<QuerySnapshot>(
      stream: seatsQuery.snapshots(),
      builder: (context, snapshot) {
        var seatDocs = snapshot.hasData ? snapshot.data!.docs.toList() : <QueryDocumentSnapshot>[];

        // Hide excluded (occupied during chosen window)
        seatDocs = seatDocs.where((d) => !excludedSeatIds.contains(d.id)).toList();

        // Collect & sort types
        final types = <String>{};
        for (final d in seatDocs) {
          final t = ((d.data() as Map<String, dynamic>)['type'] ?? '').toString();
          if (t.isNotEmpty) types.add(t);
        }
        final typeList = ['All', ...types.toList()..sort()];

        // ✅ Natural sort seats by label (C1..C9..C10 correct)
        seatDocs.sort((a, b) {
          final ma = a.data() as Map<String, dynamic>;
          final mb = b.data() as Map<String, dynamic>;
          final la = (ma['label'] ?? '').toString();
          final lb = (mb['label'] ?? '').toString();
          return _compareSeatLabelsNatural(la, lb);
        });

        // Filter by type
        Iterable<QueryDocumentSnapshot> filtered = seatDocs;
        if (currentFilter != 'All' && currentFilter.isNotEmpty) {
          filtered = filtered.where((d) => ((d.data() as Map<String, dynamic>)['type'] ?? '') == currentFilter);
        }
        // Search
        if (search.isNotEmpty) {
          final q = search.toLowerCase();
          filtered = filtered.where((d) {
            final m = d.data() as Map<String, dynamic>;
            final label = (m['label'] ?? '').toString().toLowerCase();
            final type = (m['type'] ?? '').toString().toLowerCase();
            return label.contains(q) || type.contains(q);
          });
        }
        final list = filtered.toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Filter + Search
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: currentFilter,
                    dropdownColor: const Color(0xFF111827),
                    style: const TextStyle(color: Colors.white),
                    decoration: _darkInput('Seat type'),
                    items: typeList.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (v) => onFilterChanged(v ?? 'All'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    decoration: _darkTextField('Search (label/type)'),
                    onChanged: onSearchChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Seats list with checkbox + per-seat mode (Single/Multi)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: list.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(18.0),
                          child: Text('No seats match the filter or are available for this time.'),
                        ),
                      )
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (ctx, i) {
                          final d = list[i];
                          final m = d.data() as Map<String, dynamic>;
                          final seatId = d.id;
                          final label = (m['label'] ?? 'Seat').toString();
                          final type = (m['type'] ?? '').toString();
                          final rate = (m['ratePerHour'] ?? 0).toString();

                          final already = selected[seatId] != null;
                          final disallowMulti = _typeDisallowsMulti(type);
                          final supportsMulti =
                              (m['supportsMultiplayer'] == true) || m['rate30Multi'] != null || m['rate60Multi'] != null;
                          final canMulti = supportsMulti && !disallowMulti;

                          return CheckboxListTile(
                            value: already,
                            onChanged: (v) {
                              if (v == true) {
                                selected[seatId] = _SelectedSeat(
                                  seatId: seatId,
                                  seatLabel: label,
                                  seatType: type,
                                  mode: 'single', // default single
                                  allowsMulti: canMulti,
                                );
                              } else {
                                selected.remove(seatId);
                              }
                              // trigger parent rebuild
                              (context as Element).markNeedsBuild();
                            },
                            title: Text('$label • $type • ₹$rate/hr'),
                            controlAffinity: ListTileControlAffinity.leading,
                            secondary: _SeatModePill(
                              enabled: already,
                              allowsMulti: canMulti,
                              mode: already ? selected[seatId]!.mode : 'single',
                              onToggle: () {
                                if (!already) return;
                                final cur = selected[seatId]!;
                                if (!cur.allowsMulti) return;
                                cur.mode = (cur.mode == 'single') ? 'multi' : 'single';
                                (context as Element).markNeedsBuild();
                              },
                            ),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tip: Seats overlapping with the chosen time are hidden. Toggle Single/Multiplayer per seat (disabled for Couch/Racing).',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        );
      },
    );
  }
}

// Small pill showing Single/Multi with toggle behavior
class _SeatModePill extends StatelessWidget {
  final bool enabled;
  final bool allowsMulti;
  final String mode; // 'single' | 'multi'
  final VoidCallback onToggle;

  const _SeatModePill({
    required this.enabled,
    required this.allowsMulti,
    required this.mode,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isMulti = mode == 'multi';
    final locked = !allowsMulti;
    final label = locked ? 'Single' : (isMulti ? 'Multi' : 'Single');

    return InkWell(
      onTap: (!enabled || locked) ? null : onToggle,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white24),
          color: (!enabled)
              ? Colors.white12
              : (locked ? Colors.white10 : (isMulti ? Colors.white : Colors.transparent)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              locked ? Icons.lock : (isMulti ? Icons.group : Icons.person_outline),
              size: 14,
              color: locked ? Colors.white60 : (isMulti ? const Color(0xFF111827) : Colors.white70),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: locked ? Colors.white60 : (isMulti ? const Color(0xFF111827) : Colors.white),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────────
// Models & helpers (local to this file)
// ───────────────────────────────────────────────────────────────────────────────
class _SelectedSeat {
  final String seatId;
  final String seatLabel;
  final String seatType;
  bool allowsMulti;
  String mode; // 'single' | 'multi'

  _SelectedSeat({
    required this.seatId,
    required this.seatLabel,
    required this.seatType,
    required this.mode,
    required this.allowsMulti,
  });
}

// Shared input decorations
InputDecoration _darkInput(String label) {
  return const InputDecoration(
    labelText: null,
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

InputDecoration _darkTextField(String label) => _darkInput(label);

// ───────────────────────────────────────────────────────────────────────────────
// Helpers: robust int parse + natural label sorting (C2 < C10)
// ───────────────────────────────────────────────────────────────────────────────

int _asInt(dynamic v, {int fallback = 0}) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    final x = int.tryParse(v.trim());
    return x ?? fallback;
  }
  return fallback;
}

/// Natural compare: "C2" < "C10", "PS3" < "PS12", fallback to lowercase string.
int _compareSeatLabelsNatural(String a, String b) {
  final ka = _seatNaturalKey(a);
  final kb = _seatNaturalKey(b);

  // prefix compare
  final p = ka.prefix.compareTo(kb.prefix);
  if (p != 0) return p;

  // numeric compare (missing numbers go last)
  final na = ka.number;
  final nb = kb.number;
  if (na != null || nb != null) {
    if (na == null && nb != null) return 1;
    if (na != null && nb == null) return -1;
    if (na != null && nb != null) {
      final n = na.compareTo(nb);
      if (n != 0) return n;
    }
  }

  // suffix compare
  final s = ka.suffix.compareTo(kb.suffix);
  if (s != 0) return s;

  // full fallback
  return a.toLowerCase().compareTo(b.toLowerCase());
}

_SeatKey _seatNaturalKey(String raw) {
  final s = raw.trim();
  final lower = s.toLowerCase();

  // Match: letters (prefix) + optional spaces + digits + rest
  final re = RegExp(r'^([a-zA-Z]+)\s*0*([0-9]+)(.*)$');
  final m = re.firstMatch(s);
  if (m == null) {
    // no leading letters+digits => treat whole string as prefix, no number
    return _SeatKey(prefix: lower, number: null, suffix: '');
  }

  final prefix = (m.group(1) ?? '').toLowerCase();
  final numStr = (m.group(2) ?? '').trim();
  final num = int.tryParse(numStr);
  final suffix = (m.group(3) ?? '').toLowerCase().trim();
  return _SeatKey(prefix: prefix, number: num, suffix: suffix);
}

class _SeatKey {
  final String prefix;
  final int? number;
  final String suffix;
  _SeatKey({required this.prefix, required this.number, required this.suffix});
}
