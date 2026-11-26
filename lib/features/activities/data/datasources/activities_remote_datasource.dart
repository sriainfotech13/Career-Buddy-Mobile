import 'package:dio/dio.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../domain/entities/activity_detail.dart';
import '../../domain/entities/activity_list_data.dart';
import '../../domain/entities/activity_progress_semantics.dart';
import '../../domain/entities/activity_summary.dart';
import '../../domain/entities/sub_activity_detail.dart';
import '../activities_html_parser.dart';
import '../activities_page_guard.dart';

/// Scrapes the real, live `/activities/...` HTML pages — see
/// `ApiEndpoints.activityList`'s doc comment for why this doesn't call the
/// JSON siblings it was originally written against (undeployed, and absent
/// from CB 3.0).
///
/// Phase 90: every page response goes through the shared HTML classifier
/// (`parseActivitiesPage`), so only confirmed login evidence triggers the
/// existing session-expired recovery; a changed/unexpected page is a
/// recoverable `PageFormatChangedException`; role/403 responses never log
/// the user out. **No request is ever sent with a non-positive id** (see the
/// per-method guards) — a negative id is only the synthetic list-card id of a
/// workshop/AI-module activity and is answered from the list parse.
class ActivitiesRemoteDataSource {
  ActivitiesRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<ActivityListData> getActivityList({String? category}) async {
    final hasCategory = category != null && category.isNotEmpty;
    try {
      final response = await _apiClient.dio.get<String>(
        ApiEndpoints.activityListHtml,
        queryParameters: hasCategory ? {'category': category} : null,
        options: hasCategory
            ? Options(responseType: ResponseType.plain, followRedirects: false, validateStatus: _is2xxOr3xx)
            : Options(responseType: ResponseType.plain),
      );

      // `?category=` with exactly ONE active activity makes the server answer
      // 302 → `/activities/<pk>/` instead of a list (`activities/views.py:
      // 548-551`). Previously that detail page was followed and then failed
      // to parse as a list, which surfaced as "session expired".
      if (hasCategory && response.statusCode != null && response.statusCode! >= 300) {
        return _singleActivityList(category, response.headers.value('location') ?? '');
      }

      final html = response.data;
      if (html is! String) throw const UnexpectedResponseException();
      return parseActivitiesPage(
        statusCode: response.statusCode,
        finalUri: response.realUri,
        body: html,
        isExpectedPage: isActivityListHtml,
        parse: parseActivityListHtml,
      );
    } on DioException catch (e) {
      throw e.error is AppException ? e.error as AppException : const UnexpectedResponseException();
    }
  }

