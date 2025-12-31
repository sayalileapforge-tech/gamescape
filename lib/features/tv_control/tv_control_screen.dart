// FULL FILE: lib/features/tv_control/tv_control_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_shell.dart';
import '../../data/repositories/tv_control_repo.dart';

class TvControlScreen extends StatefulWidget {
  const TvControlScreen({super.key});

  @override
  State<TvControlScreen> createState() => _TvControlScreenState();
}

class _TvControlScreenState extends State<TvControlScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? _selectedBranchId;
  String? _selectedBranchName;
  final TextEditingController _seatIdController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  // HDMI port selection for "Switch to HDMI"
  int _selectedHdmiPort = 1;

  // Toast controls
  final TextEditingController _toastMessageController = TextEditingController();
  final TextEditingController _toastDurationController =
      TextEditingController(text: '5');
  String _toastSeverity = 'info';

  @override
  void dispose() {
    _seatIdController.dispose();
    _notesController.dispose();
    _toastMessageController.dispose();
    _toastDurationController.dispose();
    super.dispose();
  }

  // ----------------------------
  // COMMAND SENDER
  // ----------------------------
  Future<void> _sendCommand({
    required String type,
    Map<String, dynamic>? extraPayload,
  }) async {
    final branchId = _selectedBranchId;
    if (branchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a branch first')),
      );
      return;
    }

    try {
      await TvControlRepo.I.sendCommand(
        branchId: branchId,
        type: type,
        seatId: _seatIdController.text.trim().isEmpty
            ? null
            : _seatIdController.text.trim(),
        payload: {
          if (extraPayload != null) ...extraPayload,
          if (_notesController.text.trim().isNotEmpty)
            'notes': _notesController.text.trim(),
        },
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Command "$type" queued for $_selectedBranchName'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send command: $e')),
      );
    }
  }

  // ----------------------------
  // TOAST SENDER
  // ----------------------------
  Future<void> _sendToast() async {
    final branchId = _selectedBranchId;
    if (branchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a branch first')),
      );
      return;
    }

    final message = _toastMessageController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a toast message')),
      );
      return;
    }

    int duration = 5;
    if (_toastDurationController.text.trim().isNotEmpty) {
      final parsed = int.tryParse(_toastDurationController.text.trim());
      if (parsed != null && parsed > 0) {
        duration = parsed;
      }
    }

    try {
      await TvControlRepo.I.sendToast(
        branchId: branchId,
        seatId: _seatIdController.text.trim().isEmpty
            ? null
            : _seatIdController.text.trim(),
        message: message,
        severity: _toastSeverity,
        durationSeconds: duration,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Toast queued to TV overlay')),
      );
      _toastMessageController.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send toast: $e')),
      );
    }
  }

  // ----------------------------
  // BRANCH DROPDOWN
  // ----------------------------
  Widget _buildBranchDropdown() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Text(
        'Not signed in',
        style: TextStyle(color: AppTheme.textMute),
      );
    }

    final userDoc = FirebaseFirestore.instance.collection('users').doc(uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDoc.snapshots(),
      builder: (context, userSnap) {
        if (!userSnap.hasData) {
          return const SizedBox(
            height: 40,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final userData = userSnap.data!.data() ?? {};
        final branchIds = (userData['branchIds'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();

        if (branchIds.isEmpty) {
          return const Text(
            'No branches assigned to your user.',
            style: TextStyle(color: AppTheme.textMute),
          );
        }

        final branchesQuery = FirebaseFirestore.instance
            .collection('branches')
            .where(FieldPath.documentId, whereIn: branchIds);

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: branchesQuery.snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const SizedBox(
                height: 40,
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }

            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return const Text(
                'No branches found.',
                style: TextStyle(color: AppTheme.textMute),
              );
            }

            if (_selectedBranchId == null) {
              final first = docs.first;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() {
                  _selectedBranchId = first.id;
                  _selectedBranchName =
                      first.data()['name']?.toString() ?? first.id;
                });
              });
            }

            return DropdownButtonFormField<String>(
              value: _selectedBranchId,
              decoration: const InputDecoration(
                labelText: 'Branch',
              ),
              items: docs.map((doc) {
                final name = doc.data()['name']?.toString() ?? doc.id;
                return DropdownMenuItem<String>(
                  value: doc.id,
                  child: Text(name, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (v) {
                setState(() {
                  _selectedBranchId = v;
                  final doc = docs.firstWhere((d) => d.id == v);
                  _selectedBranchName =
                      doc.data()['name']?.toString() ?? doc.id;
                  _seatIdController.clear();
                });
              },
            );
          },
        );
      },
    );
  }

  // ----------------------------
  // SEAT FIELD + DROPDOWN
  // ----------------------------
  Widget _buildSeatSelectorField() {
    final branchId = _selectedBranchId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _seatIdController,
          decoration: const InputDecoration(
            labelText: 'Seat ID (optional)',
            hintText: 'Prefer seat *doc id* (e.g. abcd1234)',
          ),
        ),
        const SizedBox(height: 6),
        if (branchId != null)
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db
                .collection('branches')
                .doc(branchId)
                .collection('seats')
                .orderBy('label', descending: false)
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const SizedBox(
                  height: 32,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }

              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return const Text(
                  'No seats configured for this branch.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMute),
                );
              }

              final currentValue = _seatIdController.text.trim();
              String? dropdownValue = currentValue.isEmpty ? null : currentValue;

              if (dropdownValue != null &&
                  !docs.any((d) => d.id == dropdownValue)) {
                dropdownValue = null;
              }

              return DropdownButtonFormField<String>(
                value: dropdownValue,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'Pick a seat (optional)',
                ),
                items: docs.map((doc) {
                  final data = doc.data();
                  final label = (data['label'] ?? doc.id).toString();
                  return DropdownMenuItem<String>(
                    value: doc.id,
                    child: Text('$label (${doc.id})',
                        overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (value) {
                  _seatIdController.text = value ?? '';
                },
              );
            },
          )
        else
          const Text(
            'Select a branch to load seats.',
            style: TextStyle(fontSize: 12, color: AppTheme.textMute),
          ),
      ],
    );
  }

  // Small helper: compact HDMI picker to avoid overflow
  Widget _hdmiPicker() {
    return SizedBox(
      width: 160,
      child: DropdownButtonFormField<int>(
        isExpanded: true,
        value: _selectedHdmiPort,
        decoration: const InputDecoration(
          labelText: 'HDMI Port',
          hintText: 'Default: HDMI 1',
        ),
        items: const [
          DropdownMenuItem(value: 1, child: Text('HDMI 1')),
          DropdownMenuItem(value: 2, child: Text('HDMI 2')),
          DropdownMenuItem(value: 3, child: Text('HDMI 3')),
          DropdownMenuItem(value: 4, child: Text('HDMI 4')),
        ],
        onChanged: (v) => setState(() => _selectedHdmiPort = v ?? 1),
      ),
    );
  }

  // ----------------------------
  // CARD 1 – COMMANDS
  // ----------------------------
  Widget _buildControlsCard() {
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppTheme.textMute,
          fontWeight: FontWeight.w600,
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: LayoutBuilder(
          builder: (context, c) {
            final narrow = c.maxWidth < 760;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TV Control Center',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  'Consumer TVs: Use Launch/Bring to Front (Remote API) + TV overlay app.\n'
                  'Commercial TVs: Power/Input/Volume may work via port 9761.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),

                // Branch + Seat
                if (narrow) ...[
                  _buildBranchDropdown(),
                  const SizedBox(height: 12),
                  _buildSeatSelectorField(),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildBranchDropdown()),
                      const SizedBox(width: 12),
                      Expanded(child: _buildSeatSelectorField()),
                    ],
                  ),

                const SizedBox(height: 12),
                Text('Notes (optional)', style: labelStyle),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Operator notes, reason, etc.',
                  ),
                ),

                const SizedBox(height: 20),
                Text('Consumer-Safe (WebOS Remote API)',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _sendCommand(
                        type: 'launch_app',
                        extraPayload: {
                          'appId': 'com.leapforge.gamescape.tv.webos',
                        },
                      ),
                      icon: const Icon(Icons.rocket_launch_outlined),
                      label: const Text('Launch Overlay App'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _sendCommand(type: 'bring_to_front'),
                      icon: const Icon(Icons.fullscreen),
                      label: const Text('Bring App to Front'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _sendCommand(type: 'refresh_status'),
                      icon: const Icon(Icons.sync),
                      label: const Text('Refresh Status'),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                Text('Commercial (Port 9761 / RS232-IP)',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _hdmiPicker(),
                    ElevatedButton.icon(
                      onPressed: () => _sendCommand(type: 'power_on'),
                      icon: const Icon(Icons.power_settings_new),
                      label: const Text('Power ON'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _sendCommand(type: 'power_off'),
                      icon: const Icon(Icons.power_off),
                      label: const Text('Power OFF'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _sendCommand(
                        type: 'switch_input',
                        extraPayload: {
                          'target': 'hdmi',
                          'hdmiPort': _selectedHdmiPort
                        },
                      ),
                      icon: const Icon(Icons.settings_input_hdmi),
                      label: const Text('Switch to HDMI'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _sendCommand(
                        type: 'switch_input',
                        extraPayload: {'target': 'app'},
                      ),
                      icon: const Icon(Icons.apps),
                      label: const Text('Switch to App'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _sendCommand(type: 'lock_inputs'),
                      icon: const Icon(Icons.lock_outline),
                      label: const Text('Lock Inputs'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _sendCommand(type: 'unlock_inputs'),
                      icon: const Icon(Icons.lock_open_outlined),
                      label: const Text('Unlock Inputs'),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                Text('Audio (Commercial / Best Effort)',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _sendCommand(type: 'mute'),
                      icon: const Icon(Icons.volume_off),
                      label: const Text('Mute'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _sendCommand(type: 'unmute'),
                      icon: const Icon(Icons.volume_up),
                      label: const Text('Unmute'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _sendCommand(
                        type: 'volume_delta',
                        extraPayload: {'delta': 5},
                      ),
                      icon: const Icon(Icons.volume_up_outlined),
                      label: const Text('Volume +'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _sendCommand(
                        type: 'volume_delta',
                        extraPayload: {'delta': -5},
                      ),
                      icon: const Icon(Icons.volume_down_outlined),
                      label: const Text('Volume -'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ----------------------------
  // CARD 1b – SEND TOAST
  // ----------------------------
  Widget _buildToastCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Send On-TV Toast',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Send a small overlay notification to the WebOS TV app. '
              'If Seat ID is empty, this can be treated as branch-wide by the overlay.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _toastMessageController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Message',
                hintText: 'e.g. "Your time is almost up, please save your game."',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _toastSeverity,
                    decoration: const InputDecoration(labelText: 'Severity'),
                    items: const [
                      DropdownMenuItem(value: 'info', child: Text('Info')),
                      DropdownMenuItem(value: 'success', child: Text('Success')),
                      DropdownMenuItem(value: 'warning', child: Text('Warning')),
                      DropdownMenuItem(value: 'error', child: Text('Error')),
                    ],
                    onChanged: (v) =>
                        setState(() => _toastSeverity = v ?? 'info'),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    controller: _toastDurationController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Duration (s)',
                      helperText: '1–60',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _sendToast,
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Send Toast'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------
  // CARD 2 – TV ↔ SEAT MAPPING (adds MAC + optional controlPort; keeps everything else same)
  // ----------------------------

  bool _isValidMac(String mac) {
    final cleaned = mac.trim();
    if (cleaned.isEmpty) return false;
    // Accept AA:BB:CC:DD:EE:FF or AA-BB-CC-DD-EE-FF (case-insensitive)
    final reg = RegExp(r'^([0-9A-Fa-f]{2}([-:])){5}([0-9A-Fa-f]{2})$');
    return reg.hasMatch(cleaned);
  }

  String? _normalizeMac(String mac) {
    final v = mac.trim();
    if (v.isEmpty) return null;
    if (!_isValidMac(v)) return null;
    // Normalize to colon-separated upper
    final parts = v.replaceAll('-', ':').split(':').map((p) => p.toUpperCase()).toList();
    if (parts.length != 6) return null;
    return parts.join(':');
  }

  Future<void> _showAddOrEditTvDeviceDialog({
    String? tvId,
    Map<String, dynamic>? existing,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> allSeats,
  }) async {
    final tvNumberController =
        TextEditingController(text: (existing?['tvNumber'] ?? '').toString());
    final ipController =
        TextEditingController(text: existing?['ip']?.toString() ?? '');
    final modelController =
        TextEditingController(text: existing?['model']?.toString() ?? '');

    // NEW: MAC address (for Wake-on-LAN)
    final macController =
        TextEditingController(text: (existing?['mac'] ?? '').toString());

    // NEW: optional control port for commercial TVs
    final controlPortController =
        TextEditingController(text: (existing?['controlPort'] ?? '').toString());

    final kind = ValueNotifier<String>((existing?['kind'] ?? 'commercial').toString());
    final enabled = ValueNotifier<bool>(existing?['enabled'] == true);

    final existingSeatIds =
        (existing?['seatIds'] as List<dynamic>?)?.map((e) => e.toString()).toSet() ??
            <String>{};
    final selectedSeatIds = ValueNotifier<Set<String>>(existingSeatIds);

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(tvId == null ? 'Add TV Device' : 'Edit TV Device'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: tvNumberController,
                    decoration: const InputDecoration(
                      labelText: 'TV Number / Label',
                      helperText: 'e.g. 0, 1, 2 or custom like TV-01',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ipController,
                    decoration: const InputDecoration(
                      labelText: 'IP Address',
                      helperText: 'Example: 192.168.1.50',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: modelController,
                    decoration: const InputDecoration(
                      labelText: 'Model',
                      helperText: 'Example: 43UR801C',
                    ),
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<String>(
                    valueListenable: kind,
                    builder: (context, value, _) {
                      return DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: value,
                        decoration: const InputDecoration(labelText: 'Kind'),
                        items: const [
                          DropdownMenuItem(value: 'commercial', child: Text('Commercial')),
                          DropdownMenuItem(value: 'consumer', child: Text('Consumer')),
                        ],
                        onChanged: (v) => v != null ? kind.value = v : null,
                      );
                    },
                  ),

                  // NEW: MAC Address
                  const SizedBox(height: 12),
                  TextField(
                    controller: macController,
                    decoration: const InputDecoration(
                      labelText: 'MAC Address (recommended)',
                      helperText:
                          'Required for Consumer Power ON via Wake-on-LAN. Example: AA:BB:CC:DD:EE:FF',
                    ),
                  ),

                  // NEW: control port (optional)
                  const SizedBox(height: 12),
                  TextField(
                    controller: controlPortController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Control Port (optional)',
                      helperText: 'Commercial IP Control port. Default is 9761 if empty.',
                    ),
                  ),

                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Mapped Seats',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textMute,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ValueListenableBuilder<Set<String>>(
                    valueListenable: selectedSeatIds,
                    builder: (context, selected, _) {
                      if (allSeats.isEmpty) {
                        return const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'No seats found for this branch.',
                            style: TextStyle(color: AppTheme.textMute),
                          ),
                        );
                      }
                      return Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: allSeats.map((seatDoc) {
                          final seatId = seatDoc.id;
                          final seatData = seatDoc.data();
                          final label = (seatData['label'] ?? seatId).toString();
                          final isSelected = selected.contains(seatId);
                          return FilterChip(
                            label: Text(label),
                            selected: isSelected,
                            onSelected: (v) {
                              final copy = Set<String>.from(selected);
                              v ? copy.add(seatId) : copy.remove(seatId);
                              selectedSeatIds.value = copy;
                            },
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<bool>(
                    valueListenable: enabled,
                    builder: (context, value, _) {
                      return SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Enabled'),
                        value: value,
                        onChanged: (v) => enabled.value = v,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final branchId = _selectedBranchId;
                if (branchId == null) return;

                final tvNumber = tvNumberController.text.trim();
                if (tvNumber.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('TV Number / Label is required.')),
                  );
                  return;
                }

                final normalizedMac = _normalizeMac(macController.text);
                if (macController.text.trim().isNotEmpty && normalizedMac == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Invalid MAC. Use AA:BB:CC:DD:EE:FF (or AA-BB-CC-DD-EE-FF).'),
                    ),
                  );
                  return;
                }

                int? controlPort;
                final portText = controlPortController.text.trim();
                if (portText.isNotEmpty) {
                  final parsed = int.tryParse(portText);
                  if (parsed == null || parsed <= 0 || parsed > 65535) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invalid control port. Use 1–65535.')),
                    );
                    return;
                  }
                  controlPort = parsed;
                }

                final currentUser = FirebaseAuth.instance.currentUser;
                String? createdByName;
                if (currentUser != null) {
                  try {
                    final u = await _db.collection('users').doc(currentUser.uid).get();
                    createdByName = (u.data()?['name'] as String?) ?? currentUser.email;
                  } catch (_) {}
                }

                final payload = <String, dynamic>{
                  'branchId': branchId,
                  'tvNumber': tvNumber,
                  'ip': ipController.text.trim(),
                  'model': modelController.text.trim(),
                  'kind': kind.value,
                  'seatIds': selectedSeatIds.value.toList(),
                  'enabled': enabled.value,
                  'updatedAt': FieldValue.serverTimestamp(),
                  if (currentUser != null) 'createdBy': currentUser.uid,
                  if (createdByName != null) 'createdByName': createdByName,

                  // NEW FIELDS (additive)
                  if (normalizedMac != null) 'mac': normalizedMac,
                  if (controlPort != null) 'controlPort': controlPort,
                };
                if (existing == null) {
                  payload['createdAt'] = FieldValue.serverTimestamp();
                }

                try {
                  final ref = _db
                      .collection('branches')
                      .doc(branchId)
                      .collection('tvDevices');
                  if (tvId == null) {
                    await ref.add(payload);
                  } else {
                    await ref.doc(tvId).set(payload, SetOptions(merge: true));
                  }
                  if (mounted) Navigator.of(context).pop();

                  if (normalizedMac == null && kind.value == 'consumer') {
                    // Non-blocking tip
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Saved. Tip: add MAC for Wake-on-LAN Power ON on consumer TVs.'),
                      ),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to save TV device: $e')),
                  );
                }
              },
              child: Text(tvId == null ? 'Add' : 'Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _toggleTvEnabled(String tvId, bool value) async {
    final branchId = _selectedBranchId;
    if (branchId == null) return;
    try {
      await _db
          .collection('branches')
          .doc(branchId)
          .collection('tvDevices')
          .doc(tvId)
          .set(
        {
          'enabled': value,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update TV state: $e')),
      );
    }
  }

  Widget _buildTvMappingCard() {
    final branchId = _selectedBranchId;
    if (branchId == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: Text(
            'Select a branch to configure TV devices and seat mapping.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }

    final seatsRef = _db.collection('branches').doc(branchId).collection('seats');
    final tvDevicesRef =
        _db.collection('branches').doc(branchId).collection('tvDevices');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('TV Devices & Seat Mapping',
                    style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () async {
                    final seatsSnap = await seatsRef.get();
                    final allSeats = seatsSnap.docs;
                    await _showAddOrEditTvDeviceDialog(
                      tvId: null,
                      existing: null,
                      allSeats: allSeats,
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add TV'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Configure per-branch TVs with IP, model, kind and map them to one or more seats. '
              'The TV controller uses this mapping to route commands by seatId.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 360,
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: seatsRef.snapshots(),
                builder: (context, seatsSnap) {
                  if (!seatsSnap.hasData) {
                    return const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  final seatDocs = seatsSnap.data!.docs;

                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: tvDevicesRef.snapshots(),
                    builder: (context, tvSnap) {
                      if (!tvSnap.hasData) {
                        return const Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }

                      final tvDocs = tvSnap.data!.docs;

                      final seatIdToLabel = <String, String>{};
                      for (final seat in seatDocs) {
                        final data = seat.data();
                        seatIdToLabel[seat.id] =
                            (data['label'] ?? seat.id).toString();
                      }

                      final seatIdToTvNumbers = <String, List<String>>{};
                      for (final tv in tvDocs) {
                        final tvData = tv.data();
                        final tvNumber = (tvData['tvNumber'] ?? tv.id).toString();
                        final seatIds = (tvData['seatIds'] as List<dynamic>?)
                                ?.map((e) => e.toString())
                                .toList() ??
                            <String>[];
                        for (final sid in seatIds) {
                          seatIdToTvNumbers.putIfAbsent(sid, () => []);
                          seatIdToTvNumbers[sid]!.add(tvNumber);
                        }
                      }

                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Seats in Branch',
                                    style: Theme.of(context).textTheme.titleSmall),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: seatDocs.isEmpty
                                      ? const Center(
                                          child: Text(
                                            'No seats found for this branch.',
                                            style: TextStyle(color: AppTheme.textMute),
                                          ),
                                        )
                                      : ListView.separated(
                                          itemCount: seatDocs.length,
                                          separatorBuilder: (_, __) =>
                                              const Divider(height: 1, thickness: 0.4),
                                          itemBuilder: (context, index) {
                                            final seatDoc = seatDocs[index];
                                            final seatId = seatDoc.id;
                                            final label = seatIdToLabel[seatId] ?? seatId;
                                            final tvNumbers =
                                                seatIdToTvNumbers[seatId] ?? const [];
                                            final tvDisplay = tvNumbers.isEmpty
                                                ? '—'
                                                : tvNumbers.join(', ');
                                            return ListTile(
                                              dense: true,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(horizontal: 4),
                                              title: Text(
                                                label,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      color: AppTheme.textStrong,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                              ),
                                              subtitle: Text(
                                                'Seat ID: $seatId • TV(s): $tvDisplay',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(color: AppTheme.textMute),
                                              ),
                                              onTap: () {
                                                _seatIdController.text = seatId;
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text('Seat ID copied into control box: $seatId'),
                                                  ),
                                                );
                                              },
                                            );
                                          },
                                        ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('TV Devices',
                                    style: Theme.of(context).textTheme.titleSmall),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: tvDocs.isEmpty
                                      ? const Center(
                                          child: Text(
                                            'No TV devices configured yet. Use "Add TV" to create one.',
                                            style: TextStyle(color: AppTheme.textMute),
                                          ),
                                        )
                                      : ListView.separated(
                                          itemCount: tvDocs.length,
                                          separatorBuilder: (_, __) =>
                                              const Divider(height: 1, thickness: 0.4),
                                          itemBuilder: (context, index) {
                                            final tvDoc = tvDocs[index];
                                            final data = tvDoc.data();
                                            final tvNumber =
                                                (data['tvNumber'] ?? tvDoc.id).toString();
                                            final ip = (data['ip'] ?? '').toString();
                                            final model = (data['model'] ?? '').toString();
                                            final kind =
                                                (data['kind'] ?? 'commercial').toString();
                                            final seatIds =
                                                (data['seatIds'] as List<dynamic>?)
                                                        ?.map((e) => e.toString())
                                                        .toList() ??
                                                    <String>[];
                                            final seatsDisplay = seatIds
                                                .map((sid) => seatIdToLabel[sid] ?? sid)
                                                .join(', ');
                                            final enabled = data['enabled'] == true;

                                            // NEW: show if MAC exists (helps WOL debugging)
                                            final mac = (data['mac'] ?? '').toString().trim();
                                            final macLine = mac.isEmpty ? '' : '\nMAC: $mac';

                                            DateTime? lastSeen;
                                            final lastSeenTs =
                                                data['controllerLastSeen'] as Timestamp?;
                                            final altLastSeenTs = data['lastSeen'] as Timestamp?;
                                            if (lastSeenTs != null) {
                                              lastSeen = lastSeenTs.toDate();
                                            } else if (altLastSeenTs != null) {
                                              lastSeen = altLastSeenTs.toDate();
                                            }

                                            bool controllerOnline = false;
                                            if (lastSeen != null) {
                                              controllerOnline =
                                                  DateTime.now().difference(lastSeen).inSeconds <= 90;
                                            } else if (data['online'] is bool) {
                                              controllerOnline = data['online'] == true;
                                            }

                                            final controllerStatusText = lastSeen == null
                                                ? 'Controller: Unknown'
                                                : 'Controller: ${controllerOnline ? 'Online' : 'Offline'}';

                                            return ListTile(
                                              dense: true,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(horizontal: 4),
                                              leading: CircleAvatar(
                                                radius: 16,
                                                backgroundColor: enabled
                                                    ? AppTheme.primaryBlue.withOpacity(0.25)
                                                    : AppTheme.bg3,
                                                child: Text(
                                                  tvNumber,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppTheme.textStrong,
                                                  ),
                                                ),
                                              ),
                                              title: Text(
                                                '$model (${kind.toUpperCase()})',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      color: AppTheme.textStrong,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                              ),
                                              subtitle: Text(
                                                'IP: ${ip.isEmpty ? '—' : ip}$macLine\n'
                                                'Seats: ${seatsDisplay.isEmpty ? 'None' : seatsDisplay}\n'
                                                '$controllerStatusText',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(color: AppTheme.textMute),
                                              ),
                                              trailing: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Switch(
                                                    value: enabled,
                                                    onChanged: (v) => _toggleTvEnabled(tvDoc.id, v),
                                                  ),
                                                  IconButton(
                                                    tooltip: 'Edit TV',
                                                    icon: const Icon(Icons.edit_outlined, size: 18),
                                                    onPressed: () async {
                                                      final seatsSnap = await seatsRef.get();
                                                      await _showAddOrEditTvDeviceDialog(
                                                        tvId: tvDoc.id,
                                                        existing: data,
                                                        allSeats: seatsSnap.docs,
                                                      );
                                                    },
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------
  // CARD 3 – RECENT COMMANDS (UNCHANGED)
  // ----------------------------
  Widget _buildRecentCommandsCard() {
    final branchId = _selectedBranchId;
    if (branchId == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: Text(
            'Select a branch to see recent TV commands.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }

    final query = FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('tvCommands')
        .orderBy('createdAt', descending: true)
        .limit(20);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recent Commands', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            SizedBox(
              height: 260,
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: query.snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }

                  final docs = snap.data!.docs;
                  if (docs.isEmpty) {
                    return const Center(
                      child: Text('No commands yet.',
                          style: TextStyle(color: AppTheme.textMute)),
                    );
                  }

                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, thickness: 0.4),
                    itemBuilder: (context, index) {
                      final data = docs[index].data();
                      final type = (data['type'] ?? '--').toString();
                      final seatId = (data['seatId'] ?? '').toString();
                      final processed = data['processed'] == true;

                      // NOTE: result is an object in Firestore (result: {status,message,...})
                      // Keep your existing UI behavior, but make it not ugly if it's a Map.
                      final resultRaw = data['result'];
                      String? resultText;
                      if (resultRaw != null) {
                        if (resultRaw is Map) {
                          final status = (resultRaw['status'] ?? '').toString();
                          final msg = (resultRaw['message'] ?? '').toString();
                          resultText = [status, msg].where((s) => s.isNotEmpty).join(': ');
                        } else {
                          resultText = resultRaw.toString();
                        }
                      }

                      final ts = data['createdAt'] as Timestamp?;
                      final dt = ts?.toDate();
                      final subtitle = <String>[
                        if (seatId.isNotEmpty) 'Seat: $seatId',
                        if (processed) 'Processed' else 'Pending',
                        if (resultText != null && resultText.isNotEmpty) 'Result: $resultText',
                        if (dt != null) dt.toLocal().toString(),
                      ].where((e) => e.isNotEmpty).join(' • ');

                      return ListTile(
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                        leading: Icon(
                          Icons.tv_outlined,
                          color: processed ? AppTheme.lightCyan : AppTheme.textMute,
                          size: 20,
                        ),
                        title: Text(
                          type,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: AppTheme.textStrong,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        subtitle: Text(
                          subtitle,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppTheme.textMute),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------
  // BUILD
  // ----------------------------
  @override
  Widget build(BuildContext context) {
    return AppShell(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 1200;
              if (isWide) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                _buildControlsCard(),
                                const SizedBox(height: 20),
                                _buildToastCard(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(child: _buildTvMappingCard()),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _buildRecentCommandsCard(),
                    ],
                  ),
                );
              } else {
                return ListView(
                  children: [
                    _buildControlsCard(),
                    const SizedBox(height: 20),
                    _buildToastCard(),
                    const SizedBox(height: 20),
                    _buildTvMappingCard(),
                    const SizedBox(height: 20),
                    _buildRecentCommandsCard(),
                  ],
                );
              }
            },
          ),
        ),
      ),
    );
  }
}
