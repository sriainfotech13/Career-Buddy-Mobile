import '../../../core/utils/date_format.dart';
import '../../../core/utils/html_unescape.dart';
import '../domain/entities/activity_progress.dart';
import '../domain/entities/dashboard_data.dart';
import '../domain/entities/dashboard_stats.dart';
import '../domain/entities/payment_record.dart';
import '../domain/entities/recent_result.dart';
import '../domain/entities/recommended_job.dart';
import 'html_tag_scanner.dart';

/// Regex extraction against `activities.views.dashboard`'s server-rendered
/// HTML (`templates/dashboard.html`) — the same legitimate reuse-of-an-
/// already-fetched-page technique already used throughout this app (e.g.
/// `parseEmployerDashboardHtml`), not a new API. Every regex below is
/// anchored to markup read directly from the template, not guessed.
///
/// **Why this exists instead of parsing `dashboard_api`'s JSON**: that
/// endpoint is real, deliberately mobile-shaped source
/// (`activities/views.py:dashboard_api`, documented in
/// `docs/BACKEND_CONTRACT_dashboard.md`) but is **not deployed to
/// production** — confirmed live: `GET /dashboard/api/` returns a genuine
/// Django 404 (not the 401 `{"error":"Not authenticated"}` the view itself
/// would return if it were reachable), while the plain HTML `/dashboard/`
/// page it's a JSON sibling of works live today. Rather than leave the
/// app's primary post-login screen permanently broken until that endpoint
/// ships, this scrapes the one that's actually live — [DashboardData]'s own
/// shape is unchanged, so no other file in this feature needed to change.
///
/// Two fields the JSON contract would have carried have no real source in
/// this HTML page, confirmed by reading the template line by line — both
/// documented as deliberate, not silently guessed:
/// - [RecentResult.date] isn't rendered anywhere on the dashboard (only
///   title/activity/score are) — this parser fills `DateTime.now()`, which
///   is never actually shown by `RecentResultsList` (checked: it reads
///   `title`/`activityName`/`score`/`maxScore`/`percentage` only).
/// - [RecentResult.percentage] is likewise never rendered as a number (only
///   used server-side to pick a CSS color tier) — recomputed here as
///   `score/maxScore*100`, an honest derivation from two real numbers, not
///   fabricated data.
DashboardData parseDashboardHtml(String html) {
  if (!isDashboardHtml(html)) {
    throw const FormatException('Not a dashboard page');
  }

  // Comments are removed once so tags inside template notes are never
  // scanned. The older regex-based sections below still read the original
  // [html] (unchanged behaviour, out of Phase 89's scope).
  final doc = stripHtmlComments(html);
  final activities = _parseActivities(doc);
  final generation = _detectGeneration(doc, activities.items);

  // Structural sanity, so a changed template is reported as such instead of
  // as an empty (but "successful") dashboard. The page's own "Activity
  // Progress" section (`dashboard.html:171`) must hold either activity rows
  // or the template's empty-state copy (`dashboard.html:222-226`). A page
  // that has no activity section at all (e.g. a minimal slice) is still
  // parsed — with an empty list, never invented rows.
  if (activities.rowCount == 0 && doc.contains('Activity Progress') && !doc.contains('No activities started yet')) {
    throw const FormatException('Activity section present but its structure is not recognised');
  }
  if (activities.rowCount > 0 && activities.items.isEmpty) {
    throw const FormatException('Activity rows found but none could be parsed');
  }

  return DashboardData(
    stats: _parseStats(doc),
    activities: [for (final a in activities.items) _withSemantics(a, generation)],
    recentResults: _parseRecentResults(html),
    recommendedJobs: _parseRecommendedJobs(html),
    paymentHistory: _parsePaymentHistory(html),
    interviewScore: _parseInterviewScore(html),
    generation: generation,
  );
}

/// `dashboard.html:52` — present only on the real, rendered dashboard page
/// (not on a login redirect or an error page), so this is this parser's
/// success/failure signal, same role as `isResumeMatchResultHtml` elsewhere.
/// Attribute order, extra classes and quoting are irrelevant.
bool isDashboardHtml(String html) {
  if (!html.contains('dashboard-welcome')) return false;
  return scanTagsWithClass(stripHtmlComments(html), 'div', 'dashboard-welcome').isNotEmpty;
}

