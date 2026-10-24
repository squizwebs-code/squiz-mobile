import 'package:flutter/material.dart';
import '../../core/brand.dart';
import '../../core/theme.dart';
import '../widgets/common.dart';
import 'admin_common.dart';

enum _Range { d7, d30, d90, custom }

/// All the app's statistics in one place: users, learning, question quality and content, for a chosen period.
class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});
  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  _Range _range = _Range.d30;
  DateTimeRange? _custom;
  int _gen = 0;

  (DateTime, DateTime) get _dates {
    final today = DateTime.now();
    final to = DateTime(today.year, today.month, today.day);
    return switch (_range) {
      _Range.d7 => (to.subtract(const Duration(days: 6)), to),
      _Range.d30 => (to.subtract(const Duration(days: 29)), to),
      _Range.d90 => (to.subtract(const Duration(days: 89)), to),
      _Range.custom => (_custom?.start ?? to.subtract(const Duration(days: 29)), _custom?.end ?? to),
    };
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(context: context, firstDate: DateTime(2024), lastDate: now, initialDateRange: _custom);
    if (r != null) setState(() {
      _custom = r;
      _range = _Range.custom;
      _gen++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final (from, to) = _dates;
    return Constrained(
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SegmentedButton<_Range>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _Range.d7, label: Text('7 days')),
              ButtonSegment(value: _Range.d30, label: Text('30 days')),
              ButtonSegment(value: _Range.d90, label: Text('90 days')),
            ],
            selected: {if (_range != _Range.custom) _range},
            emptySelectionAllowed: true,
            onSelectionChanged: (s) => setState(() {
              if (s.isNotEmpty) _range = s.first;
              _gen++;
            }),
          ),
          OutlinedButton.icon(onPressed: _pickCustom, icon: const Icon(Icons.date_range_rounded), label: Text(_range == _Range.custom ? '${shortDate(from.toIso8601String())} – ${shortDate(to.toIso8601String())}' : 'Custom range')),
          IconButton.filledTonal(tooltip: 'Refresh', onPressed: () => setState(() => _gen++), icon: const Icon(Icons.refresh_rounded)),
          IconButton.filledTonal(
            tooltip: 'Download statistics (Excel)',
            icon: const Icon(Icons.download_rounded),
            onPressed: () async {
              final bytes = await guarded(context, () => context.adminApi.exportStats(from: from, to: to));
              if (bytes != null && context.mounted) await saveBytes(context, bytes, 'squiz-statistics.xlsx');
            },
          ),
        ]),
        const SizedBox(height: 14),
        Loader<Map<String, dynamic>>(
          key: ValueKey('$_gen-${from.toIso8601String()}-${to.toIso8601String()}'),
          load: () => context.adminApi.stats(from: from, to: to),
          builder: (c, s, reload) => _Stats(s),
        ),
      ]),
    );
  }
}

int _i(dynamic v) => (v as num?)?.toInt() ?? 0;
String _p(dynamic v) => v == null ? '–' : '$v%';
List<Map<String, dynamic>> _list(dynamic v) => [for (final x in (v as List? ?? const [])) Map<String, dynamic>.from(x as Map)];

class _Stats extends StatelessWidget {
  const _Stats(this.s);
  final Map<String, dynamic> s;

