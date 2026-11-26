import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:career_buddy_lms/core/errors/exceptions.dart';
import 'package:career_buddy_lms/core/network/api_client.dart';
import 'package:career_buddy_lms/core/network/api_exceptions_interceptor.dart';
import 'package:career_buddy_lms/features/activities/data/datasources/activities_remote_datasource.dart';
import 'package:career_buddy_lms/features/activities/domain/activity_access_messages.dart';
import 'package:career_buddy_lms/features/activities/domain/entities/activity_progress_semantics.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 90 — activities data source: shared-classifier integration, id
/// guards (no HTTP for invalid ids), single-category redirect, legacy-only
/// completion. OFFLINE tests with a fake HTTP adapter — nothing here talks to
/// a real server and none of it proves deployed-backend compatibility.
String fixture(String name) => File('test/fixtures/activities/$name').readAsStringSync();
String dashFixture(String name) => File('test/fixtures/dashboard/$name').readAsStringSync();

class FakeResp {
  const FakeResp(this.status, {this.body = '', this.location, this.finalPath});
  final int status;
  final String body;
  final String? location;
  final String? finalPath;
}

/// Records every request and answers from [respond].
class RecordingAdapter implements HttpClientAdapter {
  RecordingAdapter(this.respond);
  final FakeResp Function(RequestOptions options) respond;
  final List<String> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add('${options.method} ${options.uri.path}${options.uri.hasQuery ? '?${options.uri.query}' : ''}');
    final r = respond(options);
    return ResponseBody(
      Stream.value(Uint8List.fromList(utf8.encode(r.body))),
      r.status,
      headers: {
        if (r.location != null) 'location': [r.location!],
        'content-type': ['text/html'],
      },
      redirects: r.finalPath == null
          ? null
          : [RedirectRecord(302, options.method, Uri.parse('http://test${r.finalPath}'))],
    );
  }

  @override
  void close({bool force = false}) {}
}

({ActivitiesRemoteDataSource ds, RecordingAdapter adapter}) make(FakeResp Function(RequestOptions) respond) {
  final adapter = RecordingAdapter(respond);
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = adapter
    ..interceptors.add(ApiExceptionsInterceptor());
  return (ds: ActivitiesRemoteDataSource(ApiClient.forTesting(dio)), adapter: adapter);
}

({ActivitiesRemoteDataSource ds, RecordingAdapter adapter}) one(FakeResp r) => make((_) => r);

Future<Object?> thrownBy(Future<Object?> Function() call) async {
  try {
    await call();
  } catch (e) {
    return e;
  }
  return null;
}

