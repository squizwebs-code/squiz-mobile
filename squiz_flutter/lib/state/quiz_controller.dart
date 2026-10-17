import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../data/bank.dart';
import '../data/models.dart';
import 'app_state.dart';

enum QuizMode { practice, exam }

class QuestionResult {
  const QuestionResult(this.question, this.choice, this.marked);
  final Question question;
  final int? choice;
  final bool marked;
  bool get skipped => choice == null;
  bool get correct => choice != null && choice == question.answer;
}

class QuizSummary {
  const QuizSummary({required this.title, required this.mode, required this.results, required this.seconds, required this.timedOut});
  final String title;
  final QuizMode mode;
  final List<QuestionResult> results;
  final int seconds;
  final bool timedOut;
  int get total => results.length;
  int get correct => results.where((r) => r.correct).length;
  int get skipped => results.where((r) => r.skipped).length;
  int get wrong => total - correct - skipped;
  int get percent => total == 0 ? 0 : (correct * 100 / total).round();
}

/// Rules for one quiz run.
///  practice: an answer locks as soon as it is chosen and feedback shows at once; every answer is recorded immediately.
///  exam: answers can be changed until submit, nothing is revealed, a countdown can end it, answers are recorded at submit.
/// The run is saved after every change, so closing the app never loses it.
class QuizController extends ChangeNotifier {
  QuizController({required this.app, required this.mode, required this.title, required this.questions, int? limitSeconds, SavedSession? resume, this.recordHistory = true, int Function()? nowMs})
      : _now = nowMs ?? app.nowMs,
        limitSeconds = limitSeconds ?? resume?.limitSeconds {
    final r = resume;
    if (r != null) {
      choices.addAll(r.choices);
      marked.addAll(r.marked);
      index = r.index.clamp(0, max(0, questions.length - 1));
      startedMs = r.startedMs;
      endsMs = r.endsMs;
    } else {
      startedMs = _now();
      if (this.limitSeconds != null) endsMs = startedMs + this.limitSeconds! * 1000;
    }
  }

  final AppState app;
  final QuizMode mode;
  final String title;
  final List<Question> questions;
  final int? limitSeconds;
  final bool recordHistory; // false for one-off "practise this question" runs
  final int Function() _now;

  final Map<int, int> choices = {};
  final Set<int> marked = {};
  int index = 0;
  late final int startedMs;
  int? endsMs;
  Timer? _timer;
  bool finished = false;
  QuizSummary? summary;

  bool get isExam => mode == QuizMode.exam;
  Question get current => questions[index];
  int? get choice => choices[index];
  bool get answered => choices.containsKey(index);
  int get answeredCount => choices.length;
  bool get isLast => index == questions.length - 1;

  /// null when there is no timer.
  int? get secondsLeft => endsMs == null ? null : max(0, ((endsMs! - _now()) / 1000).ceil());

  void start() {
    if (endsMs != null) {
      if (secondsLeft == 0) {
        scheduleMicrotask(() => finish(timedOut: true));
        return;
      }
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (finished) return;
        if (secondsLeft == 0) {
          finish(timedOut: true);
        } else {
          notifyListeners();
        }
      });
    }
  }

  /// Returns true when the tap changed something.
  bool select(int option) {
    if (finished || option < 0 || option >= current.options.length) return false;
    if (!isExam && answered) return false; // practice answers are locked
    if (isExam && choices[index] == option) {
      choices.remove(index); // tapping the chosen option again clears it
    } else {
      choices[index] = option;
      if (!isExam) app.recordAnswer(current, option == current.answer);
    }
    _save();
    notifyListeners();
    return true;
  }

  void toggleMark() {
    if (!marked.remove(index)) marked.add(index);
    _save();
    notifyListeners();
  }

  void goTo(int i) {
    if (i < 0 || i >= questions.length || i == index) return;
    // practice: you can go back freely but not past the first unanswered question
    if (!isExam && i > index && !answered) return;
    index = i;
    _save();
    notifyListeners();
  }

  void next() => goTo(index + 1);
  void prev() => goTo(index - 1);

  QuizSummary finish({bool timedOut = false}) {
    if (summary != null) return summary!;
    finished = true;
    _timer?.cancel();
    final results = [for (var i = 0; i < questions.length; i++) QuestionResult(questions[i], choices[i], marked.contains(i))];
    if (isExam) {
      for (final r in results) {
        if (!r.skipped) app.recordAnswer(r.question, r.correct);
      }
    }
    final seconds = max(0, ((min(_now(), endsMs ?? _now()) - startedMs) / 1000).round());
    summary = QuizSummary(title: title, mode: mode, results: results, seconds: seconds, timedOut: timedOut);
    if (recordHistory) app.addHistory(HistoryItem(id: app.newId(), title: title, mode: isExam ? 'exam' : 'practice', total: summary!.total, correct: summary!.correct, ts: _now(), seconds: seconds));
    unawaited(app.saveSession(null));
    notifyListeners();
    return summary!;
  }

  /// Leaving without finishing keeps the run so it can be resumed from Home.
  void _save() {
    if (finished || !recordHistory) return; // one-off runs are not resumable either
    unawaited(app.saveSession(SavedSession(mode: mode.name, title: title, keys: [for (final q in questions) q.key], choices: Map.of(choices), marked: Set.of(marked), index: index, startedMs: startedMs, endsMs: endsMs, limitSeconds: limitSeconds)));
  }

  void saveNow() => _save();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
