import 'package:flutter/material.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../data/api.dart' show kApiBaseUrl;
import '../widgets/common.dart';
import 'admin_common.dart';
import 'admin_users_page.dart' show trackLabel;

typedef Json = Map<String, dynamic>;
int _id(dynamic v) => (v as num).toInt();

/// Grade -> subjects -> units -> questions.
class AdminContentPage extends StatefulWidget {
  const AdminContentPage({super.key});
  @override
  State<AdminContentPage> createState() => _AdminContentPageState();
}

class _AdminContentPageState extends State<AdminContentPage> {
  int? _gradeId;
  bool _archived = false;
  int _gen = 0;
  void _refresh() => setState(() => _gen++);

  Future<void> _addGrade() async {
    final n = await askText(context, title: 'Add grade', label: 'Grade number (1–12)');
    final number = int.tryParse((n ?? '').trim());
    if (number == null || !mounted) return;
    final name = await askText(context, title: 'Grade name', label: 'Name', initial: 'Grade $number');
    if (name == null || name.trim().isEmpty || !mounted) return;
    final r = await guarded(context, () => context.adminApi.createGrade(number, name.trim()), success: 'Grade added');
    if (r != null) {
      _gradeId = _id(r['id']);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Constrained(
      child: Loader<List<Json>>(
        key: ValueKey('$_gen-$_archived'),
        load: () => context.adminApi.grades(archived: true),
        builder: (c, grades, reload) {
          final shown = grades.where((g) => _archived || g['archived'] != true).toList();
          Json? grade;
          for (final g in shown) {
            if (_id(g['id']) == _gradeId) grade = g;
          }
          grade ??= shown.isEmpty ? null : shown.first;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final g in shown)
                ChoiceChip(
                  label: Text('${g['name']}${g['archived'] == true ? ' (archived)' : g['published'] == false ? ' (hidden)' : ''}'),
                  selected: grade != null && _id(g['id']) == _id(grade['id']),
                  onSelected: (_) => setState(() => _gradeId = _id(g['id'])),
                ),
              ActionChip(avatar: const Icon(Icons.add_rounded, size: 18), label: const Text('Grade'), onPressed: _addGrade),
              FilterChip(label: const Text('Show archived'), selected: _archived, onSelected: (v) => setState(() => _archived = v)),
            ]),
            const SizedBox(height: 12),
            if (grade == null)
              const EmptyState(icon: Icons.school_rounded, title: 'No grades yet', text: 'Add a grade to start building content.')
            else
              _GradeBody(key: ValueKey('${grade['id']}-$_gen'), grade: grade, onChanged: _refresh),
          ]);
        },
      ),
    );
  }
}

class _GradeBody extends StatefulWidget {
  const _GradeBody({super.key, required this.grade, required this.onChanged});
  final Json grade;
  final VoidCallback onChanged;
  @override
  State<_GradeBody> createState() => _GradeBodyState();
}

class _GradeBodyState extends State<_GradeBody> {
  int _gen = 0;
  void _refresh() => setState(() => _gen++);

  Json get g => widget.grade;
  bool get _gradeArchived => g['archived'] == true;