void main() {
  group('list page', () {
    test('legacy list parses', () async {
      final t = one(FakeResp(200, body: fixture('list_legacy.html')));
      expect((await t.ds.getActivityList()).activities, hasLength(3));
    });

    test('CB 3.0 list parses', () async {
      final t = one(FakeResp(200, body: fixture('list_cb3.html')));
      final data = await t.ds.getActivityList();
      expect(data.activities.first.progressSemantics, ActivityProgressSemantics.score);
    });

    test('an empty list page is valid (empty list), not an error', () async {
      final t = one(FakeResp(200, body: fixture('list_empty.html')));
      expect((await t.ds.getActivityList()).activities, isEmpty);
    });

    test('a followed login redirect (final URL /users/login/) is confirmed session expiry', () async {
      final t = one(FakeResp(200, body: dashFixture('dashboard_login_redirect.html'), finalPath: '/users/login/'));
      expect(await thrownBy(t.ds.getActivityList), isA<UnauthorizedException>());
    });

    test('HTTP 401 is session expiry', () async {
      expect(await thrownBy(one(const FakeResp(401)).ds.getActivityList), isA<UnauthorizedException>());
    });

    test('HTTP 403 is access denied, never session expiry', () async {
      final e = await thrownBy(one(const FakeResp(403)).ds.getActivityList);
      expect(e, isA<ForbiddenException>());
      expect(e, isNot(isA<UnauthorizedException>()));
    });

    test('an employer-portal landing is a role mismatch (Forbidden), not session expiry', () async {
      final t = one(FakeResp(200, body: dashFixture('dashboard_employer_redirect.html'), finalPath: '/employer-home/'));
      final e = await thrownBy(t.ds.getActivityList);
      expect(e, isA<ForbiddenException>().having((x) => x.message, 'message', activityRoleMismatchMessage));
    });

    test('unexpected HTML throws PageFormatChangedException, never UnauthorizedException', () async {
      final t = one(FakeResp(200, body: dashFixture('dashboard_unknown_page.html')));
      final e = await thrownBy(t.ds.getActivityList);
      expect(e, isA<PageFormatChangedException>());
      expect(e, isNot(isA<UnauthorizedException>()));
    });

    test(
      'the recruiter forced set-password page is NOT mistaken for a login form (Phase 89 regression kept)',
      () async {
        const body =
            '<form method="post" class="auth-form"><input type="hidden" name="csrfmiddlewaretoken" value="x">'
            '<input type="password" name="new_password"><input type="password" name="confirm_password"></form>';
        final viaUrl = await thrownBy(
          one(FakeResp(200, body: body, finalPath: '/recruiter/set-password/')).ds.getActivityList,
        );
        expect(viaUrl, isA<ForbiddenException>());
        final bodyOnly = await thrownBy(one(const FakeResp(200, body: body)).ds.getActivityList);
        expect(bodyOnly, isA<PageFormatChangedException>());
      },
    );

    test('an unrelated registration-style password form is not a login', () async {
      const body =
          '<form class="auth-form"><input type="hidden" name="csrfmiddlewaretoken" value="x">'
          '<input name="username"><input type="password" name="password1"><input type="password" name="password2"></form>';
      expect(
        await thrownBy(one(const FakeResp(200, body: body)).ds.getActivityList),
        isA<PageFormatChangedException>(),
      );
    });

    test('a list page whose structure changed is a recoverable format change', () async {
      final changed = fixture('list_cb3.html').replaceAll('activities-page', 'renamed-page');
      expect(await thrownBy(one(FakeResp(200, body: changed)).ds.getActivityList), isA<PageFormatChangedException>());
    });

    test('server errors and network failures keep their own exception types', () async {
      expect(await thrownBy(one(const FakeResp(500)).ds.getActivityList), isA<ServerException>());
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = ThrowingAdapter()
        ..interceptors.add(ApiExceptionsInterceptor());
      expect(
        await thrownBy(ActivitiesRemoteDataSource(ApiClient.forTesting(dio)).getActivityList),
        isA<NetworkUnavailableException>(),
      );
    });

    test('workshop list uses the same classifier (login → Unauthorized, odd page → format changed)', () async {
      expect(
        await thrownBy(
          one(
            FakeResp(200, body: dashFixture('dashboard_login_redirect.html'), finalPath: '/users/login/'),
          ).ds.getWorkshopModules,
        ),
        isA<UnauthorizedException>(),
      );
      expect(
        await thrownBy(one(FakeResp(200, body: dashFixture('dashboard_unknown_page.html'))).ds.getWorkshopModules),
        isA<PageFormatChangedException>(),
      );
    });
  });

  group('single-category redirect (list → 302 → detail)', () {
    test('a category redirect to a real activity no longer reads as "session expired"', () async {
      final t = make((o) {
        if (o.uri.path == '/activities/' && o.uri.hasQuery) {
          return const FakeResp(302, location: '/activities/13/');
        }
        return FakeResp(200, body: fixture('list_cb3.html'));
      });
      final data = await t.ds.getActivityList(category: 'speaking');
      expect(data.activities.single.id, 13);
      expect(data.selectedCategory, 'speaking');
      expect(data.categories, isNotEmpty);
    });

    test('an activity missing from the full list is rebuilt from its real detail page', () async {
      final t = make((o) {
        if (o.uri.path == '/activities/' && o.uri.hasQuery) return const FakeResp(302, location: '/activities/4/');
        if (o.uri.path == '/activities/') return FakeResp(200, body: fixture('list_empty.html'));
        return FakeResp(200, body: fixture('detail_cb3.html'));
      });
      final data = await t.ds.getActivityList(category: 'vocabulary');
      expect(data.activities.single.id, 4);
      expect(data.activities.single.title, 'Business Vocabulary');
      expect(data.activities.single.progressSemantics, ActivityProgressSemantics.score);
      expect(data.activities.single.attemptedExercises, 5);
    });

    test('a category redirect to the login page is session expiry', () async {
      final t = one(const FakeResp(302, location: '/users/login/?next=/activities/'));
      expect(await thrownBy(() => t.ds.getActivityList(category: 'speaking')), isA<UnauthorizedException>());
    });

    test('a category redirect to an employer portal is a role mismatch (no logout)', () async {
      final t = one(const FakeResp(302, location: '/employer-home/'));
      expect(await thrownBy(() => t.ds.getActivityList(category: 'speaking')), isA<ForbiddenException>());
    });

    test('a category redirect somewhere unrecognised is a recoverable unexpected response', () async {
      final t = one(const FakeResp(302, location: '/gd/'));
      final e = await thrownBy(() => t.ds.getActivityList(category: 'workshop'));
      expect(e, isA<UnexpectedResponseException>());
      expect(e, isNot(isA<UnauthorizedException>()));
    });
  });

  group('final review — single-category redirect destinations', () {
    for (final location in [
      '/activities/exercise/37/',
      '/activities/4/sub/35/',
      '/activities/?locked=0',
      'https://evil.example/activities/13/',
    ]) {
      test('a redirect to "$location" is NOT accepted as an activity detail', () async {
        final t = make((o) => FakeResp(302, location: location));
        final e = await thrownBy(() => t.ds.getActivityList(category: 'speaking'));
        expect(e, isA<UnexpectedResponseException>());
        expect(e, isNot(isA<UnauthorizedException>()));
        // Nothing but the single category request was sent.
        expect(t.adapter.requests, hasLength(1));
      });
    }

    test('a recruiter-portal redirect is a role mismatch (Forbidden), never an activity', () async {
      final t = one(const FakeResp(302, location: '/recruiter/dashboard/'));
      expect(await thrownBy(() => t.ds.getActivityList(category: 'speaking')), isA<ForbiddenException>());
    });

    test('a same-site absolute URL to a real activity is accepted', () async {
      final t = make((o) {
        if (o.uri.path == '/activities/' && o.uri.hasQuery) {
          return const FakeResp(302, location: 'http://test/activities/13/');
        }
        return FakeResp(200, body: fixture('list_cb3.html'));
      });
      expect((await t.ds.getActivityList(category: 'speaking')).activities.single.id, 13);
    });
  });

  group('activity detail', () {
    test('CB 3.0 detail parses (score semantics)', () async {
      final t = one(FakeResp(200, body: fixture('detail_cb3.html')));
      final d = await t.ds.getActivityDetail(4);
      expect(d.progressSemantics, ActivityProgressSemantics.score);
      expect(d.subActivities, hasLength(3));
    });

    test('legacy detail parses (completion semantics)', () async {
      final t = one(FakeResp(200, body: fixture('detail_legacy.html')));
      expect((await t.ds.getActivityDetail(4)).progressSemantics, ActivityProgressSemantics.completion);
    });

    test('id 0 is rejected with NotFound and NO request is sent', () async {
      final t = one(const FakeResp(200));
      expect(await thrownBy(() => t.ds.getActivityDetail(0)), isA<NotFoundException>());
      expect(t.adapter.requests, isEmpty);
    });

    test('a negative synthetic id never appears in a request path; only the list is fetched', () async {
      final t = one(FakeResp(200, body: fixture('list_cb3.html')));
      final id = (await t.ds.getActivityList()).activities.firstWhere((a) => a.title == 'Group Discussion').id;
      t.adapter.requests.clear();
      final d = await t.ds.getActivityDetail(id);
      expect(d.title, 'Group Discussion');
      expect(t.adapter.requests, ['GET /activities/']);
      expect(t.adapter.requests.any((r) => r.contains('-')), isFalse);
    });

    test('Location redirects: login → Unauthorized; locked → Forbidden(upgrade); role → Forbidden(role)', () async {
      expect(
        await thrownBy(
          () => one(const FakeResp(302, location: '/users/login/?next=/activities/4/')).ds.getActivityDetail(4),
        ),
        isA<UnauthorizedException>(),
      );
      expect(
        await thrownBy(() => one(const FakeResp(302, location: '/activities/?locked=1')).ds.getActivityDetail(4)),
        isA<ForbiddenException>().having((e) => e.message, 'message', activityLockedMessage),
      );
      expect(
        await thrownBy(() => one(const FakeResp(302, location: '/employer-home/')).ds.getActivityDetail(4)),
        isA<ForbiddenException>().having((e) => e.message, 'message', activityRoleMismatchMessage),
      );
    });

    test('unexpected HTML on a 200 is a format change; a changed detail page too', () async {
      expect(
        await thrownBy(
          () => one(FakeResp(200, body: dashFixture('dashboard_unknown_page.html'))).ds.getActivityDetail(4),
        ),
        isA<PageFormatChangedException>(),
      );
      final changed = fixture('detail_cb3.html').replaceAll('activity-detail-page', 'renamed');
      expect(
        await thrownBy(() => one(FakeResp(200, body: changed)).ds.getActivityDetail(4)),
        isA<PageFormatChangedException>(),
      );
    });

    test('HTTP 403 and a login body are classified (Forbidden / Unauthorized)', () async {
      expect(await thrownBy(() => one(const FakeResp(403)).ds.getActivityDetail(4)), isA<ForbiddenException>());
      expect(
        await thrownBy(
          () => one(FakeResp(200, body: dashFixture('dashboard_login_redirect.html'))).ds.getActivityDetail(4),
        ),
        isA<UnauthorizedException>(),
      );
    });
  });

  group('sub-activity detail', () {
    test('CB 3.0 sub page carries the REQUESTED id (35), not a sentinel', () async {
      final t = one(FakeResp(200, body: fixture('sub_cb3_partial.html')));
      final d = await t.ds.getSubActivityDetail(4, 35);
      expect(d.id, 35);
      expect(t.adapter.requests, ['GET /activities/4/sub/35/']);
    });

    test('non-positive ids send NO request', () async {
      for (final ids in [(0, 35), (4, 0), (-1, 35), (4, -1)]) {
        final t = one(const FakeResp(200));
        expect(await thrownBy(() => t.ds.getSubActivityDetail(ids.$1, ids.$2)), isA<NotFoundException>());
        expect(t.adapter.requests, isEmpty, reason: 'ids $ids');
      }
    });

    test('Location redirects: login / locked / role; any other redirect is unexpected (never a logout)', () async {
      expect(
        await thrownBy(() => one(const FakeResp(302, location: '/users/login/')).ds.getSubActivityDetail(4, 35)),
        isA<UnauthorizedException>(),
      );
      expect(
        await thrownBy(
          () => one(const FakeResp(302, location: '/activities/?locked=1')).ds.getSubActivityDetail(4, 35),
        ),
        isA<ForbiddenException>(),
      );
      expect(
        await thrownBy(
          () => one(const FakeResp(302, location: '/recruiter/dashboard/')).ds.getSubActivityDetail(4, 35),
        ),
        isA<ForbiddenException>(),
      );
      final other = await thrownBy(() => one(const FakeResp(302, location: '/gd/')).ds.getSubActivityDetail(4, 35));
      expect(other, isA<UnexpectedResponseException>());
    });

    test('unexpected HTML and a login body are classified apart', () async {
      final odd = await thrownBy(
        () => one(FakeResp(200, body: dashFixture('dashboard_unknown_page.html'))).ds.getSubActivityDetail(4, 35),
      );
      expect(odd, isA<PageFormatChangedException>());
      final login = await thrownBy(
        () => one(FakeResp(200, body: dashFixture('dashboard_login_redirect.html'))).ds.getSubActivityDetail(4, 35),
      );
      expect(login, isA<UnauthorizedException>());
    });

    test('HTTP 403 and 500 map without logout', () async {
      expect(await thrownBy(() => one(const FakeResp(403)).ds.getSubActivityDetail(4, 35)), isA<ForbiddenException>());
      expect(await thrownBy(() => one(const FakeResp(500)).ds.getSubActivityDetail(4, 35)), isA<ServerException>());
    });
  });

  group('markSubComplete (legacy only)', () {
    test('the old -1 sentinel NEVER produces a request', () async {
      final t = one(const FakeResp(302));
      expect(await thrownBy(() => t.ds.markSubComplete(-1)), isA<UnexpectedResponseException>());
      expect(t.adapter.requests, isEmpty);
    });

    test('0 and other non-positive ids never produce a request', () async {
      final t = one(const FakeResp(302));
      for (final id in [0, -2, -999]) {
        expect(await thrownBy(() => t.ds.markSubComplete(id)), isA<UnexpectedResponseException>());
      }
      expect(t.adapter.requests, isEmpty);
    });

    test('a valid legacy id sends exactly one POST to the verified route', () async {
      final t = one(const FakeResp(302));
      await t.ds.markSubComplete(35);
      expect(t.adapter.requests, ['POST /activities/sub/35/complete/']);
    });
  });
}

class ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) {
    throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
  }

  @override
  void close({bool force = false}) {}
}
