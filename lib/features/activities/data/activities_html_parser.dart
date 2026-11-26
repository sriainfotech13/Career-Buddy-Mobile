import '../../../core/utils/date_format.dart';
import '../../../core/utils/html_unescape.dart';
import '../../ai_listening/domain/services/listening_module_detection.dart';
import '../../ai_reading/domain/services/reading_module_detection.dart';
import '../../ai_speaking/domain/services/speaking_module_detection.dart';
import '../../ai_writing/domain/services/writing_module_detection.dart';
import '../../dashboard/data/html_tag_scanner.dart';
import '../domain/entities/activity_category.dart';
import '../domain/entities/activity_detail.dart';
import '../domain/entities/activity_list_data.dart';
import '../domain/entities/activity_progress_semantics.dart';
import '../domain/entities/activity_summary.dart';
import '../domain/entities/exercise_attempt.dart';
import '../domain/entities/exercise_summary.dart';
import '../domain/entities/sub_activity_detail.dart';
import '../domain/entities/sub_activity_status.dart';
import '../domain/entities/sub_activity_summary.dart';

/// HTML extraction against `activities.views.activity_list` /
/// `activity_detail` / `sub_activity_detail`'s server-rendered pages
/// (`templates/activities/list.html` / `detail.html` / `sub_activity.html`)
/// — the same "scrape the real, live page instead of the documented but
/// undeployed JSON sibling" technique already used for the dashboard (see
/// `dashboard_html_parser.dart`). Confirmed live in an earlier phase:
/// `/activities/api/...` 404s (undeployed) while the HTML pages work behind
/// `@login_required`.
///
/// Phase 90: supports BOTH the previous web markup (completion-based
/// progress, `mark_sub_complete` form) and CB 3.0 markup (score-based
/// progress from `activities/progress.py`, no completion form). Ids that
/// matter for requests/navigation are read from real destination links
/// (`/activities/<id>/`, `/activities/<a>/sub/<s>/`,
/// `/activities/exercise/<id>/`) — never "the first number" — and a page's
/// own sub-activity id is never inferred from markup at all (the caller's
/// route id is used). Matching goes through the shared tag scanner, so it is
/// independent of attribute order, whitespace/newlines and quoting.

bool isActivityListHtml(String html) => _hasClassToken(html, 'activities-page');

bool isActivityDetailHtml(String html) => _hasClassToken(html, 'activity-detail-page');

bool isSubActivityDetailHtml(String html) => html.contains('sub-activity-hero');

/// True when any tag carries [token] as a whole class token.
bool _hasClassToken(String html, String token) {
  if (!html.contains(token)) return false;
  return scanTags(stripHtmlComments(html)).any((t) => t.hasClass(token));
}

/// Leaf-element text of the first [tag] carrying class [token].
String? _textOfClass(String html, String tag, String token) {
  final found = scanTagsWithClass(html, tag, token).firstOrNull;
  return found == null ? null : innerText(html, found);
}

/// One slice per start tag of [tag] carrying class [token], each running to
/// the next such tag (or [maxLength] characters). The start tag is returned
/// with its slice so the caller can read the tag's own classes.
List<({HtmlTag tag, String body})> _sliceByClass(String html, String tag, String token, {int maxLength = 4000}) {
  final tags = scanTagsWithClass(html, tag, token).toList();
  return [
    for (var i = 0; i < tags.length; i++)
      (
        tag: tags[i],
        body: html.substring(
          tags[i].end,
          i + 1 < tags.length ? tags[i + 1].start : (tags[i].end + maxLength).clamp(0, html.length),
        ),
      ),
  ];
}

final RegExp _activityHref = RegExp(r'^/activities/(\d+)/?$');
final RegExp _subActivityHref = RegExp(r'^/activities/(\d+)/sub/(\d+)/?$');
final RegExp _exerciseHref = RegExp(r'^/activities/exercise/(\d+)/?$');
final RegExp _completeAction = RegExp(r'^/activities/sub/(\d+)/complete/?$');

String _pathOf(String href) => Uri.tryParse(href)?.path ?? href;

