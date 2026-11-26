/// The four stat tiles. Each is null when the page did not render it —
/// a missing tile is never shown as a fabricated 0.
class DashboardStats {
  const DashboardStats({
    required this.completedCount,
    required this.inProgressCount,
    required this.totalActivities,
    required this.totalScore,
  });

  /// Previous web: activities with every sub-activity done. CB 3.0: activities
  /// whose exercises were all *attempted* (`activities/views.py:229-236`,
  /// `progress.py`), regardless of score.
  final int? completedCount;
  final int? inProgressCount;
  final int? totalActivities;
  final num? totalScore;
}
