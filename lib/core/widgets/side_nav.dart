import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import 'side_nav_controller.dart';

class SideNav extends StatefulWidget {
  final String role;
  final List<String>? navOrderKeys;

  const SideNav({
    super.key,
    required this.role,
    this.navOrderKeys,
  });

  @override
  State<SideNav> createState() => _SideNavState();
}

class _SideNavState extends State<SideNav> {
  late List<_NavItemSpec> _baseItems;
  late List<_NavItemSpec> _ordered;

  bool get _isAdminLike =>
      widget.role == 'admin' ||
      widget.role == 'manager' ||
      widget.role == 'superadmin';
  bool get _canSeeUsers =>
      widget.role == 'admin' || widget.role == 'superadmin';
  bool get _canSeeReports =>
      widget.role == 'admin' || widget.role == 'superadmin';

  @override
  void initState() {
    super.initState();
    _baseItems = _allItems();
    _ordered = _applyOrderAndRole(_baseItems, widget.navOrderKeys);
  }

  @override
  void didUpdateWidget(covariant SideNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.role != widget.role ||
        oldWidget.navOrderKeys != widget.navOrderKeys) {
      _baseItems = _allItems();
      _ordered = _applyOrderAndRole(_baseItems, widget.navOrderKeys);
      setState(() {});
    }
  }

  List<_NavItemSpec> _applyOrderAndRole(
      List<_NavItemSpec> all, List<String>? orderKeys) {
    final filtered = all.where((it) {
      if (it.key == 'branches' && !_isAdminLike) return false;
      if (it.key == 'inventory' && !_isAdminLike) return false;
      if (it.key == 'inventory-unified' && !_isAdminLike) return false;
      if (it.key == 'users' && !_canSeeUsers) return false;
      if (it.key == 'reports' && !_canSeeReports) return false;
      if (it.key == 'tv-control' && !_isAdminLike) return false; // ✅ TV control only for admin-like
      if (it.key == 'tv-devices' && !_isAdminLike) return false; // ✅ TV devices only for admin-like
      return true;
    }).toList();

    if (orderKeys == null || orderKeys.isEmpty) return filtered;

    final keyToIndex = <String, int>{};
    for (var i = 0; i < orderKeys.length; i++) {
      keyToIndex[orderKeys[i]] = i;
    }
    filtered.sort((a, b) {
      final ai = keyToIndex[a.key];
      final bi = keyToIndex[b.key];
      if (ai == null && bi == null) return 0;
      if (ai == null) return 1;
      if (bi == null) return -1;
      return ai.compareTo(bi);
    });
    return filtered;
  }

  List<_NavItemSpec> _allItems() => <_NavItemSpec>[
        _NavItemSpec(
            'dashboard', Icons.dashboard_outlined, 'Dashboard', '/dashboard'),
        _NavItemSpec(
            'branches', Icons.home_work_outlined, 'Branches', '/branches'),
        _NavItemSpec(
            'bookings', Icons.chair_outlined, 'Bookings', '/bookings'),
        _NavItemSpec('live-sessions', Icons.live_tv_outlined, 'Live Sessions',
            '/live-sessions'),
        _NavItemSpec(
            'customers', Icons.person_outline, 'Customers', '/customers'),
        // ✅ TV Control – placed near sessions / infra-related items
        _NavItemSpec(
            'tv-control', Icons.tv_outlined, 'TV Control', '/tv-control'),
        // ✅ TV Devices – dedicated device manager screen
        _NavItemSpec('tv-devices', Icons.developer_board_outlined,
            'TV Devices', '/tv-devices'),
        _NavItemSpec('inventory-unified', Icons.inventory_outlined,
            'Inventory (Unified)', '/inventory-unified'),
        _NavItemSpec(
            'users', Icons.group_outlined, 'Users', '/users'),
        _NavItemSpec('reports', Icons.receipt_long_outlined, 'Reports',
            '/reports'),
        _NavItemSpec('invoices', Icons.picture_as_pdf_outlined, 'Invoices',
            '/invoices'),
      ];

  bool _isActive(String location, String path) {
    if (location == path) return true;
    if (location.startsWith('$path/')) return true;
    return false;
  }

  Future<void> _saveOrderToUser(List<_NavItemSpec> items) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final keys = items.map((e) => e.key).toList();
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'prefs': {'navOrder': keys}
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: sideNavController,
      builder: (context, _) {
        final width = sideNavController.isExpanded ? 220.0 : 74.0;
        final location = GoRouterState.of(context).uri.toString();

        return AnimatedContainer(
          width: width,
          duration: const Duration(milliseconds: 200),
          color: AppTheme.bg0,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  mainAxisAlignment: sideNavController.isExpanded
                      ? MainAxisAlignment.spaceBetween
                      : MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: sideNavController.isExpanded
                          ? 'Collapse'
                          : 'Expand',
                      onPressed: sideNavController.toggle,
                      icon: Icon(
                        sideNavController.isExpanded
                            ? Icons.arrow_back_ios_new_rounded
                            : Icons.arrow_forward_ios_rounded,
                        color: AppTheme.textStrong,
                        size: 18,
                      ),
                    ),
                    if (sideNavController.isExpanded)
                      IconButton(
                        tooltip: sideNavController.isReorderMode
                            ? 'Done'
                            : 'Reorder menu',
                        onPressed: () =>
                            setState(sideNavController.toggleReorder),
                        icon: Icon(
                          sideNavController.isReorderMode
                              ? Icons.check_rounded
                              : Icons.edit_outlined,
                          color: AppTheme.textStrong,
                          size: 18,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Brand tile (was white; now themed)
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.bg2,
                  border: Border.all(color: AppTheme.outlineSoft),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  'G',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppTheme.textStrong,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const SizedBox(height: 16),

              if (sideNavController.isExpanded &&
                  sideNavController.isReorderMode)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0),
                  child: Row(
                    children: [
                      const Icon(Icons.drag_indicator,
                          color: AppTheme.textMute, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Drag to rearrange. Your order is saved.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppTheme.textMute),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 6),

              Expanded(
                child: sideNavController.isReorderMode
                    ? ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _ordered.length,
                        onReorder: (oldIndex, newIndex) async {
                          setState(() {
                            if (newIndex > oldIndex) newIndex -= 1;
                            final item = _ordered.removeAt(oldIndex);
                            _ordered.insert(newIndex, item);
                          });
                          await _saveOrderToUser(_ordered);
                        },
                        itemBuilder: (context, i) {
                          final it = _ordered[i];
                          final selected = _isActive(location, it.route);
                          return ReorderableDragStartListener(
                            key: ValueKey(it.key),
                            index: i,
                            child: _NavTile(
                              icon: it.icon,
                              label: it.label,
                              expanded: sideNavController.isExpanded,
                              selected: selected,
                              onTap: () {
                                if (!selected) context.go(it.route);
                              },
                              showDragHandle: true,
                            ),
                          );
                        },
                      )
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: sideNavController.isExpanded
                              ? CrossAxisAlignment.start
                              : CrossAxisAlignment.center,
                          children: _ordered.map((it) {
                            final selected = _isActive(location, it.route);
                            return _NavTile(
                              key: ValueKey(it.key),
                              icon: it.icon,
                              label: it.label,
                              expanded: sideNavController.isExpanded,
                              selected: selected,
                              onTap: () {
                                if (!selected) context.go(it.route);
                              },
                            );
                          }).toList(),
                        ),
                      ),
              ),

              _NavTile(
                icon: Icons.logout,
                label: 'Logout',
                expanded: sideNavController.isExpanded,
                selected: false,
                onTap: () async {
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) context.go('/login');
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}

class _NavTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool expanded;
  final bool selected;
  final bool showDragHandle;

  const _NavTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.expanded,
    required this.selected,
    this.showDragHandle = false,
  });

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.selected
        ? AppTheme.primaryBlue.withOpacity(.18)
        : (_hover ? AppTheme.bg1 : Colors.transparent);
    final borderColor =
        widget.selected ? AppTheme.outlineHard : AppTheme.outlineSoft;
    final iconColor = AppTheme.textStrong;
    final textColor = AppTheme.textStrong;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          padding: EdgeInsets.symmetric(
            vertical: 10,
            horizontal: widget.expanded ? 10 : 0,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisAlignment: widget.expanded
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              if (widget.showDragHandle && widget.expanded) ...[
                const Icon(Icons.drag_indicator,
                    color: AppTheme.textMute, size: 18),
                const SizedBox(width: 6),
              ],
              Icon(widget.icon, color: iconColor),
              if (widget.expanded) const SizedBox(width: 10),
              if (widget.expanded)
                Expanded(
                  child: Text(
                    widget.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItemSpec {
  final String key;
  final IconData icon;
  final String label;
  final String route;
  _NavItemSpec(this.key, this.icon, this.label, this.route);
}