/// The first `<a>` in [html] whose href *path* matches [pattern].
RegExpMatch? _firstLinkMatching(String html, RegExp pattern) {
  for (final a in scanTags(html, name: 'a')) {
    final href = a.attributes['href'];
    if (href == null) continue;
    final m = pattern.firstMatch(_pathOf(href));
    if (m != null) return m;
  }
  return null;
}

ActivityListData parseActivityListHtml(String html) {
  if (!isActivityListHtml(html)) {
    throw const FormatException('Not an activity list page');
  }
  final doc = stripHtmlComments(html);

  final categories = [
    for (final m in RegExp(
      r'module-card mod-([\w-]+)[^"]*">\s*<div class="mod-icon">.*?<span class="mod-label">([^<]*)</span>',
      dotAll: true,
    ).allMatches(doc))
      if (m.group(1) != 'all') ActivityCategory(value: m.group(1)!, label: _unescape(m.group(2)!.trim())),
  ];

  // `mod-active` on a chip other than the implicit "All" one — matches
  // `list.html`'s own `{% if selected_category == value %}mod-active{% endif %}`.
  final activeMatch = RegExp(r'module-card mod-([\w-]+)[^"]*mod-active').firstMatch(doc);
  final selectedCategory = (activeMatch == null || activeMatch.group(1) == 'all') ? '' : activeMatch.group(1)!;

  final isFreePreview = doc.contains('Free Plan — choose any one');

  // CB 3.0 labels the block `Progress (score)` and prints `a/b exercises
  // attempted` (`list.html:117-130`); the previous web printed plain `Progress`.
  final pageIsScoreBased =
      doc.contains('Progress (score)') || RegExp(r'\d+\s*/\s*\d+\s*exercises attempted').hasMatch(doc);

  final activities = <ActivitySummary>[];
  for (final entry in _sliceByClass(doc, 'div', 'activity-card')) {
    final card = entry.body;
    final isLocked = card.contains('js-locked-activity');

    // Id from the card's own `/activities/<id>/` link only; a card whose link
    // points elsewhere (`direct_url`: workshop / AI-module pages) has no real
    // activity id (see the synthetic-id note below).
    final idFromHref = _firstLinkMatching(card, _activityHref)?.group(1);

    final title = _unescape((_textOfClass(card, 'h5', 'activity-title') ?? '').trim());
    if (title.isEmpty) continue;
    final objective = _textOfClass(card, 'p', 'activity-objective');
    final level = _textOfClass(card, 'span', 'badge-level');
    final categoryTag = scanTagsWithClass(card, 'span', 'badge-category').firstOrNull;
    final categoryDisplay = categoryTag?.attributes['title'];
    // The raw `category` slug isn't printed as text anywhere on this page
    // (only its icon class and display title are) — recovered from whichever
    // `fa-*` icon this card's badge actually rendered.
    final category = _categorySlugFromIcon(card);

    final rateText = _textOfClass(card, 'small', 'fw-semibold');
    final rateMatch = rateText == null ? null : RegExp(r'^([\d.]+)\s*%$').firstMatch(rateText);
    final rate = rateMatch != null ? (double.tryParse(rateMatch.group(1)!) ?? 0).round() : 0;
    final counter = RegExp(r'(\d+)\s*/\s*(\d+)\s*exercises attempted').firstMatch(htmlToText(card));

    // Done marker: `activity-card-done` on the card's own class (legacy: rate
    // was 100; CB 3.0: every exercise *attempted*, any score) or the
    // `activity-done-badge` inside it — NOT `rate == 100`, which is wrong in
    // both generations (`list.html:90,96-98`).
    final isDone = entry.tag.hasClass('activity-card-done') || card.contains('activity-done-badge');

    activities.add(
      ActivitySummary(
        // A locked card's id is never used for navigation (the parent
        // screen shows an upgrade dialog instead). A card with no real
        // activity pk in its href (`direct_url` — workshop/AI module
        // activities, whose link points straight at their own page) gets a
        // synthetic NEGATIVE id derived from the title's hash, never from its
        // position, so it is identical across the filtered and unfiltered
        // lists. `ActivitiesRemoteDataSource.getActivityDetail` recognises a
        // negative id and answers from the list parse — no HTTP request is
        // ever made for a negative id.
        id: idFromHref != null ? int.parse(idFromHref) : -(title.hashCode.abs() % 1000000 + 1),
        title: title,
        description: _unescape((objective ?? '').trim()),
        category: category,
        categoryDisplay: _unescape((categoryDisplay ?? '').trim()),
        level: _unescape((level ?? '').trim()),
        // Not rendered on this page — honest empty default.
        duration: '',
        isLocked: isLocked,
        completionRate: rate,
        isCompleted: isDone,
        progressSemantics: (pageIsScoreBased || counter != null)
            ? ActivityProgressSemantics.score
            : ActivityProgressSemantics.completion,
        attemptedExercises: counter == null ? null : int.parse(counter.group(1)!),
        totalExercises: counter == null ? null : int.parse(counter.group(2)!),
        hasProgressPercent: rateMatch != null,
      ),
    );
  }

  return ActivityListData(
    activities: activities,
    categories: categories,
    selectedCategory: selectedCategory,
    isFreePreview: isFreePreview,
    // The real `total_activities` counter is only shown inside free-text
    // prose — the parsed list length is what callers actually use.
    totalActivities: activities.length,
  );
}

