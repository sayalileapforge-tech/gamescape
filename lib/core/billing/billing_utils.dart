// FULL FILE: lib/core/billing/billing_utils.dart
import 'dart:math' as math;

/// Ceil-division helper (e.g., ceilDiv(61, 60) = 2).
int ceilDiv(int a, int b) => (a + b - 1) ~/ b;

/// Normalize "Extend N mins":
/// - Scheduled end = startUtc + scheduledMinutes
/// - Base = max(nowUtc, scheduled end)
/// - New end = Base + addMinutes
/// Returns the new durationMinutes to persist on the session.
/// This avoids extending from a negative overrun.
int extendByMinutes({
  required DateTime startUtc,
  required int scheduledMinutes,
  required int addMinutes,
  DateTime? nowUtc,
}) {
  final now = (nowUtc ?? DateTime.now().toUtc());
  final currentSchedEnd =
      startUtc.add(Duration(minutes: math.max(0, scheduledMinutes)));
  final base = now.isAfter(currentSchedEnd) ? now : currentSchedEnd;
  final newEnd = base.add(Duration(minutes: addMinutes));
  return math.max(0, newEnd.difference(startUtc).inMinutes);
}

/// Given actual minutes and a block size (30 or 60),
/// returns the number of billable units using ceiling logic.
int billedUnitsForPlan({
  required int actualMinutes,
  required int blockMinutes,
}) {
  final minutes = math.max(0, actualMinutes);
  return ceilDiv(minutes, math.max(1, blockMinutes));
}
