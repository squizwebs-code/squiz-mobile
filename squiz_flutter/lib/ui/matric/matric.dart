import 'package:flutter/material.dart';
import '../../core/brand.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../data/api.dart';
import '../../data/bank.dart';
import '../app_scope.dart';
import '../quiz/launcher.dart';
import '../widgets/common.dart';

String trackName(String? t) => switch (t) { 'natural' => 'Natural Science', 'social' => 'Social Science', _ => 'All subjects' };

/// The two Matric streams plus "show everything". Used in onboarding and in the profile.
class TrackPicker extends StatelessWidget {
  const TrackPicker({super.key, required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget card(String? t, IconData icon, String title, String sub) {
      final sel = value == t;
      return Semantics(
        selected: sel,
        button: true,
        label: '$title. $sub',
        child: AnimatedContainer(
          duration: Motion.d(context, 200),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: sel ? context.sq.soft : context.cs.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: sel ? kBrand : context.cs.outlineVariant, width: sel ? 2 : 1),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                Haptic.tap();
                onChanged(t);
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  CircleAvatar(backgroundColor: kBrand.withValues(alpha: .15), child: Icon(icon, color: context.sq.link)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    Text(sub, style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
                  ])),
                  Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off, color: sel ? kBrand : context.cs.outline),
                ]),
              ),
            ),
          ),
        ),
      );
    }

    return Column(children: [
      card('natural', Icons.science_rounded, 'Natural Science', 'Mathematics, Physics, Chemistry, Biology, English'),
      card('social', Icons.public_rounded, 'Social Science', 'Mathematics, Geography, History, Economics, English'),
      card(null, Icons.apps_rounded, 'Show all subjects', 'Not sure yet, or preparing for both'),
    ]);
  }
}

Future<void> showTrackSheet(BuildContext context) {
  final app = AppScope.read(context);
  return showModalBottomSheet<void>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your Matric stream', style: c.tt.titleLarge),
            const SizedBox(height: 4),
            Text('Subjects outside your stream are hidden in Grades 11 and 12. Saved items stay available.', style: c.tt.bodyMedium?.copyWith(color: c.cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            TrackPicker(
              value: app.track,
              onChanged: (t) async {
                await app.setTrack(t);
                if (c.mounted) Navigator.pop(c);
              },
            ),
          ]),
        ),
      ),
    ),
  );
}

/// "142 days to the Ethiopian University Entrance Exam" — shown only when an administrator has set the exam date.
class ExamCountdownCard extends StatelessWidget {
  const ExamCountdownCard({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final d = app.examDate;
    if (d == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final days = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days < 0) return const SizedBox.shrink();
    final weeks = days ~/ 7;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: context.sq.soft, borderRadius: BorderRadius.circular(16)),
            alignment: Alignment.center,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedCount(value: days, style: context.tt.headlineSmall?.copyWith(color: context.sq.link, fontWeight: FontWeight.w800)),
              Text(days == 1 ? 'day' : 'days', style: context.tt.labelSmall),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(days == 0 ? 'Exam day. Good luck!' : 'until the ${app.examName}', style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(days > 14 ? 'About $weeks weeks to prepare. A little every day adds up.' : 'Focus on your weakest subjects and take a mock exam.', style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
          ])),
        ]),
      ),
    );
  }
}

/// Matric readiness: how much of each stream subject has been answered, and how accurately.
class ReadinessCard extends StatelessWidget {
  const ReadinessCard({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final stats = app.subjectStats();
    if (stats.isEmpty) return const SizedBox.shrink();
    final answered = stats.fold<int>(0, (a, s) => a + s.answered);
    final correct = stats.fold<int>(0, (a, s) => a + s.correct);
    final total = stats.fold<int>(0, (a, s) => a + s.total);
    final acc = answered == 0 ? null : (correct * 100 / answered).round();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(app.grade >= 11 ? 'Matric readiness' : 'Subject readiness', style: context.tt.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            if (app.grade >= 11 && app.bank?.hasTracks == true) TextButton(onPressed: () => showTrackSheet(context), child: Text(trackName(app.track))),
          ]),
          Text(answered == 0 ? 'Answer some questions to see where you stand.' : '$answered of $total questions answered · ${acc ?? 0}% correct', style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          for (final s in stats)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                SizedBox(width: 92, child: Text(s.subject.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.labelLarge)),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: s.accuracy == null ? 0 : s.accuracy! / 100),
                      duration: Motion.d(context, 600),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 10, color: subjectColor(s.subject.id), backgroundColor: context.cs.surfaceContainerHigh),
                    ),
                  ),
                ),
                SizedBox(width: 44, child: Text(s.accuracy == null ? '–' : '${s.accuracy}%', textAlign: TextAlign.right, style: context.tt.labelLarge)),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Messages from the administrators (exam dates, new content, maintenance).