  Future<void> _addSubject(List<Json> all) async {
    final gid = _id(g['id']);
    final free = all.where((s) => s['archived'] != true && !(s['grades'] as List).any((l) => _id((l as Map)['grade_id']) == gid)).toList();
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (s) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(leading: const Icon(Icons.add_circle_outline_rounded), title: const Text('Create a new subject'), onTap: () => Navigator.pop(s, 'new')),
          if (free.isNotEmpty) const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text('Or add an existing subject')),
          for (final f in free) ListTile(title: Text('${f['name']}'), subtitle: Text(trackLabel(f['track'] == 'all' ? null : f['track'] as String?).replaceAll('No stream', 'All students')), onTap: () => Navigator.pop(s, f)),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice is Json) {
      await guarded(context, () => context.adminApi.assignSubject(gid, _id(choice['id'])), success: 'Subject added');
      _refresh();
      return;
    }
    final name = await askText(context, title: 'New subject', label: 'Subject name', ok: 'Next');
    if (name == null || name.trim().isEmpty || !mounted) return;
    final track = await _askTrack(context, 'all');
    if (track == null || !mounted) return;
    final key = name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    final made = await guarded(context, () => context.adminApi.createSubject(key.length < 2 ? '$key-x' : key, name.trim(), track));
    if (made == null || !mounted) return;
    await guarded(context, () => context.adminApi.assignSubject(gid, _id(made['id'])), success: 'Subject added');
    _refresh();
  }

  Future<void> _gradeMenu(String v) async {
    final id = _id(g['id']);
    switch (v) {
      case 'rename':
        final n = await askText(context, title: 'Rename grade', initial: '${g['name']}');
        if (n != null && n.trim().isNotEmpty && mounted) await guarded(context, () => context.adminApi.patchGrade(id, {'name': n.trim()}));
      case 'publish':
        await guarded(context, () => context.adminApi.patchGrade(id, {'published': g['published'] != true}), success: g['published'] == true ? 'Hidden from students' : 'Visible to students');
      case 'archive':
        if (await confirmDialog(context, title: 'Archive ${g['name']}?', body: 'It disappears for students. Nothing is deleted and you can restore it.', ok: 'Archive', danger: true) && mounted) await guarded(context, () => context.adminApi.archiveGrade(id));
      case 'restore':
        await guarded(context, () => context.adminApi.restoreGrade(id));
    }
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final gid = _id(g['id']);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('Subjects in ${g['name']}', style: context.tt.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
        PopupMenuButton<String>(
          onSelected: _gradeMenu,
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'rename', child: Text('Rename grade')),
            PopupMenuItem(value: 'publish', child: Text(g['published'] == true ? 'Hide from students' : 'Show to students')),
            _gradeArchived ? const PopupMenuItem(value: 'restore', child: Text('Restore grade')) : const PopupMenuItem(value: 'archive', child: Text('Archive grade')),
          ],
        ),
      ]),
      Loader<List<Json>>(
        key: ValueKey(_gen),
        load: () => context.adminApi.subjects(archived: false),
        builder: (c, all, reload) {
          final mine = all.where((s) => (s['grades'] as List).any((l) => _id((l as Map)['grade_id']) == gid)).toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (mine.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('No subjects in this grade yet.'))),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorder: (a, b) async {
                if (b > a) b--;
                final order = [...mine];
                order.insert(b, order.removeAt(a));
                // Keep other grades' subjects in their slots: only reorder the ones shown here.
                final mineIds = {for (final s in mine) _id(s['id'])};
                final it = order.iterator;
                final full = <int>[
                  for (final s in all) if (mineIds.contains(_id(s['id']))) (it..moveNext()).current['id'] as int else _id(s['id'])
                ];
                await guarded(context, () => context.adminApi.reorderSubjects(full));
                _refresh();
              },
              children: [
                for (final (i, s) in mine.indexed)
                  _SubjectTile(
                    key: ValueKey(s['id']),
                    index: i,
                    subject: s,
                    gradeId: gid,
                    onChanged: _refresh,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (!_gradeArchived) FilledButton.tonalIcon(onPressed: () => _addSubject(all), icon: const Icon(Icons.add_rounded), label: const Text('Add subject')),
          ]);
        },
      ),
    ]);
  }
}

Future<String?> _askTrack(BuildContext context, String current) => showDialog<String>(
      context: context,
      builder: (d) => SimpleDialog(title: const Text('Who is this subject for?'), children: [
        for (final t in const [('all', 'Everyone in the grade'), ('natural', 'Natural Science stream only'), ('social', 'Social Science stream only')])
          SimpleDialogOption(onPressed: () => Navigator.pop(d, t.$1), child: Row(children: [Icon(current == t.$1 ? Icons.radio_button_checked : Icons.radio_button_off, size: 20), const SizedBox(width: 10), Text(t.$2)])),
      ]),
    );

class _SubjectTile extends StatelessWidget {
  const _SubjectTile({super.key, required this.index, required this.subject, required this.gradeId, required this.onChanged});
  final int index, gradeId;
  final Json subject;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final s = subject;
    final link = (s['grades'] as List).cast<Map>().firstWhere((l) => _id(l['grade_id']) == gradeId);
    final track = '${s['track']}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () async {
          await pushPage(context, AdminUnitsPage(gradeId: gradeId, subject: s));
          onChanged();
        },
        leading: ReorderableDragStartListener(index: index, child: const Icon(Icons.drag_indicator_rounded)),
        title: Text('${s['name']}'),
        subtitle: Wrap(spacing: 6, children: [
          if (track != 'all') Pill(trackLabel(track), icon: Icons.alt_route_rounded),
          if (link['published'] != true) Pill('Hidden', color: context.sq.warn),
        ]),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            final api = context.adminApi;
            switch (v) {
              case 'publish':
                await guarded(context, () => api.assignSubject(gradeId, _id(s['id']), published: link['published'] != true));
              case 'rename':
                final n = await askText(context, title: 'Rename subject', initial: '${s['name']}');
                if (n != null && n.trim().isNotEmpty && context.mounted) await guarded(context, () => api.patchSubject(_id(s['id']), {'name': n.trim()}));
              case 'track':
                final t = await _askTrack(context, track);
                if (t != null && context.mounted) await guarded(context, () => api.patchSubject(_id(s['id']), {'track': t}));
              case 'archive':
                if (await confirmDialog(context, title: 'Archive ${s['name']}?', body: 'It is hidden in every grade. Questions are kept.', ok: 'Archive', danger: true) && context.mounted) await guarded(context, () => api.archiveSubject(_id(s['id'])));
            }
            onChanged();
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'publish', child: Text(link['published'] == true ? 'Hide in this grade' : 'Show in this grade')),
            const PopupMenuItem(value: 'rename', child: Text('Rename')),
            const PopupMenuItem(value: 'track', child: Text('Change stream')),
            const PopupMenuItem(value: 'archive', child: Text('Archive subject')),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ units