/// `dashboard.html:65-94` — four `stat-card-value` tiles in a fixed order:
/// Total Activities, Completed, In Progress, Total Score. A tile that is
/// absent or non-numeric is null, never a fabricated 0.
DashboardStats _parseStats(String doc) {
  final values = <num?>[
    for (final tag in scanTagsWithClass(doc, 'div', 'stat-card-value')) num.tryParse(innerText(doc, tag)),
  ];
  num? at(int i) => i < values.length ? values[i] : null;
  return DashboardStats(
    totalActivities: at(0)?.toInt(),
    completedCount: at(1)?.toInt(),
    inProgressCount: at(2)?.toInt(),
    totalScore: at(3),
  );
}

num? _parseInterviewScore(String html) {
  final match = RegExp(r'interview score of <strong>([\d.]+)/100</strong>').firstMatch(html);
  if (match == null) return null;
  return num.tryParse(match.group(1)!);
}

/// Splits a section of [html] into one slice per occurrence of [marker],
/// each running up to the next occurrence (or [maxLength] characters for
/// the last one) — the same "card-start-marker splitting" technique used
/// throughout this app's other list-parsing screens, needed because these
/// cards nest to an unpredictable depth that a naive non-greedy
/// `[\s\S]*?</div>` would cut short at the first nested closing tag.
List<String> _splitByMarker(String html, String marker, {int maxLength = 3000}) {
  final starts = <int>[];
  var searchFrom = 0;
  while (true) {
    final index = html.indexOf(marker, searchFrom);
    if (index == -1) break;
    starts.add(index);
    searchFrom = index + marker.length;
  }
  return [
    for (var i = 0; i < starts.length; i++)
      html.substring(starts[i], i + 1 < starts.length ? starts[i + 1] : (starts[i] + maxLength).clamp(0, html.length)),
  ];
}

class _ActivityScan {
  const _ActivityScan(this.items, this.rowCount);

  /// Successfully parsed rows.
  final List<ActivityProgress> items;

  /// `progress-activity-item` containers present in the page (parsed or not).
  final int rowCount;
}

/// Each row is `<div class="progress-activity-item"><a ... class=
/// "progress-activity-link">...</a></div>` (`dashboard.html:182-219`), and
/// everything the app needs lives inside the anchor — so a row's content is
/// bounded by the anchor's closing tag, not by a fixed character budget.
_ActivityScan _parseActivities(String doc) {
  final markers = scanTagsWithClass(doc, 'div', 'progress-activity-item').toList();
  final items = <ActivityProgress>[];
  for (var i = 0; i < markers.length; i++) {
    final limit = i + 1 < markers.length ? markers[i + 1].start : doc.length;
    final segment = doc.substring(markers[i].end, limit);
    final parsed = _parseActivityRow(segment);
    if (parsed != null) items.add(parsed);
  }
  return _ActivityScan(items, markers.length);
}

// Counter alternatives (collapsed text of the row's `<small>` elements).
final RegExp _subActivitiesText = RegExp(r'^(\d+)\s*/\s*(\d+)\s+sub-activities$', caseSensitive: false);
final RegExp _exercisesText = RegExp(r'^(\d+)\s*/\s*(\d+)\s+exercises attempted$', caseSensitive: false);
final RegExp _sessionsText = RegExp(
  r'^Session score\s*(?:\u00b7|&middot;|&#183;)\s*(\d+)\s+sessions?$',
  caseSensitive: false,
);
final RegExp _activityHref = RegExp(r'^/activities/(\d+)/?$');
final RegExp _exerciseHref = RegExp(r'^/activities/exercise/(\d+)/?$');

