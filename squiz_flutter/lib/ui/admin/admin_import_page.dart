import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../widgets/common.dart';
import 'admin_common.dart';

typedef _Json = Map<String, dynamic>;

/// Excel import: template -> choose file -> check -> import -> history with undo, plus bank export.
class AdminImportPage extends StatefulWidget {
  const AdminImportPage({super.key});
  @override
  State<AdminImportPage> createState() => _AdminImportPageState();
}

class _AdminImportPageState extends State<AdminImportPage> {
  PickedFile? _file;
  bool _createMissing = true, _publish = false, _busy = false;
  String _policy = 'skip';
  _Json? _check, _done;
  int _gen = 0;

  Future<void> _pick() async {
    final f = await pickFile(['xlsx', 'csv', 'json']);
    if (f == null) return;
    setState(() {
      _file = f;
      _check = null;
      _done = null;
    });
    await _validate();
  }

  Future<void> _validate() async {
    final f = _file;
    if (f == null) return;
    setState(() => _busy = true);
    final r = await guarded(context, () => context.adminApi.importValidate(f.bytes, f.name, createMissing: _createMissing));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _check = r;
    });
  }

  Future<void> _commit() async {
    final f = _file;
    if (f == null) return;
    final s = Map<String, dynamic>.from(_check!['summary'] as Map);
    final ok = await confirmDialog(context,
        title: 'Import ${s['ok']} questions?',
        body: '${_publish ? 'They will be visible to students.' : 'They are saved as drafts, so students will not see them until you publish.'} Rows with errors are skipped. You can undo the whole import afterwards.',
        ok: 'Import');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final r = await guarded(context, () => context.adminApi.importCommit(f.bytes, f.name, createMissing: _createMissing, policy: _policy, publish: _publish));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r != null) {
        _done = r;
        _check = null;
        _file = null;
        _gen++;
      }
    });
  }

  Future<void> _export(String format) async {
    final bytes = await guarded(context, () => context.adminApi.exportQuestions(format));
    if (bytes != null && mounted) await saveBytes(context, bytes, 'squiz-questions.$format');
  }

  @override
  Widget build(BuildContext context) {
    final check = _check;
    return Constrained(
      maxWidth: 900,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        SectionCard(
          title: '1. Get the template',
          subtitle: 'One row per question: grade, subject, unit, question, options A–D, correct answer, explanation, difficulty.',
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(
              icon: const Icon(Icons.download_rounded),
              label: const Text('Excel template'),
              onPressed: () async {
                final b = await guarded(context, () => context.adminApi.template());
                if (b != null && context.mounted) await saveBytes(context, b, 'squiz-import-template.xlsx');
              },
            ),
            OutlinedButton.icon(icon: const Icon(Icons.table_view_rounded), label: const Text('Export all questions (Excel)'), onPressed: () => _export('xlsx')),
            OutlinedButton(onPressed: () => _export('csv'), child: const Text('CSV')),
            OutlinedButton(onPressed: () => _export('json'), child: const Text('JSON')),
          ]),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '2. Choose your file',
          subtitle: 'Excel (.xlsx), CSV or JSON',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              FilledButton.icon(onPressed: _busy ? null : _pick, icon: const Icon(Icons.upload_file_rounded), label: Text(_file == null ? 'Choose file' : 'Choose another')),
              const SizedBox(width: 12),
              if (_file != null) Expanded(child: Text(_file!.name, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Create missing subjects and units'),
              subtitle: const Text('Otherwise rows that name an unknown subject or unit are rejected.'),
              value: _createMissing,
              onChanged: _busy ? null : (v) {
                setState(() => _createMissing = v);
                _validate();
              },
            ),
            Text('If a question already exists in the unit', style: context.tt.labelLarge),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: 'skip', label: Text('Skip')), ButtonSegment(value: 'update', label: Text('Update')), ButtonSegment(value: 'add', label: Text('Add copy'))],
              selected: {_policy},
              onSelectionChanged: (s) => setState(() => _policy = s.first),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Publish right away'),
              subtitle: const Text('Off: questions arrive as drafts for you to review.'),
              value: _publish,
              onChanged: (v) => setState(() => _publish = v),
            ),
          ]),
        ),
        if (_busy) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        if (check != null && !_busy) ...[
          const SizedBox(height: 12),
          _Preview(check: check, onImport: _commit),
        ],
        if (_done != null) ...[
          const SizedBox(height: 12),
          _Done(result: _done!),
        ],
        const SizedBox(height: 12),
        SectionCard(
          title: 'Import history',
          child: Loader<_Json>(
            key: ValueKey(_gen),
            load: () => context.adminApi.importHistory(),
            builder: (c, data, reload) {
              final items = [for (final x in data['items'] as List) _Json.from(x as Map)];
              if (items.isEmpty) return const Text('No imports yet.');
              return Column(children: [
                for (final b in items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(b['status'] == 'undone' ? Icons.undo_rounded : Icons.check_circle_rounded, color: b['status'] == 'undone' ? c.cs.outline : c.sq.good),
                    title: Text('${b['filename']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${shortDateTime(b['created_at'])} · ${b['admin']} · ${(b['counts'] as Map)['created'] ?? 0} added, ${(b['counts'] as Map)['updated'] ?? 0} updated${b['status'] == 'undone' ? ' · undone' : ''}'),
                    trailing: b['status'] == 'undone'
                        ? null
                        : TextButton(
                            onPressed: () async {
                              if (!await confirmDialog(c, title: 'Undo this import?', body: 'Added questions are removed and updated ones are restored to how they were.', ok: 'Undo', danger: true)) return;
                              if (!c.mounted) return;
                              final r = await guarded(c, () => c.adminApi.importUndo((b['id'] as num).toInt()), success: 'Import undone');
                              if (r != null) await reload();
                            },
                            child: const Text('Undo')),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.check, required this.onImport});
  final _Json check;
  final VoidCallback onImport;
  @override
  Widget build(BuildContext context) {
    final s = Map<String, dynamic>.from(check['summary'] as Map);
    final rows = [for (final x in check['rows'] as List) _Json.from(x as Map)];
    final problems = rows.where((r) => r['status'] != 'ok').toList();
    final ok = (s['ok'] as num).toInt();
    return SectionCard(
      title: '3. Check',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          Pill('${s['total']} rows', icon: Icons.table_rows_rounded),
          Pill('${s['ok']} ready', icon: Icons.check_rounded, color: context.sq.good),
          if ((s['duplicates'] as num) > 0) Pill('${s['duplicates']} already exist', icon: Icons.content_copy_rounded, color: context.sq.warn),
          if ((s['errors'] as num) > 0) Pill('${s['errors']} with errors', icon: Icons.error_outline_rounded, color: context.sq.bad),
        ]),
        if (problems.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Rows that need attention', style: context.tt.labelLarge),
          for (final r in problems.take(50))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(r['status'] == 'duplicate' ? Icons.content_copy_rounded : Icons.error_outline_rounded, size: 18, color: r['status'] == 'duplicate' ? context.sq.warn : context.sq.bad),
                const SizedBox(width: 8),
                Expanded(child: Text('Row ${r['row']}: ${(r['errors'] as List).isEmpty ? 'already exists in this unit' : (r['errors'] as List).join('; ')}\n${r['question'] ?? ''}', style: context.tt.bodySmall)),
              ]),
            ),
          if (problems.length > 50) Padding(padding: const EdgeInsets.only(top: 6), child: Text('…and ${problems.length - 50} more.', style: context.tt.bodySmall)),
        ],
        const SizedBox(height: 14),
        FilledButton.icon(onPressed: ok == 0 && (s['duplicates'] as num) == 0 ? null : onImport, icon: const Icon(Icons.playlist_add_check_rounded), label: Text('Import $ok questions')),
      ]),
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.result});
  final _Json result;
  @override
  Widget build(BuildContext context) {
    final c = Map<String, dynamic>.from(result['created'] as Map);
    return Card(
      color: context.cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(Icons.check_circle_rounded, color: context.cs.onPrimaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Imported: ${c['created']} added, ${c['updated']} updated, ${c['skipped_duplicates']} skipped. New subjects ${c['subjects']}, new units ${c['units']}.',
              style: TextStyle(color: context.cs.onPrimaryContainer, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      ),
    );
  }
}
