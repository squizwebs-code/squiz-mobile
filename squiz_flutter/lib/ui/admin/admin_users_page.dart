import 'dart:async';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../app_scope.dart';
import '../widgets/common.dart';
import 'admin_common.dart';

/// Every user's info, with search/filters, role changes, suspend/activate and password tools.
class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});
  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  String? _role, _status;
  int? _grade;
  int _page = 1;
  int _gen = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _changed() => setState(() {
        _page = 1;
        _gen++;
      });

  @override
  Widget build(BuildContext context) {
    return Constrained(
      child: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _search,
          decoration: InputDecoration(
            hintText: 'Search name, username or phone',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _search.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () { _search.clear(); _changed(); }),
          ),
          onChanged: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 400), _changed);
          },
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final r in const [(null, 'All roles'), ('student', 'Students'), ('admin', 'Admins')])
            ChoiceChip(label: Text(r.$2), selected: _role == r.$1, onSelected: (_) { _role = r.$1; _changed(); }),
          for (final s in const [(null, 'Any status'), ('active', 'Active'), ('suspended', 'Suspended')])
            ChoiceChip(label: Text(s.$2), selected: _status == s.$1, onSelected: (_) { _status = s.$1; _changed(); }),
          for (final g in const [null, 9, 10, 11, 12])
            ChoiceChip(label: Text(g == null ? 'Any grade' : 'Grade $g'), selected: _grade == g, onSelected: (_) { _grade = g; _changed(); }),
        ]),
        const SizedBox(height: 12),
        Loader<Map<String, dynamic>>(
          key: ValueKey('$_gen-$_page'),
          load: () => context.adminApi.users(q: _search.text, role: _role, status: _status, grade: _grade, page: _page),
          builder: (c, data, reload) {
            final items = [for (final x in (data['items'] as List)) Map<String, dynamic>.from(x as Map)];
            final total = (data['total'] as num).toInt();
            final size = (data['size'] as num).toInt();
            final pages = (total / size).ceil().clamp(1, 1 << 30);
            if (items.isEmpty) return const EmptyState(icon: Icons.person_search_rounded, title: 'No users found', text: 'Try another search or clear the filters.');
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('$total users', style: c.tt.labelLarge?.copyWith(color: c.cs.onSurfaceVariant))),
              for (final u in items)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    onTap: () async {
                      await pushPage(context, AdminUserDetailPage(userId: (u['id'] as num).toInt()));
                      if (mounted) setState(() => _gen++);
                    },
                    leading: CircleAvatar(backgroundColor: c.cs.primaryContainer, child: Text(_initials('${u['full_name']}'), style: TextStyle(color: c.cs.onPrimaryContainer, fontWeight: FontWeight.w800))),
                    title: Text('${u['full_name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('@${u['username']} · ${u['phone']}\nLast active ${ago(u['last_active_at'])}', maxLines: 2, overflow: TextOverflow.ellipsis),
                    isThreeLine: true,
                    trailing: Wrap(direction: Axis.vertical, spacing: 4, crossAxisAlignment: WrapCrossAlignment.end, children: [
                      if (u['is_owner'] == true) const Pill('Owner', icon: Icons.verified_rounded) else if (u['role'] == 'admin') const Pill('Admin', icon: Icons.admin_panel_settings_rounded),
                      if (u['status'] == 'suspended') Pill('Suspended', color: c.sq.bad),
                      if (u['selected_grade'] != null) Text('Grade ${u['selected_grade']}', style: c.tt.labelSmall),
                    ]),
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
    );
  }
}

String _initials(String name) {
  final p = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (p.isEmpty) return '?';
  return (p.first[0] + (p.length > 1 ? p.last[0] : '')).toUpperCase();
}

String trackLabel(String? t) => switch (t) { 'natural' => 'Natural Science', 'social' => 'Social Science', _ => 'No stream' };

class AdminUserDetailPage extends StatefulWidget {
  const AdminUserDetailPage({super.key, required this.userId});
  final int userId;
  @override
  State<AdminUserDetailPage> createState() => _AdminUserDetailPageState();
}

class _AdminUserDetailPageState extends State<AdminUserDetailPage> {
  int _gen = 0;
  void _refresh() => setState(() => _gen++);

  Future<void> _act(Future<dynamic> Function() f, String done) async {
    final r = await guarded(context, f, success: done);
    if (r != null || done.isEmpty) _refresh();
  }

