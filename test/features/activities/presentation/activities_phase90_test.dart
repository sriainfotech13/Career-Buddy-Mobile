import 'package:career_buddy_lms/core/errors/failures.dart';
import 'package:career_buddy_lms/core/utils/result.dart';
import 'package:career_buddy_lms/features/activities/domain/activity_access_messages.dart';
import 'package:career_buddy_lms/features/activities/domain/entities/activity_detail.dart';
import 'package:career_buddy_lms/features/activities/domain/entities/activity_list_data.dart';
import 'package:career_buddy_lms/features/activities/domain/entities/activity_progress_semantics.dart';
import 'package:career_buddy_lms/features/activities/domain/entities/activity_summary.dart';
import 'package:career_buddy_lms/features/activities/domain/entities/exercise_summary.dart';
import 'package:career_buddy_lms/features/activities/domain/entities/sub_activity_detail.dart';
import 'package:career_buddy_lms/features/activities/domain/entities/sub_activity_status.dart';
import 'package:career_buddy_lms/features/activities/domain/entities/sub_activity_summary.dart';
import 'package:career_buddy_lms/features/activities/domain/repositories/activities_repository.dart';
import 'package:career_buddy_lms/features/activities/presentation/controllers/mark_sub_complete_controller.dart';
import 'package:career_buddy_lms/features/activities/presentation/providers/activities_providers.dart';
import 'package:career_buddy_lms/features/activities/presentation/screens/activity_detail_screen.dart';
import 'package:career_buddy_lms/features/activities/presentation/screens/sub_activity_detail_screen.dart';
import 'package:career_buddy_lms/features/activities/presentation/widgets/activity_card.dart';
import 'package:career_buddy_lms/features/activities/presentation/widgets/learning_tips_card.dart';
import 'package:career_buddy_lms/features/activities/presentation/widgets/mark_complete_section.dart';
import 'package:career_buddy_lms/features/auth/domain/entities/auth_user.dart';
import 'package:career_buddy_lms/features/auth/domain/entities/student_registration_data.dart';
import 'package:career_buddy_lms/features/auth/domain/repositories/auth_repository.dart';
import 'package:career_buddy_lms/features/auth/presentation/providers/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 90 — controller, widget and screen behaviour for the activity /
/// sub-activity compatibility work. Offline widget tests with fake
/// repositories; they do not exercise the deployed backend.
class FakeAuth implements AuthRepository {
  int logoutCalls = 0;

  @override
  Future<AuthUser?> restoreSession() async => const AuthUser(username: 'jane');

  @override
  Future<Result<AuthUser>> login({required String usernameOrEmail, required String password}) async =>
      throw UnimplementedError();

  @override
  Future<Result<void>> logout() async {
    logoutCalls++;
    return const Success(null);
  }

  @override
  Future<Result<String>> sendOtp(String email) async => throw UnimplementedError();

  @override
  Future<Result<String>> verifyOtp({required String email, required String code}) async => throw UnimplementedError();

  @override
  Future<Result<AuthUser>> register(StudentRegistrationData data) async => throw UnimplementedError();
}

class FakeRepo implements ActivitiesRepository {
  FakeRepo({this.sub, this.detail});

  Result<SubActivityDetail>? sub;
  Result<ActivityDetail>? detail;
  int subCalls = 0;
  final List<int> completeCalls = [];

  @override
  Future<Result<SubActivityDetail>> getSubActivityDetail(int activityId, int subActivityId) async {
    subCalls++;
    return sub ?? const Failed(NotFoundFailure());
  }

  @override
  Future<Result<ActivityDetail>> getActivityDetail(int id) async => detail ?? const Failed(NotFoundFailure());

  @override
  Future<Result<ActivityListData>> getActivityList({String? category}) async => const Failed(NotFoundFailure());

  @override
  Future<Result<ActivityListData>> getWorkshopModules() async => throw UnimplementedError();

  @override
  Future<Result<void>> markSubComplete(int subActivityId) async {
    completeCalls.add(subActivityId);
    return const Success(null);
  }
}

