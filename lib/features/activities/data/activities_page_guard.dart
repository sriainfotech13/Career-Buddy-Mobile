import '../../../core/errors/exceptions.dart';
import '../../../core/network/html_response_classifier.dart';
import '../domain/activity_access_messages.dart';
export '../domain/activity_access_messages.dart';

/// Applies the shared Phase 89 classifier (`classifyHtmlPage`) to a fetched
/// activities HTML page and parses it, so each outcome maps to its own
/// exception instead of every parse failure becoming
/// [UnauthorizedException] (which logs the user out):
/// - confirmed login redirect / HTTP 401 → [UnauthorizedException]
///   (the existing session-expired recovery);
/// - HTTP 403 → [ForbiddenException];
/// - employer/recruiter portal landing → [ForbiddenException] (valid session,
///   wrong role — never a logout);
/// - a page that is neither the expected one nor login/role evidence, or an
///   expected page whose structure can't be parsed →
///   [PageFormatChangedException] (recoverable with Retry, session kept).
///
/// A thin adapter: the classifier itself is reused unchanged.
T parseActivitiesPage<T>({
  required int? statusCode,
  required Uri? finalUri,
  required String body,
  required bool Function(String body) isExpectedPage,
  required T Function(String body) parse,
}) {
  final classification = classifyHtmlPage(
    statusCode: statusCode,
    finalUri: finalUri,
    body: body,
    isExpectedPage: isExpectedPage,
  );
  switch (classification) {
    case HtmlLoginRequired():
      throw const UnauthorizedException();
    case HtmlAccessDenied():
      throw const ForbiddenException();
    case HtmlRoleMismatch():
      throw const ForbiddenException(activityRoleMismatchMessage);
    case HtmlUnexpectedFormat():
      throw const PageFormatChangedException();
    case HtmlPageRecognized():
      try {
        return parse(body);
      } on FormatException {
        throw const PageFormatChangedException();
      }
  }
}

/// What a redirect `Location` (when redirects are not followed) means for an
/// activities request. Mirrors the classifier's evidence rules: only the login
/// URL is a login; employer/recruiter portals are role mismatches; the locked
/// page is the plan upgrade prompt.
enum ActivitiesRedirectKind { login, locked, roleMismatch, other }

ActivitiesRedirectKind classifyActivitiesRedirect(String location) {
  final path = Uri.tryParse(location)?.path ?? location;
  if (path.startsWith('/users/login')) return ActivitiesRedirectKind.login;
  if (location.contains('locked=1')) return ActivitiesRedirectKind.locked;
  if (path.startsWith('/employer-home') || path.startsWith('/employer/') || path.startsWith('/recruiter/')) {
    return ActivitiesRedirectKind.roleMismatch;
  }
  return ActivitiesRedirectKind.other;
}