const _categoryIcons = {
  'fa-microphone': 'speaking',
  'fa-pen': 'writing',
  'fa-puzzle-piece': 'vocabulary',
  'fa-handshake': 'negotiation',
  'fa-globe': 'communication',
  'fa-chart-pie': 'analysis',
  'fa-chalkboard-teacher': 'workshop',
};

String _categorySlugFromIcon(String card) {
  final badgeMatch = RegExp(r'class="badge-category"[^>]*>([\s\S]*?)</span>').firstMatch(card);
  final badge = badgeMatch?.group(1) ?? '';
  for (final entry in _categoryIcons.entries) {
    if (badge.contains(entry.key)) return entry.value;
  }
  return '';
}

/// Builds a minimal [ActivityDetail] for an activity whose real detail
/// page is genuinely unreachable this way — either a workshop/module
/// activity (its list card carries no activity pk at all) or a positive id
/// whose `/activities/<id>/` request redirected somewhere other than the
/// login or locked-upgrade pages. [subActivities] is honestly empty.
ActivityDetail activityDetailFromSummary(ActivitySummary summary) {
  return ActivityDetail(
    id: summary.id,
    title: summary.title,
    description: summary.description,
    category: summary.category,
    categoryDisplay: summary.categoryDisplay,
    level: summary.level,
    duration: summary.duration,
    isWorkshop: summary.category == 'workshop',
    isModule:
        isSpeakingModuleActivity(summary.title) ||
        isWritingModuleActivity(summary.title) ||
        isListeningModuleActivity(summary.title) ||
        isReadingModuleActivity(summary.title),
    completionRate: summary.completionRate,
    subActivities: const [],
    progressSemantics: summary.progressSemantics,
    attemptedExercises: summary.attemptedExercises,
    totalExercises: summary.totalExercises,
  );
}