class AdminUnitsPage extends StatefulWidget {
  const AdminUnitsPage({super.key, required this.gradeId, required this.subject});
  final int gradeId;
  final Json subject;
  @override
  State<AdminUnitsPage> createState() => _AdminUnitsPageState();
}

class _AdminUnitsPageState extends State<AdminUnitsPage> {
  int _gen = 0;
  bool _archived = false;
  void _refresh() => setState(() => _gen++);

  Future<void> _add() async {
    final t = await askText(context, title: 'Add unit', label: 'Unit title', ok: 'Add');
    if (t == null || t.trim().isEmpty || !mounted) return;
    await guarded(context, () => context.adminApi.createUnit(widget.gradeId, _id(widget.subject['id']), t.trim()), success: 'Unit added');
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final sid = _id(widget.subject['id']);
    return Scaffold(
      appBar: AppBar(title: Text('${widget.subject['name']}'), actions: [
        IconButton(tooltip: _archived ? 'Hide archived' : 'Show archived', icon: Icon(_archived ? Icons.inventory_2_rounded : Icons.inventory_2_outlined), onPressed: () => setState(() {
              _archived = !_archived;
              _gen++;
            })),
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add_rounded), label: const Text('Unit')),
      body: Constrained(
        maxWidth: 800,
        child: Loader<List<Json>>(
          key: ValueKey(_gen),
          load: () => context.adminApi.units(gradeId: widget.gradeId, subjectId: sid, archived: _archived),
          builder: (c, units, reload) {
            if (units.isEmpty) return const EmptyState(icon: Icons.folder_open_rounded, title: 'No units yet', text: 'Add a unit, then add questions to it.');
            final active = units.where((u) => u['archived'] != true).toList();
            final gone = units.where((u) => u['archived'] == true).toList();
            return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorder: (a, b) async {
                  if (b > a) b--;
                  final order = [...active];
                  order.insert(b, order.removeAt(a));
                  await guarded(context, () => context.adminApi.reorderUnits(widget.gradeId, sid, [for (final u in order) _id(u['id'])]));
                  _refresh();
                },
                children: [for (final (i, u) in active.indexed) _unitTile(c, u, i)],
              ),
              for (final u in gone) _unitTile(c, u, null),
            ]);
          },
        ),
      ),
    );
  }

  Widget _unitTile(BuildContext c, Json u, int? index) {
    final counts = Map<String, dynamic>.from(u['questions'] as Map);
    final archived = u['archived'] == true;
    return Card(
      key: ValueKey(u['id']),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: archived ? null : () async {
          await pushPage(context, AdminQuestionsPage(unit: u));
          _refresh();
        },
        leading: index == null ? const Icon(Icons.inventory_2_outlined) : ReorderableDragStartListener(index: index, child: const Icon(Icons.drag_indicator_rounded)),
        title: Text('${u['title']}', style: archived ? TextStyle(color: c.cs.outline) : null),
        subtitle: Text('${counts['published'] ?? 0} published · ${counts['draft'] ?? 0} draft${archived ? ' · archived' : ''}'),
        trailing: archived
            ? TextButton(onPressed: () async { await guarded(context, () => context.adminApi.restoreUnit(_id(u['id']))); _refresh(); }, child: const Text('Restore'))
            : Row(mainAxisSize: MainAxisSize.min, children: [
                Switch(value: u['published'] == true, onChanged: (v) async { await guarded(context, () => context.adminApi.patchUnit(_id(u['id']), {'published': v})); _refresh(); }),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'rename') {
                      final n = await askText(context, title: 'Rename unit', initial: '${u['title']}');
                      if (n != null && n.trim().isNotEmpty && mounted) await guarded(context, () => context.adminApi.patchUnit(_id(u['id']), {'title': n.trim()}));
                    } else if (await confirmDialog(context, title: 'Archive this unit?', body: 'Students stop seeing it. Its questions are kept and you can restore it.', ok: 'Archive', danger: true) && mounted) {
                      await guarded(context, () => context.adminApi.archiveUnit(_id(u['id'])));
                    }
                    _refresh();
                  },
                  itemBuilder: (_) => const [PopupMenuItem(value: 'rename', child: Text('Rename')), PopupMenuItem(value: 'archive', child: Text('Archive'))],
                ),
              ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ questions
class AdminQuestionsPage extends StatefulWidget {
  const AdminQuestionsPage({super.key, required this.unit});
  final Json unit;
  @override
  State<AdminQuestionsPage> createState() => _AdminQuestionsPageState();
}

class _AdminQuestionsPageState extends State<AdminQuestionsPage> {
  String? _status;
  int _page = 1, _gen = 0;
  void _refresh() => setState(() => _gen++);

  Future<void> _edit([Json? q]) async {
    final saved = await pushPage<bool>(context, QuestionEditPage(unitId: _id(widget.unit['id']), question: q));
    if (saved == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.unit['title']}')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _edit, icon: const Icon(Icons.add_rounded), label: const Text('Question')),
      body: Constrained(
        maxWidth: 800,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
          Wrap(spacing: 8, children: [
            for (final s in const [(null, 'All'), ('published', 'Published'), ('draft', 'Drafts'), ('archived', 'Archived')])
              ChoiceChip(label: Text(s.$2), selected: _status == s.$1, onSelected: (_) => setState(() {
                    _status = s.$1;
                    _page = 1;
                    _gen++;
                  })),
          ]),
          const SizedBox(height: 10),
          Loader<Json>(
            key: ValueKey('$_gen-$_page'),
            load: () => context.adminApi.questions(unitId: _id(widget.unit['id']), status: _status, page: _page),
            builder: (c, data, reload) {
              final items = [for (final x in data['items'] as List) Json.from(x as Map)];
              final pages = ((data['total'] as num) / (data['size'] as num)).ceil().clamp(1, 1 << 30);
              if (items.isEmpty) return const EmptyState(icon: Icons.help_outline_rounded, title: 'No questions here', text: 'Add one with the button below, or import an Excel file.');
              return Column(children: [
                for (final q in items)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      onTap: () => _edit(q),
                      title: Text('${q['text']}', maxLines: 3, overflow: TextOverflow.ellipsis),
                      subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(spacing: 6, children: [
                        Pill('${q['status']}'.replaceFirst('published', 'Published').replaceFirst('draft', 'Draft').replaceFirst('archived', 'Archived'), color: q['status'] == 'published' ? c.sq.good : (q['status'] == 'draft' ? c.sq.warn : c.cs.outline)),
                        if (q['difficulty'] != null) Pill('${q['difficulty']}'),
                      ])),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          await guarded(context, () => context.adminApi.setQuestionStatus(_id(q['id']), v));
                          _refresh();
                        },
                        itemBuilder: (_) => [
                          if (q['status'] != 'published') const PopupMenuItem(value: 'publish', child: Text('Publish')),
                          if (q['status'] == 'published') const PopupMenuItem(value: 'unpublish', child: Text('Move to drafts')),
                          if (q['status'] != 'archived') const PopupMenuItem(value: 'archive', child: Text('Archive')),
                        ],
                      ),
                    ),
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
      ),
    );
  }
}

