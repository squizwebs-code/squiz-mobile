import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../widgets/common.dart';
import 'admin_common.dart';

typedef _Json = Map<String, dynamic>;
int _n(dynamic v) => (v as num).toInt();
List<_Json> _items(_Json page) => [for (final x in page['items'] as List) _Json.from(x as Map)];

// ------------------------------------------------------------------ reports
class AdminReportsPage extends StatefulWidget {
  const AdminReportsPage({super.key});
  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage> {
  String _status = 'open';
  int _gen = 0;

  @override
  Widget build(BuildContext context) => Constrained(
        maxWidth: 800,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Wrap(spacing: 8, children: [
            for (final s in const ['open', 'resolved', 'dismissed'])
              ChoiceChip(label: Text(s[0].toUpperCase() + s.substring(1)), selected: _status == s, onSelected: (_) => setState(() {
                    _status = s;
                    _gen++;
                  })),
          ]),
          const SizedBox(height: 10),
          Loader<_Json>(
            key: ValueKey('$_gen-$_status'),
            load: () => context.adminApi.reports(status: _status),
            builder: (c, page, reload) {
              final items = _items(page);
              if (items.isEmpty) return const EmptyState(icon: Icons.flag_outlined, title: 'No reports here', text: 'Students can report a wrong or unclear question from the quiz.');
              return Column(children: [
                for (final r in items)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${r['question_text'] ?? 'Question #${r['question_id']}'}', maxLines: 3, overflow: TextOverflow.ellipsis, style: c.tt.titleSmall),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          Pill('${r['reason']}'.replaceAll('_', ' '), icon: Icons.flag_rounded, color: c.sq.warn),
                          if (_n(r['reports_for_question']) > 1) Pill('${r['reports_for_question']} reports', color: c.sq.bad),
                        ]),
                        if ('${r['note'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('“${r['note']}”', style: c.tt.bodyMedium)),
                        Padding(padding: const EdgeInsets.only(top: 6), child: Text('${r['reporter'] ?? 'A student'} · ${ago(r['created_at'])}', style: c.tt.labelSmall?.copyWith(color: c.cs.onSurfaceVariant))),
                        if (_status == 'open')
                          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                            TextButton(onPressed: () async { await guarded(c, () => c.adminApi.closeReport(_n(r['id']), false)); await reload(); }, child: const Text('Dismiss')),
                            FilledButton.tonal(onPressed: () async { await guarded(c, () => c.adminApi.closeReport(_n(r['id']), true)); await reload(); }, child: const Text('Mark resolved')),
                          ]),
                      ]),
                    ),
                  ),
              ]);
            },
          ),
        ]),
      );
}

// ------------------------------------------------------------------ announcements
class AdminAnnouncementsPage extends StatefulWidget {
  const AdminAnnouncementsPage({super.key});
  @override
  State<AdminAnnouncementsPage> createState() => _AdminAnnouncementsPageState();
}

class _AdminAnnouncementsPageState extends State<AdminAnnouncementsPage> {
  int _gen = 0;

  Future<void> _edit([_Json? a]) async {
    final title = TextEditingController(text: a?['title'] as String? ?? '');
    final body = TextEditingController(text: a?['body'] as String? ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(a == null ? 'New announcement' : 'Edit announcement'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, maxLength: 120, decoration: const InputDecoration(labelText: 'Title')),
          TextField(controller: body, maxLength: 2000, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'Message')),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save'))],
      ),
    );
    final t = title.text.trim(), b = body.text.trim();
    title.dispose();
    body.dispose();
    if (ok != true || t.isEmpty || b.isEmpty || !mounted) return;
    await guarded(context, () => a == null ? context.adminApi.createAnnouncement(t, b) : context.adminApi.patchAnnouncement(_n(a['id']), {'title': t, 'body': b}), success: 'Saved');
    setState(() => _gen++);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(onPressed: _edit, icon: const Icon(Icons.add_rounded), label: const Text('Announcement')),
        body: Constrained(
          maxWidth: 800,
          child: Loader<List<_Json>>(
            key: ValueKey(_gen),
            load: () => context.adminApi.announcements(),
            builder: (c, items, reload) {
              if (items.isEmpty) return const EmptyState(icon: Icons.campaign_outlined, title: 'No announcements', text: 'Active announcements show on every student\'s home screen.');
              return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
                for (final a in items)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      onTap: () => _edit(a),
                      title: Text('${a['title']}'),
                      subtitle: Text('${a['body']}', maxLines: 3, overflow: TextOverflow.ellipsis),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Switch(value: a['active'] == true, onChanged: (v) async { await guarded(c, () => c.adminApi.patchAnnouncement(_n(a['id']), {'active': v})); await reload(); }),
                        IconButton(icon: const Icon(Icons.delete_outline_rounded), onPressed: () async {
                          if (!await confirmDialog(c, title: 'Delete announcement?', body: 'Students will no longer see it.', ok: 'Delete', danger: true)) return;
                          if (!c.mounted) return;
                          await guarded(c, () => c.adminApi.deleteAnnouncement(_n(a['id'])));
                          await reload();
                        }),
                      ]),
                    ),
                  ),
              ]);
            },
          ),
        ),
      );
}

