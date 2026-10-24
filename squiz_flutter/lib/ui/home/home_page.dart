import 'package:flutter/material.dart';
import '../../core/brand.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../app_scope.dart';
import '../browse/subject_page.dart';
import '../matric/matric.dart';
import '../practice/exam_sheet.dart';
import '../quiz/launcher.dart';
import '../shell.dart';
import '../widgets/common.dart';
import '../widgets/sheets.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : (h < 18 ? 'Good afternoon' : 'Good evening');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final bank = app.bank!;
    final stats = app.subjectStats();
    final mistakes = app.mistakes();
    final weak = app.weakestSubject();
    final first = app.user?.fullName.split(' ').first;
    return AppPage(
      title: 'SQUIZ',
      onRefresh: () => app.signedIn ? app.syncNow() : Future.value(),
      actions: [
        if (app.signedIn) _SyncDot(app),
        IconButton(
          tooltip: app.themeMode == ThemeMode.dark || (app.themeMode == ThemeMode.system && Theme.of(context).brightness == Brightness.dark) ? 'Switch to light theme' : 'Switch to dark theme',
          icon: Icon(Theme.of(context).brightness == Brightness.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
          onPressed: () => app.setThemeMode(Theme.of(context).brightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark),
        ),
      ],
      slivers: [
        SliverList.list(children: [
          StaggeredIn(index: 0, child: _Hero(greeting: first == null ? _greeting() : '${_greeting()}, $first', grade: app.grade, track: app.effectiveTrack, questions: bank.questionsFor(app.grade).length)),
          if (app.announcements.isNotEmpty) ...[const SizedBox(height: 14), const AnnouncementsCard()],
          if (app.examDate != null) ...[const SizedBox(height: 14), const ExamCountdownCard()],
          if (app.resumable != null) ...[const SizedBox(height: 14), StaggeredIn(index: 1, child: _ResumeCard(app: app))],
          const SizedBox(height: 14),
          StaggeredIn(index: 2, child: _ProgressCard(app: app)),
          const SizedBox(height: 14),
          const ReadinessCard(),
          if (weak != null) ...[const SizedBox(height: 14), StaggeredIn(index: 3, child: _WeakCard(stat: weak))],
          const SectionHeader('Quick start'),
          SizedBox(
            height: 112,
            child: ListView(scrollDirection: Axis.horizontal, clipBehavior: Clip.none, children: [
              _QuickAction(icon: Icons.shuffle_rounded, title: 'Mixed practice', sub: '20 random questions', onTap: () => QuizLauncher.practice(context, title: 'Mixed practice', questions: bank.questionsFor(app.grade), count: 20)),
              _QuickAction(icon: Icons.workspace_premium_rounded, title: app.grade >= 11 ? 'Matric mock exam' : 'Mock exam', sub: 'All subjects, timed', onTap: () => showMockExamSheet(context)),
              _QuickAction(icon: Icons.timer_rounded, title: 'Take an exam', sub: 'Timed, graded at the end', onTap: () => showExamSheet(context, title: 'Mixed exam', questions: bank.questionsFor(app.grade))),
              _QuickAction(icon: Icons.refresh_rounded, title: 'Fix mistakes', sub: mistakes.isEmpty ? 'Nothing to fix yet' : '${mistakes.length} to review', onTap: mistakes.isEmpty ? null : () => QuizLauncher.practice(context, title: 'Mistakes', questions: mistakes)),
              _QuickAction(icon: Icons.flash_on_rounded, title: 'Quick 10', sub: 'Ten random questions', onTap: () => QuizLauncher.practice(context, title: 'Quick 10', questions: bank.questionsFor(app.grade), count: 10)),
            ]),
          ),
          SectionHeader('Subjects', subtitle: app.effectiveTrack == null ? 'Grade ${app.grade}' : 'Grade ${app.grade} · ${trackName(app.effectiveTrack)}', action: 'See all', onAction: () => AppShellState.of(context)?.goTo(1)),
        ]),
        SliverList.builder(
          itemCount: stats.length,
          itemBuilder: (_, i) => Padding(padding: const EdgeInsets.only(bottom: 10), child: StaggeredIn(index: i, child: SubjectTile(stat: stats[i]))),
        ),
        if (stats.isEmpty) const SliverToBoxAdapter(child: EmptyState(icon: Icons.menu_book_outlined, title: 'No questions for this grade yet', text: 'Try another grade from the chip at the top.')),
      ],
    );
  }
}

