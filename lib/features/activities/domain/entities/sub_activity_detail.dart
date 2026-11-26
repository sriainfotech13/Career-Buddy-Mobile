import 'activity_progress_semantics.dart';
import 'exercise_summary.dart';
import 'sub_activity_status.dart';

class SubActivityDetail {
  const SubActivityDetail({
    required this.id,
    required this.title,
    required this.description,
    required this.instructions,
    required this.order,
    required this.activityId,
    required this.activityTitle,
    required this.status,
    required this.allExercisesDone,
    required this.exercises,
    this.startedAt,
    this.completedAt,
    this.completionMode = SubActivityCompletionMode.legacyForm,
    this.scorePercent,
    this.attemptedExercises,
    this.totalExercises,
  });

  /// The sub-activity id taken from the REQUESTED route — never inferred
  /// from page markup, and never a sentinel such as -1.
  final int id;
  final String title;
  final String description;
  final String instructions;
  final int order;
  final int activityId;
  final String activityTitle;
  final SubActivityStatus status;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final bool allExercisesDone;
  final List<ExerciseSummary> exercises;

  /// Whether a manual completion action exists for this page.
  final SubActivityCompletionMode completionMode;

  /// CB 3.0 score summary (`Your progress in this sub-activity: N%`,
  /// `Based on your scores: a/b exercises attempted`). Null when absent.
  final int? scorePercent;
  final int? attemptedExercises;
  final int? totalExercises;

  /// True only for legacy markup with a valid positive id: the sole case in
  /// which `POST /activities/sub/<id>/complete/` may be sent.
  bool get canMarkComplete => completionMode == SubActivityCompletionMode.legacyForm && id > 0;
}
