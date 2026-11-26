import 'dart:io';

import 'package:career_buddy_lms/features/dashboard/data/dashboard_html_parser.dart';
import 'package:career_buddy_lms/features/dashboard/domain/entities/activity_progress.dart';
import 'package:career_buddy_lms/features/dashboard/domain/entities/dashboard_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 89 — dashboard parser against sanitized, source-derived fixtures
/// (`test/fixtures/dashboard/*.html`, derived from the rendered shape of
/// `CB_3.0/frontend/templates/dashboard.html` and the previous web's
/// `templates/dashboard.html`). These are OFFLINE fixture tests: they prove
/// the parser against source-derived markup, not against the deployed
/// backend.
String fixture(String name) => File('test/fixtures/dashboard/$name').readAsStringSync();

void main() {
  group('legacy dashboard (previous web)', () {
    late DashboardData data;
    setUp(() => data = parseDashboardHtml(fixture('dashboard_legacy_subactivities.html')));

    test('is detected as the legacy generation', () {
      expect(data.generation, DashboardMarkupGeneration.legacy);
    });

    test('parses MULTILINE activity links (newline between href and class) — the confirmed regression', () {
      expect(data.activities, hasLength(3));
      expect(data.activities.map((a) => a.activityId), [4, 7, 9]);
      expect(data.activities.map((a) => a.title), ['Business Vocabulary', 'Negotiation', 'Presentations']);
    });

    test('preserves legacy count-based progress when genuinely present', () {
      final first = data.activities.first;
      expect(first.basis, ProgressBasis.subActivities);
      expect(first.semantics, ProgressSemantics.completion);
      expect(first.completedSubActivities, 3);
      expect(first.totalSubActivities, 5);
      expect(first.completionRate, 60);
      expect(first.startedAt, DateTime(2026, 9, 1));
    });

    test('a legitimate legacy 0/4 stays 0/4, distinct from missing counts', () {
      final second = data.activities[1];
      expect(second.completedSubActivities, 0);
      expect(second.totalSubActivities, 4);
      expect(second.completionRate, 0);
      expect(second.startedAt, isNull);
    });

    test('legacy 100% is a completion percentage', () {
      expect(data.activities[2].completionRate, 100);
      expect(data.activities[2].semantics, ProgressSemantics.completion);
    });

    test('order prefix is captured as order, not as the id', () {
      expect(data.activities.first.order, 1);
      expect(data.activities.first.activityId, 4);
    });
  });

  group('CB 3.0 dashboard (score-based)', () {
    late DashboardData data;
    setUp(() => data = parseDashboardHtml(fixture('dashboard_cb3_scores.html')));

    test('is detected as the cb3 generation', () {
      expect(data.generation, DashboardMarkupGeneration.cb3);
    });

    test('parses all seven rows with multiline anchors', () {
      expect(data.activities, hasLength(7));
      expect(data.activities.map((a) => a.order), [1, 2, 3, 4, 5, 6, 7]);
    });

    test('exercise counters become attempted/total — never sub-activity counts, never 0/0', () {
      final email = data.activities[1];
      expect(email.basis, ProgressBasis.exercises);
      expect(email.semantics, ProgressSemantics.score);
      expect(email.attemptedExercises, 7);
      expect(email.totalExercises, 7);
      expect(email.completedSubActivities, isNull);
      expect(email.totalSubActivities, isNull);
      expect(email.completionRate, 70);
      expect(email.band, ProgressBand.warning);
    });

    test('a legitimate 0 percent / 0 attempted stays 0 (not null), with muted band', () {
      final first = data.activities.first;
      expect(first.completionRate, 0);
      expect(first.attemptedExercises, 0);
      expect(first.totalExercises, 6);
      expect(first.band, ProgressBand.muted);
    });

    test('score semantics: 100 vs attempted are different things (7/7 attempted at 70% score)', () {
      final email = data.activities[1];
      expect(email.attemptedExercises, email.totalExercises);
      expect(email.completionRate, lessThan(100));
    });

    test('danger and success bands are read from the server class', () {
      expect(data.activities[2].band, ProgressBand.danger);
      expect(data.activities[3].band, ProgressBand.success);
    });

    test('workshop rows: session count, fractional score preserved', () {
      final gd = data.activities[4];
      expect(gd.basis, ProgressBasis.workshopSessions);
      expect(gd.sessionCount, 2);
      expect(gd.completionRate, 78.5);
      expect(gd.activityId, isNull); // `/gd/` is not an activity detail page
      expect(gd.isNavigable, isFalse);
    });

    test('"No sessions yet" is a legitimate zero sessions', () {
      final jam = data.activities[5];
      expect(jam.basis, ProgressBasis.workshopSessions);
      expect(jam.sessionCount, 0);
    });

    test('"No scored exercises" has no counts at all', () {
      final reading = data.activities[6];
      expect(reading.basis, ProgressBasis.noScoredExercises);
      expect(reading.attemptedExercises, isNull);
      expect(reading.totalExercises, isNull);
      expect(reading.completedSubActivities, isNull);
    });

    test('stats: fractional total score preserved', () {
      expect(data.stats.totalActivities, 23);
      expect(data.stats.completedCount, 2);
      expect(data.stats.inProgressCount, 3);
      expect(data.stats.totalScore, 310.5);
    });
  });

  group('module rows and href kinds', () {
    test('a module row links to an EXERCISE id: it is not treated as an activity id and is not navigable', () {
      final data = parseDashboardHtml(fixture('dashboard_cb3_module_direct.html'));
      final module = data.activities.first;
      expect(module.linkKind, ActivityLinkKind.moduleExercise);
      expect(module.exerciseId, 37);
      expect(module.activityId, isNull);
      expect(module.isNavigable, isFalse);
      // The ordinary row next to it is unaffected.
      expect(data.activities[1].activityId, 4);
      expect(data.activities[1].isNavigable, isTrue);
    });
  });

  group('empty, partial and malformed pages', () {
    test('empty dashboard (template empty-state) parses to an empty list, not a failure', () {
      final data = parseDashboardHtml(fixture('dashboard_cb3_empty_activities.html'));
      expect(data.activities, isEmpty);
      expect(data.stats.totalActivities, 23);
      expect(data.generation, DashboardMarkupGeneration.cb3); // from "Progress is based on your scores"
    });

    test('missing stat tiles are null — never a fabricated 0', () {
      final data = parseDashboardHtml(fixture('dashboard_missing_stats.html'));
      expect(data.stats.totalActivities, isNull);
      expect(data.stats.completedCount, isNull);
      expect(data.stats.inProgressCount, isNull);
      expect(data.stats.totalScore, isNull);
      expect(data.activities, hasLength(1));
    });

    test('a page cut off mid-row keeps the complete row(s) and parses the partial one tolerantly', () {
      final data = parseDashboardHtml(fixture('dashboard_truncated.html'));
      expect(data.activities.first.title, 'Business Vocabulary');
      expect(data.activities.first.attemptedExercises, 3);
      // The cut-off row has a title but no counter/percent: counts stay null.
      final partial = data.activities.where((a) => a.title == 'Email Writing');
      for (final a in partial) {
        expect(a.attemptedExercises, isNull);
        expect(a.completedSubActivities, isNull);
      }
    });

    test('a page with no dashboard marker throws FormatException', () {
      expect(() => parseDashboardHtml(fixture('dashboard_unknown_page.html')), throwsFormatException);
    });

    test('an activity section whose rows are not recognised is reported, not shown as an empty dashboard', () {
      final changed = fixture('dashboard_cb3_scores.html').replaceAll('progress-activity-item', 'renamed-row');
      expect(() => parseDashboardHtml(changed), throwsFormatException);
    });

    test('rows present but with no usable link throw instead of returning an empty list', () {
      final broken = fixture('dashboard_cb3_scores.html').replaceAll('progress-activity-link', 'renamed-link');
      expect(() => parseDashboardHtml(broken), throwsFormatException);
    });

    test('a missing counter leaves counts null with unknown basis', () {
      final html = fixture('dashboard_cb3_scores.html').replaceAll('3/5 exercises attempted', '');
      final data = parseDashboardHtml(html);
      final row = data.activities[2];
      expect(row.basis, ProgressBasis.unknown);
      expect(row.attemptedExercises, isNull);
      expect(row.totalExercises, isNull);
      expect(row.completedSubActivities, isNull);
      expect(row.completionRate, 45); // percent still parsed
      expect(row.semantics, ProgressSemantics.score); // from the page's generation
    });

    test('a missing percentage leaves completionRate null — no invented percentage', () {
      final html = fixture(
        'dashboard_cb3_scores.html',
      ).replaceAll(RegExp(r'<span class="progress-activity-pct[\s\S]*?</span>'), '');
      final data = parseDashboardHtml(html);
      expect(data.activities.every((a) => a.completionRate == null), isTrue);
      expect(data.activities.first.attemptedExercises, 0); // counts unaffected
    });
  });

  group('markup variations (attribute order, quoting, whitespace, extra attributes)', () {
    test('attributes in a different order, extra attributes, single quotes and extra spaces still parse', () {
      const html = '''
<div   data-x="1"   class='dashboard-welcome  extra'  ></div>
<div class="stat-card-value">1</div><div class="stat-card-value">2</div>
<div class="stat-card-value">3</div><div class="stat-card-value">4</div>
<div id="r1" class='progress-activity-item  highlighted'>
  <a
      data-track="x"
      class='progress-activity-link   big'

      title="Open"
      href='/activities/11/'  >
    <span   style="x"  class="progress-activity-name  fw">1.   Spaced   Out </span>
    <span  title="Score-based progress"
       class="a progress-activity-pct text-success b">  88 % </span>
    <small   class='text-muted'>
        5 / 5   exercises   attempted
    </small>
  </a>
</div>
''';
      final data = parseDashboardHtml(html);
      expect(data.activities, hasLength(1));
      final a = data.activities.single;
      expect(a.activityId, 11);
      expect(a.title, 'Spaced Out');
      expect(a.completionRate, 88);
      expect(a.attemptedExercises, 5);
      expect(a.totalExercises, 5);
      expect(a.band, ProgressBand.success);
    });

    test('a ">" inside an attribute value does not break tag scanning', () {
      const html = '''
<div class="dashboard-welcome"></div>
<div class="progress-activity-item"><a onclick="if(a>b){x()}" href="/activities/3/" class="progress-activity-link">
<span class="progress-activity-name">1. Tricky</span><span class="progress-activity-pct text-muted">0%</span>
<small>0/2 exercises attempted</small></a></div>
''';
      final data = parseDashboardHtml(html);
      expect(data.activities.single.activityId, 3);
      expect(data.activities.single.totalExercises, 2);
    });

    test('markup inside HTML comments is ignored', () {
      const html = '''
<div class="dashboard-welcome"></div>
<!-- <div class="progress-activity-item"><a href="/activities/99/" class="progress-activity-link"><span class="progress-activity-name">1. Ghost</span></a></div> -->
<div class="progress-activity-item"><a href="/activities/3/" class="progress-activity-link">
<span class="progress-activity-name">1. Real</span><span class="progress-activity-pct text-muted">0%</span>
<small>0/2 exercises attempted</small></a></div>
''';
      final data = parseDashboardHtml(html);
      expect(data.activities.map((a) => a.title), ['Real']);
    });

    test('HTML-escaped titles are unescaped', () {
      final html = fixture('dashboard_cb3_scores.html').replaceAll('Email Writing', 'Q&amp;A &amp; Email');
      expect(parseDashboardHtml(html).activities[1].title, 'Q&A & Email');
    });

    test('final review: unquoted attributes, uppercase tags/attributes and escaped entities in href/title parse', () {
      const html = '''
<DIV CLASS=dashboard-welcome></DIV>
<DIV CLASS="progress-activity-item"><A HREF="/activities/21/?from=dash&amp;x=1" CLASS=progress-activity-link>
<SPAN CLASS="progress-activity-name">3. Tom&#x27;s &quot;Big&quot; Day</SPAN><SPAN CLASS="progress-activity-pct text-danger">12%</SPAN>
<SMALL>1/8 exercises attempted</SMALL></A></DIV>
''';
      final a = parseDashboardHtml(html).activities.single;
      expect(a.activityId, 21);
      expect(a.title, 'Tom\'s "Big" Day');
      expect(a.order, 3);
      expect(a.band, ProgressBand.danger);
      expect(a.attemptedExercises, 1);
    });

    test('final review: an exercise href with a query string still yields an exercise id, never an activity id', () {
      const html = '''
<div class="dashboard-welcome"></div>
<div class="progress-activity-item"><a href="/activities/exercise/37/?x=1" class="progress-activity-link">
<span class="progress-activity-name">1. M</span><span class="progress-activity-pct text-muted">0%</span>
<small>0/2 exercises attempted</small></a></div>
''';
      final a = parseDashboardHtml(html).activities.single;
      expect(a.exerciseId, 37);
      expect(a.activityId, isNull);
    });

    test(
      'final review: absent "Activity Progress" section + marker-only page is a genuine minimal dashboard (empty list)',
      () {
        final data = parseDashboardHtml('<div class="dashboard-welcome"></div><div class="stat-card-value">1</div>');
        expect(data.activities, isEmpty);
      },
    );

    test(
      'final review: an unrelated page that merely mentions "Activity Progress" without the marker is not a dashboard',
      () {
        expect(() => parseDashboardHtml('<h5>Activity Progress</h5><p>hello</p>'), throwsFormatException);
      },
    );
  });

  group('other sections are unchanged', () {
    test('jobs, payments and recent results still parse (incl. job department line in a card)', () {
      final unlocked = parseDashboardHtml(fixture('dashboard_cb3_jobs_unlocked.html'));
      expect(unlocked.interviewScore, 92);
      expect(unlocked.recommendedJobs, hasLength(2));
      expect(unlocked.recommendedJobs.first.id, 42);
      expect(unlocked.recommendedJobs.first.title, 'Customer Support Executive');

      final locked = parseDashboardHtml(fixture('dashboard_cb3_jobs_locked.html'));
      expect(locked.recommendedJobs, isEmpty);
      expect(locked.interviewScore, isNull);

      final pay = parseDashboardHtml(fixture('dashboard_payments_recent_results.html'));
      expect(pay.paymentHistory, hasLength(2));
      expect(pay.paymentHistory.first.isPlanActive, isTrue);
      expect(pay.paymentHistory.last.isPlanActive, isFalse);
      expect(pay.paymentHistory.first.amountRupees, 499);
      expect(pay.recentResults, hasLength(3));
      expect(pay.recentResults[1].score, 17.5);
    });
  });
}
