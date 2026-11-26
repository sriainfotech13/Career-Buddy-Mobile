import 'dart:io';

import 'package:career_buddy_lms/core/errors/failures.dart';
import 'package:career_buddy_lms/core/network/api_client.dart';
import 'package:career_buddy_lms/core/network/api_exceptions_interceptor.dart';
import 'package:career_buddy_lms/core/utils/result.dart';
import 'package:career_buddy_lms/features/activities/data/datasources/activities_remote_datasource.dart';
import 'package:career_buddy_lms/features/activities/data/repositories/activities_repository_impl.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http_client_adapter.dart';

/// Phase 90 — failure mapping through the repository: a parser/format problem
/// must surface as `PageFormatChangedFailure` (recoverable), never as
/// `UnauthorizedFailure` (which logs the user out). Offline fake adapter.
String fixture(String name) => File('test/fixtures/activities/$name').readAsStringSync();

ActivitiesRepositoryImpl repo(int status, String body, {Uri? finalUri}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = FakeHttpClientAdapter(statusCode: status, body: body, finalUri: finalUri)
    ..interceptors.add(ApiExceptionsInterceptor());
  return ActivitiesRepositoryImpl(ActivitiesRemoteDataSource(ApiClient.forTesting(dio)));
}

void main() {
  test('a recognised CB 3.0 sub-activity page is a Success carrying the requested id', () async {
    final result = await repo(200, fixture('sub_cb3_partial.html')).getSubActivityDetail(4, 35);
    expect(result, isA<Success>());
    expect((result as Success).value.id, 35);
  });

  test('unexpected HTML maps to PageFormatChangedFailure, not UnauthorizedFailure', () async {
    final result = await repo(200, '<html><body>maintenance</body></html>').getActivityList();
    final failure = (result as Failed).failure;
    expect(failure, isA<PageFormatChangedFailure>());
    expect(failure, isNot(isA<UnauthorizedFailure>()));
  });

  test('a confirmed login redirect maps to UnauthorizedFailure', () async {
    final result = await repo(
      200,
      '<form id="login-form"></form>',
      finalUri: Uri.parse('http://test/users/login/'),
    ).getActivityList();
    expect((result as Failed).failure, isA<UnauthorizedFailure>());
  });

  test('HTTP 403 maps to ForbiddenFailure', () async {
    final result = await repo(403, '').getActivityList();
    expect((result as Failed).failure, isA<ForbiddenFailure>());
  });

  test('invalid ids surface as NotFoundFailure without a request', () async {
    final result = await repo(200, '').getSubActivityDetail(4, -1);
    expect((result as Failed).failure, isA<NotFoundFailure>());
  });

  test('markSubComplete with the old -1 sentinel is a failure, not a request', () async {
    final result = await repo(302, '').markSubComplete(-1);
    expect((result as Failed).failure, isA<UnexpectedFailure>());
  });
}
