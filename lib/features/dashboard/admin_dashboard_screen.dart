// FULL FILE: lib/features/dashboard/admin_dashboard_screen.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/app_shell.dart';
import 'layout/dashboard_layout.dart';
import 'sections/stats_section.dart';
import 'sections/quick_actions_section.dart';
import 'sections/console_map_section.dart';
import 'sections/timeline_section.dart';
import 'sections/active_overdue_section.dart';
import 'sections/upcoming_section.dart';
import 'sections/cashbook_section.dart';

// ───────────────────────── Time helpers ─────────────────────────
class _DayRangeUtc {
  final Timestamp startUtc;
  final Timestamp endUtc;
  const _DayRangeUtc(this.startUtc, this.endUtc);
}

_DayRangeUtc _todayIstToUtc() {
  final nowLocal = DateTime.now();
  final startLocal = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
  final endLocal = startLocal.add(const Duration(days: 1));
  return _DayRangeUtc(
    Timestamp.fromDate(startLocal.toUtc()),
    Timestamp.fromDate(endLocal.toUtc()),
  );
}

DateTime? _endFrom(Map<String, dynamic> m) {
  final ts = (m['startTime'] as Timestamp?)?.toDate();
  final dur = (m['durationMinutes'] as num?)?.toInt() ?? 60;
  if (ts == null) return null;
  return ts.add(Duration(minutes: dur));
}

bool _isActiveNow(Map<String, dynamic> m, DateTime now) {
  final status = ((m['status'] as String?) ?? '').toLowerCase();
  if (status == 'cancelled' || status == 'completed') return false;
  final start = (m['startTime'] as Timestamp?)?.toDate();
  final end = _endFrom(m);
  if (start == null || end == null) return false;
  return start.isBefore(now) && end.isAfter(now);
}