  Future<void> _suspend(Map<String, dynamic> u) async {
    final reason = TextEditingController();
    String duration = 'forever';
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text('Suspend ${u['full_name']}?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('They are signed out immediately and cannot sign in until you activate them again.'),
            const SizedBox(height: 12),
            TextField(controller: reason, maxLines: 2, decoration: const InputDecoration(labelText: 'Reason (shown to the user)')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: duration,
              decoration: const InputDecoration(labelText: 'For how long'),
              items: const [
                DropdownMenuItem(value: 'forever', child: Text('Until I activate them')),
                DropdownMenuItem(value: '1', child: Text('1 day')),
                DropdownMenuItem(value: '7', child: Text('7 days')),
                DropdownMenuItem(value: '30', child: Text('30 days')),
              ],
              onChanged: (v) => set(() => duration = v ?? 'forever'),
            ),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Suspend'))],
        ),
      ),
    );
    final text = reason.text;
    reason.dispose();
    if (ok != true || !mounted) return;
    await _act(() => context.adminApi.suspend((u['id'] as num).toInt(), reason: text, days: duration == 'forever' ? null : int.parse(duration)), 'Suspended');
  }

  Future<void> _reset(Map<String, dynamic> u) async {
    if (!await confirmDialog(context, title: 'Reset password?', body: 'A temporary password is created and shown once. ${u['full_name']} is signed out everywhere and must choose a new password at the next sign-in.', ok: 'Reset')) return;
    if (!mounted) return;
    final temp = await guarded(context, () => context.adminApi.resetPassword((u['id'] as num).toInt()));
    if (temp == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Temporary password'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Give it to the user privately. It will not be shown again.'),
          const SizedBox(height: 12),
          SelectableText(temp, style: d.tt.titleLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()], fontWeight: FontWeight.w800)),
        ]),
        actions: [TextButton(onPressed: () => copyText(d, temp, 'Password'), child: const Text('Copy')), FilledButton(onPressed: () => Navigator.pop(d), child: const Text('Done'))],
      ),
    );
    _refresh();
  }

  Future<void> _delete(Map<String, dynamic> u) async {
    final typed = await askText(context, title: 'Delete ${u['full_name']}?', label: 'Type their username (${u['username']}) to confirm', ok: 'Delete');
    if (typed == null || !mounted) return;
    if (typed.trim().toLowerCase() != '${u['username']}'.toLowerCase()) {
      showSnack(context, 'The username did not match, nothing was deleted.');
      return;
    }
    final r = await guarded(context, () => context.adminApi.deleteUser((u['id'] as num).toInt()), success: 'User deleted');
    if (r == null && mounted) {
      // guarded returns null for void too, so check by reloading
      try {
        await context.adminApi.user((u['id'] as num).toInt());
      } catch (_) {
        if (mounted) Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User')),
      body: Constrained(
        maxWidth: 800,
        child: Loader<Map<String, dynamic>>(
          key: ValueKey(_gen),
          load: () => context.adminApi.user(widget.userId),
          builder: (c, u, reload) => ListView(padding: const EdgeInsets.all(16), children: [_body(c, u)]),
        ),
      ),
    );
  }

  Widget _body(BuildContext c, Map<String, dynamic> u) {
    final canManage = u['can_manage'] == true;
    final suspended = u['status'] == 'suspended';
    final isAdmin = u['role'] == 'admin';
    final owner = u['is_owner'] == true;
    final progress = Map<String, dynamic>.from(u['progress'] as Map);
    final chain = [for (final x in (u['promotion_chain'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
    final promoter = u['promoted_by'] as Map?;
    final me = AppScope.read(c).user?.id;
    final self = me == u['id'];

    Widget action(IconData icon, String label, VoidCallback onTap, {bool danger = false}) => OutlinedButton.icon(
          onPressed: canManage ? onTap : null,
          icon: Icon(icon, color: canManage && danger ? c.cs.error : null),
          label: Text(label, style: TextStyle(color: canManage && danger ? c.cs.error : null)),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        CircleAvatar(radius: 28, backgroundColor: c.cs.primaryContainer, child: Text(_initials('${u['full_name']}'), style: c.tt.titleLarge?.copyWith(color: c.cs.onPrimaryContainer, fontWeight: FontWeight.w800))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${u['full_name']}', style: c.tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          Text('@${u['username']}', style: c.tt.bodyMedium?.copyWith(color: c.cs.onSurfaceVariant)),
        ])),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (owner) const Pill('Owner', icon: Icons.verified_rounded) else Pill(isAdmin ? 'Admin' : 'Student', icon: isAdmin ? Icons.admin_panel_settings_rounded : Icons.school_rounded),
        Pill(suspended ? 'Suspended' : 'Active', color: suspended ? c.sq.bad : c.sq.good),
        if (u['must_change_password'] == true) Pill('Must change password', color: c.sq.warn),
        if (self) const Pill('You'),
      ]),
      const SizedBox(height: 14),
      SectionCard(title: 'Account', child: Column(children: [
        _row('Phone', '${u['phone']}'),
        _row('Grade', u['selected_grade'] == null ? '–' : 'Grade ${u['selected_grade']}'),
        if ((u['selected_grade'] ?? 0) >= 11) _row('Stream', trackLabel(u['selected_track'] as String?)),
        _row('Joined', shortDate(u['created_at'])),
        _row('Last active', ago(u['last_active_at'])),
        if (isAdmin && !owner) _row('Promoted by', promoter == null ? '–' : '${promoter['name']}'),
        if (suspended) ...[
          _row('Suspended', shortDateTime(u['suspended_at'])),
          _row('Until', u['suspended_until'] == null ? 'Until activated' : shortDateTime(u['suspended_until'])),
          if ('${u['suspended_reason'] ?? ''}'.isNotEmpty) _row('Reason', '${u['suspended_reason']}'),
        ],
      ])),
      if (isAdmin && chain.isNotEmpty) ...[
        const SizedBox(height: 12),
        SectionCard(title: 'Promotion chain', subtitle: 'Anyone above can demote this admin', child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final (i, a) in chain.reversed.indexed) ...[
            if (i > 0) const Icon(Icons.chevron_right_rounded, size: 18),
            Pill('${a['name']}'),
          ],
        ])),
      ],
      const SizedBox(height: 12),
      SectionCard(title: 'Learning progress', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          Pill('${progress['answered']} answered', icon: Icons.task_alt_rounded),
          Pill('${progress['accuracy'] ?? '–'}${progress['accuracy'] == null ? '' : '%'} accuracy', icon: Icons.track_changes_rounded, color: c.sq.good),
          Pill('${progress['sessions']} quizzes · ${progress['exams']} exams', icon: Icons.quiz_rounded),
          Pill('${progress['bookmarks']} saved · ${progress['flags']} flagged', icon: Icons.bookmark_rounded),
        ]),
        const SizedBox(height: 10),
        for (final s in (progress['by_subject'] as List? ?? const []))
          HBar(label: '${(s as Map)['subject']}', fraction: ((s['accuracy'] as num?) ?? 0) / 100, value: s['accuracy'] == null ? '–' : '${s['accuracy']}%', sub: '${s['answered']}'),
        if ((progress['recent'] as List? ?? const []).isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Recent quizzes', style: c.tt.labelLarge),
          for (final r in (progress['recent'] as List).take(5))
            Padding(padding: const EdgeInsets.only(top: 4), child: Text('${(r as Map)['title'] ?? 'Quiz'} · ${r['correct']}/${r['total']} · ${shortDate(r['at'])}', style: c.tt.bodySmall)),
        ],
      ])),
      const SizedBox(height: 12),
      SectionCard(title: 'Actions', subtitle: canManage ? null : '${u['cannot_manage_reason'] ?? 'You cannot manage this user.'}', child: Wrap(spacing: 8, runSpacing: 8, children: [
        if (!owner)
          action(isAdmin ? Icons.person_remove_rounded : Icons.admin_panel_settings_rounded, isAdmin ? 'Make student' : 'Make admin', () async {
            final to = isAdmin ? 'student' : 'admin';
            final ok = await confirmDialog(c, title: isAdmin ? 'Remove admin rights?' : 'Make ${u['full_name']} an admin?', body: isAdmin ? 'They become a student and are signed out. Admins they promoted move up to your chain.' : 'They get full access to this admin area. Only you and the admins above you can undo it.', ok: isAdmin ? 'Demote' : 'Promote', danger: isAdmin);
            if (ok && mounted) await _act(() => context.adminApi.setRole((u['id'] as num).toInt(), to), isAdmin ? 'Now a student' : 'Now an admin');
          }),
        if (suspended) action(Icons.lock_open_rounded, 'Activate', () => _act(() => context.adminApi.activate((u['id'] as num).toInt()), 'Activated')) else action(Icons.block_rounded, 'Suspend', () => _suspend(u), danger: true),
        action(Icons.password_rounded, 'Reset password', () => _reset(u)),
        action(Icons.lock_reset_rounded, 'Force password change', () => _act(() => context.adminApi.forcePasswordChange((u['id'] as num).toInt()), 'They must change it at next sign-in')),
        action(Icons.logout_rounded, 'Log out everywhere', () => _act(() async { await context.adminApi.logoutEverywhere((u['id'] as num).toInt()); return true; }, 'Signed out of all devices')),
        action(Icons.delete_forever_rounded, 'Delete user', () => _delete(u), danger: true),
      ])),
    ]);
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(k, style: context.tt.labelLarge?.copyWith(color: context.cs.onSurfaceVariant))),
          Expanded(child: SelectableText(v)),
        ]),
      );
}
