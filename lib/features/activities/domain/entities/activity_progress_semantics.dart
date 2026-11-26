/// What a progress percentage on the activity pages means. The previous web
/// showed a *completion* percentage (`rate == 100` ⇒ done); CB 3.0 shows a
/// *score* percentage — the mean of exercise scores with unattempted
/// exercises counted as 0 (`CB_3.0/backend/apps/activities/progress.py`).
/// In score mode 100% means a perfect score, and a "completed" status only
/// means every exercise was *attempted*. No pass/fail is defined for
/// activities, so none is ever shown.
enum ActivityProgressSemantics { completion, score }

/// How a sub-activity page lets (or does not let) the user mark it complete.
enum SubActivityCompletionMode {
  /// Legacy markup: the page carried the `mark_sub_complete` form for this
  /// sub-activity (or its completed banner). The action is only offered in
  /// this mode, and only with a valid positive sub-activity id.
  legacyForm,

  /// CB 3.0 markup: completion is automatic from exercise attempts; the
  /// page has a score summary and **no** completion form. No action exists.
  scoreBased,

  /// Neither marker was recognised. No action is offered.
  unknown,
}
