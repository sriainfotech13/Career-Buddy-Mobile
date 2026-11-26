import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../domain/entities/activity_progress.dart';

/// Mirrors the web dashboard's activity-progress list —
/// `dashboard.html:153-200`, including its `{% empty %}` copy and "Start
/// Learning" CTA (`dashboard.html:192-197`).
class ActivityProgressList extends StatelessWidget {
  const ActivityProgressList({required this.activities, this.onTapActivity, this.onStartLearning, super.key});

  final List<ActivityProgress> activities;

  /// Called with the tapped activity's id, if the caller wants tiles to
  /// navigate (e.g. to the Activities feature's detail screen). Omitted in
  /// contexts where tapping shouldn't navigate.
  final void Function(int activityId)? onTapActivity;

  /// The empty state's "Start Learning" button (`{% url 'activity_list' %}`
  /// on the web). Omitted in contexts where the button shouldn't navigate.
  final VoidCallback? onStartLearning;

  @override
  Widget build(BuildContext context) {
    if (activities.isEmpty) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('No activities started yet.'),
            if (onStartLearning != null) ...[
              const SizedBox(height: AppSpacing.md),
              AppButton(label: 'Start Learning', fullWidth: false, onPressed: onStartLearning),
            ],
          ],
        ),
      );
    }

    return Column(
      children: [
        for (final activity in activities) ...[
          _ActivityTile(activity: activity, onTap: onTapActivity),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.activity, this.onTap});

  final ActivityProgress activity;
  final void Function(int activityId)? onTap;

  static const _gold = Color(0xFFFCA311);

  /// Legacy (completion) tiers — `text-success` at 100%, `text-warning`
  /// above 0%, `text-muted` at 0% (previous `dashboard.html:172-178`).
  Color _completionColor(num rate) {
    if (rate == 100) return AppColors.success;
    if (rate > 0) return _gold;
    return AppColors.textMuted;
  }

  /// CB 3.0 (score) tiers: the server's own band class when present
  /// (`dashboard.html:193`), otherwise the same thresholds it uses —
  /// `progress.py` (>=80 success, >=50 warning, else danger; nothing
  /// attempted = muted).
  Color _scoreColor(ActivityProgress a) {
    final band = a.band ?? _derivedBand(a);
    return switch (band) {
      ProgressBand.success => AppColors.success,
      ProgressBand.warning => _gold,
      ProgressBand.danger => AppColors.danger,
      ProgressBand.muted => AppColors.textMuted,
    };
  }

  ProgressBand _derivedBand(ActivityProgress a) {
    final rate = a.completionRate;
    if (rate == null) return ProgressBand.muted;
    if (rate >= 80) return ProgressBand.success;
    if (rate >= 50) return ProgressBand.warning;
    return rate > 0 ? ProgressBand.danger : ProgressBand.muted;
  }

  Color _tierColor(ActivityProgress a) {
    final rate = a.completionRate;
    if (rate == null) return AppColors.textMuted;
    return a.semantics == ProgressSemantics.score ? _scoreColor(a) : _completionColor(rate);
  }

  /// The count text, built only from counts the page actually rendered. A
  /// missing count is never shown as 0/0. Returns null when there is nothing
  /// honest to say.
  String? _countText(ActivityProgress a) {
    switch (a.basis) {
      case ProgressBasis.subActivities:
        if (a.completedSubActivities == null || a.totalSubActivities == null) return null;
        return '${a.completedSubActivities}/${a.totalSubActivities} completed';
      case ProgressBasis.exercises:
        if (a.attemptedExercises == null || a.totalExercises == null) return null;
        return '${a.attemptedExercises}/${a.totalExercises} exercises attempted';
      case ProgressBasis.workshopSessions:
        final n = a.sessionCount;
        if (n == null) return null;
        return n == 0 ? 'No sessions yet' : 'Session score \u00b7 $n session${n == 1 ? '' : 's'}';
      case ProgressBasis.noScoredExercises:
        return 'No scored exercises';
      case ProgressBasis.unknown:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rate = activity.completionRate;
    final tierColor = _tierColor(activity);
    final countText = _countText(activity);
    final onTap = this.onTap;
    final scoreMode = activity.semantics == ProgressSemantics.score;

    final card = AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(activity.title, style: Theme.of(context).textTheme.titleMedium),
          if (rate != null) ...[
            const SizedBox(height: AppSpacing.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (rate.clamp(0, 100)) / 100,
                minHeight: 8,
                backgroundColor: AppColors.border,
                color: tierColor,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                    children: [
                      if (countText != null) TextSpan(text: rate != null ? '$countText \u2022 ' : countText),
                      if (rate != null)
                        TextSpan(
                          text: scoreMode && activity.basis == ProgressBasis.exercises
                              ? 'Score ${rate.round()}%'
                              : '${rate.round()}%',
                          style: TextStyle(color: tierColor, fontWeight: FontWeight.w700),
                        ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (activity.startedAt != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Icon(Icons.calendar_today_outlined, size: 12, color: AppColors.action),
                const SizedBox(width: 4),
                Text(
                  'Started ${formatMonthDayYear(activity.startedAt!)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.action),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    // Module rows (link to an exercise page) and unrecognised links have no
    // activityId and are deliberately not navigable — no route is invented.
    final id = activity.activityId;
    if (onTap == null || id == null) return card;
    return InkWell(onTap: () => onTap(id), borderRadius: BorderRadius.circular(12), child: card);
  }
}
