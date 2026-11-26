import 'dart:io';

import 'package:career_buddy_lms/features/activities/data/activities_html_parser.dart';
import 'package:career_buddy_lms/features/activities/domain/entities/activity_progress_semantics.dart';
import 'package:career_buddy_lms/features/activities/domain/entities/sub_activity_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 90 — activity list / detail / sub-activity parsing against
/// sanitized fixtures derived from the previous web and CB 3.0 templates
/// (`test/fixtures/activities/*.html`). OFFLINE fixture validation only: it
/// proves parsing of source-derived markup, not the deployed backend.
String fixture(String name) => File('test/fixtures/activities/$name').readAsStringSync();

void main() {
  group('activity list', () {
    test('legacy: done marker (not rate==100) and plain "Progress" semantics', () {
      final data = parseActivityListHtml(fixture('list_legacy.html'));
      expect(data.activities, hasLength(3));
      final vocab = data.activities.first;
      expect(vocab.id, 4);
      expect(vocab.isCompleted, isTrue);
      expect(vocab.completionRate, 100);
      expect(vocab.progressSemantics, ActivityProgressSemantics.completion);
      expect(vocab.attemptedExercises, isNull);
      expect(vocab.totalExercises, isNull);
    });

    test('legacy: partial progress is not "completed"; untouched card has rate 0', () {
      final data = parseActivityListHtml(fixture('list_legacy.html'));
      expect(data.activities[1].completionRate, 40);
      expect(data.activities[1].isCompleted, isFalse);
      expect(data.activities[2].completionRate, 0);
      expect(data.activities[2].isCompleted, isFalse);
    });

    test('CB 3.0: score semantics with attempted/total exercises', () {
      final data = parseActivityListHtml(fixture('list_cb3.html'));
      final vocab = data.activities.first;
      expect(vocab.progressSemantics, ActivityProgressSemantics.score);
      expect(vocab.attemptedExercises, 7);
      expect(vocab.totalExercises, 7);
      expect(vocab.completionRate, 70);
    });

    test('CB 3.0: "completed" means all attempted — a 70% score is done but not perfect', () {
      final vocab = parseActivityListHtml(fixture('list_cb3.html')).activities.first;
      expect(vocab.isCompleted, isTrue);
      expect(vocab.completionRate, lessThan(100));
    });

    test('CB 3.0: a genuine 0% score with attempts keeps 0 and its real counts', () {
      final nego = parseActivityListHtml(fixture('list_cb3.html')).activities[1];
      expect(nego.completionRate, 0);
      expect(nego.attemptedExercises, 1);
      expect(nego.totalExercises, 5);
      expect(nego.isCompleted, isFalse);
    });

    test('CB 3.0: a not-started card has no counts (null, not 0/0)', () {
      final fresh = parseActivityListHtml(fixture('list_cb3.html')).activities[2];
      expect(fresh.attemptedExercises, isNull);
      expect(fresh.totalExercises, isNull);
      expect(fresh.isCompleted, isFalse);
    });

    test('a locked card is flagged; its button carries no link, so it gets no real id (never navigated)', () {
      final locked = parseActivityListHtml(fixture('list_cb3.html')).activities[3];
      expect(locked.isLocked, isTrue);
      expect(locked.title, 'Email Writing');
      expect(locked.id, lessThan(0));
    });

    test('a direct_url card (workshop) gets a synthetic NEGATIVE id; real ids are positive', () {
      final data = parseActivityListHtml(fixture('list_cb3.html'));
      final gd = data.activities.firstWhere((a) => a.title == 'Group Discussion');
      expect(gd.id, lessThan(0));
      expect(data.activities.where((a) => a.id > 0).length, 4);
    });

    test('perfect score card: done and 100', () {
      final perfect = parseActivityListHtml(fixture('list_cb3.html')).activities.last;
      expect(perfect.isCompleted, isTrue);
      expect(perfect.completionRate, 100);
    });

    test('empty list page (no matching activities) parses to an empty list, not a failure', () {
      final data = parseActivityListHtml(fixture('list_empty.html'));
      expect(data.activities, isEmpty);
    });

    test('category chips are still parsed', () {
      final data = parseActivityListHtml(fixture('list_cb3.html'));
      expect(data.categories.map((c) => c.value), ['speaking', 'workshop']);
    });

    test('a non-list page throws FormatException', () {
      expect(() => parseActivityListHtml('<html><body>Hello</body></html>'), throwsFormatException);
    });
  });

  group('activity detail', () {
    test('legacy: "Complete" ring is completion semantics with no exercise counts', () {
      final d = parseActivityDetailHtml(fixture('detail_legacy.html'), id: 4);
      expect(d.completionRate, 40);
      expect(d.progressSemantics, ActivityProgressSemantics.completion);
      expect(d.attemptedExercises, isNull);
      expect(d.totalExercises, isNull);
    });

    test('CB 3.0: "Score" ring with a/b exercises', () {
      final d = parseActivityDetailHtml(fixture('detail_cb3.html'), id: 4);
      expect(d.completionRate, 58);
      expect(d.progressSemantics, ActivityProgressSemantics.score);
      expect(d.attemptedExercises, 5);
      expect(d.totalExercises, 8);
    });

    test('sub-activity ids come from each card\'s own /activities/<a>/sub/<s>/ link', () {
      final d = parseActivityDetailHtml(fixture('detail_cb3.html'), id: 4);
      expect(d.subActivities.map((s) => s.id), [34, 35, 36]);
      expect(d.subActivities.map((s) => s.status), [
        SubActivityStatus.completed,
        SubActivityStatus.inProgress,
        SubActivityStatus.notStarted,
      ]);
    });

    test('CB 3.0 sub-activity Score badge is read; absent badge stays null (never 0)', () {
      final subs = parseActivityDetailHtml(fixture('detail_cb3.html'), id: 4).subActivities;
      expect(subs[0].scorePercent, 70);
      expect(subs[1].scorePercent, 45);
      expect(subs[2].scorePercent, isNull);
    });

    test('legacy sub cards have no score badge', () {
      final subs = parseActivityDetailHtml(fixture('detail_legacy.html'), id: 4).subActivities;
      expect(subs.every((s) => s.scorePercent == null), isTrue);
    });

    test('started/completed dates are parsed when present', () {
      final subs = parseActivityDetailHtml(fixture('detail_cb3.html'), id: 4).subActivities;
      expect(subs[0].startedAt, DateTime(2026, 9, 1));
      expect(subs[0].completedAt, DateTime(2026, 9, 1));
      expect(subs[2].startedAt, isNull);
    });

    test('detail title and objective survive reordered attributes and extra whitespace', () {
      const html = '''
<div  data-x="1"   class='x activity-detail-page'>
  <h1 data-a=1
      class='activity-hero-title  big'>  Spaced  Title </h1>
  <p class="activity-hero-objective" id="o">An objective.</p>
  <div class="hero-progress-ring"><div class='ring-value'> 12 %</div><div class="ring-label">Score</div></div>
</div>''';
      final d = parseActivityDetailHtml(html, id: 9);
      expect(d.title, 'Spaced Title');
      expect(d.description, 'An objective.');
      expect(d.completionRate, 12);
      expect(d.progressSemantics, ActivityProgressSemantics.score);
    });

    test('a non-detail page throws FormatException', () {
      expect(() => parseActivityDetailHtml('<html></html>', id: 1), throwsFormatException);
    });
  });

  group('sub-activity detail — identifiers', () {
    test('the id is the REQUESTED route id on CB 3.0 pages that carry no id in the body (never -1)', () {
      final d = parseSubActivityDetailHtml(fixture('sub_cb3_partial.html'), activityId: 4, subActivityId: 35);
      expect(d.id, 35);
      expect(d.activityId, 4);
    });

    test('a CB 3.0 page parsed WITHOUT a route id is rejected instead of yielding a sentinel id', () {
      expect(() => parseSubActivityDetailHtml(fixture('sub_cb3_partial.html'), activityId: 4), throwsFormatException);
    });

    test('a non-positive route id is not accepted as the id', () {
      expect(
        () => parseSubActivityDetailHtml(fixture('sub_cb3_partial.html'), activityId: 4, subActivityId: -1),
        throwsFormatException,
      );
      expect(
        () => parseSubActivityDetailHtml(fixture('sub_cb3_partial.html'), activityId: 4, subActivityId: 0),
        throwsFormatException,
      );
    });

    test('legacy page without a route id falls back to the form\'s own id', () {
      final d = parseSubActivityDetailHtml(fixture('sub_legacy_form.html'), activityId: 4);
      expect(d.id, 35);
    });

    test('exercise ids come from /activities/exercise/<id>/ links and are distinct from the sub id', () {
      final d = parseSubActivityDetailHtml(fixture('sub_cb3_partial.html'), activityId: 4, subActivityId: 35);
      expect(d.exercises.map((e) => e.id), [501, 502, 503]);
      expect(d.exercises.every((e) => e.id != d.id), isTrue);
      expect(d.exercises.map((e) => e.exerciseType), ['mcq', 'fill_blank', 'ordering']);
    });

    test('an exercise with a non-positive id link is skipped, never surfaced', () {
      final html = fixture('sub_cb3_partial.html').replaceAll('/activities/exercise/502/', '/activities/exercise/0/');
      final d = parseSubActivityDetailHtml(html, activityId: 4, subActivityId: 35);
      expect(d.exercises.map((e) => e.id), [501, 503]);
    });

    test('an exercise link that is not an exercise route is skipped (no fabricated destination)', () {
      final html = fixture('sub_cb3_partial.html').replaceAll('/activities/exercise/503/', '/somewhere/else/503/');
      final d = parseSubActivityDetailHtml(html, activityId: 4, subActivityId: 35);
      expect(d.exercises.map((e) => e.id), [501, 502]);
    });
  });

  group('sub-activity detail — legacy completion', () {
    test('legacy form with the lock text: completion action present, all-done false', () {
      final d = parseSubActivityDetailHtml(fixture('sub_legacy_form.html'), activityId: 4, subActivityId: 35);
      expect(d.completionMode, SubActivityCompletionMode.legacyForm);
      expect(d.canMarkComplete, isTrue);
      expect(d.allExercisesDone, isFalse);
    });

    test('legacy form without the lock text: all-done true', () {
      final d = parseSubActivityDetailHtml(fixture('sub_legacy_all_done.html'), activityId: 4, subActivityId: 35);
      expect(d.completionMode, SubActivityCompletionMode.legacyForm);
      expect(d.allExercisesDone, isTrue);
    });

    test('legacy completed banner: completedAt parsed, status completed', () {
      final d = parseSubActivityDetailHtml(fixture('sub_legacy_completed.html'), activityId: 4, subActivityId: 35);
      expect(d.completedAt, DateTime(2026, 9, 5));
      expect(d.status, SubActivityStatus.completed);
      expect(d.completionMode, SubActivityCompletionMode.legacyForm);
    });

    test('a legacy form for a DIFFERENT sub-activity does not enable the action', () {
      final d = parseSubActivityDetailHtml(fixture('sub_legacy_form.html'), activityId: 4, subActivityId: 99);
      expect(d.completionMode, SubActivityCompletionMode.unknown);
      expect(d.canMarkComplete, isFalse);
    });
  });

  group('sub-activity detail — CB 3.0 (automatic completion, score based)', () {
    test('no completion form: scoreBased mode, no manual completion possible', () {
      final d = parseSubActivityDetailHtml(fixture('sub_cb3_partial.html'), activityId: 4, subActivityId: 35);
      expect(d.completionMode, SubActivityCompletionMode.scoreBased);
      expect(d.canMarkComplete, isFalse);
    });

    test('partial: score, counts and in-progress status', () {
      final d = parseSubActivityDetailHtml(fixture('sub_cb3_partial.html'), activityId: 4, subActivityId: 35);
      expect(d.scorePercent, 45);
      expect(d.attemptedExercises, 1);
      expect(d.totalExercises, 3);
      expect(d.allExercisesDone, isFalse);
      expect(d.status, SubActivityStatus.inProgress);
      expect(d.completedAt, isNull);
    });

    test('all attempted at 70%: completed status, all-done true, still NOT a perfect score', () {
      final d = parseSubActivityDetailHtml(fixture('sub_cb3_all_attempted.html'), activityId: 4, subActivityId: 35);
      expect(d.status, SubActivityStatus.completed);
      expect(d.allExercisesDone, isTrue);
      expect(d.scorePercent, 70);
      expect(d.canMarkComplete, isFalse);
    });

    test('perfect score: 100 with all attempted', () {
      final d = parseSubActivityDetailHtml(fixture('sub_cb3_perfect.html'), activityId: 4, subActivityId: 35);
      expect(d.scorePercent, 100);
      expect(d.attemptedExercises, 3);
    });

    test('exercises keep attempted-vs-unattempted: lastAttempt only when a score was shown', () {
      final d = parseSubActivityDetailHtml(fixture('sub_cb3_partial.html'), activityId: 4, subActivityId: 35);
      expect(d.exercises[0].lastAttempt?.score, 7);
      expect(d.exercises[0].lastAttempt?.maxScore, 10);
      expect(d.exercises[0].lastAttempt?.percentage, 70);
      expect(d.exercises[1].lastAttempt, isNull);
    });

    test('no exercises: no score card, so every score field stays null (no 0%, no 0/0)', () {
      final d = parseSubActivityDetailHtml(fixture('sub_cb3_no_exercises.html'), activityId: 4, subActivityId: 35);
      expect(d.exercises, isEmpty);
      expect(d.scorePercent, isNull);
      expect(d.attemptedExercises, isNull);
      expect(d.totalExercises, isNull);
      expect(d.allExercisesDone, isFalse);
      expect(d.completionMode, SubActivityCompletionMode.unknown);
      expect(d.status, SubActivityStatus.notStarted);
    });

    test('a genuine 0% with 0/3 attempted is preserved as zero, not null', () {
      final html = fixture(
        'sub_cb3_partial.html',
      ).replaceAll('45%', '0%').replaceAll('1/3 exercises attempted', '0/3 exercises attempted');
      final d = parseSubActivityDetailHtml(html, activityId: 4, subActivityId: 35);
      expect(d.scorePercent, 0);
      expect(d.attemptedExercises, 0);
      expect(d.totalExercises, 3);
    });

    test('the removed legacy text never makes CB 3.0 look "all done" (previously always true)', () {
      final d = parseSubActivityDetailHtml(fixture('sub_cb3_partial.html'), activityId: 4, subActivityId: 35);
      expect(d.allExercisesDone, isFalse);
    });
  });

  group('sub-activity detail — markup variations', () {
    test('title, description, instructions and breadcrumb are read', () {
      final d = parseSubActivityDetailHtml(fixture('sub_cb3_partial.html'), activityId: 4, subActivityId: 35);
      expect(d.title, 'Meeting Phrases');
      expect(d.description, 'Phrases for meetings.');
      expect(d.instructions, 'Read each phrase. Then try the exercises.');
      expect(d.activityTitle, 'Business Vocabulary');
      expect(d.order, 2);
    });

    test('exercise cards with reordered attributes, single quotes and extra attributes still parse', () {
      const html = '''
<div class="sub-activity-hero"><h2 class="text-white mb-0">T</h2></div>
<div data-x="1" class='exercise-card  highlighted'>
  <div  id="i" class='exercise-type-icon   exercise-matching'></div>
  <div class="exercise-type-label">Matching</div>
  <h6 data-y=2
      class='exercise-title'>Match Them</h6>
  <a
     class="btn btn-primary btn-sm"
     href='/activities/exercise/77/'>Start</a>
</div>''';
      final d = parseSubActivityDetailHtml(html, activityId: 4, subActivityId: 35);
      expect(d.exercises.single.id, 77);
      expect(d.exercises.single.exerciseType, 'matching');
      expect(d.exercises.single.title, 'Match Them');
    });

    test('a page without the sub-activity marker throws FormatException', () {
      expect(
        () => parseSubActivityDetailHtml('<html></html>', activityId: 4, subActivityId: 35),
        throwsFormatException,
      );
    });
  });

  group('final review — progress percentage presence', () {
    test('CB 3.0 cards with a progress block have a known percentage', () {
      final data = parseActivityListHtml(fixture('list_cb3.html'));
      expect(data.activities.first.hasProgressPercent, isTrue);
    });

    test('a done card whose progress block is missing is NOT given a known score (placeholder 0 only)', () {
      final html = fixture('list_cb3.html').replaceAll(RegExp(r'<small class="fw-semibold[^>]*>[^<]*</small>'), '');
      final first = parseActivityListHtml(html).activities.first;
      expect(first.isCompleted, isTrue);
      expect(first.hasProgressPercent, isFalse);
    });

    test('a genuine 0% is a known percentage (distinct from a missing one)', () {
      final nego = parseActivityListHtml(fixture('list_cb3.html')).activities[1];
      expect(nego.completionRate, 0);
      expect(nego.hasProgressPercent, isTrue);
    });
  });
}