// ───────────────────────── Dashboard Screen ─────────────────────────

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  String? _selectedBranchId;  bool _hasInitializedBranch = false;
  // “ending soon” watcher state
  final Set<String> _endingSoonAlerted = <String>{};
  bool _endingSoonDialogOpen = false;
  StreamSubscription<QuerySnapshot>? _endingSoonSub;

  // Typed key for UpcomingSection state so we can call refresh()
  final GlobalKey<UpcomingSectionState> _upcomingKey =
      GlobalKey<UpcomingSectionState>();

  @override
  void dispose() {
    _endingSoonSub?.cancel();
    super.dispose();
  }

  void _attachEndingSoonWatcher({required String branchId}) {
    _endingSoonSub?.cancel();

    final col = FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('sessions');

    _endingSoonSub = col.snapshots().listen((snap) async {
      if (!mounted) return;
      final now = DateTime.now();
      for (final d in snap.docs) {
        final m = d.data() as Map<String, dynamic>? ?? {};
        final status = (m['status'] ?? '').toString().toLowerCase();
        if (status != 'active') continue;

        final start = (m['startTime'] as Timestamp?)?.toDate();
        final dur = (m['durationMinutes'] as num?)?.toInt() ?? 0;
        if (start == null) continue;
        final endAt = start.add(Duration(minutes: dur));
        final timeLeft = endAt.difference(now);

        if (timeLeft.inMilliseconds <= 0) continue; // already overdue
        if (endAt.isAfter(now) &&
            !endAt.isAfter(now.add(const Duration(minutes: 10)))) {
          if (_endingSoonAlerted.contains(d.id) || _endingSoonDialogOpen) {
            continue;
          }
          _endingSoonAlerted.add(d.id);
          _endingSoonDialogOpen = true;

          // ignore: use_build_context_synchronously
          await showDialog(
            context: context,
            barrierDismissible: true,
            builder: (_) => AlertDialog(
              backgroundColor: const Color(0xFF111827),
              title: const Text('Session ending soon',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
              content: Text(
                '${m['customerName'] ?? 'Walk-in'} • ${m['seatLabel'] ?? 'Seat'}\nEnds in ~${timeLeft.inMinutes}:${(timeLeft.inSeconds % 60).toString().padLeft(2, '0')}',
                style: const TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK',
                      style: TextStyle(color: Colors.white70)),
                ),
              ],
            ),
          );

          _endingSoonDialogOpen = false;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return AppShell(
      child: user == null
          ? const Center(
              child: Text('Not logged in', style: TextStyle(color: Colors.white)),
            )
          : StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, userSnap) {
                if (userSnap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: Colors.white));
                }

                final userData =
                    userSnap.data?.data() as Map<String, dynamic>? ?? {};
                final role = (userData['role'] ?? 'staff').toString();
                final List<dynamic> branchIdsDyn =
                    (userData['branchIds'] as List<dynamic>?) ?? [];
                final allowedBranchIds =
                    branchIdsDyn.map((e) => e.toString()).toList();

                final branchesRef =
                    FirebaseFirestore.instance.collection('branches');

                return StreamBuilder<QuerySnapshot>(
                  stream: branchesRef.snapshots(),
                  builder: (context, branchSnap) {
                    if (branchSnap.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator(color: Colors.white));
                    }
                    if (!branchSnap.hasData ||
                        branchSnap.data!.docs.isEmpty) {
                      return const Center(
                        child: Text('No branches configured yet.',
                            style: TextStyle(color: Colors.white70)),
                      );
                    }

                    final allBranches = branchSnap.data!.docs;
                    final visibleBranches =
                        (role == 'superadmin' || allowedBranchIds.isEmpty)
                            ? allBranches
                            : allBranches
                                .where((b) => allowedBranchIds.contains(b.id))
                                .toList();

                    if (visibleBranches.isEmpty) {
                      return const Center(
                        child: Text('No branches assigned to your account.',
                            style: TextStyle(color: Colors.white70)),
                      );
                    }

                    if (!_hasInitializedBranch && userSnap.hasData) {
                      _hasInitializedBranch = true;
                      
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        
                        final lastSelectedBranchId = userData['lastSelectedBranchId'] as String?;
                        String? initialBranch;
                        
                        print('🟡 Initializing branch selection...');
                        print('   Last selected from Firestore: $lastSelectedBranchId');
                        print('   Available branches: ${visibleBranches.map((b) => b.id).toList()}');
                        
                        if (lastSelectedBranchId != null &&
                            visibleBranches.any((b) => b.id == lastSelectedBranchId)) {
                          initialBranch = lastSelectedBranchId;
                          print('   ✅ Using persisted branch: $initialBranch');
                        } else {
                          initialBranch = visibleBranches.first.id;
                          print('   ⚠️  No valid persisted branch, using first: $initialBranch');
                        }
                        
                        setState(() {
                          _selectedBranchId = initialBranch;
                        });
                        
                        if (_selectedBranchId != null) {
                          _attachEndingSoonWatcher(branchId: _selectedBranchId!);
                        }
                      });
                    }

                    String effectiveBranchId =
                        _selectedBranchId ?? visibleBranches.first.id;

                    if (_selectedBranchId != null && 
                        !visibleBranches.any((b) => b.id == _selectedBranchId)) {
                      effectiveBranchId = visibleBranches.first.id;
                    }

                    final selectedBranchDoc = visibleBranches
                        .firstWhere((b) => b.id == effectiveBranchId);
                    final selectedBranchName =
                        (selectedBranchDoc.data()
                                    as Map<String, dynamic>?)?['name']
                                ?.toString() ??
                            effectiveBranchId;

                    return DashboardLayout(
                      userId: user.uid,
                      userName: (userData['name'] ?? 'Admin').toString(),
                      role: role,
                      selectedBranchId: effectiveBranchId,
                      selectedBranchName: selectedBranchName,
                      visibleBranches: visibleBranches
                          .map((b) => (
                                id: b.id,
                                name: ((b.data()
                                                as Map<String, dynamic>? ??
                                            {})['name'] ??
                                        b.id)
                                    .toString()
                              ))
                          .toList(),
                      onChangeBranch: (v) async {
                        // Persist the selection to Firestore FIRST
                        try {
                          final branchDoc = visibleBranches.firstWhere((b) => b.id == v);
                          final branchName = (branchDoc.data() as Map<String, dynamic>?)?['name']?.toString() ?? v;
                          
                          print('🔵 Saving branch selection: $branchName ($v)');
                          
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(user.uid)
                              .set({
                            'lastSelectedBranchId': v,
                            'lastSelectedBranchName': branchName,
                          }, SetOptions(merge: true));
                          
                          print('✅ Branch selection saved successfully');
                        } catch (e) {
                          print('❌ Failed to save branch selection: $e');
                        }
                        
                        setState(() {
                          _selectedBranchId = v;
                          _endingSoonAlerted.clear(); // per-branch
                        });
                        _attachEndingSoonWatcher(branchId: v);
                        _upcomingKey.currentState?.refresh(); // << refresh section
                      },
                      sections: [
                        StatsSection(
                          selectedBranchId: effectiveBranchId,
                          todayRangeUtc: _todayIstToUtc(),
                          // ✅ Bug 1: Revenue tiles hidden for everyone by default
                          showRevenue: false,
                        ),

                        // ✅ Bug 2: Staff POS cashbook
                        if (role == 'staff')
                          CashBookSection(
                            branchId: effectiveBranchId,
                            branchName: selectedBranchName,
                            staffUserId: user.uid,
                            staffName: (userData['name'] ?? 'Staff').toString(),
                          ),

                        QuickActionsSection(
                          role: role,
                          allowedBranchIds: allowedBranchIds,
                          selectedBranchId: effectiveBranchId,
                        ),
                        ConsoleMapSection(branchId: effectiveBranchId),
                        TimelineSection(branchId: effectiveBranchId),
                        ActiveOverdueSection(branchId: effectiveBranchId),
                        UpcomingSection(
                          key: _upcomingKey,
                          branchId: effectiveBranchId,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
    );
  }
}
