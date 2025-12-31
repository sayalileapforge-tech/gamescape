// FULL FILE: lib/features/tv_control/tv_devices_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_shell.dart';
import '../../data/repositories/tv_control_repo.dart';

class TvDevicesScreen extends StatefulWidget {
  const TvDevicesScreen({super.key});

  @override
  State<TvDevicesScreen> createState() => _TvDevicesScreenState();
}

class _TvDevicesScreenState extends State<TvDevicesScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? _selectedBranchId;
  String? _selectedBranchName;

  // ----------------------------
  // BRANCH DROPDOWN (same behavior as TvControlScreen)
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
                });
              },
            );
          },
        );
      },
    );
  }

  // ----------------------------
  // PAIRING DIALOG (consumer TVs)
  // ----------------------------
  Future<void> _showPairingDialog({
    required String branchId,
    required String tvId,
    required Map<String, dynamic> tvData,
  }) async {
    final TextEditingController codeCtrl = TextEditingController();
    final tvPairingRef =
        _db.collection('branches').doc(branchId).collection('tvPairing').doc(tvId);

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Pair Consumer WebOS TV'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
            child: SingleChildScrollView(
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: tvPairingRef.snapshots(),
                builder: (context, snap) {
                  final pairing = snap.data?.data();
                  final status = (pairing?['status'] ?? 'not_started').toString();
                  final lastError = pairing?['lastError']?.toString();
                  final expiresAtTs = pairing?['expiresAt'] as Timestamp?;
                  final expiresAt = expiresAtTs?.toDate();

                  final clientKey = (tvData['clientKey'] ?? '').toString();
                  final alreadyPaired = clientKey.isNotEmpty;

                  String statusLine;
                  if (alreadyPaired) {
                    statusLine = 'Status: Paired (clientKey stored)';
                  } else if (status == 'waiting_code') {
                    statusLine = 'Status: Waiting for pairing PIN';
                  } else if (status == 'code_submitted') {
                    statusLine = 'Status: PIN submitted — controller pairing...';
                  } else if (status == 'paired') {
                    statusLine = 'Status: Paired';
                  } else if (status == 'failed') {
                    statusLine = 'Status: Failed';
                  } else {
                    statusLine = 'Status: Not started';
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'This is for CONSUMER LG WebOS TVs. Pairing is required only once to get a clientKey.\n'
                        '1) On TV: Open IP Control / Pairing and note the PIN.\n'
                        '2) Here: Start pairing, enter PIN, submit.\n'
                        '3) Controller will store clientKey on tvDevices doc.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppTheme.textMute),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        statusLine,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.textStrong,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      if (expiresAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Expires: ${expiresAt.toLocal()}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppTheme.textMute),
                        ),
                      ],
                      if (lastError != null && lastError.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Last error: $lastError',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.redAccent.shade200),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                await TvControlRepo.I.startPairing(
                                  branchId: branchId,
                                  tvId: tvId,
                                  forceRePair: alreadyPaired,
                                );
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Pairing request created. Enter PIN and submit.'),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.link),
                              label: Text(alreadyPaired ? 'Re-Pair' : 'Start Pairing'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: codeCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Pairing PIN Code',
                          hintText: 'Enter the PIN shown on TV',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final code = codeCtrl.text.trim();
                            if (code.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Enter pairing PIN code')),
                              );
                              return;
                            }
                            await TvControlRepo.I.submitPairingCode(
                              branchId: branchId,
                              tvId: tvId,
                              pairingCode: code,
                            );
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('PIN submitted. Controller will complete pairing.')),
                              );
                            }
                          },
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('Submit PIN'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tip: If pairing fails, press Re-Pair and submit PIN again.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppTheme.textMute),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // ----------------------------
  // DEVICES TABLE
  // ----------------------------
  Widget _buildDevicesContent() {
    final branchId = _selectedBranchId;
    if (branchId == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: Text(
            'Select a branch to view TV devices.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }

    final tvDevicesRef =
        _db.collection('branches').doc(branchId).collection('tvDevices');
    final seatsRef =
        _db.collection('branches').doc(branchId).collection('seats');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'TV Devices (${_selectedBranchName ?? ''})',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'View all configured TVs for this branch, including IP, model, kind and mapped seats. '
              'Status and last seen timestamps help operators quickly debug TV connectivity issues.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Expanded(
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
                  final seatIdToLabel = <String, String>{};
                  for (final seat in seatDocs) {
                    final data = seat.data();
                    seatIdToLabel[seat.id] =
                        (data['label'] ?? seat.id).toString();
                  }

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
                      if (tvDocs.isEmpty) {
                        return const Center(
                          child: Text(
                            'No TV devices configured yet for this branch.',
                            style: TextStyle(color: AppTheme.textMute),
                          ),
                        );
                      }

                      return ListView.separated(
                        itemCount: tvDocs.length,
                        separatorBuilder: (_, __) => const Divider(
                          height: 1,
                          thickness: 0.4,
                        ),
                        itemBuilder: (context, index) {
                          final tvDoc = tvDocs[index];
                          final data = tvDoc.data();
                          final tvNumber =
                              (data['tvNumber'] ?? tvDoc.id).toString();
                          final ip = (data['ip'] ?? '').toString();
                          final model = (data['model'] ?? '').toString();
                          final kind =
                              (data['kind'] ?? 'commercial').toString();
                          final controlMode =
                              (data['controlMode'] ?? '').toString();
                          final enabled = data['enabled'] == true;

                          final seatIds =
                              (data['seatIds'] as List<dynamic>?)
                                      ?.map((e) => e.toString())
                                      .toList() ??
                                  <String>[];
                          final seatsDisplay = seatIds
                              .map((sid) => seatIdToLabel[sid] ?? sid)
                              .join(', ');

                          // NEW: MAC display for WOL readiness
                          final mac = (data['mac'] ?? '').toString().trim();
                          final macLine = mac.isEmpty ? '' : ' • MAC: $mac';

                          // Consumer pairing status (optional)
                          final clientKey = (data['clientKey'] ?? '').toString();
                          final isConsumer = kind == 'consumer';
                          final isPaired = isConsumer && clientKey.isNotEmpty;

                          // Prefer controllerLastSeen; fallback to lastSeen/online
                          DateTime? lastSeen;
                          final lastSeenTs =
                              data['controllerLastSeen'] as Timestamp?;
                          final altLastSeenTs =
                              data['lastSeen'] as Timestamp?;
                          if (lastSeenTs != null) {
                            lastSeen = lastSeenTs.toDate();
                          } else if (altLastSeenTs != null) {
                            lastSeen = altLastSeenTs.toDate();
                          }

                          final bool online = (lastSeen != null)
                              ? DateTime.now().difference(lastSeen).inSeconds <= 90
                              : (data['online'] == true);

                          Color statusColor;
                          String statusLabel;
                          if (online) {
                            statusColor = Colors.greenAccent.shade400;
                            statusLabel = 'Online';
                          } else if (lastSeen != null) {
                            statusColor = Colors.redAccent.shade200;
                            statusLabel = 'Offline';
                          } else {
                            statusColor = AppTheme.textMute;
                            statusLabel = 'Unknown';
                          }

                          final showMacWarning = isConsumer && mac.isEmpty;

                          return ListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor:
                                  enabled ? AppTheme.bg2 : AppTheme.bg3,
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
                              model.isNotEmpty
                                  ? '$model (${kind.toUpperCase()})'
                                  : '${kind.toUpperCase()} TV',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: AppTheme.textStrong,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'IP: ${ip.isEmpty ? "—" : ip}'
                                  '${controlMode.isNotEmpty ? ' • Mode: $controlMode' : ''}'
                                  '$macLine',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: AppTheme.textMute),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Seats: ${seatsDisplay.isEmpty ? 'None' : seatsDisplay}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: AppTheme.textMute),
                                ),
                                if (isConsumer) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Pairing: ${isPaired ? 'Paired' : 'Not paired'}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: isPaired
                                              ? Colors.greenAccent.shade100
                                              : Colors.orangeAccent.shade100,
                                        ),
                                  ),
                                ],
                                if (showMacWarning) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'WOL: MAC missing (Power ON won’t work reliably)',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: Colors.orangeAccent.shade100),
                                  ),
                                ],
                                if (lastSeen != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Last seen: ${lastSeen.toLocal()}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: AppTheme.textMute),
                                  ),
                                ],
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(right: 4),
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Text(
                                  statusLabel,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: statusColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                if (isConsumer) ...[
                                  const SizedBox(width: 10),
                                  IconButton(
                                    tooltip: 'Pair Consumer TV',
                                    icon: const Icon(Icons.link, size: 18),
                                    onPressed: () => _showPairingDialog(
                                      branchId: branchId,
                                      tvId: tvDoc.id,
                                      tvData: data,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
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
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(children: [Expanded(child: _buildBranchDropdown())]),
                const SizedBox(height: 16),
                Expanded(child: _buildDevicesContent()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
