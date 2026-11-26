import 'package:career_buddy_lms/app/theme/app_theme.dart';
import 'package:career_buddy_lms/features/dashboard/domain/entities/activity_progress.dart';
import 'package:career_buddy_lms/features/dashboard/domain/entities/dashboard_stats.dart';
import 'package:career_buddy_lms/features/dashboard/presentation/widgets/activity_progress_list.dart';
import 'package:career_buddy_lms/features/dashboard/presentation/widgets/dashboard_stats_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child, {ThemeMode mode = ThemeMode.light}) => MaterialApp(
  theme: AppTheme.light,
  darkTheme: AppTheme.dark,
  themeMode: mode,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  group('ActivityProgressList (Phase 89)', () {
    testWidgets('legacy sub-activity row keeps its original "X/Y completed • N%" text', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ActivityProgressList(
            activities: [
              ActivityProgress(
                activityId: 1,
                title: 'Vocab',
                completionRate: 60,
                completedSubActivities: 3,
                totalSubActivities: 5,
              ),
            ],
          ),
        ),
      );
      expect(find.textContaining('3/5 completed'), findsOneWidget);
      expect(find.textContaining('60%'), findsOneWidget);
    });

    testWidgets('CB 3.0 exercises row shows attempted/total and an explicit Score percentage', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ActivityProgressList(
            activities: [
              ActivityProgress(
                activityId: 2,
                title: 'Email Writing',
                completionRate: 70,
                basis: ProgressBasis.exercises,
                semantics: ProgressSemantics.score,
                attemptedExercises: 7,
                totalExercises: 7,
                band: ProgressBand.warning,
              ),
            ],
          ),
        ),
      );
      expect(find.textContaining('7/7 exercises attempted'), findsOneWidget);
      expect(find.textContaining('Score 70%'), findsOneWidget);
      // Attempted everything but not a 100 score: no "completed" claim.
      expect(find.textContaining('completed'), findsNothing);
    });

    testWidgets('missing counts render NO 0/0 text', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ActivityProgressList(
            activities: [
              ActivityProgress(
                activityId: 3,
                title: 'No Counter',
                completionRate: 45,
                basis: ProgressBasis.unknown,
                semantics: ProgressSemantics.score,
              ),
            ],
          ),
        ),
      );
      expect(find.textContaining('0/0'), findsNothing);
      expect(find.textContaining('45%'), findsOneWidget);
    });

    testWidgets('a row with no percentage shows no percentage and no progress bar (nothing invented)', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ActivityProgressList(
            activities: [
              ActivityProgress(
                activityId: 3,
                title: 'Bare',
                basis: ProgressBasis.unknown,
                semantics: ProgressSemantics.unknown,
              ),
            ],
          ),
        ),
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('workshop rows: sessions text; zero sessions says "No sessions yet"', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ActivityProgressList(
            activities: [
              ActivityProgress(
                title: 'Group Discussion',
                completionRate: 78,
                basis: ProgressBasis.workshopSessions,
                semantics: ProgressSemantics.score,
                sessionCount: 2,
              ),
              ActivityProgress(
                title: 'JAM',
                completionRate: 0,
                basis: ProgressBasis.workshopSessions,
                semantics: ProgressSemantics.score,
                sessionCount: 0,
              ),
            ],
          ),
        ),
      );
      expect(find.textContaining('Session score · 2 sessions'), findsOneWidget);
      expect(find.textContaining('No sessions yet'), findsOneWidget);
    });

    testWidgets('"No scored exercises" is shown as is', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ActivityProgressList(
            activities: [
              ActivityProgress(
                activityId: 9,
                title: 'Reading',
                completionRate: 0,
                basis: ProgressBasis.noScoredExercises,
                semantics: ProgressSemantics.score,
              ),
            ],
          ),
        ),
      );
      expect(find.textContaining('No scored exercises'), findsOneWidget);
    });

    testWidgets('existing navigation: tapping a navigable row passes its activity id', (tester) async {
      int? tapped;
      await tester.pumpWidget(
        wrap(
          ActivityProgressList(
            activities: const [ActivityProgress(activityId: 4, title: 'Vocab', completionRate: 10)],
            onTapActivity: (id) => tapped = id,
          ),
        ),
      );
      await tester.tap(find.text('Vocab'));
      expect(tapped, 4);
    });

    testWidgets('a module row (exercise link, no activity id) is NOT navigable — no route is fabricated', (
      tester,
    ) async {
      int? tapped;
      await tester.pumpWidget(
        wrap(
          ActivityProgressList(
            activities: const [
              ActivityProgress(
                title: 'Listening Practice',
                completionRate: 50,
                basis: ProgressBasis.exercises,
                semantics: ProgressSemantics.score,
                linkKind: ActivityLinkKind.moduleExercise,
                exerciseId: 37,
                attemptedExercises: 1,
                totalExercises: 2,
              ),
            ],
            onTapActivity: (id) => tapped = id,
          ),
        ),
      );
      await tester.tap(find.text('Listening Practice'));
      expect(tapped, isNull);
      expect(find.byType(InkWell), findsNothing);
    });

    for (final mode in ThemeMode.values.where((m) => m != ThemeMode.system)) {
      testWidgets('renders every basis without layout errors in ${mode.name} mode', (tester) async {
        await tester.pumpWidget(
          wrap(
            const ActivityProgressList(
              activities: [
                ActivityProgress(
                  activityId: 1,
                  title: 'A',
                  completionRate: 60,
                  completedSubActivities: 3,
                  totalSubActivities: 5,
                ),
                ActivityProgress(
                  activityId: 2,
                  title: 'B',
                  completionRate: 20,
                  basis: ProgressBasis.exercises,
                  semantics: ProgressSemantics.score,
                  attemptedExercises: 1,
                  totalExercises: 5,
                  band: ProgressBand.danger,
                ),
                ActivityProgress(title: 'C', basis: ProgressBasis.unknown, semantics: ProgressSemantics.unknown),
              ],
            ),
            mode: mode,
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('DashboardStatsRow (Phase 89)', () {
    const full = DashboardStats(completedCount: 3, inProgressCount: 2, totalActivities: 20, totalScore: 145);

    testWidgets('default (legacy/unknown) keeps the "Completed" label', (tester) async {
      await tester.pumpWidget(wrap(const DashboardStatsRow(stats: full)));
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Fully Attempted'), findsNothing);
    });

    testWidgets('CB 3.0 score-based mode uses accurate terminology', (tester) async {
      await tester.pumpWidget(wrap(const DashboardStatsRow(stats: full, scoreBased: true)));
      expect(find.text('Fully Attempted'), findsOneWidget);
      expect(find.text('Completed'), findsNothing);
    });

    testWidgets('null stats show "-" rather than a fabricated 0', (tester) async {
      const empty = DashboardStats(
        completedCount: null,
        inProgressCount: null,
        totalActivities: null,
        totalScore: null,
      );
      await tester.pumpWidget(wrap(const DashboardStatsRow(stats: empty)));
      expect(find.text('-'), findsNWidgets(4));
      expect(find.text('0'), findsNothing);
    });

    testWidgets('a legitimate 0 is shown as 0', (tester) async {
      const zero = DashboardStats(completedCount: 0, inProgressCount: 0, totalActivities: 0, totalScore: 0);
      await tester.pumpWidget(wrap(const DashboardStatsRow(stats: zero)));
      expect(find.text('0'), findsNWidgets(4));
    });
  });
}