/// Parses `detail.html` itself — only reachable for a "normal" (non-workshop,
/// non-module) activity, since the view redirects away before rendering this
/// template for workshop/module activities.
ActivityDetail parseActivityDetailHtml(String html, {required int id}) {
  if (!isActivityDetailHtml(html)) {
    throw const FormatException('Not an activity detail page');
  }
  final doc = stripHtmlComments(html);

  final title = _unescape((_textOfClass(doc, 'h1', 'activity-hero-title') ?? '').trim());
  final objective = _textOfClass(doc, 'p', 'activity-hero-objective');
  final levelMatch = RegExp(r'fa-signal me-2"></i>([^<]*)</span>').firstMatch(doc);
  final durationMatch = RegExp(r'fa-clock me-2"></i>([^<]*)</span>').firstMatch(doc);

  // Hero ring: `N%` + label `Score` (CB 3.0) or `Complete` (legacy), and for
  // CB 3.0 an optional `a/b exercises` line (`detail.html:84-89`).
  final ringValue = _textOfClass(doc, 'div', 'ring-value');
  final ringMatch = ringValue == null ? null : RegExp(r'^([\d.]+)\s*%$').firstMatch(ringValue);
  final ringLabels = [for (final t in scanTagsWithClass(doc, 'div', 'ring-label')) innerText(doc, t)];
  final isScore = ringLabels.any((l) => l.toLowerCase() == 'score');
  final exercisesLine = ringLabels
      .map((l) => RegExp(r'^(\d+)\s*/\s*(\d+)\s*exercises$').firstMatch(l))
      .whereType<RegExpMatch>()
      .firstOrNull;

  final subActivities = <SubActivitySummary>[];
  for (final entry in _sliceByClass(doc, 'div', 'sub-activity-card')) {
    final card = entry.body;
    // The sub id is the second number of this card's own
    // `/activities/<a>/sub/<s>/` link.
    final link = _firstLinkMatching(card, _subActivityHref);
    final subTitle = _textOfClass(card, 'h5', 'sub-title');
    if (link == null || subTitle == null || subTitle.isEmpty) continue;
    final subId = int.parse(link.group(2)!);
    if (subId <= 0) continue;

    final description = _textOfClass(card, 'p', 'sub-description');
    final statusTag = scanTagsWithClass(card, 'span', 'sub-status-badge').firstOrNull;
    final statusToken = statusTag?.classes.where((c) => c.startsWith('status-')).firstOrNull?.substring(7);
    final text = htmlToText(card);
    final exerciseCountMatch = RegExp(r'(\d+)\s*Exercise').firstMatch(text);
    final startedMatch = RegExp(r'Started\s+([A-Za-z]{3}\s+\d{1,2}\s+\d{4})').firstMatch(text);
    final completedMatch = RegExp(r'Completed\s+([A-Za-z]{3}\s+\d{1,2}\s+\d{4})').firstMatch(text);
    final scoreMatch = RegExp(r'Score\s+(\d{1,3})\s*%').firstMatch(text);

    subActivities.add(
      SubActivitySummary(
        id: subId,
        title: _unescape(subTitle.trim()),
        description: _unescape((description ?? '').trim()),
        order: subActivities.length + 1,
        status: SubActivityStatus.fromWire(statusToken ?? 'not_started'),
        exerciseCount: int.tryParse(exerciseCountMatch?.group(1) ?? '') ?? 0,
        startedAt: startedMatch != null ? _parseSpacedDate(startedMatch.group(1)!) : null,
        completedAt: completedMatch != null ? _parseSpacedDate(completedMatch.group(1)!) : null,
        scorePercent: scoreMatch == null ? null : int.parse(scoreMatch.group(1)!),
      ),
    );
  }

  return ActivityDetail(
    id: id,
    title: title,
    description: _unescape((objective ?? '').trim()),
    // Not rendered anywhere on this page — honest empty defaults.
    category: '',
    categoryDisplay: '',
    level: _unescape(levelMatch?.group(1)?.trim() ?? ''),
    duration: _unescape(durationMatch?.group(1)?.trim() ?? ''),
    isWorkshop: false,
    isModule:
        isSpeakingModuleActivity(title) ||
        isWritingModuleActivity(title) ||
        isListeningModuleActivity(title) ||
        isReadingModuleActivity(title),
    completionRate: ringMatch != null ? (double.tryParse(ringMatch.group(1)!) ?? 0).round() : 0,
    subActivities: subActivities,
    progressSemantics: isScore ? ActivityProgressSemantics.score : ActivityProgressSemantics.completion,
    attemptedExercises: exercisesLine == null ? null : int.parse(exercisesLine.group(1)!),
    totalExercises: exercisesLine == null ? null : int.parse(exercisesLine.group(2)!),
  );
}

