import 'package:flutter/material.dart';
import '../../core/brand.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../data/api.dart' show kApiBaseUrl;
import '../../data/bank.dart';
import '../../state/quiz_controller.dart';
import '../app_scope.dart';
import '../widgets/common.dart';
import '../matric/matric.dart';
import 'result_page.dart';

class QuizPage extends StatefulWidget {
  const QuizPage({super.key, required this.controller});
  final QuizController controller;
  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  QuizController get c => widget.controller;
  int _dir = 1;
  late int _last = c.index;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    c.start();
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    c.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    if (c.index != _last) {
      _dir = c.index > _last ? 1 : -1;
      _last = c.index;
    }
    if (c.finished && c.summary != null && !_navigated) {
      _navigated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) replacePage(context, ResultPage(summary: c.summary!));
      });
    }
    setState(() {});
  }

  Future<void> _close() async {
    if (c.finished) return Navigator.of(context).pop();
    if (c.isExam && c.recordHistory) {
      final ok = await confirmDialog(context, title: 'Leave this exam?', body: c.endsMs == null ? 'Your answers are saved. You can resume from Home.' : 'Your answers are saved, but the timer keeps running. Resume from Home before time is up.', ok: 'Leave');
      if (!ok || !mounted) return;
    }
    c.saveNow();
    if (mounted) {
      if (!c.isExam && c.recordHistory) showSnack(context, 'Progress saved. Resume from Home.');
      Navigator.of(context).pop();
    }
  }

  Future<void> _finish() async {
    if (c.isExam) {
      final left = c.questions.length - c.answeredCount;
      final parts = [if (left > 0) '$left unanswered.', if (c.marked.isNotEmpty) '${c.marked.length} marked for review.', 'You cannot change answers after submitting.'];
      if (!await confirmDialog(context, title: 'Submit exam?', body: parts.join(' '), ok: 'Submit')) return;
    }
    c.finish();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(tooltip: 'Leave quiz', icon: const Icon(Icons.close_rounded), onPressed: _close),
          titleSpacing: 0,
          title: Row(children: [
            Pill(c.isExam ? 'Exam' : 'Practice', icon: c.isExam ? Icons.timer_rounded : Icons.bolt_rounded),
            const SizedBox(width: 10),
            Expanded(child: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.titleSmall)),
          ]),
          actions: [if (c.secondsLeft != null) _TimerChip(seconds: c.secondsLeft!), const SizedBox(width: 8)],
        ),
        body: SafeArea(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -350) c.next();
              if (v > 350) c.prev();
            },
            child: Column(children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: _Segments(c: c)),
              Expanded(
                child: AnimatedSwitcher(
                  duration: Motion.d(context, 280),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, anim) {
                    final incoming = child.key == ValueKey(c.index);
                    final begin = Offset(incoming ? .12 * _dir : -.12 * _dir, 0);
                    return FadeTransition(opacity: anim, child: SlideTransition(position: Tween(begin: begin, end: Offset.zero).animate(anim), child: child));
                  },
                  child: _QuestionView(key: ValueKey(c.index), c: c),
                ),
              ),
              _BottomBar(c: c, onFinish: _finish),
            ]),
          ),
        ),
      ),
    );
  }
}

class _TimerChip extends StatelessWidget {
  const _TimerChip({required this.seconds});
  final int seconds;
  @override
  Widget build(BuildContext context) {
    final low = seconds <= 60;
    final warn = seconds <= 300;
    final color = low ? context.cs.error : (warn ? kWarn : context.cs.onSurface);
    return Semantics(
      liveRegion: low,
      label: 'Time left ${seconds ~/ 60} minutes ${seconds % 60} seconds',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(99), border: Border.all(color: color.withValues(alpha: .5))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.timer_outlined, size: 18, color: color),
          const SizedBox(width: 6),
          Text(mmss(seconds), style: TextStyle(fontWeight: FontWeight.w800, color: color, fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }
}

class _Segments extends StatelessWidget {
  const _Segments({required this.c});
  final QuizController c;
  @override
  Widget build(BuildContext context) {
    final n = c.questions.length;
    if (n > 40) return ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: (c.index + 1) / n, minHeight: 6));
    return Row(children: [
      for (var i = 0; i < n; i++)
        Expanded(
          child: AnimatedContainer(
            duration: Motion.d(context, 250),
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(color: _color(context, i), borderRadius: BorderRadius.circular(99)),
          ),
        ),
    ]);
  }

  Color _color(BuildContext context, int i) {
    final ch = c.choices[i];
    if (ch != null) {
      if (c.isExam) return context.cs.primary;
      return ch == c.questions[i].answer ? context.sq.good : context.sq.bad;
    }
    return i == c.index ? context.cs.primary.withValues(alpha: .45) : context.cs.outlineVariant;
  }
}