// ------------------------------------------------------------------ audit
class AdminAuditPage extends StatefulWidget {
  const AdminAuditPage({super.key});
  @override
  State<AdminAuditPage> createState() => _AdminAuditPageState();
}

class _AdminAuditPageState extends State<AdminAuditPage> {
  String _action = '';
  int _page = 1, _gen = 0;

  @override
  Widget build(BuildContext context) => Constrained(
        maxWidth: 900,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Wrap(spacing: 8, children: [
            for (final f in const [('', 'Everything'), ('user.', 'Users'), ('question.', 'Questions'), ('grade', 'Grades'), ('subject', 'Subjects'), ('unit', 'Units')])
              ChoiceChip(label: Text(f.$2), selected: _action == f.$1, onSelected: (_) => setState(() {
                    _action = f.$1;
                    _page = 1;
                    _gen++;
                  })),
          ]),
          const SizedBox(height: 10),
          Loader<_Json>(
            key: ValueKey('$_gen-$_page'),
            load: () => context.adminApi.audit(action: _action, page: _page),
            builder: (c, page, reload) {
              final items = _items(page);
              final pages = (_n(page['total']) / _n(page['size'])).ceil().clamp(1, 1 << 30);
              if (items.isEmpty) return const EmptyState(icon: Icons.history_rounded, title: 'Nothing logged yet');
              return Column(children: [
                for (final a in items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.history_rounded),
                    title: Text('${a['admin'] ?? 'System'} · ${a['action']}'),
                    subtitle: Text('${a['entity'] ?? ''}${a['entity_id'] == null ? '' : ' #${a['entity_id']}'} · ${shortDateTime(a['at'])}${a['details'] == null || (a['details'] as Map).isEmpty ? '' : '\n${a['details']}'}', maxLines: 3, overflow: TextOverflow.ellipsis),
                  ),
                if (pages > 1)
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    IconButton(onPressed: _page > 1 ? () => setState(() => _page--) : null, icon: const Icon(Icons.chevron_left_rounded)),
                    Text('Page $_page of $pages'),
                    IconButton(onPressed: _page < pages ? () => setState(() => _page++) : null, icon: const Icon(Icons.chevron_right_rounded)),
                  ]),
              ]);
            },
          ),
        ]),
      );
}

// ------------------------------------------------------------------ settings
class AdminSettingsPage extends StatelessWidget {
  const AdminSettingsPage({super.key});
  @override
  Widget build(BuildContext context) => Constrained(
        maxWidth: 640,
        child: Loader<_Json>(
          load: () => context.adminApi.settings(),
          builder: (c, s, reload) => _SettingsForm(initial: s),
        ),
      );
}

class _SettingsForm extends StatefulWidget {
  const _SettingsForm({required this.initial});
  final _Json initial;
  @override
  State<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<_SettingsForm> {
  late final _name = TextEditingController(text: '${widget.initial['app_name'] ?? ''}');
  late final _tagline = TextEditingController(text: '${widget.initial['tagline'] ?? ''}');
  late final _exam = TextEditingController(text: '${widget.initial['exam_name'] ?? ''}');
  DateTime? _date;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _date = DateTime.tryParse('${widget.initial['exam_date'] ?? ''}');
  }

  @override
  void dispose() {
    _name.dispose();
    _tagline.dispose();
    _exam.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showSnack(context, 'The app name cannot be empty.');
      return;
    }
    setState(() => _busy = true);
    final d = _date;
    await guarded(
        context,
        () => context.adminApi.saveSettings({
              'app_name': _name.text.trim(),
              'tagline': _tagline.text.trim(),
              'exam_name': _exam.text.trim().isEmpty ? null : _exam.text.trim(),
              if (d != null) 'exam_date': '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
            }),
        success: 'Settings saved');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        SectionCard(title: 'App', child: Column(children: [
          TextField(controller: _name, maxLength: 60, decoration: const InputDecoration(labelText: 'App name')),
          TextField(controller: _tagline, maxLength: 120, decoration: const InputDecoration(labelText: 'Tagline')),
        ])),
        const SizedBox(height: 12),
        SectionCard(title: 'Exam countdown', subtitle: 'Shown on students\' home screen', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: _exam, maxLength: 80, decoration: const InputDecoration(labelText: 'Exam name (e.g. Ethiopian University Entrance Exam)')),
          const SizedBox(height: 8),
          Row(children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.event_rounded),
              label: Text(_date == null ? 'Choose exam date' : shortDate(_date!.toIso8601String())),
              onPressed: () async {
                final now = DateTime.now();
                final d = await showDatePicker(context: context, initialDate: _date ?? now.add(const Duration(days: 90)), firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 3));
                if (d != null) setState(() => _date = d);
              },
            ),
            if (_date != null) IconButton(tooltip: 'Clear', icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _date = null)),
          ]),
        ])),
        const SizedBox(height: 16),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Save settings')),
      ]);
}
