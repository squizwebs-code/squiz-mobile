import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../data/bank.dart';
import '../app_scope.dart';
import '../quiz/launcher.dart';
import '../widgets/common.dart';
import 'subject_page.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';

class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key});
  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  String _q = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => setState(() => _q = v.trim().toLowerCase()));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final bank = app.bank!;
    final stats = app.subjectStats();
    final searching = _q.length >= 2;
    return AppPage(
      title: 'Subjects',
      subtitle: 'Grade ${app.grade}',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: TextField(
              controller: _ctrl,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search subjects, units or questions',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _ctrl.text.isEmpty ? null : IconButton(tooltip: 'Clear search', icon: const Icon(Icons.close_rounded), onPressed: () => setState(() { _ctrl.clear(); _q = ''; })),
              ),
            ),
          ),
        ),
        if (!searching)
          SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: .98),
            itemCount: stats.length,
            itemBuilder: (_, i) => StaggeredIn(index: i, child: _SubjectCard(stat: stats[i])),
          )
        else
          ..._results(context, bank, app.grade),
        if (!searching && stats.isEmpty) const SliverToBoxAdapter(child: EmptyState(icon: Icons.menu_book_outlined, title: 'No subjects for this grade yet')),
      ],
    );
  }

  List<Widget> _results(BuildContext context, QuestionBank bank, int grade) {
    final subjects = [for (final s in bank.subjectsFor(grade)) if (s.name.toLowerCase().contains(_q)) s];
    final units = <UnitData>[
      for (final u in bank.unitsFor(grade))
        if (u.title.toLowerCase().contains(_q) || bank.subjectName(u.subject).toLowerCase().contains(_q)) u
    ];
    final questions = <Question>[];
    for (final q in bank.questionsFor(grade)) {
      if (q.text.toLowerCase().contains(_q)) questions.add(q);
      if (questions.length >= 40) break;
    }
    if (subjects.isEmpty && units.isEmpty && questions.isEmpty) {
      return [SliverToBoxAdapter(child: EmptyState(icon: Icons.search_off_rounded, title: 'No matches for "$_q"', text: 'Try a shorter word or check the spelling.'))];
    }
    return [
      SliverList.list(children: [
        if (subjects.isNotEmpty) const SectionHeader('Subjects'),
        for (final s in subjects)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Pressable(onTap: () => pushPage(context, SubjectPage(subjectId: s.id)), child: ListTile(leading: SubjectBadge(s.id, size: 40), title: Text(s.name), trailing: const Icon(Icons.chevron_right_rounded)))),
        if (units.isNotEmpty) SectionHeader('Learning sets', subtitle: '${units.length} found'),
        for (final u in units.take(20))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Pressable(
              onTap: () => QuizLauncher.practice(context, title: '${bank.subjectName(u.subject)} · ${u.label}', questions: u.questions),
              child: ListTile(leading: SubjectBadge(u.subject, size: 40), title: Text(u.label), subtitle: Text('${bank.subjectName(u.subject)} · ${u.questions.length} questions'), trailing: Icon(Icons.play_circle_fill_rounded, color: context.cs.primary)),
            ),
          ),
        if (questions.isNotEmpty) SectionHeader('Questions', subtitle: questions.length == 40 ? 'First 40 matches' : '${questions.length} found'),
        for (final q in questions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Pressable(
              onTap: () => QuizLauncher.practice(context, title: 'Question', questions: [q], shuffle: false, oneOff: true),
              child: ListTile(
                leading: SubjectBadge(q.subject, size: 40),
                title: Text(q.text, maxLines: 3, overflow: TextOverflow.ellipsis),
                subtitle: Text(bank.subjectName(q.subject)),
              ),
            ),
          ),
      ]),
    ];
  }
}

class _SubjectCard extends StatelessWidget {
  const _SubjectCard({required this.stat});
  final SubjectStat stat;
  @override
  Widget build(BuildContext context) {
    final s = stat.subject;
    return Pressable(
      semanticLabel: '${s.name}, ${stat.total} questions',
      onTap: () => pushPage(context, SubjectPage(subjectId: s.id)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SubjectBadge(s.id, size: 52),
          const Spacer(),
          Text(s.name, style: context.tt.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text('${stat.total} questions', style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: stat.progress),
              duration: Motion.d(context, 800),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 6),
            ),
          ),
        ]),
      ),
    );
  }
}