class _QuestionView extends StatelessWidget {
  const _QuestionView({super.key, required this.c});
  final QuizController c;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final q = c.current;
    final chosen = c.choice;
    final reveal = !c.isExam && chosen != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        Row(children: [
          Text('QUESTION ${c.index + 1} OF ${c.questions.length}', style: context.tt.labelMedium?.copyWith(color: context.sq.link, letterSpacing: .8, fontWeight: FontWeight.w800)),
          const Spacer(),
          if (c.isExam)
            FilterChip(
              avatar: Icon(c.marked.contains(c.index) ? Icons.flag_rounded : Icons.outlined_flag_rounded, size: 18),
              label: const Text('Review later'),
              selected: c.marked.contains(c.index),
              onSelected: (_) => c.toggleMark(),
            )
          else ...[
            IconButton(
              tooltip: app.isBookmarked(q.key) ? 'Remove bookmark' : 'Bookmark this question',
              icon: Icon(app.isBookmarked(q.key) ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: app.isBookmarked(q.key) ? context.cs.primary : null),
              onPressed: () => app.toggleBookmark(q),
            ),
            IconButton(tooltip: 'Report a problem with this question', icon: const Icon(Icons.report_gmailerrorred_rounded), onPressed: () => showReportSheet(context, q)),
            IconButton(
              tooltip: app.isFlagged(q.key) ? 'Remove flag' : 'Flag as difficult',
              icon: Icon(app.isFlagged(q.key) ? Icons.flag_rounded : Icons.outlined_flag_rounded, color: app.isFlagged(q.key) ? kWarn : null),
              onPressed: () => app.toggleFlag(q),
            ),
          ],
        ]),
        const SizedBox(height: 4),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(q.text, style: context.tt.titleLarge?.copyWith(height: 1.35, fontWeight: FontWeight.w700)),
              if (q.image != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.network(q.image!.startsWith('http') ? q.image! : '$kApiBaseUrl${q.image}', errorBuilder: (_, __, ___) => const Text('Image unavailable offline'))),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < q.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _OptionTile(
              letter: String.fromCharCode(65 + i),
              text: q.options[i],
              state: _stateFor(i, q, chosen, reveal),
              onTap: () {
                if (c.select(i) && !c.isExam) {
                  (i == q.answer) ? Haptic.good() : Haptic.bad();
                }
              },
            ),
          ),
        AnimatedSize(
          duration: Motion.d(context, 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: reveal ? _Feedback(q: q, correct: chosen == q.answer) : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  _OptState _stateFor(int i, Question q, int? chosen, bool reveal) {
    if (reveal) {
      if (i == q.answer) return _OptState.correct;
      if (i == chosen) return _OptState.wrong;
      return _OptState.dim;
    }
    return i == chosen ? _OptState.selected : _OptState.idle;
  }
}

enum _OptState { idle, selected, correct, wrong, dim }

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.letter, required this.text, required this.state, required this.onTap});
  final String letter, text;
  final _OptState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final sq = context.sq;
    final (Color border, Color fill, Color accent) = switch (state) {
      _OptState.correct => (sq.good, sq.good.withValues(alpha: .12), sq.good),
      _OptState.wrong => (sq.bad, sq.bad.withValues(alpha: .12), sq.bad),
      _OptState.selected => (cs.primary, cs.primary.withValues(alpha: .12), cs.primary),
      _OptState.dim => (cs.outlineVariant, cs.surface, cs.outline),
      _OptState.idle => (cs.outlineVariant, cs.surface, cs.outline),
    };
    final locked = state == _OptState.correct || state == _OptState.wrong || state == _OptState.dim;
    final emphasised = state == _OptState.correct || state == _OptState.wrong || state == _OptState.selected;
    final spoken = switch (state) {
      _OptState.correct => ', correct answer',
      _OptState.wrong => ', your answer, incorrect',
      _OptState.selected => ', selected',
      _ => '',
    };
    return Semantics(
      button: true,
      enabled: !locked,
      label: 'Option $letter: $text$spoken',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: Motion.d(context, 240),
        curve: Curves.easeOut,
        decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(18), border: Border.all(color: border, width: emphasised ? 2 : 1)),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: locked ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                AnimatedContainer(
                  duration: Motion.d(context, 240),
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: emphasised ? accent : cs.surfaceContainerHigh),
                  child: AnimatedSwitcher(
                    duration: Motion.d(context, 200),
                    transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                    child: switch (state) {
                      _OptState.correct => const Icon(Icons.check_rounded, key: ValueKey('ok'), size: 20, color: Colors.white),
                      _OptState.wrong => const Icon(Icons.close_rounded, key: ValueKey('no'), size: 20, color: Colors.white),
                      _OptState.selected => Text(letter, key: const ValueKey('sel'), style: const TextStyle(fontWeight: FontWeight.w800, color: kOnBrand)),
                      _ => Text(letter, key: ValueKey('l$letter'), style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
                    },
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(text, style: TextStyle(fontSize: 16, height: 1.35, fontWeight: emphasised ? FontWeight.w700 : FontWeight.w500, color: state == _OptState.dim ? cs.onSurfaceVariant : cs.onSurface)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Feedback extends StatelessWidget {
  const _Feedback({required this.q, required this.correct});
  final Question q;
  final bool correct;
  @override
  Widget build(BuildContext context) {
    final color = correct ? context.sq.good : context.sq.bad;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(18), border: Border.all(color: color.withValues(alpha: .4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(correct ? Icons.check_circle_rounded : Icons.cancel_rounded, color: color),
          const SizedBox(width: 8),
          Text(correct ? 'Correct!' : 'Not quite', style: context.tt.titleMedium?.copyWith(color: color)),
        ]),
        if (!correct) Padding(padding: const EdgeInsets.only(top: 8), child: Text.rich(TextSpan(children: [const TextSpan(text: 'Correct answer: '), TextSpan(text: q.options[q.answer], style: const TextStyle(fontWeight: FontWeight.w800))]))),
        // An explanation is shown only when the question has one. Nothing is generated.
        if (q.hasExplanation) Padding(padding: const EdgeInsets.only(top: 8), child: Text(q.explanation, style: context.tt.bodyMedium?.copyWith(height: 1.4))),
      ]),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.c, required this.onFinish});
  final QuizController c;
  final VoidCallback onFinish;
  @override
  Widget build(BuildContext context) {
    final canNext = c.isExam || c.answered;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(color: context.cs.surface, border: Border(top: BorderSide(color: context.cs.outlineVariant))),
      child: Row(children: [
        IconButton.outlined(tooltip: 'Previous question', onPressed: c.index == 0 ? null : c.prev, icon: const Icon(Icons.arrow_back_rounded)),
        if (c.isExam) ...[
          const SizedBox(width: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48)),
            onPressed: () => _overview(context),
            icon: const Icon(Icons.grid_view_rounded, size: 20),
            label: Text('${c.answeredCount}/${c.questions.length}'),
          ),
        ],
        const Spacer(),
        if (!c.isLast)
          FilledButton.icon(onPressed: canNext ? c.next : null, icon: const Icon(Icons.arrow_forward_rounded), iconAlignment: IconAlignment.end, label: const Text('Next'))
        else
          FilledButton.icon(onPressed: canNext ? onFinish : null, icon: Icon(c.isExam ? Icons.send_rounded : Icons.flag_rounded), label: Text(c.isExam ? 'Submit' : 'Finish')),
      ]),
    );
  }

  void _overview(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => ListenableBuilder(
        listenable: c,
        builder: (_, __) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Questions', style: sheet.tt.titleLarge),
                const SizedBox(height: 4),
                Text('${c.answeredCount} answered · ${c.questions.length - c.answeredCount} left${c.marked.isEmpty ? '' : ' · ${c.marked.length} marked'}', style: sheet.tt.bodyMedium?.copyWith(color: sheet.cs.onSurfaceVariant)),
                const SizedBox(height: 16),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  for (var i = 0; i < c.questions.length; i++)
                    Semantics(
                      button: true,
                      label: 'Question ${i + 1}, ${c.choices.containsKey(i) ? 'answered' : 'not answered'}${c.marked.contains(i) ? ', marked for review' : ''}',
                      excludeSemantics: true,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          Navigator.pop(sheet);
                          c.goTo(i);
                        },
                        child: Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.choices.containsKey(i) ? sheet.cs.primary : null,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: i == c.index ? sheet.cs.onSurface : sheet.cs.outlineVariant, width: i == c.index ? 2.5 : 1),
                          ),
                          child: Stack(alignment: Alignment.center, children: [
                            Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w800, color: c.choices.containsKey(i) ? kOnBrand : sheet.cs.onSurface)),
                            if (c.marked.contains(i)) Positioned(top: 3, right: 4, child: Icon(Icons.flag_rounded, size: 14, color: c.choices.containsKey(i) ? kOnBrand : kWarn)),
                          ]),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Container(width: 14, height: 14, decoration: BoxDecoration(color: sheet.cs.primary, borderRadius: BorderRadius.circular(4))),
                  const SizedBox(width: 6),
                  const Text('Answered'),
                  const SizedBox(width: 16),
                  Icon(Icons.flag_rounded, size: 16, color: kWarn),
                  const SizedBox(width: 4),
                  const Text('Marked'),
                ]),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Submit exam'),
                    onPressed: () {
                      Navigator.pop(sheet);
                      onFinish();
                    },
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
