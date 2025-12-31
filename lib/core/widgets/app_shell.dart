import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'side_nav.dart';

// NOTE: path is from core/widgets → features/dashboard
import '../../features/dashboard/notification_panel_v2.dart';

class AppShell extends StatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _showNotifications = false;

  void _toggleNotifications() {
    setState(() => _showNotifications = !_showNotifications);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    // not logged in – router will usually push /login
    if (currentUser == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(child: widget.child),
      );
    }

    // Stream user doc so we can derive role + allowed branches + lastSelectedBranch
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .snapshots(),
      builder: (context, snap) {
        // defaults while loading
        String role = 'superadmin';
        List<String>? navOrderKeys;
        String? lastSelectedBranchId;
        String? lastSelectedBranchName;
        List<String> allowedBranchIds = const [];

        if (snap.hasData && snap.data!.data() != null) {
          final data = snap.data!.data() as Map<String, dynamic>;
          role = (data['role'] ?? 'superadmin').toString();

          final prefs = (data['prefs'] as Map?) ?? {};
          final dyn = (prefs['navOrder'] as List?) ?? [];
          navOrderKeys = dyn.map((e) => e.toString()).toList();

          // Optional persisted selection (if your dashboard stores it)
          lastSelectedBranchId = data['lastSelectedBranchId'] as String?;
          lastSelectedBranchName = data['lastSelectedBranchName'] as String?;

          final bidDyn = (data['branchIds'] as List<dynamic>?) ?? [];
          allowedBranchIds = bidDyn.map((e) => e.toString()).toList();
        }

        return Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          body: Stack(
            children: [
              Row(
                children: [
                  // pass role + per-user order keys
                  SideNav(role: role, navOrderKeys: navOrderKeys),
                  Expanded(
                    child: Column(
                      children: [
                        // top bar
                        Container(
                          height: 60,
                          color: const Color(0xFF111827),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'GameScape Admin',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                              ),
                              Row(
                                children: [
                                  // Bell icon with tiny badge
                                  InkWell(
                                    onTap: _toggleNotifications,
                                    borderRadius: BorderRadius.circular(999),
                                    child: Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          const Icon(Icons.notifications_none,
                                              color: Colors.white70, size: 22),
                                          if (!_showNotifications)
                                            Positioned(
                                              right: -1,
                                              top: -1,
                                              child: Container(
                                                height: 10,
                                                width: 10,
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF22C55E),
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                  border: Border.all(
                                                    color: const Color(0xFF111827),
                                                    width: 2,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Avatar only (name removed per request)
                                  const CircleAvatar(
                                    radius: 18,
                                    backgroundColor: AppTheme.primaryBlue,
                                    child:
                                        Icon(Icons.person, color: Colors.white),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // page content
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: widget.child,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Right overlay notification panel
              if (_showNotifications)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: _toggleNotifications, // close when tapping scrim
                    child: Container(
                      color: Colors.black.withOpacity(0.35),
                    ),
                  ),
                ),

              if (_showNotifications)
                Positioned(
                  top: 70,
                  right: 20,
                  bottom: 20,
                  child: SizedBox(
                    width: 380,
                    child: Material(
                      color: Colors.transparent,
                      // Build the panel *inside* here so the Stack child is stable
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('branches')
                            .snapshots(),
                        builder: (context, branchSnap) {
                          String effectiveBranchId = '';
                          String effectiveBranchName = '';

                          if (branchSnap.hasData &&
                              branchSnap.data!.docs.isNotEmpty) {
                            final allBranches = branchSnap.data!.docs;

                            // Filter by role/allowed list
                            final visibleBranches = (role == 'superadmin' ||
                                    allowedBranchIds.isEmpty)
                                ? allBranches
                                : allBranches
                                    .where((b) =>
                                        allowedBranchIds.contains(b.id))
                                    .toList();

                            if (visibleBranches.isNotEmpty) {
                              // 1) if user has a persisted selection and it's visible, use it
                              if (lastSelectedBranchId != null &&
                                  visibleBranches.any((b) =>
                                      b.id == lastSelectedBranchId)) {
                                effectiveBranchId = lastSelectedBranchId!;
                                final sel = visibleBranches.firstWhere(
                                    (b) => b.id == lastSelectedBranchId);
                                effectiveBranchName = lastSelectedBranchName ??
                                    (((sel.data()
                                                    as Map<String, dynamic>?)?[
                                                'name']) ??
                                            sel.id)
                                        .toString();
                              } else {
                                // 2) else fall back to the first visible branch
                                final first = visibleBranches.first;
                                effectiveBranchId = first.id;
                                effectiveBranchName =
                                    ((first.data() as Map<String, dynamic>?)?[
                                                'name'] ??
                                            first.id)
                                        .toString();
                              }
                            }
                          }

                          return NotificationPanelV2(
                            userId: currentUser.uid,
                            branchId:
                                effectiveBranchId, // populated when branches exist
                            branchName: effectiveBranchName,
                          );
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