  @override
  Widget build(BuildContext context) {
    final u = Map<String, dynamic>.from(s['users'] as Map);
    final l = Map<String, dynamic>.from(s['learning'] as Map);
    final q = Map<String, dynamic>.from(s['questions'] as Map);
    final c = Map<String, dynamic>.from(s['content'] as Map);
    final active = Map<String, dynamic>.from(u['active'] as Map);
    final ret = Map<String, dynamic>.from(u['retention'] as Map);
    final sessions = Map<String, dynamic>.from(l['sessions'] as Map);
    final byMode = Map<String, dynamic>.from(sessions['by_mode'] as Map);
    final cq = Map<String, dynamic>.from(c['questions'] as Map);
    final newDaily = _list(u['new_per_day']);
    final sessDaily = _list(sessions['per_day']);
    final width = MediaQuery.sizeOf(context).width;
    final cols = width >= 1000 ? 4 : (width >= 600 ? 3 : 2);

    Widget grid(List<Widget> kids) => LayoutBuilder(builder: (context, box) {
          final w = (box.maxWidth - (cols - 1) * 10) / cols;
          return Wrap(spacing: 10, runSpacing: 10, children: [for (final k in kids) SizedBox(width: w, child: k)]);
        });

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      grid([
        KpiCard(label: 'Total users', value: '${u['total']}', icon: Icons.people_rounded, sub: '${u['students']} students · ${u['admins']} admins'),
        KpiCard(label: 'New in period', value: '${u['new_in_range']}', icon: Icons.person_add_alt_1_rounded),
        KpiCard(label: 'Active learners', value: '${l['active_learners']}', icon: Icons.bolt_rounded, sub: 'practised in this period'),
        KpiCard(label: 'Suspended', value: '${u['suspended']}', icon: Icons.block_rounded, color: context.sq.bad),
        KpiCard(label: 'Questions answered', value: '${l['questions_answered']}', icon: Icons.task_alt_rounded),
        KpiCard(label: 'Overall accuracy', value: _p(l['accuracy']), icon: Icons.track_changes_rounded, color: context.sq.good),
        KpiCard(label: 'Quizzes finished', value: '${sessions['total']}', icon: Icons.quiz_rounded),
        KpiCard(label: 'Published questions', value: '${cq['published'] ?? 0}', icon: Icons.library_books_rounded, sub: '${cq['draft'] ?? 0} draft · ${cq['archived'] ?? 0} archived'),
      ]),
      const SizedBox(height: 14),
      SectionCard(
        title: 'Users',
        subtitle: 'Sign-ups and activity',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('New users per day', style: context.tt.labelLarge),
          const SizedBox(height: 6),
          LineChart(values: [for (final d in newDaily) _i(d['count'])]),
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: [
            Pill('Daily active ${active['daily']}', icon: Icons.today_rounded),
            Pill('Weekly active ${active['weekly']}', icon: Icons.date_range_rounded),
            Pill('Monthly active ${active['monthly']}', icon: Icons.calendar_month_rounded),
          ]),
          const SizedBox(height: 14),
          Text('Retention (students who came back)', style: context.tt.labelLarge),
          const SizedBox(height: 6),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final e in {'day_1': 'After 1 day', 'day_7': 'After 7 days', 'day_30': 'After 30 days'}.entries)
              Pill('${e.value}: ${_p((ret[e.key] as Map)['percent'])} of ${(ret[e.key] as Map)['cohort']}', icon: Icons.replay_rounded),
          ]),
          const SizedBox(height: 14),
          Text('Users by grade', style: context.tt.labelLarge),
          const SizedBox(height: 6),
          Builder(builder: (_) {
            final g = _list(u['by_grade']);
            if (g.isEmpty) return Text('No grades chosen yet.', style: context.tt.bodySmall);
            final max = g.fold<int>(1, (a, e) => _i(e['users']) > a ? _i(e['users']) : a);
            return Column(children: [for (final e in g) HBar(label: 'Grade ${e['grade']}', fraction: _i(e['users']) / max, value: '${e['users']}')]);
          }),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final e in Map<String, dynamic>.from(u['by_track'] as Map).entries) Pill('${_trackLabel(e.key)}: ${e.value}', icon: Icons.alt_route_rounded)]),
        ]),
      ),
      const SizedBox(height: 14),
      SectionCard(
        title: 'Learning',
        subtitle: 'Accuracy uses each student\'s latest answer to each question',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Accuracy by subject', style: context.tt.labelLarge),
          const SizedBox(height: 4),
          if (_list(l['by_subject']).isEmpty) Text('No answers in this period.', style: context.tt.bodySmall),
          for (final e in _list(l['by_subject'])) HBar(label: '${e['subject']}', fraction: (e['accuracy'] as num? ?? 0) / 100, value: _p(e['accuracy']), sub: '${e['answered']} answers', color: _accColor(context, e['accuracy'])),
          const SizedBox(height: 14),
          Text('Accuracy by grade', style: context.tt.labelLarge),
          const SizedBox(height: 4),
          for (final e in _list(l['by_grade'])) HBar(label: 'Grade ${e['grade']}', fraction: (e['accuracy'] as num? ?? 0) / 100, value: _p(e['accuracy']), sub: '${e['answered']} answers', color: _accColor(context, e['accuracy'])),
          const SizedBox(height: 14),
          Text('Practice vs exam', style: context.tt.labelLarge),
          const SizedBox(height: 6),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final m in ['practice', 'exam'])
              if (byMode[m] != null)
                Pill('${m == 'exam' ? 'Exams' : 'Practice'}: ${(byMode[m] as Map)['sessions']} · avg ${_p((byMode[m] as Map)['average_percent'])}${(byMode[m] as Map)['average_minutes'] == null ? '' : ' · ${(byMode[m] as Map)['average_minutes']} min'}', icon: m == 'exam' ? Icons.timer_rounded : Icons.bolt_rounded),
            if (byMode.isEmpty) Text('No finished quizzes in this period.', style: context.tt.bodySmall),
          ]),
          const SizedBox(height: 14),
          Text('Quizzes finished per day', style: context.tt.labelLarge),
          const SizedBox(height: 6),
          LineChart(values: [for (final d in sessDaily) _i(d['count'])], color: kGood),
          const SizedBox(height: 14),
          Text('Busiest hours', style: context.tt.labelLarge),
          const SizedBox(height: 6),
          BarsChart(values: [for (final h in _list(l['busiest_hours'])) _i(h['sessions'])], labels: [for (final h in _list(l['busiest_hours'])) '${h['hour']}'], height: 80, showEvery: 3),
          const SizedBox(height: 10),
          Text('Busiest weekdays', style: context.tt.labelLarge),
          const SizedBox(height: 6),
          BarsChart(values: [for (final h in _list(l['busiest_weekdays'])) _i(h['sessions'])], labels: [for (final h in _list(l['busiest_weekdays'])) '${h['day']}'.substring(0, 3)], height: 80),
        ]),
      ),
      const SizedBox(height: 14),
      SectionCard(
        title: 'Question quality',
        subtitle: 'Needs at least ${q['min_answers']} answers per question',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _QList(title: 'May have a wrong answer key (under 25% correct)', icon: Icons.warning_amber_rounded, color: context.sq.warn, items: _list(q['may_have_wrong_answer_key'])),
          _QList(title: 'Hardest questions', icon: Icons.trending_down_rounded, color: context.sq.bad, items: _list(q['hardest'])),
          _QList(title: 'Easiest questions', icon: Icons.trending_up_rounded, color: context.sq.good, items: _list(q['easiest'])),
          const SizedBox(height: 6),
          Text('${q['never_answered_count']} published questions have never been answered.', style: context.tt.bodyMedium),
          for (final e in _list(q['never_answered_sample'])) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• #${e['question_id']} ${e['text']}', style: context.tt.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
        ]),
      ),
      const SizedBox(height: 14),
      SectionCard(
        title: 'Content',
        subtitle: '${c['subjects']} subjects · ${c['units']} units',
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 22,
            headingRowHeight: 38,
            dataRowMinHeight: 34,
            dataRowMaxHeight: 40,
            columns: const [DataColumn(label: Text('Grade')), DataColumn(label: Text('Subject')), DataColumn(label: Text('Units'), numeric: true), DataColumn(label: Text('Published'), numeric: true), DataColumn(label: Text('Draft'), numeric: true), DataColumn(label: Text('Archived'), numeric: true)],
            rows: [
              for (final r in _list(c['by_grade_subject']))
                DataRow(cells: [DataCell(Text('${r['grade']}')), DataCell(Text('${r['subject']}')), DataCell(Text('${r['units'] ?? 0}')), DataCell(Text('${r['published']}')), DataCell(Text('${r['draft']}')), DataCell(Text('${r['archived']}'))]),
            ],
          ),
        ),
      ),
    ]);
  }

  static String _trackLabel(String k) => switch (k) { 'natural' => 'Natural Science', 'social' => 'Social Science', _ => 'No stream chosen' };

  static Color _accColor(BuildContext c, dynamic acc) {
    final a = (acc as num?)?.toInt() ?? 0;
    return a >= 70 ? c.sq.good : (a >= 40 ? c.sq.warn : c.sq.bad);
  }
}

class _QList extends StatelessWidget {
  const _QList({required this.title, required this.icon, required this.color, required this.items});
  final String title;
  final IconData icon;
  final Color color;
  final List<Map<String, dynamic>> items;
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, size: 18, color: color), const SizedBox(width: 6), Expanded(child: Text(title, style: context.tt.labelLarge))]),
        const SizedBox(height: 4),
        for (final e in items.take(8))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 48, child: Text('${e['accuracy']}%', style: context.tt.labelLarge?.copyWith(color: color))),
              Expanded(child: Text('${e['text']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall)),
              const SizedBox(width: 8),
              Text('#${e['question_id']} · ${e['answered']}×', style: context.tt.labelSmall?.copyWith(color: context.cs.onSurfaceVariant)),
            ]),
          ),
      ]),
    );
  }
}
