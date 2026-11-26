/// What the dashboard's per-activity counter text says it counts. Derived
/// from the actual rendered text, never assumed — see
/// `DashboardHtmlParser` and `CB_3.0/frontend/templates/dashboard.html:205-213`.
enum ProgressBasis {
  /// Legacy `N/M sub-activities` (previous web).
  subActivities,

  /// CB 3.0 `N/M exercises attempted`.
  exercises,

  /// CB 3.0 workshop rows: `Session score · N session(s)` / `No sessions yet`.
  workshopSessions,

  /// CB 3.0 `No scored exercises` (the activity has nothing scorable).
  noScoredExercises,

  /// The counter text was missing or unrecognised. Counts must stay null.
  unknown,
}

/// What [ActivityProgress.completionRate] means. The previous web showed a
/// *completion* percentage; CB 3.0 shows a *score* percentage (average of
/// exercise scores, unattempted = 0) — `activities/progress.py`. 100% in
/// score mode means a perfect score, not "finished".
enum ProgressSemantics { completion, score, unknown }

/// Where the row's link points (`dashboard.html:184`): a normal activity
/// detail page, or — for module activities — straight to an exercise page
/// whose number is an *exercise* id, never an activity id.
enum ActivityLinkKind { activity, moduleExercise, unknown }

/// The `text-<band>` colour class the server chose for the percentage.
enum ProgressBand { success, warning, danger, muted }

class ActivityProgress {
  const ActivityProgress({
    this.activityId,
    required this.title,
    this.completionRate,
    this.completedSubActivities,
    this.totalSubActivities,
    this.startedAt,
    this.basis = ProgressBasis.subActivities,
    this.semantics = ProgressSemantics.completion,
    this.linkKind = ActivityLinkKind.activity,
    this.exerciseId,
    this.order,
    this.attemptedExercises,
    this.totalExercises,
    this.sessionCount,
    this.band,
  });

  /// Null when the row does not link to an activity detail page (module rows
  /// link to an exercise page; unrecognised hrefs). Such rows are not
  /// navigable — the app never fabricates a route for them.
  final int? activityId;
  final String title;

  /// Percentage 0-100, or null when the page did not show one (never
  /// invented). See [semantics] for what it means.
  final double? completionRate;

  /// Legacy count-based progress. Null unless the page genuinely rendered
  /// `N/M sub-activities` — a legitimate 0 stays 0, a missing count is null.
  final int? completedSubActivities;
  final int? totalSubActivities;
  final DateTime? startedAt;

  final ProgressBasis basis;
  final ProgressSemantics semantics;
  final ActivityLinkKind linkKind;

  /// Set only for [ActivityLinkKind.moduleExercise] rows.
  final int? exerciseId;

  /// `Activity.order` shown as the "N. " title prefix — NOT a primary key.
  final int? order;

  /// CB 3.0 `attempted/total exercises attempted`. Attempted is not the same
  /// as passed or completed-with-a-good-score.
  final int? attemptedExercises;
  final int? totalExercises;

  /// CB 3.0 workshop rows: number of recorded sessions.
  final int? sessionCount;
  final ProgressBand? band;

  bool get isNavigable => activityId != null;
}