class AnnouncementsCard extends StatelessWidget {
  const AnnouncementsCard({super.key});
  @override
  Widget build(BuildContext context) {
    final list = context.app.announcements;
    if (list.isEmpty) return const SizedBox.shrink();
    final a = list.first;
    return Card(
      color: context.sq.soft,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.campaign_rounded, color: context.sq.link),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((a['title'] ?? '').toString(), style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text((a['body'] ?? '').toString(), style: context.tt.bodyMedium),
            if (list.length > 1) Text('+${list.length - 1} more', style: context.tt.labelSmall?.copyWith(color: context.cs.onSurfaceVariant)),
          ])),
        ]),
      ),
    );
  }
}

/// Full mock exam: pick the subjects, how many questions from each, and the time. Sections follow subject order.
Future<void> showMockExamSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (c) => _MockSheet(parentContext: context),
  );
}

class _MockSheet extends StatefulWidget {
  const _MockSheet({required this.parentContext});
  final BuildContext parentContext;
  @override
  State<_MockSheet> createState() => _MockSheetState();
}

class _MockSheetState extends State<_MockSheet> {
  final Set<String> _off = {};
  int _per = 20;
  int? _minutes;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final bank = app.bank!;
    final subjects = bank.subjectsFor(app.grade);
    final on = [for (final s in subjects) if (!_off.contains(s.id)) s];
    int take(Subject s) => bank.countFor(app.grade, s.id) < _per ? bank.countFor(app.grade, s.id) : _per;
    final total = on.fold<int>(0, (a, s) => a + take(s));
    final minutes = _minutes ?? (total == 0 ? 30 : ((total * 1.2) / 5).ceil() * 5);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Mock exam', style: context.tt.titleLarge),
            Text(app.grade >= 11 ? '${trackName(app.track)} · Grade ${app.grade}' : 'Grade ${app.grade}', style: context.tt.bodyMedium?.copyWith(color: context.cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            Text('Subjects', style: context.tt.titleSmall),
            const SizedBox(height: 4),
            for (final s in subjects)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: !_off.contains(s.id),
                onChanged: (v) => setState(() => v == true ? _off.remove(s.id) : _off.add(s.id)),
                title: Text(s.name),
                subtitle: Text('${take(s)} questions'),
                secondary: SubjectBadge(s.id, size: 36),
              ),
            const SizedBox(height: 8),
            Text('Questions per subject', style: context.tt.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [for (final n in const [10, 20, 30, 40, 50]) ChoiceChip(label: Text('$n'), selected: _per == n, onSelected: (_) => setState(() => _per = n))]),
            const SizedBox(height: 16),
            Text('Time', style: context.tt.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(label: Text('Suggested · $minutes min'), selected: _minutes == null, onSelected: (_) => setState(() => _minutes = null)),
              for (final m in const [30, 60, 90, 120, 180]) ChoiceChip(label: Text('$m min'), selected: _minutes == m, onSelected: (_) => setState(() => _minutes = m)),
            ]),
            const SizedBox(height: 12),
            Text('Answers stay hidden until you submit. Your result shows a score for each subject.', style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text('Start · $total questions · $minutes min'),
                onPressed: total == 0
                    ? null
                    : () {
                        final qs = <Question>[];
                        for (final s in on) {
                          final pool = List<Question>.of(bank.questionsFor(app.grade, subject: s.id))..shuffle();
                          qs.addAll(pool.take(take(s)));
                        }
                        Navigator.pop(context);
                        QuizLauncher.exam(widget.parentContext, title: 'Mock exam · ${app.grade >= 11 ? trackName(app.track) : 'Grade ${app.grade}'}', questions: qs, minutes: minutes, ordered: true);
                      },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Reason chips + optional note; sent to the administrators' review queue.
Future<void> showReportSheet(BuildContext context, Question q) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (c) => _ReportSheet(parentContext: context, q: q),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.parentContext, required this.q});
  final BuildContext parentContext;
  final Question q;
  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String _reason = 'wrong_answer';
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final app = AppScope.read(context);
    final host = widget.parentContext;
    final nav = Navigator.of(context);
    if (!app.signedIn) {
      nav.pop();
      showSnack(host, 'Sign in from the Profile tab to report a question.');
      return;
    }
    setState(() => _busy = true);
    try {
      await app.syncApi.reportQuestion(widget.q.key, _reason, _note.text);
      nav.pop();
      if (host.mounted) showSnack(host, 'Thanks. An administrator will review this question.');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, e.offline ? 'No connection. Try again when you are online.' : e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const reasons = {'wrong_answer': 'Wrong answer', 'typo': 'Typo', 'unclear': 'Unclear question', 'other': 'Other'};
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Report a problem', style: context.tt.titleLarge),
          const SizedBox(height: 6),
          Text(widget.q.text, maxLines: 3, overflow: TextOverflow.ellipsis, style: context.tt.bodyMedium?.copyWith(color: context.cs.onSurfaceVariant)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final e in reasons.entries) ChoiceChip(label: Text(e.value), selected: _reason == e.key, onSelected: (_) => setState(() => _reason = e.key))]),
          const SizedBox(height: 14),
          TextField(controller: _note, maxLength: 500, maxLines: 3, decoration: const InputDecoration(labelText: 'What is wrong? (optional)')),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : _send, child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('Send report'))),
        ]),
      ),
    );
  }
}