SubActivityDetail sub({
  int id = 35,
  SubActivityCompletionMode mode = SubActivityCompletionMode.legacyForm,
  bool allDone = true,
  SubActivityStatus status = SubActivityStatus.inProgress,
  int? score,
  int? attempted,
  int? total,
  DateTime? completedAt,
}) => SubActivityDetail(
  id: id,
  title: 'Meeting Phrases',
  description: 'Phrases.',
  instructions: 'Read.',
  order: 2,
  activityId: 4,
  activityTitle: 'Business Vocabulary',
  status: status,
  allExercisesDone: allDone,
  exercises: const <ExerciseSummary>[],
  completionMode: mode,
  scorePercent: score,
  attemptedExercises: attempted,
  totalExercises: total,
  completedAt: completedAt,
);

ActivitySummary summary({
  int rate = 0,
  bool done = false,
  ActivityProgressSemantics sem = ActivityProgressSemantics.completion,
  int? attempted,
  int? total,
  bool hasPercent = true,
}) => ActivitySummary(
  id: 4,
  title: 'Business Vocabulary',
  description: 'd',
  category: 'vocabulary',
  categoryDisplay: 'Vocabulary',
  level: 'Intermediate',
  duration: '',
  isLocked: false,
  completionRate: rate,
  isCompleted: done,
  progressSemantics: sem,
  attemptedExercises: attempted,
  totalExercises: total,
  hasProgressPercent: hasPercent,
);

Widget app(Widget home, {ThemeMode mode = ThemeMode.light}) => MaterialApp(
  themeMode: mode,
  theme: ThemeData.light(),
  darkTheme: ThemeData.dark(),
  home: Scaffold(body: SingleChildScrollView(child: home)),
);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
}

Future<FakeAuth> pumpSub(WidgetTester tester, FakeRepo repo, {ThemeMode mode = ThemeMode.light}) async {
  final auth = FakeAuth();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(auth), activitiesRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        themeMode: mode,
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        home: const SubActivityDetailScreen(activityId: 4, subActivityId: 35),
      ),
    ),
  );
  await settle(tester);
  return auth;
}

