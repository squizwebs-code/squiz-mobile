import 'package:flutter/material.dart';
import '../matric/matric.dart';
import '../../core/brand.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../state/quiz_controller.dart';
import '../app_scope.dart';
import '../widgets/common.dart';
import 'launcher.dart';

enum _Filter { all, wrong, skipped, marked }

class ResultPage extends StatefulWidget {
  const ResultPage({super.key, required this.summary});
  final QuizSummary summary;
  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  _Filter _filter = _Filter.all;
  QuizSummary get s => widget.summary;

  (String, String) get _message {
    final p = s.percent;
    if (s.total == 0) return ('Done', 'No questions were answered.');
    if (p >= 90) return ('Outstanding!', 'You really know this material.');
    if (p >= 70) return ('Great work', 'Solid result. A little review will make it perfect.');
    if (p >= 50) return ('Good effort', 'You are getting there. Review the ones you missed.');
    return ('Keep practising', 'Every attempt helps. Go through the answers below.');
  }

  @override
  Widget build(BuildContext context) {
    final color = s.percent >= 70 ? context.sq.good : (s.percent >= 40 ? context.cs.primary : kWarn);
    final (title, sub) = _message;
    final filtered = s.results.where((r) => switch (_filter) { _Filter.all => true, _Filter.wrong => !r.correct && !r.skipped, _Filter.skipped => r.skipped, _Filter.marked => r.marked }).toList();
    final retry = [for (final r in s.results) if (!r.correct) r.question];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).popUntil((r) => r.isFirst);
      },
      child: Scaffold(
        body: AppPage(
          title: 'Results',
          leading: IconButton(tooltip: 'Close', icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst)),
          slivers: [
            SliverList.list(children: [
              StaggeredIn(
                index: 0,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(children: [
                      ProgressRing(
                        value: s.percent / 100,
                        size: 168,
                        stroke: 14,
                        color: color,
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          AnimatedCount(value: s.percent, suffix: '%', style: context.tt.displayMedium),
                          Text('${s.correct} of ${s.total}', style: context.tt.bodyMedium?.copyWith(color: context.cs.onSurfaceVariant)),
                        ]),
                      ),
                      const SizedBox(height: 18),
                      Text(title, style: context.tt.headlineSmall),
                      const SizedBox(height: 4),
                      Text(sub, textAlign: TextAlign.center, style: context.tt.bodyMedium?.copyWith(color: context.cs.onSurfaceVariant)),
                      const SizedBox(height: 14),
                      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                        Pill(s.mode == QuizMode.exam ? 'Exam' : 'Practice', icon: s.mode == QuizMode.exam ? Icons.timer_rounded : Icons.bolt_rounded),
                        Pill(mmss(s.seconds), icon: Icons.schedule_rounded),
                        if (s.timedOut) const Pill('Time ran out', icon: Icons.hourglass_bottom_rounded, color: kWarn),
                      ]),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              StaggeredIn(
                index: 1,
                child: Row(children: [
                  Expanded(child: _Stat(icon: Icons.check_circle_rounded, color: context.sq.good, value: s.correct, label: 'Correct')),
                  const SizedBox(width: 10),
                  Expanded(child: _Stat(icon: Icons.cancel_rounded, color: context.sq.bad, value: s.wrong, label: 'Wrong')),
                  const SizedBox(width: 10),
                  Expanded(child: _Stat(icon: Icons.remove_circle_rounded, color: context.cs.outline, value: s.skipped, label: 'Skipped')),
                ]),
              ),
              const SizedBox(height: 16),
              Row(children: [
                if (retry.isNotEmpty) ...[
                  Expanded(child: OutlinedButton.icon(onPressed: () => QuizLauncher.practice(context, title: 'Retry: ${s.title}', questions: retry), icon: const Icon(Icons.refresh_rounded), label: Text('Retry ${retry.length}'))),
                  const SizedBox(width: 12),
                ],
                Expanded(child: FilledButton(onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst), child: const Text('Done'))),
              ]),
              _BySubject(summary: s),
              const SectionHeader('Review your answers'),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final f in _Filter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(switch (f) { _Filter.all => 'All ${s.total}', _Filter.wrong => 'Wrong ${s.wrong}', _Filter.skipped => 'Skipped ${s.skipped}', _Filter.marked => 'Marked ${s.results.where((r) => r.marked).length}' }),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
            ]),
            SliverList.builder(
              itemCount: filtered.length,
              itemBuilder: (_, i) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _ReviewCard(r: filtered[i], number: s.results.indexOf(filtered[i]) + 1)),
            ),
            if (filtered.isEmpty) const SliverToBoxAdapter(child: EmptyState(icon: Icons.celebration_rounded, title: 'Nothing in this list', text: 'Nice. There are no questions in this category.')),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.color, required this.value, required this.label});
  final IconData icon;
  final Color color;
  final int value;
  final String label;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(children: [
            Icon(icon, color: color),
            const SizedBox(height: 6),
            AnimatedCount(value: value, style: context.tt.titleLarge),
            Text(label, style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
          ]),
        ),
      );
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.r, required this.number});
  final QuestionResult r;
  final int number;
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final q = r.question;
    final (label, color, icon) = r.skipped ? ('Skipped', context.cs.outline, Icons.remove_circle_rounded) : (r.correct ? ('Correct', context.sq.good, Icons.check_circle_rounded) : ('Wrong', context.sq.bad, Icons.cancel_rounded));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Q$number', style: context.tt.labelLarge),
            const SizedBox(width: 8),
            Pill(label, icon: icon, color: color),
            if (r.marked) ...[const SizedBox(width: 6), const Pill('Marked', icon: Icons.flag_rounded, color: kWarn)],
            const Spacer(),
            IconButton(
              tooltip: app.isBookmarked(q.key) ? 'Remove bookmark' : 'Bookmark',
              icon: Icon(app.isBookmarked(q.key) ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: app.isBookmarked(q.key) ? context.cs.primary : null),
              onPressed: () => app.toggleBookmark(q),
            ),
            IconButton(tooltip: 'Report a problem', icon: const Icon(Icons.report_gmailerrorred_rounded), onPressed: () => showReportSheet(context, q)),
          ]),
          const SizedBox(height: 4),
          Text(q.text, style: context.tt.titleSmall?.copyWith(height: 1.35)),
          const SizedBox(height: 10),
          for (final (i, o) in q.options.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(i == q.answer ? Icons.check_circle_rounded : (i == r.choice ? Icons.cancel_rounded : Icons.circle_outlined), size: 20, color: i == q.answer ? context.sq.good : (i == r.choice ? context.sq.bad : context.cs.outline)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: o, style: TextStyle(fontWeight: i == q.answer || i == r.choice ? FontWeight.w700 : FontWeight.w500)),
                    if (i == r.choice) TextSpan(text: '  (your answer)', style: TextStyle(color: context.cs.onSurfaceVariant)),
                    if (i == q.answer && i != r.choice) TextSpan(text: '  (correct)', style: TextStyle(color: context.sq.good, fontWeight: FontWeight.w700)),
                  ])),
                ),
              ]),
            ),
          if (q.hasExplanation) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: context.sq.soft, borderRadius: BorderRadius.circular(12)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.lightbulb_outline_rounded, size: 18, color: context.sq.link),
                const SizedBox(width: 8),
                Expanded(child: Text(q.explanation, style: context.tt.bodySmall?.copyWith(height: 1.4))),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}


/// Score for each subject, shown for mixed sessions such as a Matric mock exam.
class _BySubject extends StatelessWidget {
  const _BySubject({required this.summary});
  final QuizSummary summary;
  @override
  Widget build(BuildContext context) {
    final groups = <String, List<QuestionResult>>{};
    for (final r in summary.results) {
      groups.putIfAbsent(r.question.subject, () => []).add(r);
    }
    if (groups.length < 2) return const SizedBox.shrink();
    final bank = context.app.bank;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHeader('By subject'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            for (final e in groups.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  SizedBox(width: 110, child: Text(bank?.subjectName(e.key) ?? e.key, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.labelLarge)),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(value: e.value.where((r) => r.correct).length / e.value.length, minHeight: 10, color: subjectColor(e.key), backgroundColor: context.cs.surfaceContainerHigh),
                    ),
                  ),
                  SizedBox(width: 64, child: Text('${e.value.where((r) => r.correct).length}/${e.value.length}', textAlign: TextAlign.right, style: context.tt.labelLarge)),
                ]),
              ),
          ]),
        ),
      ),
    ]);
  }
}
