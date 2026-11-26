import 'package:dio/dio.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/html_response_classifier.dart';
import '../../domain/entities/dashboard_data.dart';
import '../dashboard_html_parser.dart';

/// Scrapes the real, live `/dashboard/` HTML page — see
/// `ApiEndpoints.dashboard`'s doc comment for why this doesn't call the
/// JSON sibling it was originally written against (that endpoint exists in
/// source but was confirmed, live, not deployed to production, and is
/// absent from CB 3.0).
///
/// Every response is classified *before* parsing (`classifyHtmlPage`), so
/// each outcome maps to its own exception:
/// - confirmed login redirect / HTTP 401 → [UnauthorizedException] (the only
///   case that triggers the existing session-expired recovery);
/// - employer/recruiter portal redirect → [ForbiddenException] (valid
///   session, wrong role — never logs the user out);
/// - HTTP 403 → [ForbiddenException];
/// - a page that is neither the dashboard nor a login/role redirect, or a
///   dashboard whose structure can't be parsed → [PageFormatChangedException]
///   (recoverable with Retry; the session is left untouched);
/// - network/timeout/5xx → the existing interceptor exceptions.
class DashboardRemoteDataSource {
  DashboardRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<DashboardData> getDashboard() async {
    final Response<String> response;
    try {
      response = await _apiClient.dio.get<String>(
        ApiEndpoints.dashboardHtml,
        options: Options(responseType: ResponseType.plain),
      );
    } on DioException catch (e) {
      throw e.error is AppException ? e.error as AppException : const UnexpectedResponseException();
    }

    final html = response.data;
    if (html is! String) throw const UnexpectedResponseException();

    final classification = classifyHtmlPage(
      statusCode: response.statusCode,
      finalUri: response.realUri,
      body: html,
      isExpectedPage: isDashboardHtml,
    );
    switch (classification) {
      case HtmlLoginRequired():
        throw const UnauthorizedException();
      case HtmlAccessDenied():
        throw const ForbiddenException();
      case HtmlRoleMismatch():
        throw const ForbiddenException(
          'The student dashboard is not available for this account type. '
          'Please use the portal that matches your account.',
        );
      case HtmlUnexpectedFormat():
        throw const PageFormatChangedException();
      case HtmlPageRecognized():
        try {
          return parseDashboardHtml(html);
        } on FormatException {
          // The page IS the dashboard (marker present) but its structure
          // changed — not an expired session.
          throw const PageFormatChangedException();
        }
    }
  }
}