class _SyncDot extends StatelessWidget {
  const _SyncDot(this.app);
  final AppState app;
  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (app.syncStatus) {
      SyncStatus.syncing => (Icons.sync_rounded, 'Syncing'),
      SyncStatus.ok => (Icons.cloud_done_rounded, 'Synced'),
      SyncStatus.error => (Icons.cloud_off_rounded, 'Not synced'),
      SyncStatus.idle => (Icons.cloud_queue_rounded, 'Signed in'),
    };
    return IconButton(tooltip: '$label. Tap to sync now.', icon: Icon(icon), onPressed: app.syncStatus == SyncStatus.syncing ? null : app.syncNow);
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.greeting, required this.grade, required this.questions, this.track});
  final String greeting;
  final int grade, questions;
  final String? track;
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [kBrandDeep, kBrand, kBrandBright], begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: Stack(children: [
          Positioned(right: -40, top: -40, child: Container(width: 150, height: 150, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: .10)))),
          Positioned(right: 30, bottom: -50, child: Container(width: 110, height: 110, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: .08)))),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(
              button: true,
              label: 'Grade $grade. Tap to change.',
              child: InkWell(
                borderRadius: BorderRadius.circular(99),
                onTap: () => showGradeSheet(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .20), borderRadius: BorderRadius.circular(99)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.school_rounded, size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(track == null ? 'Grade $grade' : 'Grade $grade · ${trackName(track)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    const Icon(Icons.expand_more_rounded, size: 18, color: Colors.white),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(greeting, style: context.tt.headlineSmall?.copyWith(color: Colors.white)),
            const SizedBox(height: 4),
            Text('$questions questions ready to practise.', style: const TextStyle(color: Colors.white70, fontSize: 15)),
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: kBrandDeep),
              onPressed: () {
                final app = AppScope.read(context);
                QuizLauncher.practice(context, title: 'Mixed practice', questions: app.bank!.questionsFor(app.grade), count: 20);
              },
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start practising'),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.app});
  final AppState app;
  @override
  Widget build(BuildContext context) {
    final r = app.resumable!;
    final exam = r.mode == 'exam';
    return Pressable(
      color: context.sq.soft,
      onTap: () => QuizLauncher.resume(context),
      semanticLabel: 'Resume ${r.title}',
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(width: 46, height: 46, decoration: BoxDecoration(color: context.cs.primary, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.play_arrow_rounded, color: kOnBrand)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Resume ${exam ? 'exam' : 'practice'}', style: context.tt.titleSmall),
            Text('${r.title} · ${r.choices.length} of ${r.keys.length} answered', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
          ])),
          const Icon(Icons.chevron_right_rounded),
        ]),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.app});
  final AppState app;
  @override
  Widget build(BuildContext context) {
    final acc = app.accuracy;
    final week = app.last7();
    final maxDay = week.fold<int>(1, (m, e) => e.value > m ? e.value : m);
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(children: [
          Row(children: [
            ProgressRing(
              value: (acc ?? 0) / 100,
              size: 96,
              child: acc == null ? Text('–', style: context.tt.headlineSmall) : AnimatedCount(value: acc, suffix: '%', style: context.tt.titleLarge),
            ),
            const SizedBox(width: 18),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your progress', style: context.tt.titleMedium),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Pill('${app.answeredCount} answered', icon: Icons.check_circle_rounded),
                Pill('${app.streak} day streak', icon: Icons.local_fire_department_rounded, color: kWarn),
              ]),
            ])),
          ]),
          const SizedBox(height: 18),
          Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (final e in week)
              Expanded(
                child: Semantics(
                  label: '${dayNames[e.key.weekday - 1]}: ${e.value} answers',
                  child: Column(children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: e.value == 0 ? 4 : 6 + 44 * e.value / maxDay),
                      duration: Motion.d(context, 700),
                      curve: Curves.easeOutCubic,
                      builder: (_, h, __) => Container(width: 14, height: h, decoration: BoxDecoration(color: e.value == 0 ? context.cs.outlineVariant : context.cs.primary, borderRadius: BorderRadius.circular(6))),
                    ),
                    const SizedBox(height: 6),
                    Text(dayNames[e.key.weekday - 1][0], style: context.tt.labelSmall?.copyWith(color: context.cs.onSurfaceVariant)),
                  ]),
                ),
              ),
          ]),
        ]),
      ),
    );
  }
}

class _WeakCard extends StatelessWidget {
  const _WeakCard({required this.stat});
  final SubjectStat stat;
  @override
  Widget build(BuildContext context) => Pressable(
        onTap: () => pushPage(context, SubjectPage(subjectId: stat.subject.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            SubjectBadge(stat.subject.id),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Worth another look', style: context.tt.labelMedium?.copyWith(color: context.sq.link)),
              Text('${stat.subject.name}: ${stat.accuracy}% correct', style: context.tt.titleSmall),
              Text('Based on ${stat.answered} answers', style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
            ])),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
      );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.title, required this.sub, required this.onTap});
  final IconData icon;
  final String title, sub;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 12),
        child: SizedBox(
          width: 164,
          child: Opacity(
            opacity: onTap == null ? .55 : 1,
            child: Pressable(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Container(width: 38, height: 38, decoration: BoxDecoration(color: context.sq.soft, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: context.sq.link, size: 22)),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: context.tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(sub, style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      );
}
