import 'package:flutter/material.dart';
import '../../core/brand.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../app_scope.dart';
import '../matric/matric.dart';
import '../quiz/launcher.dart';
import '../widgets/common.dart';

/// Build-your-own session: pick a subject (or everything), a mode, a length, then start.
class PracticePage extends StatefulWidget {
  const PracticePage({super.key});
  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  String? subject; // null = all subjects
  bool exam = false;
  int count = 20;
  int? minutes = 30;
  bool shuffle = true;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final bank = app.bank;
    if (bank == null) return const AppPage(title: 'Practice', slivers: [SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()))]);
    final subjects = bank.subjectsFor(app.grade);
    if (subject != null && !subjects.any((s) => s.id == subject)) subject = null; // grade changed
    final pool = bank.questionsFor(app.grade, subject: subject);
    final counts = {for (final n in const [10, 20, 30, 50]) if (n < pool.length) n, if (pool.isNotEmpty) pool.length}.toList()..sort();
    if (counts.isNotEmpty && !counts.contains(count)) count = counts.contains(20) ? 20 : counts.last;
    final title = subject == null ? 'Mixed · Grade ${app.grade}' : '${subjects.firstWhere((s) => s.id == subject).name} · Grade ${app.grade}';
    final recent = app.history.take(5).toList();

    return AppPage(
      title: 'Practice',
      subtitle: 'Build a session that fits the time you have.',
      slivers: [
        SliverList.list(children: [
          Card(
            color: context.sq.soft,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => showMockExamSheet(context),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  CircleAvatar(backgroundColor: kBrand, child: const Icon(Icons.workspace_premium_rounded, color: kOnBrand)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(app.grade >= 11 ? 'Matric mock exam' : 'Full mock exam', style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    Text('Questions from every subject in one timed paper, with a score per subject.', style: context.tt.bodySmall),
                  ])),
                  const Icon(Icons.chevron_right_rounded),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const SectionHeader('Subject'),
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: const Text('All subjects'), selected: subject == null, onSelected: (_) => setState(() => subject = null))),
              for (final s in subjects)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(avatar: Icon(subjectIcon(s.id), size: 18, color: subjectColor(s.id)), label: Text(s.name), selected: subject == s.id, onSelected: (_) => setState(() => subject = s.id)),
                ),
            ]),
          ),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, icon: Icon(Icons.bolt_rounded), label: Text('Practice')),
              ButtonSegment(value: true, icon: Icon(Icons.timer_outlined), label: Text('Exam')),
            ],
            selected: {exam},
            onSelectionChanged: (s) {
              Haptic.tap();
              setState(() => exam = s.first);
            },
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: Motion.d(context, 200),
            child: Text(
              exam ? 'Exam: answers stay hidden until you submit, you can change them, and an optional timer ends the exam for you.' : 'Practice: you see the right answer and explanation as soon as you answer.',
              key: ValueKey(exam),
              style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 20),
          Text('Questions', style: context.tt.titleSmall),
          const SizedBox(height: 8),
          if (pool.isEmpty)
            const EmptyState(icon: Icons.inbox_outlined, title: 'No questions here yet', text: 'Try another subject or grade.')
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final n in counts) ChoiceChip(label: Text(n == pool.length ? 'All $n' : '$n'), selected: count == n, onSelected: (_) => setState(() => count = n)),
            ]),
          if (exam) ...[
            const SizedBox(height: 20),
            Text('Timer', style: context.tt.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(label: const Text('No timer'), selected: minutes == null, onSelected: (_) => setState(() => minutes = null)),
              for (final m in const [10, 15, 20, 30, 45, 60, 90]) ChoiceChip(label: Text('$m min'), selected: minutes == m, onSelected: (_) => setState(() => minutes = m)),
            ]),
          ] else
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Shuffle questions'), subtitle: const Text('Off keeps them in textbook order'), value: shuffle, onChanged: (v) => setState(() => shuffle = v)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(pool.isEmpty ? 'Nothing to start' : 'Start ${exam ? 'exam' : 'practice'} · ${count > pool.length ? pool.length : count} questions'),
              onPressed: pool.isEmpty
                  ? null
                  : () {
                      Haptic.tap();
                      if (exam) {
                        QuizLauncher.exam(context, title: title, questions: pool, count: count, minutes: minutes);
                      } else {
                        QuizLauncher.practice(context, title: title, questions: pool, shuffle: shuffle, count: count);
                      }
                    },
            ),
          ),
          if (app.resumable != null) ...[
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(icon: const Icon(Icons.history_rounded), label: Text('Resume "${app.resumable!.title}"'), onPressed: () => QuizLauncher.resume(context))),
          ],
          const SizedBox(height: 28),
          const SectionHeader('Recent sessions'),
          if (recent.isEmpty)
            const EmptyState(icon: Icons.insights_outlined, title: 'No sessions yet', text: 'Finish a quiz and it will appear here.')
          else
            for (final (i, h) in recent.indexed) StaggeredIn(index: i, child: _HistoryTile(h)),
        ]),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile(this.h);
  final HistoryItem h;
  @override
  Widget build(BuildContext context) {
    final p = h.percent;
    final color = p >= 70 ? context.sq.good : (p >= 40 ? context.sq.warn : context.sq.bad);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withValues(alpha: .15), child: Text('$p%', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12))),
        title: Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${h.isExam ? 'Exam' : 'Practice'} · ${h.correct}/${h.total} · ${relativeTime(h.ts, DateTime.now().millisecondsSinceEpoch)}'),
      ),
    );
  }
}
