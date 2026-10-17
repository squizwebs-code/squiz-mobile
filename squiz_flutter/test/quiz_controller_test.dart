import 'package:flutter_test/flutter_test.dart';
import 'package:squiz/state/quiz_controller.dart';
import 'helpers.dart';

void main() {
  test('practice: first tap locks the answer and is recorded at once', () async {
    final app = await makeApp();
    final qs = app.bank!.questionsFor(11, subject: 'math');
    final c = QuizController(app: app, mode: QuizMode.practice, title: 't', questions: qs);
    final q = c.current;
    final wrong = (q.answer + 1) % q.options.length;
    expect(c.select(wrong), isTrue);
    expect(c.select(q.answer), isFalse); // locked
    expect(app.answers[q.key]!.on, isFalse);
    c.dispose();
  });

  test('practice: cannot skip ahead past an unanswered question', () async {
    final app = await makeApp();
    final c = QuizController(app: app, mode: QuizMode.practice, title: 't', questions: app.bank!.questionsFor(11));
    c.goTo(2);
    expect(c.index, 0);
    c.select(0);
    c.goTo(1);
    expect(c.index, 1);
    c.dispose();
  });

  test('exam: answers can change, nothing is recorded until finish, finish scores', () async {
    final app = await makeApp();
    final qs = app.bank!.questionsFor(11, subject: 'math');
    final c = QuizController(app: app, mode: QuizMode.exam, title: 't', questions: qs);
    c.select((c.current.answer + 1) % c.current.options.length);
    c.select(c.current.answer); // change to the right one
    expect(app.answers, isEmpty);
    final s = c.finish();
    expect(s.total, 2);
    expect(s.correct, 1);
    expect(s.skipped, 1);
    expect(app.answers.length, 1);
    expect(app.history.length, 1);
    expect(c.finish(), same(s)); // finishing twice does not double count
    expect(app.history.length, 1);
    c.dispose();
  });

  test('exam: tapping the chosen option again clears it', () async {
    final app = await makeApp();
    final c = QuizController(app: app, mode: QuizMode.exam, title: 't', questions: app.bank!.questionsFor(11));
    c.select(0);
    c.select(0);
    expect(c.answered, isFalse);
    c.dispose();
  });

  test('timer: countdown reaches zero from the clock', () async {
    var now = 1000000;
    final app = await makeApp(nowMs: () => now);
    final c = QuizController(app: app, mode: QuizMode.exam, title: 't', questions: app.bank!.questionsFor(11), limitSeconds: 60);
    expect(c.secondsLeft, 60);
    now += 61000;
    expect(c.secondsLeft, 0);
    final s = c.finish(timedOut: true);
    expect(s.timedOut, isTrue);
    c.dispose();
  });

  test('one-off runs record answers but not history', () async {
    final app = await makeApp();
    final c = QuizController(app: app, mode: QuizMode.practice, title: 't', questions: app.bank!.questionsFor(11).take(1).toList(), recordHistory: false);
    c.select(0);
    c.finish();
    expect(app.history, isEmpty);
    c.dispose();
  });
}