  /// Handles the redirect answer to a category request. Only a redirect to a
  /// real `/activities/<id>/` detail page is understood; login/role/locked
  /// redirects map exactly as for the detail page; anything else is a
  /// recoverable unexpected response (never a logout).
  Future<ActivityListData> _singleActivityList(String category, String location) async {
    switch (classifyActivitiesRedirect(location)) {
      case ActivitiesRedirectKind.login:
        throw const UnauthorizedException();
      case ActivitiesRedirectKind.roleMismatch:
        throw const ForbiddenException(activityRoleMismatchMessage);
      case ActivitiesRedirectKind.locked:
        throw const ForbiddenException(activityLockedMessage);
      case ActivitiesRedirectKind.other:
        break;
    }
    // Only a same-site `/activities/<id>/` destination is a valid activity
    // detail: a redirect to another host, or to any other route (an exercise
    // page, a sub-activity, `/gd/`, ...), is never reinterpreted as one.
    final target = Uri.tryParse(location);
    final baseHost = Uri.tryParse(_apiClient.dio.options.baseUrl)?.host;
    if (target == null || (target.hasAuthority && target.host != baseHost)) {
      throw const UnexpectedResponseException();
    }
    final id = int.tryParse(RegExp(r'^/activities/(\d+)/?$').firstMatch(target.path)?.group(1) ?? '');
    if (id == null || id <= 0) throw const UnexpectedResponseException();

    // Categories (the filter chips) come from the unfiltered list so the user
    // can still switch category; the activity itself is that list's own card
    // when present, otherwise rebuilt from its real detail page.
    final all = await getActivityList();
    for (final summary in all.activities) {
      if (summary.id == id) {
        return ActivityListData(
          activities: [summary],
          categories: all.categories,
          selectedCategory: category,
          isFreePreview: all.isFreePreview,
          totalActivities: 1,
        );
      }
    }
    final detail = await getActivityDetail(id);
    final attempted = detail.attemptedExercises;
    final total = detail.totalExercises;
    final isScore = detail.progressSemantics == ActivityProgressSemantics.score;
    return ActivityListData(
      activities: [
        ActivitySummary(
          id: detail.id,
          title: detail.title,
          description: detail.description,
          category: category,
          categoryDisplay: detail.categoryDisplay,
          level: detail.level,
          duration: detail.duration,
          isLocked: false,
          completionRate: detail.completionRate,
          isCompleted: isScore
              ? (attempted != null && total != null && total > 0 && attempted >= total)
              : detail.completionRate == 100,
          progressSemantics: detail.progressSemantics,
          attemptedExercises: attempted,
          totalExercises: total,
          // Score mode: the ring prints the percentage alongside the counts;
          // without counts the score is not established.
          hasProgressPercent: isScore ? attempted != null : true,
        ),
      ],
      categories: all.categories,
      selectedCategory: category,
      isFreePreview: all.isFreePreview,
      totalActivities: 1,
    );
  }

  /// See `ApiEndpoints.workshopDashboardHtml`'s doc comment — the real,
  /// ungated `/activities/workshop/` page, not [getActivityList] with a
  /// `category` filter.
  Future<ActivityListData> getWorkshopModules() async {
    try {
      final response = await _apiClient.dio.get<String>(
        ApiEndpoints.workshopDashboardHtml,
        options: Options(responseType: ResponseType.plain),
      );
      final html = response.data;
      if (html is! String) throw const UnexpectedResponseException();
      return parseActivitiesPage(
        statusCode: response.statusCode,
        finalUri: response.realUri,
        body: html,
        isExpectedPage: isActivityListHtml,
        parse: parseActivityListHtml,
      );
    } on DioException catch (e) {
      throw e.error is AppException ? e.error as AppException : const UnexpectedResponseException();
    }
  }

  /// A negative [id] marks a workshop/AI-module activity with no real
  /// detail-page id (see `parseActivityListHtml`); nothing is requested for
  /// it — the list-derived fallback is used. `0` is never a valid id and is
  /// rejected without any request.
  Future<ActivityDetail> getActivityDetail(int id) async {
    if (id == 0) throw const NotFoundException();
    if (id < 0) return _activityDetailFallback(id);

    try {
      final response = await _apiClient.dio.get<String>(
        ApiEndpoints.activityDetailHtml(id),
        options: Options(responseType: ResponseType.plain, followRedirects: false, validateStatus: _is2xxOr3xx),
      );

      if (response.statusCode != null && response.statusCode! >= 300) {
        switch (classifyActivitiesRedirect(response.headers.value('location') ?? '')) {
          case ActivitiesRedirectKind.login:
            throw const UnauthorizedException();
          case ActivitiesRedirectKind.locked:
            throw const ForbiddenException(activityLockedMessage);
          case ActivitiesRedirectKind.roleMismatch:
            throw const ForbiddenException(activityRoleMismatchMessage);
          case ActivitiesRedirectKind.other:
            // `activity_detail` redirects away before rendering `detail.html`
            // for workshop/AI-module activities too — same list-derived
            // fallback as the negative-id case.
            return _activityDetailFallback(id);
        }
      }

      final html = response.data;
      if (html is! String) throw const UnexpectedResponseException();
      return parseActivitiesPage(
        statusCode: response.statusCode,
        finalUri: response.realUri,
        body: html,
        isExpectedPage: isActivityDetailHtml,
        parse: (body) => parseActivityDetailHtml(body, id: id),
      );
    } on DioException catch (e) {
      throw e.error is AppException ? e.error as AppException : const UnexpectedResponseException();
    }
  }