/// Parses `sub_activity.html`. [subActivityId] is the id the app REQUESTED
/// (the route) and is the only id used for the result: CB 3.0 pages carry no
/// sub-activity pk in their body (the `mark_sub_complete` form was removed),
/// so inferring one from markup yielded `-1`. If it is omitted, the id must
/// come from a legacy completion form; otherwise the page is rejected.
SubActivityDetail parseSubActivityDetailHtml(String html, {required int activityId, int? subActivityId}) {
  if (!isSubActivityDetailHtml(html)) {
    throw const FormatException('Not a sub-activity detail page');
  }
  final doc = stripHtmlComments(html);
  final text = htmlToText(doc);

  // Legacy completion form: `<form action="/activities/sub/<pk>/complete/">`.
  int? legacyFormSubId;
  for (final f in scanTags(doc, name: 'form')) {
    final action = f.attributes['action'];
    if (action == null) continue;
    final m = _completeAction.firstMatch(_pathOf(action));
    if (m != null) {
      legacyFormSubId = int.parse(m.group(1)!);
      break;
    }
  }

  final resolvedId = (subActivityId != null && subActivityId > 0) ? subActivityId : legacyFormSubId;
  if (resolvedId == null || resolvedId <= 0) {
    throw const FormatException('Sub-activity id unavailable');
  }

  final hasLegacyBanner = RegExp(r'Sub-activity completed on [A-Za-z]+ \d{1,2}, \d{4}').hasMatch(text);
  final hasScoreSummary =
      text.contains('Your progress in this sub-activity') || doc.contains('aria-label="Sub-activity performance"');
  // Manual completion exists only with legacy markup for THIS sub-activity.
  final formMatchesRoute = legacyFormSubId != null && legacyFormSubId == resolvedId;
  final mode = hasScoreSummary
      ? SubActivityCompletionMode.scoreBased
      : (formMatchesRoute || hasLegacyBanner)
      ? SubActivityCompletionMode.legacyForm
      : SubActivityCompletionMode.unknown;

  final title = _textOfClass(doc, 'h2', 'text-white');
  final orderMatch = RegExp(r'Sub-Activity (\d+) of (\d+)').firstMatch(text);
  // Breadcrumb: `Activities` › <activity title> › <active: this sub-activity>
  // (older/minimal pages may omit the leading `Activities` crumb).
  final crumbs = [
    for (final t in scanTagsWithClass(doc, 'li', 'breadcrumb-item'))
      if (!t.hasClass('active')) innerText(doc, t),
  ];
  // The crumb immediately before the active one is the activity.
  final activityTitle = crumbs.isEmpty ? '' : crumbs.last;

  // Status badge: the first `badge px-3 py-2` span whose text is a status.
  String? statusText;
  for (final t in scanTags(doc, name: 'span')) {
    if (!(t.hasClass('badge') && t.hasClass('px-3') && t.hasClass('py-2'))) continue;
    final badgeText = innerText(doc, t);
    if (RegExp(r'^(Completed|In Progress|Not Started)$').hasMatch(badgeText)) {
      statusText = badgeText;
      break;
    }
  }

  final descTag = scanTags(doc, name: 'span').where((t) => t.attributes['id'] == 'descOverview').firstOrNull;
  final instructionsTag = scanTags(doc).where((t) => t.attributes['id'] == 'instructionsBox').firstOrNull;

  // CB 3.0 score summary (`sub_activity.html:161-180`) and header badge.
  final progressMatch = RegExp(r'Your progress in this sub-activity:\s*(\d{1,3})\s*%').firstMatch(text);
  final badgeScoreMatch = RegExp(r'Score\s+(\d{1,3})\s*%').firstMatch(text);
  final attemptedMatch = RegExp(r'Based on your scores:\s*(\d+)\s*/\s*(\d+)\s*exercises?\s*attempted').firstMatch(text);
  final attempted = attemptedMatch == null ? null : int.parse(attemptedMatch.group(1)!);
  final total = attemptedMatch == null ? null : int.parse(attemptedMatch.group(2)!);
  final scorePercent = progressMatch != null
      ? int.parse(progressMatch.group(1)!)
      : (badgeScoreMatch != null ? int.parse(badgeScoreMatch.group(1)!) : null);

  // `allExercisesDone`: legacy = the page lacks the "Please complete all
  // interactive exercises first" lock text; CB 3.0 = every exercise attempted
  // (and only when the counts were actually shown). Never assumed.
  final allDone = switch (mode) {
    SubActivityCompletionMode.legacyForm => !text.contains('Please complete all interactive exercises first'),
    SubActivityCompletionMode.scoreBased => attempted != null && total != null && total > 0 && attempted >= total,
    SubActivityCompletionMode.unknown => false,
  };

  final completedAtMatch = RegExp(r'Sub-activity completed on ([A-Za-z]+ \d{1,2}, \d{4})').firstMatch(text);

  final exercises = <ExerciseSummary>[];
  for (final entry in _sliceByClass(doc, 'div', 'exercise-card')) {
    final card = entry.body;
    final exMatch = _firstLinkMatching(card, _exerciseHref);
    final exTitle = _textOfClass(card, 'h6', 'exercise-title');
    final iconTag = scanTagsWithClass(card, 'div', 'exercise-type-icon').firstOrNull;
    final typeToken = iconTag?.classes
        .where((c) => c.startsWith('exercise-') && c != 'exercise-type-icon')
        .firstOrNull
        ?.substring(9);
    if (exMatch == null || exTitle == null || exTitle.isEmpty || typeToken == null || typeToken.isEmpty) continue;
    final exerciseId = int.parse(exMatch.group(1)!);
    if (exerciseId <= 0) continue;

    final cardText = htmlToText(card);
    final scoreMatch = RegExp(r'Last score:\s*(\d+)\s*/\s*(\d+)').firstMatch(cardText);
    final pctMatch = RegExp(r'Last score:\s*\d+\s*/\s*\d+\s*([\d.]+)\s*%').firstMatch(cardText);

    exercises.add(
      ExerciseSummary(
        id: exerciseId,
        title: _unescape(exTitle.trim()),
        exerciseType: typeToken,
        exerciseTypeDisplay: _unescape((_textOfClass(card, 'div', 'exercise-type-label') ?? '').trim()),
        order: exercises.length + 1,
        lastAttempt: scoreMatch == null
            ? null
            : ExerciseAttempt(
                score: int.parse(scoreMatch.group(1)!),
                maxScore: int.parse(scoreMatch.group(2)!),
                percentage: pctMatch != null ? (double.tryParse(pctMatch.group(1)!) ?? 0).round() : 0,
                // Neither is rendered on this page — honest placeholders; no
                // widget reads either off a freshly-scraped `lastAttempt`.
                attemptNumber: 1,
                completedAt: DateTime.now(),
              ),
      ),
    );
  }

  return SubActivityDetail(
    id: resolvedId,
    title: _unescape((title ?? '').trim()),
    description: _unescape(descTag == null ? '' : innerText(doc, descTag)),
    instructions: instructionsTag == null ? '' : _stripTags(_sliceUntilClose(doc, instructionsTag)),
    order: orderMatch != null ? int.parse(orderMatch.group(1)!) : 1,
    activityId: activityId,
    activityTitle: _unescape(activityTitle.trim()),
    status: switch (statusText) {
      'Completed' => SubActivityStatus.completed,
      'In Progress' => SubActivityStatus.inProgress,
      _ => SubActivityStatus.notStarted,
    },
    allExercisesDone: allDone,
    exercises: exercises,
    // `started_at` isn't shown on this page; `completed_at` only via the
    // legacy banner.
    startedAt: null,
    completedAt: completedAtMatch != null ? _parseLongDate(completedAtMatch.group(1)!) : null,
    completionMode: mode,
    scorePercent: scorePercent,
    attemptedExercises: attempted,
    totalExercises: total,
  );
}

