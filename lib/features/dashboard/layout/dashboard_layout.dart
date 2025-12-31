import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/dashboard_prefs.dart';

/// Base contract every section already implements.
abstract class DashboardSectionWidget {
  String get persistentKey;
  String get title;
}

/// Optional contract for sections that want a header action (e.g., Refresh).
abstract class DashboardHeaderAction {
  Widget? buildHeaderAction(BuildContext context);
}

/// Extension so callers can always ask for an action without type errors.
/// If the section doesn't implement DashboardHeaderAction, this returns null.
extension DashboardSectionHeaderActionExt on DashboardSectionWidget {
  Widget? headerAction(BuildContext context) {
    if (this is DashboardHeaderAction) {
      return (this as DashboardHeaderAction).buildHeaderAction(context);
    }
    return null;
  }
}

class DashboardLayout extends StatefulWidget {
  final String userId;
  final String userName;
  final String role;

  final String selectedBranchId;
  final String selectedBranchName;

  final List<({String id, String name})> visibleBranches;
  final ValueChanged<String> onChangeBranch;
  final List<DashboardSectionWidget> sections;

  const DashboardLayout({
    super.key,
    required this.userId,
    required this.userName,
    required this.role,
    required this.selectedBranchId,
    required this.selectedBranchName,
    required this.visibleBranches,
    required this.onChangeBranch,
    required this.sections,
  });

  @override
  State<DashboardLayout> createState() => _DashboardLayoutState();
}

class _DashboardLayoutState extends State<DashboardLayout> {
  late final DashboardPrefsService _prefs;
  late List<DashboardSectionWidget> _ordered;
  bool _loadingOrder = true;

  @override
  void initState() {
    super.initState();
    _prefs = DashboardPrefsService(widget.userId);
    _ordered = List.of(widget.sections);
    _restoreOrder();
  }

  Future<void> _restoreOrder() async {
    try {
      final saved = await _prefs.loadOrder();
      if (saved != null && saved.isNotEmpty) {
        final map = {for (final s in widget.sections) s.persistentKey: s};
        final restored = <DashboardSectionWidget>[];
        for (final key in saved) {
          final sec = map[key];
          if (sec != null) restored.add(sec);
        }
        for (final s in widget.sections) {
          if (!restored.any((e) => e.persistentKey == s.persistentKey)) {
            restored.add(s);
          }
        }
        setState(() => _ordered = restored);
      }
    } finally {
      if (mounted) setState(() => _loadingOrder = false);
    }
  }

  Future<void> _persistOrder() async {
    await _prefs.saveOrder(_ordered.map((e) => e.persistentKey).toList());
  }

  @override
  void didUpdateWidget(covariant DashboardLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = widget.sections;
    if (incoming.length != oldWidget.sections.length ||
        !_sameKeys(incoming, oldWidget.sections)) {
      final map = {for (final s in incoming) s.persistentKey: s};
      final next = <DashboardSectionWidget>[];
      for (final s in _ordered) {
        final rep = map[s.persistentKey];
        if (rep != null) next.add(rep);
      }
      for (final s in incoming) {
        if (!next.any((e) => e.persistentKey == s.persistentKey)) {
          next.add(s);
        }
      }
      setState(() => _ordered = next);
    }
  }

  bool _sameKeys(List<DashboardSectionWidget> a, List<DashboardSectionWidget> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].persistentKey != b[i].persistentKey) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(right: 16, bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hello, ${widget.userName} 👋',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Branch:',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: DropdownButton<String>(
                  value: widget.selectedBranchId,
                  dropdownColor: const Color(0xFF111827),
                  underline: const SizedBox.shrink(),
                  style: const TextStyle(color: Colors.white),
                  items: widget.visibleBranches
                      .map((b) => DropdownMenuItem(value: b.id, child: Text(b.name)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    widget.onChangeBranch(v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          if (_loadingOrder)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            )
          else
            _buildReorderable(),
        ],
      ),
    );
  }

  Widget _buildReorderable() {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _ordered.length,
      onReorder: (oldIndex, newIndex) async {
        if (newIndex > oldIndex) newIndex -= 1;
        setState(() {
          final item = _ordered.removeAt(oldIndex);
          _ordered.insert(newIndex, item);
        });
        await _persistOrder();
      },
      proxyDecorator: (child, index, animation) {
        return Material(
          color: Colors.transparent,
          child: Transform.scale(scale: 1.01, child: Opacity(opacity: 0.98, child: child)),
        );
      },
      itemBuilder: (context, index) {
        final section = _ordered[index];

        // Use the extension to fetch an optional header action safely.
        final trailing = section.headerAction(context);

        return Padding(
          key: ValueKey(section.persistentKey),
          padding: const EdgeInsets.only(bottom: 24),
          child: _SectionCard(
            index: index,
            title: section.title,
            trailing: trailing,
            child: section as Widget,
          ),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  final int index;
  final String title;
  final Widget? trailing;
  final Widget child;
  const _SectionCard({
    required this.index,
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final header = Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReorderableDelayedDragStartListener(index: index, child: header),
          const Divider(height: 1, color: Color(0x1FFFFFFF)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: child,
          ),
        ],
      ),
    );
  }
}
