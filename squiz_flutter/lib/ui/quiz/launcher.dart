import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/motion.dart';
import '../../data/bank.dart';
import '../../state/app_state.dart';
import '../../state/quiz_controller.dart';
import '../app_scope.dart';
import '../widgets/common.dart';
import 'quiz_page.dart';

/// Every way of starting a quiz goes through here so the rules (empty checks, unfinished-quiz warning, shuffling) are in one place.
class QuizLauncher {
  static List<Question> _pick(List<Question> all, {required bool shuffle, int? count}) {
    final list = List<Question>.of(all);
    if (shuffle) list.shuffle(Random());
    return count != null && list.length > count ? list.sublist(0, count) : list;
  }

  static Future<bool> _okToStart(BuildContext context, AppState app, bool oneOff) async {
    if (oneOff || app.resumable == null) return true;
    final r = app.resumable!;
    return confirmDialog(context,
        title: 'Discard unfinished quiz?', body: 'You have an unfinished ${r.mode == 'exam' ? 'exam' : 'practice'} "${r.title}". Starting a new one will discard it.', ok: 'Start new', danger: true);
  }

  static Future<void> practice(BuildContext context, {required String title, required List<Question> questions, bool shuffle = true, int? count, bool oneOff = false}) async {
    final app = AppScope.read(context);
    if (questions.isEmpty) return showSnack(context, 'No questions available here yet.');
    if (!await _okToStart(context, app, oneOff) || !context.mounted) return;
    final c = QuizController(app: app, mode: QuizMode.practice, title: title, questions: _pick(questions, shuffle: shuffle, count: count), recordHistory: !oneOff);
    await pushPage(context, QuizPage(controller: c));
  }

  static Future<void> exam(BuildContext context, {required String title, required List<Question> questions, int? count, int? minutes}) async {
    final app = AppScope.read(context);
    if (questions.isEmpty) return showSnack(context, 'No questions available here yet.');
    if (!await _okToStart(context, app, false) || !context.mounted) return;
    final c = QuizController(app: app, mode: QuizMode.exam, title: title, questions: _pick(questions, shuffle: true, count: count), limitSeconds: minutes == null ? null : minutes * 60);
    await pushPage(context, QuizPage(controller: c));
  }

  /// Rebuilds the unfinished run from its saved question keys. Questions removed from the bank since are dropped.
  static Future<void> resume(BuildContext context) async {
    final app = AppScope.read(context);
    final s = app.resumable, bank = app.bank;
    if (s == null || bank == null) return;
    final keep = <int>[];
    final qs = <Question>[];
    for (final (i, k) in s.keys.indexed) {
      final q = bank.byKey[k];
      if (q != null) {
        keep.add(i);
        qs.add(q);
      }
    }
    if (qs.isEmpty) {
      await app.saveSession(null);
      if (context.mounted) showSnack(context, 'That quiz is no longer available.');
      return;
    }
    // question positions shift when some were removed: remap saved answers/marks to the new positions
    final remap = {for (final (n, old) in keep.indexed) old: n};
    final fixed = SavedSession(
      mode: s.mode,
      title: s.title,
      keys: [for (final q in qs) q.key],
      choices: {for (final e in s.choices.entries) if (remap[e.key] != null) remap[e.key]!: e.value},
      marked: {for (final m in s.marked) if (remap[m] != null) remap[m]!},
      index: remap[s.index] ?? 0,
      startedMs: s.startedMs,
      endsMs: s.endsMs,
      limitSeconds: s.limitSeconds,
    );
    final c = QuizController(app: app, mode: s.mode == 'exam' ? QuizMode.exam : QuizMode.practice, title: s.title, questions: qs, resume: fixed);
    await pushPage(context, QuizPage(controller: c));
  }
}