void main() {
  group('MarkSubCompleteController — invalid identifiers never reach the repository', () {
    ProviderContainer containerWith(FakeRepo repo) {
      final c = ProviderContainer(overrides: [activitiesRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      return c;
    }

    test('-1 (the old sentinel) fails locally with zero repository calls', () async {
      final repo = FakeRepo();
      final c = containerWith(repo);
      final provider = markSubCompleteControllerProvider((activityId: 4, subActivityId: -1));
      await c.read(provider.notifier).submit();
      expect(repo.completeCalls, isEmpty);
      expect(c.read(provider), isA<MarkCompleteFailed>());
    });

    test('0 and other non-positive ids also make no repository call', () async {
      final repo = FakeRepo();
      final c = containerWith(repo);
      for (final id in [0, -5]) {
        await c.read(markSubCompleteControllerProvider((activityId: 4, subActivityId: id)).notifier).submit();
      }
      expect(repo.completeCalls, isEmpty);
    });

    test('a valid id calls the repository exactly once with that id', () async {
      final repo = FakeRepo(sub: Success(sub()));
      final c = containerWith(repo);
      await c.read(markSubCompleteControllerProvider((activityId: 4, subActivityId: 35)).notifier).submit();
      expect(repo.completeCalls, [35]);
    });
  });

  group('MarkCompleteSection modes', () {
    Widget section(
      SubActivityCompletionMode mode, {
      bool allDone = false,
      DateTime? completedAt,
      int? score,
      int? attempted,
      int? total,
      bool fully = false,
      ThemeMode theme = ThemeMode.light,
    }) {
      return app(
        MarkCompleteSection(
          mode: mode,
          allExercisesDone: allDone,
          completedAt: completedAt,
          state: const MarkCompleteIdle(),
          onSubmit: () {},
          scorePercent: score,
          attemptedExercises: attempted,
          totalExercises: total,
          isFullyAttempted: fully,
        ),
        mode: theme,
      );
    }

    testWidgets('legacy form: Finished? card with a Mark Complete button (unchanged behaviour)', (tester) async {
      await tester.pumpWidget(section(SubActivityCompletionMode.legacyForm, allDone: true));
      expect(find.text('Finished this sub-activity?'), findsOneWidget);
      expect(find.text('Mark Complete'), findsOneWidget);
    });

    testWidgets('legacy completed banner shows the completion date and no button', (tester) async {
      await tester.pumpWidget(
        section(SubActivityCompletionMode.legacyForm, allDone: true, completedAt: DateTime(2026, 9, 5)),
      );
      expect(find.textContaining('Sub-activity completed on'), findsOneWidget);
      expect(find.text('Mark Complete'), findsNothing);
    });

    testWidgets('CB 3.0: NO Mark Complete action — score summary only', (tester) async {
      await tester.pumpWidget(section(SubActivityCompletionMode.scoreBased, score: 45, attempted: 1, total: 3));
      expect(find.text('Mark Complete'), findsNothing);
      expect(find.text('Finished this sub-activity?'), findsNothing);
      expect(find.textContaining('45%'), findsOneWidget);
      expect(find.textContaining('1/3 exercises attempted'), findsOneWidget);
    });

    testWidgets('CB 3.0 hints: untried / retry / perfect (attempted is never "passed")', (tester) async {
      await tester.pumpWidget(section(SubActivityCompletionMode.scoreBased, score: 45, attempted: 1, total: 3));
      expect(find.textContaining("Exercises you haven't tried count as 0%"), findsOneWidget);

      await tester.pumpWidget(
        section(SubActivityCompletionMode.scoreBased, score: 70, attempted: 3, total: 3, fully: true),
      );
      expect(find.textContaining('Retry an exercise to raise your score'), findsOneWidget);
      expect(find.textContaining('passed'), findsNothing);

      await tester.pumpWidget(
        section(SubActivityCompletionMode.scoreBased, score: 100, attempted: 3, total: 3, fully: true),
      );
      expect(find.textContaining('Perfect score!'), findsOneWidget);
    });

    testWidgets('CB 3.0 singular exercise wording', (tester) async {
      await tester.pumpWidget(
        section(SubActivityCompletionMode.scoreBased, score: 10, attempted: 1, total: 1, fully: true),
      );
      expect(find.textContaining('1/1 exercise attempted'), findsOneWidget);
    });

    testWidgets('CB 3.0 with nothing parsed renders nothing (no 0%, no 0/0)', (tester) async {
      await tester.pumpWidget(section(SubActivityCompletionMode.scoreBased));
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('0/0'), findsNothing);
    });

    testWidgets('a genuine 0% with 0/3 attempted is shown as zero', (tester) async {
      await tester.pumpWidget(section(SubActivityCompletionMode.scoreBased, score: 0, attempted: 0, total: 3));
      expect(find.textContaining('0%'), findsWidgets);
      expect(find.textContaining('0/3 exercises attempted'), findsOneWidget);
    });

    testWidgets('unknown mode shows nothing', (tester) async {
      await tester.pumpWidget(section(SubActivityCompletionMode.unknown));
      expect(find.text('Mark Complete'), findsNothing);
      expect(find.textContaining('progress'), findsNothing);
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('score card renders without errors in ${mode.name} mode', (tester) async {
        await tester.pumpWidget(
          section(SubActivityCompletionMode.scoreBased, score: 70, attempted: 3, total: 3, fully: true, theme: mode),
        );
        expect(tester.takeException(), isNull);
        expect(find.textContaining('70%'), findsOneWidget);
      });
    }
  });

  group('ActivityCard progress semantics', () {
    Widget card(ActivitySummary a) => app(ActivityCard(activity: a, onTap: () {}));

    testWidgets('legacy: unchanged labels (Start / Continue / Review) and plain percent', (tester) async {
      await tester.pumpWidget(card(summary()));
      expect(find.text('Start Activity'), findsOneWidget);
      await tester.pumpWidget(card(summary(rate: 40)));
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);
      await tester.pumpWidget(card(summary(rate: 100, done: true)));
      expect(find.text('Review Activity'), findsOneWidget);
    });

    testWidgets('CB 3.0: all attempted at 70% offers "Improve Score" with "Score 70%" and the attempted counter', (
      tester,
    ) async {
      await tester.pumpWidget(
        card(summary(rate: 70, done: true, sem: ActivityProgressSemantics.score, attempted: 7, total: 7)),
      );
      expect(find.text('Improve Score'), findsOneWidget);
      expect(find.text('Score 70%'), findsOneWidget);
      expect(find.text('7/7 exercises attempted'), findsOneWidget);
    });

    testWidgets('CB 3.0: a perfect score is "Review Activity"', (tester) async {
      await tester.pumpWidget(
        card(summary(rate: 100, done: true, sem: ActivityProgressSemantics.score, attempted: 4, total: 4)),
      );
      expect(find.text('Review Activity'), findsOneWidget);
    });

    testWidgets('CB 3.0: attempted with a 0% score still shows progress and "Continue"', (tester) async {
      await tester.pumpWidget(card(summary(rate: 0, sem: ActivityProgressSemantics.score, attempted: 1, total: 5)));
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Score 0%'), findsOneWidget);
      expect(find.text('1/5 exercises attempted'), findsOneWidget);
    });

    testWidgets('CB 3.0: nothing attempted shows no progress block and "Start Activity"', (tester) async {
      await tester.pumpWidget(card(summary(sem: ActivityProgressSemantics.score)));
      expect(find.text('Start Activity'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });

  group('SubActivityDetailScreen', () {
    testWidgets('CB 3.0 page: no Mark Complete button and no completion request is ever sent', (tester) async {
      final repo = FakeRepo(
        sub: Success(
          sub(mode: SubActivityCompletionMode.scoreBased, allDone: false, score: 45, attempted: 1, total: 3),
        ),
      );
      await pumpSub(tester, repo);
      expect(find.text('Mark Complete'), findsNothing);
      expect(find.textContaining('1/3 exercises attempted'), findsOneWidget);
      expect(repo.completeCalls, isEmpty);
    });

    testWidgets('legacy page: Mark Complete sends the ROUTE id once', (tester) async {
      final repo = FakeRepo(sub: Success(sub()));
      await pumpSub(tester, repo);
      await tester.ensureVisible(find.text('Mark Complete'));
      await tester.tap(find.text('Mark Complete'));
      await settle(tester);
      expect(repo.completeCalls, [35]);
    });

    testWidgets('a sentinel -1 id can never trigger a completion request, even with legacy markup and all done', (
      tester,
    ) async {
      final repo = FakeRepo(sub: Success(sub(id: -1)));
      await pumpSub(tester, repo);
      await tester.ensureVisible(find.text('Mark Complete'));
      await tester.tap(find.text('Mark Complete'));
      await settle(tester);
      expect(repo.completeCalls, isEmpty);
    });

    testWidgets('unknown completion mode: no action at all', (tester) async {
      final repo = FakeRepo(sub: Success(sub(mode: SubActivityCompletionMode.unknown, allDone: false)));
      await pumpSub(tester, repo);
      expect(find.text('Mark Complete'), findsNothing);
    });

    testWidgets('format change: recoverable error with Retry; the session is NOT logged out', (tester) async {
      final repo = FakeRepo(sub: const Failed(PageFormatChangedFailure()));
      final auth = await pumpSub(tester, repo);
      expect(find.text(const PageFormatChangedFailure().message), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('session has expired'), findsNothing);
      expect(auth.logoutCalls, 0);
    });

    testWidgets('Retry re-fetches and recovers', (tester) async {
      final repo = FakeRepo(sub: const Failed(PageFormatChangedFailure()));
      await pumpSub(tester, repo);
      repo.sub = Success(sub(mode: SubActivityCompletionMode.scoreBased, score: 45, attempted: 1, total: 3));
      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(repo.subCalls, 2);
      expect(find.text('Retry'), findsNothing);
      expect(find.textContaining('45%'), findsWidgets);
    });

    testWidgets('confirmed session expiry still logs out (existing recovery)', (tester) async {
      final auth = await pumpSub(tester, FakeRepo(sub: const Failed(UnauthorizedFailure())));
      expect(auth.logoutCalls, 1);
    });

    testWidgets('role mismatch: plain message with Retry, NO upgrade prompt, no logout', (tester) async {
      final auth = await pumpSub(tester, FakeRepo(sub: const Failed(ForbiddenFailure(activityRoleMismatchMessage))));
      expect(find.text(activityRoleMismatchMessage), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('View Plans'), findsNothing);
      expect(auth.logoutCalls, 0);
    });

    testWidgets('plan lock: upgrade prompt is kept for the locked message', (tester) async {
      final auth = await pumpSub(tester, FakeRepo(sub: const Failed(ForbiddenFailure(activityLockedMessage))));
      expect(find.text('View Plans'), findsOneWidget);
      expect(auth.logoutCalls, 0);
    });

    testWidgets('network failure is distinct from a format change and keeps the session', (tester) async {
      final auth = await pumpSub(tester, FakeRepo(sub: const Failed(NetworkFailure())));
      expect(find.text(const NetworkFailure().message), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(auth.logoutCalls, 0);
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('CB 3.0 sub-activity page renders in ${mode.name} mode', (tester) async {
        final repo = FakeRepo(
          sub: Success(
            sub(
              mode: SubActivityCompletionMode.scoreBased,
              score: 70,
              attempted: 3,
              total: 3,
              status: SubActivityStatus.completed,
            ),
          ),
        );
        await pumpSub(tester, repo, mode: mode);
        expect(tester.takeException(), isNull);
        expect(find.textContaining('70%'), findsWidgets);
      });
    }
  });

  group('ActivityDetailScreen ring label', () {
    ActivityDetail detail(ActivityProgressSemantics sem, {int? attempted, int? total}) => ActivityDetail(
      id: 4,
      title: 'Business Vocabulary',
      description: 'd',
      category: '',
      categoryDisplay: '',
      level: 'Intermediate',
      duration: '30 min',
      isWorkshop: false,
      isModule: false,
      completionRate: 58,
      subActivities: const <SubActivitySummary>[],
      progressSemantics: sem,
      attemptedExercises: attempted,
      totalExercises: total,
    );

    Future<FakeAuth> pump(WidgetTester tester, ActivityDetail d) async {
      final auth = FakeAuth();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            activitiesRepositoryProvider.overrideWithValue(FakeRepo(detail: Success(d))),
          ],
          child: const MaterialApp(home: ActivityDetailScreen(activityId: 4)),
        ),
      );
      await settle(tester);
      return auth;
    }

    testWidgets('legacy detail keeps the "Complete" label', (tester) async {
      await pump(tester, detail(ActivityProgressSemantics.completion));
      expect(find.text('Complete'), findsOneWidget);
      expect(find.text('Score'), findsNothing);
    });

    testWidgets('CB 3.0 detail says "Score" with the a/b exercises line', (tester) async {
      await pump(tester, detail(ActivityProgressSemantics.score, attempted: 5, total: 8));
      expect(find.text('Score'), findsOneWidget);
      expect(find.text('5/8 exercises'), findsOneWidget);
      expect(find.text('Complete'), findsNothing);
    });

    testWidgets('detail format change shows Retry without logging out', (tester) async {
      final auth = FakeAuth();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            activitiesRepositoryProvider.overrideWithValue(FakeRepo(detail: const Failed(PageFormatChangedFailure()))),
          ],
          child: const MaterialApp(home: ActivityDetailScreen(activityId: 4)),
        ),
      );
      await settle(tester);
      expect(find.text('Retry'), findsOneWidget);
      expect(auth.logoutCalls, 0);
    });
  });

  group('final review — learning tip follows verified completion capability', () {
    testWidgets('LearningTipsCard: manual completion available keeps the legacy tip', (tester) async {
      await tester.pumpWidget(app(const LearningTipsCard()));
      expect(find.text(LearningTipsCard.legacyCompletionTip), findsOneWidget);
      expect(find.text(LearningTipsCard.automaticCompletionTip), findsNothing);
    });

    testWidgets('LearningTipsCard: automatic completion uses the exercise-based tip', (tester) async {
      await tester.pumpWidget(app(const LearningTipsCard(manualCompletionAvailable: false)));
      expect(find.text('Complete the exercises to update your progress.'), findsOneWidget);
      expect(find.text('Mark complete when you feel confident.'), findsNothing);
    });

    testWidgets('legacy sub-activity page (button exists): legacy tip', (tester) async {
      await pumpSub(tester, FakeRepo(sub: Success(sub())));
      await tester.scrollUntilVisible(find.text('Learning Tips'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Mark complete when you feel confident.'), findsOneWidget);
    });

    testWidgets('CB 3.0 page (no button): the tip does not mention a button that does not exist', (tester) async {
      await pumpSub(
        tester,
        FakeRepo(sub: Success(sub(mode: SubActivityCompletionMode.scoreBased, score: 45, attempted: 1, total: 3))),
      );
      await tester.scrollUntilVisible(find.text('Learning Tips'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Complete the exercises to update your progress.'), findsOneWidget);
      expect(find.text('Mark complete when you feel confident.'), findsNothing);
    });

    testWidgets('unknown completion mode and a legacy completed banner also use the automatic tip', (tester) async {
      await pumpSub(tester, FakeRepo(sub: Success(sub(mode: SubActivityCompletionMode.unknown, allDone: false))));
      await tester.scrollUntilVisible(find.text('Learning Tips'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Mark complete when you feel confident.'), findsNothing);

      await pumpSub(
        tester,
        FakeRepo(
          sub: Success(sub(completedAt: DateTime(2026, 9, 5), status: SubActivityStatus.completed)),
        ),
      );
      await tester.scrollUntilVisible(find.text('Learning Tips'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Mark complete when you feel confident.'), findsNothing);
    });
  });

  group('final review — "Improve Score" only for a known score below 100', () {
    Widget card(ActivitySummary a) => app(ActivityCard(activity: a, onTap: () {}));

    testWidgets('done but percentage missing: "Review Activity", never "Improve Score" or "Score 0%"', (tester) async {
      await tester.pumpWidget(
        card(summary(done: true, sem: ActivityProgressSemantics.score, attempted: 3, total: 3, hasPercent: false)),
      );
      expect(find.text('Improve Score'), findsNothing);
      expect(find.text('Review Activity'), findsOneWidget);
      expect(find.textContaining('Score 0%'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      // The honest counter is still shown.
      expect(find.text('3/3 exercises attempted'), findsOneWidget);
    });

    testWidgets('done with a known 70%: "Improve Score", with no failure wording', (tester) async {
      await tester.pumpWidget(
        card(summary(rate: 70, done: true, sem: ActivityProgressSemantics.score, attempted: 3, total: 3)),
      );
      expect(find.text('Improve Score'), findsOneWidget);
      expect(find.textContaining(RegExp('fail|passed', caseSensitive: false)), findsNothing);
    });

    testWidgets('done with a known 0% (genuine zero) is still "Improve Score"', (tester) async {
      await tester.pumpWidget(
        card(summary(rate: 0, done: true, sem: ActivityProgressSemantics.score, attempted: 2, total: 2)),
      );
      expect(find.text('Improve Score'), findsOneWidget);
    });

    testWidgets('the card keeps navigating through its own onTap (activity detail), not an exercise route', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        app(
          ActivityCard(
            activity: summary(rate: 70, done: true, sem: ActivityProgressSemantics.score, attempted: 3, total: 3),
            onTap: () => taps++,
          ),
        ),
      );
      await tester.tap(find.text('Improve Score'));
      expect(taps, 1);
    });
  });

  group('final review — Forbidden never logs out', () {
    testWidgets('a generic 403 keeps the session (View Plans kept as documented Phase 93 technical debt)', (
      tester,
    ) async {
      final auth = await pumpSub(tester, FakeRepo(sub: const Failed(ForbiddenFailure('Not permitted.'))));
      expect(auth.logoutCalls, 0);
      expect(find.text('Not permitted.'), findsOneWidget);
    });

    testWidgets('role mismatch on the activity detail page: message + Retry, no upgrade prompt, no logout', (
      tester,
    ) async {
      final auth = FakeAuth();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            activitiesRepositoryProvider.overrideWithValue(
              FakeRepo(detail: const Failed(ForbiddenFailure(activityRoleMismatchMessage))),
            ),
          ],
          child: const MaterialApp(home: ActivityDetailScreen(activityId: 4)),
        ),
      );
      await settle(tester);
      expect(find.text(activityRoleMismatchMessage), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('View Plans'), findsNothing);
      expect(auth.logoutCalls, 0);
    });
  });
}