  Future<ActivityDetail> _activityDetailFallback(int id) async {
    final list = await getActivityList();
    for (final summary in list.activities) {
      if (summary.id == id) return activityDetailFromSummary(summary);
    }
    throw const NotFoundException();
  }

  /// Both ids must be positive real ids; otherwise nothing is requested.
  /// [subActivityId] (the requested route id) is passed to the parser so the
  /// result carries it — it is never re-derived from markup.
  Future<SubActivityDetail> getSubActivityDetail(int activityId, int subActivityId) async {
    if (activityId <= 0 || subActivityId <= 0) throw const NotFoundException();

    try {
      final response = await _apiClient.dio.get<String>(
        ApiEndpoints.subActivityDetailHtml(activityId, subActivityId),
        options: Options(responseType: ResponseType.plain, followRedirects: false, validateStatus: _is2xxOr3xx),
      );

      if (response.statusCode != null && response.statusCode! >= 300) {
        switch (classifyActivitiesRedirect(response.headers.value('location') ?? '')) {
          case ActivitiesRedirectKind.login:
            throw const UnauthorizedException();
          case ActivitiesRedirectKind.locked:
            throw const ForbiddenException(activityLockedMessage);
          case ActivitiesRedirectKind.roleMismatch:
            throw const ForbiddenException(activityRoleMismatchMessage);
          case ActivitiesRedirectKind.other:
            throw const UnexpectedResponseException();
        }
      }

      final html = response.data;
      if (html is! String) throw const UnexpectedResponseException();
      return parseActivitiesPage(
        statusCode: response.statusCode,
        finalUri: response.realUri,
        body: html,
        isExpectedPage: isSubActivityDetailHtml,
        parse: (body) => parseSubActivityDetailHtml(body, activityId: activityId, subActivityId: subActivityId),
      );
    } on DioException catch (e) {
      throw e.error is AppException ? e.error as AppException : const UnexpectedResponseException();
    }
  }

  /// Calls the previous web's own `mark_sub_complete` form target. **Legacy
  /// only**: CB 3.0 calculates completion automatically from exercise
  /// attempts and no CB 3.0 template references this route
  /// (`activities/urls.py:13`; `views.py:1063-1070` — `@login_required
  /// @require_POST`, CSRF-protected, no access or completion check, 302 back
  /// to the page). Callers must only reach this for legacy markup
  /// ([SubActivityDetail.canMarkComplete]).
  ///
  /// The id is validated BEFORE anything is sent: a non-positive id (such as
  /// the old `-1` sentinel) never produces a request.
  Future<void> markSubComplete(int subActivityId) async {
    if (subActivityId <= 0) {
      throw const UnexpectedResponseException('This sub-activity cannot be marked complete.');
    }
    try {
      final csrfToken = await _apiClient.readCookie('csrftoken');
      final response = await _apiClient.dio.post(
        ApiEndpoints.markSubComplete(subActivityId),
        options: Options(
          followRedirects: false,
          // 302 is the view's only success shape; every other status still
          // throws so `ApiExceptionsInterceptor` maps it (403, 404, ...).
          validateStatus: (status) => status != null && (status == 302 || (status >= 200 && status < 300)),
          headers: {'X-CSRFToken': csrfToken ?? ''},
        ),
      );
      if (response.statusCode != 302) {
        throw const UnexpectedResponseException();
      }
    } on DioException catch (e) {
      throw e.error is AppException ? e.error as AppException : const UnexpectedResponseException();
    }
  }
}

bool _is2xxOr3xx(int? status) => status != null && status >= 200 && status < 400;