/// Content of [tag] up to its matching `</div>` — for the instructions box,
/// whose `linebreaks` output nests `<p>` tags but no `<div>`.
String _sliceUntilClose(String doc, HtmlTag tag) {
  final close = doc.indexOf(RegExp(r'</div\s*>', caseSensitive: false), tag.end);
  return doc.substring(tag.end, close == -1 ? doc.length : close);
}

DateTime? _parseSpacedDate(String text) {
  // `"M d Y h:i A"` — the year is unseparated from the day by a comma, unlike
  // the dashboard's `"M d, Y"`, so `parseMonthDayYear` is reached through a
  // small adapter instead of duplicating its month table.
  final parts = text.split(RegExp(r'\s+'));
  if (parts.length < 3) return null;
  return parseMonthDayYear('${parts[0]} ${parts[1]}, ${parts[2]}');
}

DateTime? _parseLongDate(String text) {
  // `"F d, Y"` (full month name) vs `parseMonthDayYear`'s abbreviated table.
  final match = RegExp(r'^([A-Za-z]+)\s+(\d{1,2}),\s*(\d{4})$').firstMatch(text.trim());
  if (match == null) return null;
  final month = match.group(1)!;
  final abbrev = month.length >= 3 ? month.substring(0, 3) : month;
  return parseMonthDayYear('$abbrev ${match.group(2)}, ${match.group(3)}');
}

String _stripTags(String html) =>
    _unescape(html.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim());

String _unescape(String value) => unescapeHtmlEntities(value);
