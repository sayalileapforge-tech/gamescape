import 'package:flutter/material.dart';

import 'stats_section.dart';
import 'quick_actions_section.dart';
import 'console_map_section.dart';
import 'timeline_section.dart';
import 'active_overdue_section.dart';
import 'upcoming_section.dart';
import 'notifications_section.dart';

/// Registry to map section keys <-> constructors, used by the layout when
/// rebuilding a saved order list from Firestore.
typedef SectionBuilder = Widget Function(BuildContext, Map<String, dynamic>);

final Map<String, SectionBuilder> kSectionRegistry = {
  'stats': (ctx, p) => StatsSection(
        selectedBranchId: p['branchId'],
        todayRangeUtc: p['todayRangeUtc'],
      ),
  'quick_actions': (ctx, p) => QuickActionsSection(
        role: p['role'],
        allowedBranchIds: (p['allowedBranchIds'] as List).cast<String>(),
        selectedBranchId: p['branchId'],
      ),
  'console_map': (ctx, p) => ConsoleMapSection(branchId: p['branchId']),
  'timeline': (ctx, p) => TimelineSection(branchId: p['branchId']),
  'active_overdue': (ctx, p) => ActiveOverdueSection(branchId: p['branchId']),
  'upcoming': (ctx, p) => UpcomingSection(branchId: p['branchId']),
  'notifications': (ctx, p) => NotificationsSection(
        userId: p['userId'],
        role: p['role'],
        branchId: p['branchId'],
        branchName: p['branchName'],
      ),
};