class QuestionEditPage extends StatefulWidget {
  const QuestionEditPage({super.key, required this.unitId, this.question});
  final int unitId;
  final Json? question;
  @override
  State<QuestionEditPage> createState() => _QuestionEditPageState();
}

class _QuestionEditPageState extends State<QuestionEditPage> {
  final _form = GlobalKey<FormState>();
  late final _text = TextEditingController(text: widget.question?['text'] as String? ?? '');
  late final _expl = TextEditingController(text: widget.question?['explanation'] as String? ?? '');
  late final List<TextEditingController> _opts;
  int _correct = 0;
  String? _difficulty;
  String? _image;
  bool _publish = false, _busy = false;

  @override
  void initState() {
    super.initState();
    final q = widget.question;
    final opts = q == null ? <Json>[] : [for (final o in q['options'] as List) Json.from(o as Map)];
    final texts = opts.isEmpty ? ['', '', '', ''] : [for (final o in opts) '${o['text']}'];
    _opts = [for (final t in texts) TextEditingController(text: t)];
    final ci = opts.indexWhere((o) => o['is_correct'] == true);
    _correct = ci < 0 ? 0 : ci;
    _difficulty = q?['difficulty'] as String?;
    _image = q?['image_url'] as String?;
    _publish = q?['status'] == 'published';
  }

