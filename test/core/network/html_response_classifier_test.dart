import 'dart:io';

import 'package:career_buddy_lms/core/network/html_response_classifier.dart';
import 'package:career_buddy_lms/features/dashboard/data/dashboard_html_parser.dart';
import 'package:flutter_test/flutter_test.dart';

String fixture(String name) => File('test/fixtures/dashboard/$name').readAsStringSync();

HtmlPageClassification classify({int? status = 200, String? path, String body = '', bool Function(String)? expected}) {
  return classifyHtmlPage(
    statusCode: status,
    finalUri: path == null ? null : Uri.parse('https://example.test$path'),
    body: body,
    isExpectedPage: expected ?? isDashboardHtml,
  );
}

void main() {
  group('classifyHtmlPage', () {
    test('legacy dashboard HTML is recognised', () {
      expect(
        classify(body: fixture('dashboard_legacy_subactivities.html'), path: '/dashboard/'),
        isA<HtmlPageRecognized>(),
      );
    });

    test('CB 3.0 dashboard HTML is recognised', () {
      expect(classify(body: fixture('dashboard_cb3_scores.html'), path: '/dashboard/'), isA<HtmlPageRecognized>());
    });

    test('an authentication redirect (final URL /users/login/) is a confirmed login requirement', () {
      final c = classify(body: fixture('dashboard_login_redirect.html'), path: '/users/login/');
      expect(c, isA<HtmlLoginRequired>());
    });

    test('the login URL alone is enough evidence, even with an unfamiliar body', () {
      expect(classify(body: '<html></html>', path: '/users/login/'), isA<HtmlLoginRequired>());
    });

    test('the real login form body is login evidence even without a redirect URL', () {
      expect(classify(body: fixture('dashboard_login_redirect.html')), isA<HtmlLoginRequired>());
    });

    test('the legacy login-form marker is login evidence', () {
      expect(classify(body: '<form id="login-form"></form>'), isA<HtmlLoginRequired>());
    });

    test('HTTP 401 is a login requirement', () {
      expect(classify(status: 401), isA<HtmlLoginRequired>());
    });

    test('HTTP 403 is access denied (not an expired session)', () {
      expect(classify(status: 403), isA<HtmlAccessDenied>());
    });

    test('an employer-portal redirect is a role mismatch, not a session expiry', () {
      final c = classify(body: fixture('dashboard_employer_redirect.html'), path: '/employer-home/');
      expect(c, isA<HtmlRoleMismatch>());
      expect((c as HtmlRoleMismatch).finalPath, '/employer-home/');
    });

    test('a recruiter-portal landing is also a role mismatch', () {
      expect(classify(body: '<html></html>', path: '/recruiter/dashboard/'), isA<HtmlRoleMismatch>());
    });

    test(
      'unexpected HTML (no marker, no login/role evidence) is an unsupported format — never a login requirement',
      () {
        final c = classify(body: fixture('dashboard_unknown_page.html'), path: '/dashboard/');
        expect(c, isA<HtmlUnexpectedFormat>());
      },
    );

    test('empty body at the expected URL is an unexpected format, not a login requirement', () {
      expect(classify(body: '', path: '/dashboard/'), isA<HtmlUnexpectedFormat>());
    });

    test('the expected-page marker wins over URL heuristics', () {
      expect(classify(body: fixture('dashboard_cb3_scores.html'), path: '/employer/x/'), isA<HtmlPageRecognized>());
    });
  });

  group('final review regressions — unrelated password forms must never read as a login', () {
    // Shapes taken from employer_auth/recruiter_set_password.html:58-83 and
    // recruiter_activate.html:56-85 (sanitized).
    const recruiterSetPassword = '''
<form method="post" class="auth-form">
  <input type="hidden" name="csrfmiddlewaretoken" value="FIXTURE_TOKEN">
  <input type="password" id="spNew" name="new_password" autocomplete="new-password">
  <input type="password" id="spConfirm" name="confirm_password" autocomplete="new-password">
</form>''';
    const recruiterActivate = '''
<form method="post" class="auth-form">
  <input type="hidden" name="csrfmiddlewaretoken" value="FIXTURE_TOKEN">
  <input type="password" name="temporary_password">
  <input type="password" name="new_password">
  <input type="password" name="confirm_password">
</form>''';

    test('the recruiter forced set-password page at a /recruiter/ URL is a role mismatch, not a login', () {
      final c = classify(body: recruiterSetPassword, path: '/recruiter/set-password/');
      expect(c, isA<HtmlRoleMismatch>());
    });

    test('role/portal URL wins over a login-shaped body (valid session is never treated as expired)', () {
      expect(
        classify(body: fixture('dashboard_login_redirect.html'), path: '/recruiter/dashboard/'),
        isA<HtmlRoleMismatch>(),
      );
    });

    test('the set-password form alone (no URL evidence) is NOT login evidence', () {
      expect(classify(body: recruiterSetPassword), isA<HtmlUnexpectedFormat>());
    });

    test('the recruiter activation form alone is NOT login evidence', () {
      expect(classify(body: recruiterActivate), isA<HtmlUnexpectedFormat>());
    });

    test('a registration/profile-like form with password fields and a CSRF token is NOT login evidence', () {
      const register = '''
<form method="post" class="auth-form">
  <input type="hidden" name="csrfmiddlewaretoken" value="x">
  <input type="text" name="username"><input type="password" name="password1"><input type="password" name="password2">
</form>''';
      expect(classify(body: register), isA<HtmlUnexpectedFormat>());
    });

    test('a bare password field without the sign-in shape is NOT login evidence', () {
      expect(
        classify(body: '<form class="auth-form"><input type="password" name="password"></form>'),
        isA<HtmlUnexpectedFormat>(),
      );
    });

    test('the real sign-in form is still login evidence regardless of attribute order', () {
      const signIn = '''
<form method="post" class="auth-form">
  <input type="hidden" name="csrfmiddlewaretoken" value="x">
  <input name="username" type="text"><input name="password" type="password">
</form>''';
      expect(classify(body: signIn), isA<HtmlLoginRequired>());
    });
  });
}