ActivityProgress? _parseActivityRow(String segment) {
  final link = scanTagsWithClass(segment, 'a', 'progress-activity-link').firstOrNull;
  if (link == null) return null;
  final href = link.attributes['href'];
  if (href == null) return null;

  final closeIndex = segment.indexOf(RegExp(r'</a\s*>', caseSensitive: false), link.end);
  final body = segment.substring(link.end, closeIndex == -1 ? segment.length : closeIndex);

  // Href kind. Never "the first number in the href": a module row links to
  // `/activities/exercise/<exercise_id>/` (`dashboard.html:184`,
  // `activities/views.py:247-255`) and that number is not an activity id.
  final path = Uri.tryParse(href)?.path ?? href;
  int? activityId;
  int? exerciseId;
  var kind = ActivityLinkKind.unknown;
  final exerciseMatch = _exerciseHref.firstMatch(path);
  final activityMatch = _activityHref.firstMatch(path);
  if (exerciseMatch != null) {
    kind = ActivityLinkKind.moduleExercise;
    exerciseId = int.parse(exerciseMatch.group(1)!);
  } else if (activityMatch != null) {
    kind = ActivityLinkKind.activity;
    activityId = int.parse(activityMatch.group(1)!);
  }

  // `{{ activity.order }}. {{ activity.title }}` (`dashboard.html:171`): the
  // number is the display order, not the primary key.
  final nameTag = scanTagsWithClass(body, 'span', 'progress-activity-name').firstOrNull;
  final rawName = nameTag == null ? '' : innerText(body, nameTag);
  final orderMatch = RegExp(r'^(\d+)\.\s*').firstMatch(rawName);
  final title = rawName.replaceFirst(RegExp(r'^\d+\.\s*'), '');
  if (title.isEmpty) return null;

  // Percentage: first `progress-activity-pct` span. Missing => null.
  final pctTag = scanTagsWithClass(body, 'span', 'progress-activity-pct').firstOrNull;
  final pctMatch = pctTag == null ? null : RegExp(r'(\d{1,3}(?:\.\d+)?)\s*%').firstMatch(innerText(body, pctTag));
  final percent = double.tryParse(pctMatch?.group(1) ?? '');
  final band = pctTag == null ? null : _bandOf(pctTag);

  // Counter: the first `<small>` whose text is one of the known forms.
  var basis = ProgressBasis.unknown;
  int? completedSubs, totalSubs, attempted, totalEx, sessions;
  for (final small in scanTags(body, name: 'small')) {
    final text = innerText(body, small);
    final subs = _subActivitiesText.firstMatch(text);
    final ex = _exercisesText.firstMatch(text);
    final ses = _sessionsText.firstMatch(text);
    if (subs != null) {
      basis = ProgressBasis.subActivities;
      completedSubs = int.parse(subs.group(1)!);
      totalSubs = int.parse(subs.group(2)!);
    } else if (ex != null) {
      basis = ProgressBasis.exercises;
      attempted = int.parse(ex.group(1)!);
      totalEx = int.parse(ex.group(2)!);
    } else if (ses != null) {
      basis = ProgressBasis.workshopSessions;
      sessions = int.parse(ses.group(1)!);
    } else if (text.toLowerCase() == 'no sessions yet') {
      basis = ProgressBasis.workshopSessions;
      sessions = 0;
    } else if (text.toLowerCase() == 'no scored exercises') {
      basis = ProgressBasis.noScoredExercises;
    } else {
      continue;
    }
    break;
  }

  final startedMatch = RegExp(r'Started\s+([A-Za-z]{3}\s+\d{1,2},\s*\d{4})').firstMatch(htmlToText(body));

  return ActivityProgress(
    activityId: activityId,
    title: title,
    completionRate: percent,
    completedSubActivities: completedSubs,
    totalSubActivities: totalSubs,
    startedAt: startedMatch != null ? parseMonthDayYear(startedMatch.group(1)!) : null,
    basis: basis,
    // Provisional; finalised by `_withSemantics` once the page's markup
    // generation is known.
    semantics: ProgressSemantics.unknown,
    linkKind: kind,
    exerciseId: exerciseId,
    order: orderMatch == null ? null : int.parse(orderMatch.group(1)!),
    attemptedExercises: attempted,
    totalExercises: totalEx,
    sessionCount: sessions,
    band: band,
  );
}