  @override
  void dispose() {
    _text.dispose();
    _expl.dispose();
    for (final o in _opts) {
      o.dispose();
    }
    super.dispose();
  }

  Future<void> _upload() async {
    final f = await pickFile(['png', 'jpg', 'jpeg', 'webp', 'gif']);
    if (f == null || !mounted) return;
    final url = await guarded(context, () => context.adminApi.uploadImage(f.bytes, f.name));
    if (url != null) setState(() => _image = url);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final body = {
      'unit_id': widget.unitId,
      'text': _text.text.trim(),
      'explanation': _expl.text.trim().isEmpty ? null : _expl.text.trim(),
      'difficulty': _difficulty,
      'image_url': _image,
      'status': _publish ? 'published' : (widget.question?['status'] == 'archived' ? 'archived' : 'draft'),
      'options': [for (final (i, o) in _opts.indexed) {'text': o.text.trim(), 'is_correct': i == _correct}],
    };
    final q = widget.question;
    final r = await guarded(context, () => q == null ? context.adminApi.createQuestion(body) : context.adminApi.patchQuestion(_id(q['id']), body), success: 'Saved');
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final base = kApiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    return Scaffold(
      appBar: AppBar(title: Text(widget.question == null ? 'New question' : 'Edit question'), actions: [TextButton(onPressed: _busy ? null : _save, child: const Text('Save'))]),
      body: Constrained(
        maxWidth: 720,
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            TextFormField(controller: _text, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: 'Question'), validator: (v) => (v ?? '').trim().length < 3 ? 'Write the question' : null),
            const SizedBox(height: 16),
            Text('Answers (tap the circle for the correct one)', style: context.tt.labelLarge),
            Column(children: [
              for (final (i, o) in _opts.indexed)
                Row(children: [
                  Radio<int>(value: i, groupValue: _correct, onChanged: (v) => setState(() => _correct = v ?? 0)),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: TextFormField(
                        controller: o,
                        decoration: InputDecoration(labelText: 'Option ${String.fromCharCode(65 + i)}'),
                        validator: (v) {
                          final t = (v ?? '').trim().toLowerCase();
                          if (t.isEmpty) return 'Required';
                          final dup = _opts.where((x) => x.text.trim().toLowerCase() == t).length > 1;
                          return dup ? 'Options must differ' : null;
                        },
                      ),
                    ),
                  ),
                  if (_opts.length > 2)
                    IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                        onPressed: () => setState(() {
                              _opts.removeAt(i).dispose();
                              if (_correct >= _opts.length) _correct = 0;
                            })),
                ]),
            ]),
            if (_opts.length < 6) Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => setState(() => _opts.add(TextEditingController())), icon: const Icon(Icons.add_rounded), label: const Text('Add option'))),
            const SizedBox(height: 12),
            TextFormField(controller: _expl, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'Explanation (optional)')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _difficulty,
              decoration: const InputDecoration(labelText: 'Difficulty'),
              items: const [DropdownMenuItem(value: null, child: Text('Not set')), DropdownMenuItem(value: 'easy', child: Text('Easy')), DropdownMenuItem(value: 'medium', child: Text('Medium')), DropdownMenuItem(value: 'hard', child: Text('Hard'))],
              onChanged: (v) => setState(() => _difficulty = v),
            ),
            const SizedBox(height: 12),
            if (_image != null)
              Card(child: Padding(padding: const EdgeInsets.all(8), child: Row(children: [
                ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(_image!.startsWith('http') ? _image! : '$base$_image', width: 72, height: 72, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 72, height: 72, child: Icon(Icons.broken_image_outlined)))),
                const SizedBox(width: 12),
                Expanded(child: Text(_image!, maxLines: 1, overflow: TextOverflow.ellipsis)),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _image = null)),
              ])))
            else
              Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: _upload, icon: const Icon(Icons.image_rounded), label: const Text('Add picture'))),
            const SizedBox(height: 8),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Published'), subtitle: const Text('Students only see published questions.'), value: _publish, onChanged: (v) => setState(() => _publish = v)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _busy ? null : _save, child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save question')),
          ]),
        ),
      ),
    );
  }
}
