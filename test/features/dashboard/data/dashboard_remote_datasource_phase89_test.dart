import 'dart:io';

import 'package:career_buddy_lms/core/errors/exceptions.dart';
import 'package:career_buddy_lms/core/network/api_client.dart';
import 'package:career_buddy_lms/core/network/api_exceptions_interceptor.dart';
import 'package:career_buddy_lms/features/dashboard/data/datasources/dashboard_remote_datasource.dart';
import 'package:career_buddy_lms/features/dashboard/domain/entities/dashboard_data.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_http_client_adapter.dart';

/// Phase 89 — the data source classifies the response before parsing, so a
/// parser/markup problem is never reported as an expired session. OFFLINE
/// fixture tests only (see `dashboard_html_parser_phase89_test.dart`).
String fixture(String name) => File('test/fixtures/dashboard/$name').readAsStringSync();

DashboardRemoteDataSource ds({required int status, required String body, String? finalPath}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = FakeHttpClientAdapter(
      statusCode: status,
      body: body,
      headers: const {
        'content-type': ['text/html'],
      },
      finalUri: finalPath == null ? null : Uri.parse('http://test$finalPath'),
    )
    ..interceptors.add(ApiExceptionsInterceptor());
  return DashboardRemoteDataSource(ApiClient.forTesting(dio));
}

void main() {
  test('legacy dashboard fixture parses through the data source', () async {
    final data = await ds(status: 200, body: fixture('dashboard_legacy_subactivities.html')).getDashboard();
    expect(data.generation, DashboardMarkupGeneration.legacy);
    expect(data.activities, hasLength(3));
  });

  test('CB 3.0 dashboard fixture parses through the data source', () async {
    final data = await ds(status: 200, body: fixture('dashboard_cb3_scores.html')).getDashboard();
    expect(data.generation, DashboardMarkupGeneration.cb3);
    expect(data.activities, hasLength(7));
  });

  test('a followed login redirect (final URL /users/login/) is confirmed session expiry', () async {
    expect(
      () => ds(status: 200, body: fixture('dashboard_login_redirect.html'), finalPath: '/users/login/').getDashboard(),
      throwsA(isA<UnauthorizedException>()),
    );
  });

  test('HTTP 401 is session expiry', () async {
    expect(() => ds(status: 401, body: '').getDashboard(), throwsA(isA<UnauthorizedException>()));
  });

  test('HTTP 403 is access denied (ForbiddenException), not session expiry', () async {
    expect(() => ds(status: 403, body: '').getDashboard(), throwsA(isA<ForbiddenException>()));
  });

  test('an employer-portal redirect is a role mismatch (Forbidden), NOT session expiry', () async {
    await expectLater(
      () => ds(
        status: 200,
        body: fixture('dashboard_employer_redirect.html'),
        finalPath: '/employer-home/',
      ).getDashboard(),
      throwsA(isA<ForbiddenException>()),
    );
  });

  test('unexpected HTML throws PageFormatChangedException, never UnauthorizedException', () async {
    Object? thrown;
    try {
      await ds(status: 200, body: fixture('dashboard_unknown_page.html'), finalPath: '/dashboard/').getDashboard();
    } catch (e) {
      thrown = e;
    }
    expect(thrown, isA<PageFormatChangedException>());
    expect(thrown, isNot(isA<UnauthorizedException>()));
  });

  test('an empty 200 body is a changed format, not a login requirement', () async {
    expect(
      () => ds(status: 200, body: '', finalPath: '/dashboard/').getDashboard(),
      throwsA(isA<PageFormatChangedException>()),
    );
  });

  test('a dashboard whose activity rows changed structure throws PageFormatChangedException', () async {
    final changed = fixture('dashboard_cb3_scores.html').replaceAll('progress-activity-link', 'renamed-link');
    expect(() => ds(status: 200, body: changed).getDashboard(), throwsA(isA<PageFormatChangedException>()));
  });

  test('server errors keep mapping through the existing interceptor', () async {
    expect(() => ds(status: 500, body: '').getDashboard(), throwsA(isA<ServerException>()));
    expect(() => ds(status: 404, body: '').getDashboard(), throwsA(isA<NotFoundException>()));
  });

  test('network failure keeps mapping to NetworkUnavailableException', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _ThrowingAdapter()
      ..interceptors.add(ApiExceptionsInterceptor());
    expect(
      () => DashboardRemoteDataSource(ApiClient.forTesting(dio)).getDashboard(),
      throwsA(isA<NetworkUnavailableException>()),
    );
  });

  test('final review: a recruiter set-password landing keeps the session (Forbidden, never Unauthorized)', () async {
    const body = '''
<form method="post" class="auth-form"><input type="hidden" name="csrfmiddlewaretoken" value="x">
<input type="password" name="new_password"><input type="password" name="confirm_password"></form>''';
    Object? thrown;
    try {
      await ds(status: 200, body: body, finalPath: '/recruiter/set-password/').getDashboard();
    } catch (e) {
      thrown = e;
    }
    expect(thrown, isA<ForbiddenException>());
    expect(thrown, isNot(isA<UnauthorizedException>()));
  });

  test('final review: a password-form body with no URL evidence is a format change, not an expired session', () async {
    const body =
        '<form class="auth-form"><input type="hidden" name="csrfmiddlewaretoken" value="x"><input type="password" name="new_password"></form>';
    expect(() => ds(status: 200, body: body).getDashboard(), throwsA(isA<PageFormatChangedException>()));
  });
}

class _ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) {
    throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
  }

  @override
  void close({bool force = false}) {}
}