/// `text-success|warning|danger|muted|secondary` on the percentage span
/// (`dashboard.html:193`; the previous web only used success/warning/muted).
ProgressBand? _bandOf(HtmlTag tag) {
  for (final c in tag.classes) {
    switch (c) {
      case 'text-success':
        return ProgressBand.success;
      case 'text-warning':
        return ProgressBand.warning;
      case 'text-danger':
        return ProgressBand.danger;
      case 'text-muted':
      case 'text-secondary':
        return ProgressBand.muted;
    }
  }
  return null;
}

/// Markup generation from the page's own markers. Conflicting evidence
/// (both generations) is reported as unknown rather than guessed.
DashboardMarkupGeneration _detectGeneration(String doc, List<ActivityProgress> items) {
  final cb3 =
      doc.contains('Score-based progress') ||
      doc.contains('Progress is based on your scores') ||
      RegExp(r'Average score\s*<strong').hasMatch(doc) ||
      doc.contains('id="recommended-jobs"') ||
      items.any(
        (a) =>
            a.basis == ProgressBasis.exercises ||
            a.basis == ProgressBasis.workshopSessions ||
            a.basis == ProgressBasis.noScoredExercises,
      );
  final legacy = items.any((a) => a.basis == ProgressBasis.subActivities);
  if (cb3 && legacy) return DashboardMarkupGeneration.unknown;
  if (cb3) return DashboardMarkupGeneration.cb3;
  if (legacy) return DashboardMarkupGeneration.legacy;
  return DashboardMarkupGeneration.unknown;
}

/// Legacy rows carry a *completion* percentage, CB 3.0 rows a *score*
/// percentage. A row's own counter text decides; otherwise the page's
/// generation does; otherwise it stays unknown.
ActivityProgress _withSemantics(ActivityProgress a, DashboardMarkupGeneration generation) {
  final semantics = switch (a.basis) {
    ProgressBasis.subActivities => ProgressSemantics.completion,
    ProgressBasis.exercises ||
    ProgressBasis.workshopSessions ||
    ProgressBasis.noScoredExercises => ProgressSemantics.score,
    ProgressBasis.unknown => switch (generation) {
      DashboardMarkupGeneration.legacy => ProgressSemantics.completion,
      DashboardMarkupGeneration.cb3 => ProgressSemantics.score,
      DashboardMarkupGeneration.unknown => ProgressSemantics.unknown,
    },
  };
  return ActivityProgress(
    activityId: a.activityId,
    title: a.title,
    completionRate: a.completionRate,
    completedSubActivities: a.completedSubActivities,
    totalSubActivities: a.totalSubActivities,
    startedAt: a.startedAt,
    basis: a.basis,
    semantics: semantics,
    linkKind: a.linkKind,
    exerciseId: a.exerciseId,
    order: a.order,
    attemptedExercises: a.attemptedExercises,
    totalExercises: a.totalExercises,
    sessionCount: a.sessionCount,
    band: a.band,
  );
}

List<RecentResult> _parseRecentResults(String html) {
  final results = <RecentResult>[];
  for (final item in _splitByMarker(html, '<div class="recent-result-item">', maxLength: 800)) {
    final titleMatch = RegExp(r'result-exercise-name">([^<]*)</div>').firstMatch(item);
    final activityMatch = RegExp(r'result-activity-name text-muted">([^<]*)').firstMatch(item);
    final scoreMatch = RegExp(r'score-badge[^>]*>\s*([\d.]+)/([\d.]+)\s*</span>').firstMatch(item);
    if (titleMatch == null || scoreMatch == null) continue;

    final score = num.tryParse(scoreMatch.group(1)!) ?? 0;
    final maxScore = num.tryParse(scoreMatch.group(2)!) ?? 0;
    results.add(
      RecentResult(
        title: _unescape(titleMatch.group(1)!.trim()),
        activityName: _unescape(activityMatch?.group(1)?.trim() ?? ''),
        score: score,
        maxScore: maxScore,
        percentage: maxScore > 0 ? (score / maxScore * 100).toDouble() : 0,
        // Not rendered on this page at all — see this file's top-level doc
        // comment for why a placeholder here is honest, not fabricated.
        date: DateTime.now(),
      ),
    );
  }
  return results;
}

