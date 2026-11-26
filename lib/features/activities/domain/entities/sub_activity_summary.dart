import 'sub_activity_status.dart';

class SubActivitySummary {
  const SubActivitySummary({
    required this.id,
    required this.title,
    required this.description,
    required this.order,
    required this.status,
    required this.exerciseCount,
    this.startedAt,
    this.completedAt,
    this.scorePercent,
  });

  final int id;
  final String title;
  final String description;
  final int order;
  final SubActivityStatus status;
  final int exerciseCount;
  final DateTime? startedAt;
  final DateTime? completedAt;

  /// CB 3.0 `Score N%` badge (only shown once something was attempted).
  /// Null when absent — never defaulted to 0.
  final int? scorePercent;
}
