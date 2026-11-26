import 'package:career_buddy_lms/core/errors/failures.dart';
import 'package:career_buddy_lms/core/utils/result.dart';
import 'package:career_buddy_lms/features/auth/domain/entities/auth_user.dart';
import 'package:career_buddy_lms/features/auth/domain/entities/student_registration_data.dart';
import 'package:career_buddy_lms/features/auth/domain/repositories/auth_repository.dart';
import 'package:career_buddy_lms/features/auth/presentation/controllers/auth_controller.dart';
import 'package:career_buddy_lms/features/auth/presentation/providers/auth_providers.dart';
import 'package:career_buddy_lms/features/dashboard/domain/entities/activity_progress.dart';
import 'package:career_buddy_lms/features/dashboard/domain/entities/dashboard_data.dart';
import 'package:career_buddy_lms/features/dashboard/domain/entities/dashboard_stats.dart';
import 'package:career_buddy_lms/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:career_buddy_lms/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:career_buddy_lms/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 89 — dashboard error handling. These are offline widget tests with
/// fake repositories; they do not exercise the deployed backend.
class _FakeAuthRepository implements AuthRepository {
  int logoutCallCount = 0;

  @override
  Future<AuthUser?> restoreSession() async => const AuthUser(username: 'jane');

  @override
  Future<Result<AuthUser>> login({required String usernameOrEmail, required String password}) async =>
      throw UnimplementedError();

  @override
  Future<Result<void>> logout() async {
    logoutCallCount++;
    return const Success(null);
  }

  @override
  Future<Result<String>> sendOtp(String email) async => throw UnimplementedError();

  @override
  Future<Result<String>> verifyOtp({required String email, required String code}) async => throw UnimplementedError();

  @override
  Future<Result<AuthUser>> register(StudentRegistrationData data) async => throw UnimplementedError();
}

/// Returns the queued results in order (the last one repeats).
class _SequenceDashboardRepository implements DashboardRepository {
  _SequenceDashboardRepository(this.results);
  final List<Result<DashboardData>> results;
  int calls = 0;

  @override
  Future<Result<DashboardData>> getDashboard() async {
    final i = calls < results.length ? calls : results.length - 1;
    calls++;
    return results[i];
  }
}

const _stats = DashboardStats(completedCount: 1, inProgressCount: 1, totalActivities: 5, totalScore: 10);

DashboardData data({
  List<ActivityProgress> activities = const [],
  DashboardMarkupGeneration generation = DashboardMarkupGeneration.unknown,
}) => DashboardData(
  stats: _stats,
  activities: activities,
  recentResults: const [],
  recommendedJobs: const [],
  paymentHistory: const [],
  generation: generation,
);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
}

Future<ProviderContainer> pump(
  WidgetTester tester, {
  required AuthRepository auth,
  required DashboardRepository repo,
  ThemeMode mode = ThemeMode.light,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(auth), dashboardRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        themeMode: mode,
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        home: const DashboardScreen(),
      ),
    ),
  );
  await settle(tester);
  return ProviderScope.containerOf(tester.element(find.byType(DashboardScreen)));
}

void main() {
  testWidgets('unexpected page format: recoverable error with Retry, NOT a logout, session preserved', (tester) async {
    final auth = _FakeAuthRepository();
    final container = await pump(
      tester,
      auth: auth,
      repo: _SequenceDashboardRepository([const Failed(PageFormatChangedFailure())]),
    );

    expect(find.text(const PageFormatChangedFailure().message), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('session has expired'), findsNothing);
    expect(auth.logoutCallCount, 0);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
  });

  testWidgets('Retry re-fetches and recovers once the page parses', (tester) async {
    final auth = _FakeAuthRepository();
    final repo = _SequenceDashboardRepository([const Failed(PageFormatChangedFailure()), Success(data())]);
    await pump(tester, auth: auth, repo: repo);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await settle(tester);

    expect(repo.calls, 2);
    expect(find.text('Retry'), findsNothing);
    expect(find.text('5'), findsOneWidget); // total activities tile
    expect(auth.logoutCallCount, 0);
  });

  testWidgets('a role mismatch (Forbidden) shows its own message with Retry and does not log out', (tester) async {
    final auth = _FakeAuthRepository();
    await pump(
      tester,
      auth: auth,
      repo: _SequenceDashboardRepository([const Failed(ForbiddenFailure('Wrong portal'))]),
    );

    expect(find.text('Wrong portal'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(auth.logoutCallCount, 0);
  });

  testWidgets('confirmed session expiry still follows the existing recovery (logout)', (tester) async {
    final auth = _FakeAuthRepository();
    await pump(tester, auth: auth, repo: _SequenceDashboardRepository([const Failed(UnauthorizedFailure())]));
    expect(auth.logoutCallCount, 1);
  });

  for (final failure in <Failure>[const NetworkFailure(), const ServerFailure(), const TimeoutFailure()]) {
    testWidgets('${failure.runtimeType} shows Retry without logging out', (tester) async {
      final auth = _FakeAuthRepository();
      await pump(tester, auth: auth, repo: _SequenceDashboardRepository([Failed(failure)]));
      expect(find.text(failure.message), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(auth.logoutCallCount, 0);
    });
  }

  testWidgets('the error state keeps the nav drawer reachable (existing dead-end fix)', (tester) async {
    await pump(
      tester,
      auth: _FakeAuthRepository(),
      repo: _SequenceDashboardRepository([const Failed(PageFormatChangedFailure())]),
    );
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await settle(tester);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('error view renders in dark mode too', (tester) async {
    await pump(
      tester,
      auth: _FakeAuthRepository(),
      repo: _SequenceDashboardRepository([const Failed(PageFormatChangedFailure())]),
      mode: ThemeMode.dark,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CB 3.0 data labels the Completed tile "Fully Attempted"', (tester) async {
    await pump(
      tester,
      auth: _FakeAuthRepository(),
      repo: _SequenceDashboardRepository([Success(data(generation: DashboardMarkupGeneration.cb3))]),
    );
    expect(find.text('Fully Attempted'), findsOneWidget);
    expect(find.text('Completed'), findsNothing);
  });

  testWidgets('legacy data keeps the "Completed" tile label', (tester) async {
    await pump(
      tester,
      auth: _FakeAuthRepository(),
      repo: _SequenceDashboardRepository([Success(data(generation: DashboardMarkupGeneration.legacy))]),
    );
    expect(find.text('Completed'), findsOneWidget);
  });

  testWidgets('dashboard renders an empty activity list with the existing empty-state copy', (tester) async {
    await pump(tester, auth: _FakeAuthRepository(), repo: _SequenceDashboardRepository([Success(data())]));
    expect(find.text('No activities started yet.'), findsOneWidget);
  });
}