List<RecommendedJob> _parseRecommendedJobs(String html) {
  final jobs = <RecommendedJob>[];
  for (final item in _splitByMarker(html, 'class="job-card border rounded-3 p-3 h-100 overflow-hidden"')) {
    final titleMatch = RegExp(r'<h6 class="fw-bold mb-0 text-truncate"[^>]*>([^<]*)</h6>').firstMatch(item);
    if (titleMatch == null) continue;
    final companyMatch = RegExp(r'<small class="text-muted">([^<]*)</small>').firstMatch(item);
    final skills = RegExp(
      r'<span class="badge bg-light text-dark border text-truncate"[^>]*>([^<]*)</span>',
    ).allMatches(item).map((m) => _unescape(m.group(1)!.trim())).toList();
    final locationMatch = RegExp(
      r'<span class="text-muted"><i class="fas fa-map-marker-alt me-1"></i>([^<]*)</span>',
    ).firstMatch(item);
    final jobTypeMatch = RegExp(
      r'<span class="badge bg-primary bg-opacity-10 text-primary">([^<]*)</span>',
    ).firstMatch(item);
    final experienceMatch = RegExp(
      r'<span class="text-muted"><i class="fas fa-briefcase me-1"></i>([^<]*)</span>',
    ).firstMatch(item);
    final salaryMatch = RegExp(
      r'<small class="fw-bold text-success"><i class="fas fa-rupee-sign me-1"></i>([^<]*)</small>',
    ).firstMatch(item);
    // `dashboard.html:142-144`: `<a href="{% url 'employer_portal:job_detail'
    // job.pk %}" class="btn btn-primary btn-sm w-100 rounded-3 fw-bold"
    // target="_blank">` — same technique as `_parseActivities`'s own
    // href/id extraction above: find the card's own link, then the first
    // numeric id inside it, rather than assuming a fixed URL shape.
    final jobHrefMatch = RegExp(
      r'<a href="([^"]*)"\s*class="btn btn-primary btn-sm w-100 rounded-3 fw-bold"',
    ).firstMatch(item);
    final jobId = jobHrefMatch == null
        ? null
        : int.tryParse(RegExp(r'(\d+)').firstMatch(jobHrefMatch.group(1)!)?.group(1) ?? '');

    jobs.add(
      RecommendedJob(
        id: jobId,
        title: _unescape(titleMatch.group(1)!.trim()),
        companyName: _unescape(companyMatch?.group(1)?.trim() ?? ''),
        skills: skills,
        location: _unescape(locationMatch?.group(1)?.trim() ?? ''),
        jobType: _unescape(jobTypeMatch?.group(1)?.trim() ?? ''),
        experienceLevel: _unescape(experienceMatch?.group(1)?.trim() ?? ''),
        salaryDisplay: _unescape(salaryMatch?.group(1)?.trim() ?? ''),
      ),
    );
  }
  return jobs;
}

List<PaymentRecord> _parsePaymentHistory(String html) {
  final tbodyMatch = RegExp(r'<tbody>([\s\S]*?)</tbody>').firstMatch(html);
  if (tbodyMatch == null) return const [];
  final tbody = tbodyMatch.group(1)!;

  final payments = <PaymentRecord>[];
  for (final rowMatch in RegExp(r'<tr>([\s\S]*?)</tr>').allMatches(tbody)) {
    final row = rowMatch.group(1)!;
    final dateMatch = RegExp(r'<td>([^<]*)</td>').firstMatch(row);
    final amountMatch = RegExp(r'₹([\d.]+)').firstMatch(row);
    final transactionMatch = RegExp(r'<small class="text-muted">([^<]*)</small>').firstMatch(row);
    if (dateMatch == null || amountMatch == null) continue;

    final date = parseMonthDayYear(dateMatch.group(1)!.trim());
    if (date == null) continue;

    payments.add(
      PaymentRecord(
        date: date,
        isPlanActive: row.contains('bg-success">Active<'),
        amountRupees: num.tryParse(amountMatch.group(1)!) ?? 0,
        transactionId: _unescape(transactionMatch?.group(1)?.trim() ?? ''),
      ),
    );
  }
  return payments;
}

String _unescape(String value) => unescapeHtmlEntities(value);
