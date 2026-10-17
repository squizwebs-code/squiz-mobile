import 'package:flutter/material.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../data/bank.dart';
import '../../state/app_state.dart';
import '../app_scope.dart';
import '../practice/exam_sheet.dart';
import '../quiz/launcher.dart';
import '../widgets/common.dart';

/// Subject row/card with progress. Used on Home and on the Subjects tab.
class SubjectTile extends StatelessWidget {
  const SubjectTile({super.key, required this.stat});
  final SubjectStat stat;
  @override
  Widget build(BuildContext context) {
    final s = stat.subject;
    final pct = (stat.progress * 100).round();
    return Pressable(
      semanticLabel: '${s.name}, ${stat.total} questions, $pct percent attempted',
      onTap: () => pushPage(context, SubjectPage(subjectId: s.id)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          SubjectBadge(s.id, size: 48),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.name, style: context.tt.titleSmall),
            const SizedBox(height: 2),
            Text('${stat.total} questions${stat.accuracy == null ? '' : ' · ${stat.accuracy}% correct'}', style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: stat.progress),
                duration: Motion.d(context, 800),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 6, color: context.cs.primary, backgroundColor: context.cs.outlineVariant),
              ),
            ),
          ])),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: context.cs.outline),
        ]),
      ),
    );
  }
}

class SubjectPage extends StatelessWidget {
  const SubjectPage({super.key, required this.subjectId});
  final String subjectId;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final bank = app.bank!;
    final name = bank.subjectName(subjectId);
    final units = bank.unitsFor(app.grade, subject: subjectId);
    final all = bank.questionsFor(app.grade, subject: subjectId);
    final stat = app.subjectStats().where((s) => s.subject.id == subjectId).firstOrNull;
    return Scaffold(
      body: AppPage(
        title: name,
        subtitle: 'Grade ${app.grade} · ${units.length} sets · ${all.length} questions',
        slivers: [
          SliverList.list(children: [
            const SizedBox(height: 8),
            Row(children: [
              SubjectBadge(subjectId, size: 56),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(stat?.accuracy == null ? 'Not started yet' : '${stat!.accuracy}% correct', style: context.tt.titleMedium),
                Text('${stat?.answered ?? 0} of ${all.length} attempted', style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
              ])),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: FilledButton.icon(onPressed: () => QuizLauncher.practice(context, title: name, questions: all, count: 20), icon: const Icon(Icons.play_arrow_rounded), label: const Text('Practise'))),
              const SizedBox(width: 12),
              Expanded(child: OutlinedButton.icon(onPressed: () => showExamSheet(context, title: '$name exam', questions: all), icon: const Icon(Icons.timer_outlined), label: const Text('Exam'))),
            ]),
            const SectionHeader('Learning sets'),
          ]),
          SliverList.builder(
            itemCount: units.length,
            itemBuilder: (_, i) => Padding(padding: const EdgeInsets.only(bottom: 10), child: StaggeredIn(index: i, child: _UnitTile(unit: units[i], app: app))),
          ),
          if (units.isEmpty) const SliverToBoxAdapter(child: EmptyState(icon: Icons.folder_open_rounded, title: 'Nothing here yet')),
        ],
      ),
    );
  }
}

class _UnitTile extends StatelessWidget {
  const _UnitTile({required this.unit, required this.app});
  final UnitData unit;
  final AppState app;
  @override
  Widget build(BuildContext context) {
    var answered = 0, correct = 0;
    for (final q in unit.questions) {
      final a = app.answers[q.key];
      if (a != null) {
        answered++;
        if (a.on) correct++;
      }
    }
    final progress = unit.questions.isEmpty ? 0.0 : answered / unit.questions.length;
    return Pressable(
      onTap: () => _open(context),
      semanticLabel: '${unit.label}, ${unit.questions.length} questions',
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: context.sq.soft, borderRadius: BorderRadius.circular(14)),
            child: unit.isQuick ? Icon(Icons.flash_on_rounded, color: context.sq.link) : Text('${unit.no}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: context.sq.link)),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(unit.label, style: context.tt.titleSmall),
            Text('${unit.questions.length} questions${unit.grade == 0 ? ' · all grades' : ''}${answered == 0 ? '' : ' · $correct/$answered correct'}', style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: progress, minHeight: 5)),
          ])),
          const SizedBox(width: 8),
          Icon(Icons.play_circle_fill_rounded, color: context.cs.primary, size: 30),
        ]),
      ),
    );
  }

  void _open(BuildContext context) {
    final name = '${app.bank!.subjectName(unit.subject)} · ${unit.label}';
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(unit.label, style: c.tt.titleLarge),
            Text('${unit.questions.length} questions', style: c.tt.bodyMedium?.copyWith(color: c.cs.onSurfaceVariant)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Practise with instant feedback'),
                onPressed: () {
                  Navigator.pop(c);
                  QuizLauncher.practice(context, title: name, questions: unit.questions);
                },
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.timer_outlined),
                label: const Text('Take as a timed exam'),
                onPressed: () {
                  Navigator.pop(c);
                  showExamSheet(context, title: name, questions: unit.questions);
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
