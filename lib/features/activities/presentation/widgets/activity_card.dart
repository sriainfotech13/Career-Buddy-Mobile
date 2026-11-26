import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../domain/entities/activity_progress_semantics.dart';
import '../../domain/entities/activity_summary.dart';

/// Mirrors the web activity list's card — `templates/activities/list.html`:
/// level + category badges, a progress bar only when `completionRate > 0`,
/// and a CTA whose label follows the same three states as the web
/// ("Start Activity" / "Continue" / "Review Activity"), plus a locked
/// state for activities outside the viewer's plan.
class ActivityCard extends StatelessWidget {
  const ActivityCard({required this.activity, required this.onTap, this.activityNumber, super.key});

  final ActivitySummary activity;
  final VoidCallback onTap;

  /// The card's `#N` badge (`list.html:94`, `#{{ forloop.counter }}`) — the
  /// activity's 1-based position in the currently-filtered list, not its
  /// raw `Activity.order` field (which the API doesn't expose). `null`
  /// hides the badge.
  final int? activityNumber;

  bool get _isScore => activity.progressSemantics == ActivityProgressSemantics.score;

  /// Anything attempted/progressed. CB 3.0 shows the progress block whenever
  /// an exercise was attempted (`list.html:117`, `p.attempted`) — even at a
  /// 0% score — while the previous web showed it only above 0%.
  bool get _hasProgress => activity.completionRate > 0 || (_isScore && (activity.attemptedExercises ?? 0) > 0);

  /// CB 3.0: "done" means every exercise was ATTEMPTED; only a 100% score is a
  /// perfect "Review", anything lower offers "Improve Score"
  /// (`list.html:145-152`). Legacy: done = 100% = "Review Activity".
  String get _ctaLabel {
    if (activity.isLocked) return 'Locked';
    if (activity.isCompleted) {
      // "Improve Score" only for a KNOWN score below 100. A missing
      // percentage (placeholder 0) must not be read as a low score, and a
      // score below 100 is not a failure — the button just opens the activity
      // (same destination as every other label); no retry is promised.
      return (_isScore && activity.hasProgressPercent && activity.completionRate < 100)
          ? 'Improve Score'
          : 'Review Activity';
    }
    if (_hasProgress) return 'Continue';
    return 'Start Activity';
  }

  /// `list.html:143-149` — the icon changes with the same states as the label.
  IconData get _ctaIcon {
    if (activity.isCompleted) return Icons.replay;
    if (_hasProgress) return Icons.play_arrow;
    return Icons.arrow_forward;
  }

  /// CB 3.0 bar colour tiers (`progress.py`: >=80 success, >=50 warning, else
  /// danger); legacy: success when done, otherwise the action colour.
  Color get _barColor {
    if (!_isScore) return activity.isCompleted ? AppColors.success : AppColors.action;
    final r = activity.completionRate;
    if (r >= 80) return AppColors.success;
    if (r >= 50) return AppColors.warning;
    return r > 0 ? AppColors.danger : AppColors.textMuted;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (activityNumber != null) ...[
                  Text(
                    '#$activityNumber',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.textMuted),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Expanded(
                  child: Text(
                    activity.title,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (activity.isLocked) const Icon(Icons.lock_outline, color: AppColors.textMuted, size: 20),
                if (activity.isCompleted) const Icon(Icons.check_circle, color: AppColors.success, size: 20),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                _Badge(label: activity.level, type: _BadgeType.level),
                _Badge(label: activity.categoryDisplay, type: _BadgeType.category),
              ],
            ),
            if (_hasProgress) ...[
              const SizedBox(height: AppSpacing.sm),
              // The bar and percentage only when the page showed a percentage
              // (never a placeholder 0%).
              if (activity.hasProgressPercent)
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: activity.completionRate / 100,
                          minHeight: 6,
                          backgroundColor: AppColors.border,
                          color: _barColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      _isScore ? 'Score ${activity.completionRate}%' : '${activity.completionRate}%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              // CB 3.0 `a/b exercises attempted` (`list.html:128-130`) — only
              // when the page showed it; "attempted" is not "passed".
              if (activity.attemptedExercises != null && activity.totalExercises != null)
                Text(
                  '${activity.attemptedExercises}/${activity.totalExercises} exercises attempted',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
            ],
            const SizedBox(height: AppSpacing.sm),
            // `list.html:135-151`: a real, full-width button either way —
            // `class="btn btn-secondary w-100"` (locked, 65% opacity, lock
            // icon) or `class="btn btn-primary w-100"` (unlocked). Both
            // classes resolve to the same navy fill/white text as the
            // final, real state of the cascade (`.btn-primary`'s own
            // "Reduce gold dominance" override, `style.css:2899-2919`, and
            // `.btn-secondary`'s un-overridden navy, `style.css:2671-2678`)
            // — not the gold pill this card previously, incorrectly,
            // rendered.
            if (activity.isLocked)
              // `style="cursor:not-allowed;opacity:.65;pointer-events:auto;"`
              // (`list.html:137`) — visually dimmed, but clicks still
              // register on the web (`pointer-events:auto`), consistent
              // with this card's own outer `InkWell.onTap` already firing
              // regardless of lock state. A real, non-null `onPressed` is
              // used here (delegating to the same `onTap`) specifically to
              // avoid Flutter's Material disabled-button style (a flat
              // gray fill that would misrepresent the real dimmed-navy
              // look) — the dimming is done with `Opacity`, matching the
              // web's own mechanism.
              Opacity(
                opacity: 0.65,
                child: AppButton(
                  label: 'Locked 🔒',
                  icon: Icons.lock_outline,
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  onPressed: onTap,
                ),
              )
            else
              AppButton(label: _ctaLabel, icon: _ctaIcon, onPressed: onTap),
          ],
        ),
      ),
    );
  }
}

enum _BadgeType { level, category }

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.type});

  final String label;
  final _BadgeType type;

  @override
  Widget build(BuildContext context) {
    // `.badge-level`/`.badge-category` (`static/css/style.css:964-980`).
    final (background, foreground) = switch (type) {
      _BadgeType.level => (const Color(0xFFEDE9FE), const Color(0xFF5B21B6)),
      _BadgeType.category => (const Color(0xFFF1F5F9), const Color(0xFF475569)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: foreground, fontWeight: FontWeight.w700, fontSize: 11),
      ),
    );
  }
}
