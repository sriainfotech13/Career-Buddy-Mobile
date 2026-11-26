/// Classifies a fetched server-rendered HTML page *before* a page-specific
/// parser runs, so "the markup changed" is never confused with "the session
/// expired". The backend is a Django site that answers an unauthenticated
/// request with a 302 to `/users/login/?next=...` (which Dio follows, so the
/// final response is a 200 login page whose `realUri` is the login URL) and a
/// wrong-role session with a 302 to the other portal's home/login — see
/// `CB_3.0/backend/apps/core/portal_access.py:98-103,159-176` and
/// `config/settings/base.py` (`LOGIN_URL`). Non-2xx statuses normally never
/// reach this function because `ApiExceptionsInterceptor` rejects them first;
/// 401/403 are still handled here so the function is safe to reuse.
///
/// This is pure (no Dio/Flutter dependency) so it can be unit-tested against
/// source-derived fixtures. It is evidence-based: only the final URL path, the
/// HTTP status and a few login-form markers read from `users/login.html`
/// count as evidence of a login redirect — a parser failure alone never does.
sealed class HtmlPageClassification {
  const HtmlPageClassification();
}

/// The caller's expected-page marker is present: hand the body to the parser.
final class HtmlPageRecognized extends HtmlPageClassification {
  const HtmlPageRecognized();
}

/// Confirmed unauthenticated: login URL reached, HTTP 401, or the login form.
final class HtmlLoginRequired extends HtmlPageClassification {
  const HtmlLoginRequired(this.reason);
  final String reason;
}

/// Authenticated but landed on another portal (employer/recruiter) — the
/// student-only page redirected away. Session is valid; not an expiry.
final class HtmlRoleMismatch extends HtmlPageClassification {
  const HtmlRoleMismatch(this.finalPath);
  final String finalPath;
}

/// HTTP 403 (or equivalent): access denied for this session.
final class HtmlAccessDenied extends HtmlPageClassification {
  const HtmlAccessDenied();
}

/// 200 HTML that is neither the expected page nor evidence of a login/role
/// redirect: an unsupported or changed page format (or an error page).
final class HtmlUnexpectedFormat extends HtmlPageClassification {
  const HtmlUnexpectedFormat(this.reason);
  final String reason;
}

/// Path prefixes a *student-only* page redirects a wrong-role session to.
const _roleMismatchPrefixes = ['/employer-home', '/employer/', '/recruiter/'];

/// Login page path prefix (`LOGIN_URL = /users/login/`).
const _loginPathPrefix = '/users/login';

HtmlPageClassification classifyHtmlPage({
  required int? statusCode,
  required Uri? finalUri,
  required String body,
  required bool Function(String body) isExpectedPage,
}) {
  if (statusCode == 401) return const HtmlLoginRequired('HTTP 401');
  if (statusCode == 403) return const HtmlAccessDenied();

  if (isExpectedPage(body)) return const HtmlPageRecognized();

  final path = finalUri?.path ?? '';
  if (path.startsWith(_loginPathPrefix)) {
    return HtmlLoginRequired('redirected to $path');
  }

  // Role/portal landing pages are checked BEFORE any body heuristics: a
  // valid employer/recruiter session can land on pages (e.g. the recruiter
  // forced set-password page) that carry the same `auth-form` class and CSRF
  // token as a login form, and must never be read as an expired session.
  for (final prefix in _roleMismatchPrefixes) {
    if (path.startsWith(prefix)) return HtmlRoleMismatch(path);
  }

  if (_looksLikeLoginForm(body)) {
    return const HtmlLoginRequired('login form in body');
  }

  return HtmlUnexpectedFormat(
    path.isEmpty ? 'expected page marker not found' : 'expected page marker not found at $path',
  );
}

/// Body-level evidence of a *sign-in* page, used only when no URL evidence
/// exists. Deliberately strict so an unrelated form that merely contains a
/// password field (registration, change/set-password, activation) is never
/// mistaken for a login page:
/// - the legacy `id="login-form"` marker; or
/// - the real sign-in form (`users/login.html:32,61-68`,
///   `employer_auth/login.html`): `class="auth-form"` + a CSRF token + BOTH a
///   `username` field AND a plain `password` field, and none of the
///   set/confirm/temporary-password fields the recruiter set-password and
///   activation pages use (`recruiter_set_password.html:63,83`,
///   `recruiter_activate.html:60,70,85`).
bool _looksLikeLoginForm(String body) {
  if (body.contains('id="login-form"')) return true;
  if (!RegExp(r'class\s*=\s*["\x27]auth-form["\x27]').hasMatch(body)) return false;
  if (!body.contains('csrfmiddlewaretoken')) return false;
  if (RegExp(
    r'name\s*=\s*["\x27](new_password\d?|confirm_password|temporary_password|password[12])["\x27]',
  ).hasMatch(body)) {
    return false;
  }
  final hasUsername = RegExp(r'name\s*=\s*["\x27]username["\x27]').hasMatch(body);
  final hasPassword = RegExp(r'name\s*=\s*["\x27]password["\x27]').hasMatch(body);
  return hasUsername && hasPassword;
}
