import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../domain/entities/activity_progress_semantics.dart';
import '../controllers/mark_sub_complete_controller.dart';

/// The completion area of a sub-activity page.
///
/// - [SubActivityCompletionMode.legacyForm] — mirrors the previous web's
///   `sub_activity.html:157-185`: a completed banner (with the date) or the
///   "Finished this sub-activity?" card with a Mark Complete button gated on
///   all exercises being done.
/// - [SubActivityCompletionMode.scoreBased] — CB 3.0
///   (`sub_activity.html:161-180`): there is **no** completion action;
///   completion is automatic from exercise attempts. Shows the score summary
///   only ("Based on your scores: a/b exercises attempted") — attempting
///   everything is *not* the same as passing, and no pass/fail is claimed.
/// - [SubActivityCompletionMode.unknown] — nothing recognised: nothing shown.
class MarkCompleteSection extends StatelessWidget {
  const MarkCompleteSection({
    required this.allExercisesDone,
    required this.completedAt,
    required this.state,
    required this.onSubmit,
    this.mode = SubActivityCompletionMode.legacyForm,
    this.scorePercent,
    this.attemptedExercises,
    this.totalExercises,
    this.isFullyAttempted = false,
    super.key,
  });

  final bool allExercisesDone;
  final DateTime? completedAt;
  final MarkCompleteState state;
  final VoidCallback onSubmit;
  final SubActivityCompletionMode mode;

  /// CB 3.0 score summary; each is null when the page did not show it.
  final int? scorePercent;
  final int? attemptedExercises;
  final int? totalExercises;

  /// CB 3.0 status `completed` = every exercise attempted (any score).
  final bool isFullyAttempted;

  @override
  Widget build(BuildContext context) {
    switch (mode) {
      case SubActivityCompletionMode.scoreBased:
        return _ScoreSummaryCard(
          scorePercent: scorePercent,
          attempted: attemptedExercises,
          total: totalExercises,
          isFullyAttempted: isFullyAttempted,
        );
      case SubActivityCompletionMode.unknown:
        return const SizedBox.shrink();
      case SubActivityCompletionMode.legacyForm:
        return _legacy(context);
    }
  }

  Widget _legacy(BuildContext context) {
    final completedAt = this.completedAt;
    if (completedAt != null) {
      // `.completed-banner` (`style.css:1894-1901`) — a solid green
      // gradient with white text, not a pale success-tinted card.
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.success, Color(0xFF059669)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.emoji_events_outlined, color: Colors.white),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                'Sub-activity completed on ${formatFullMonthDayYear(completedAt)}!',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    final isSubmitting = state is MarkCompleteSubmitting;

    // `.mark-complete-card` (`style.css:1886-1892`) — a light-green tinted
    // card, not the generic white `AppCard`.
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        border: Border.all(color: const Color(0xFFBBF7D0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.checklist_outlined, color: AppColors.success, size: 28),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Finished this sub-activity?', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  allExercisesDone
                      ? 'Mark it complete to track your overall progress.'
                      : 'Please complete all interactive exercises first.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: allExercisesDone ? null : AppColors.danger),
                ),
                if (state is MarkCompleteFailed) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    (state as MarkCompleteFailed).failure.message,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.danger),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                AppButton(
                  label: 'Mark Complete',
                  icon: Icons.check,
                  isLoading: isSubmitting,
                  fullWidth: false,
                  onPressed: (allExercisesDone && !isSubmitting) ? onSubmit : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// CB 3.0 `div.mark-complete-card` (`sub_activity.html:161-180`): score,
/// bar, `Based on your scores: a/b exercise(s) attempted.` and one hint. Every
/// piece is optional — a value the page did not show is simply not shown (no
/// 0%, no 0/0). Theme-aware (uses the color scheme, not fixed light colors).
class _ScoreSummaryCard extends StatelessWidget {
  const _ScoreSummaryCard({
    required this.scorePercent,
    required this.attempted,
    required this.total,
    required this.isFullyAttempted,
  });

  final int? scorePercent;
  final int? attempted;
  final int? total;
  final bool isFullyAttempted;

  static const _gold = Color(0xFFFCA311);

  Color get _band {
    final p = scorePercent;
    if (p == null) return AppColors.textMuted;
    if (p >= 80) return AppColors.success;
    if (p >= 50) return _gold;
    return p > 0 ? AppColors.danger : AppColors.textMuted;
  }

  @override
  Widget build(BuildContext context) {
    final percent = scorePercent;
    final hasCounts = attempted != null && total != null;
    if (percent == null && !hasCounts) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;
    // Hint wording per the template: untried exercises count as 0% until
    // everything is attempted; afterwards retry/perfect. Only when the score
    // is known.
    final String? hint = percent == null
        ? null
        : !isFullyAttempted
        ? "Exercises you haven't tried count as 0%."
        : percent < 100
        ? 'Retry an exercise to raise your score.'
        : 'Perfect score!';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.show_chart, color: _band, size: 28),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (percent != null) ...[
                  Text.rich(
                    TextSpan(
                      style: theme.titleSmall,
                      children: [
                        const TextSpan(text: 'Your progress in this sub-activity: '),
                        TextSpan(
                          text: '$percent%',
                          style: TextStyle(color: _band, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: percent.clamp(0, 100) / 100,
                      minHeight: 8,
                      backgroundColor: cs.outlineVariant,
                      color: _band,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                if (hasCounts)
                  Text(
                    'Based on your scores: $attempted/$total exercise${total == 1 ? '' : 's'} attempted.',
                    style: theme.bodySmall,
                  ),
                if (hint != null) Text(hint, style: theme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
