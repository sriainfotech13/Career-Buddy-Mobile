import 'activity_progress_semantics.dart';

class ActivitySummary {
  const ActivitySummary({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.categoryDisplay,
    required this.level,
    required this.duration,
    required this.isLocked,
    required this.completionRate,
    required this.isCompleted,
    this.progressSemantics = ActivityProgressSemantics.completion,
    this.attemptedExercises,
    this.totalExercises,
    this.hasProgressPercent = true,
  });

  final int id;
  final String title;
  final String description;
  final String category;
  final String categoryDisplay;
  final String level;
  final String duration;
  final bool isLocked;

  /// Percentage, 0-100.
  final int completionRate;

  /// Legacy: every sub-activity done (100%). CB 3.0 ([progressSemantics] ==
  /// score): every exercise *attempted*, whatever the score — not "passed".
  final bool isCompleted;
  final ActivityProgressSemantics progressSemantics;

  /// CB 3.0 `a/b exercises attempted`; null when the page did not show it.
  final int? attemptedExercises;
  final int? totalExercises;

  /// False when the page showed no percentage for this card, so
  /// [completionRate] (0) is a placeholder, not a score. Score-dependent UI
  /// (e.g. "Improve Score") must not treat that placeholder as a known 0%.
  final bool hasProgressPercent;
}
