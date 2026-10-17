import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/api.dart';
import '../../state/app_state.dart';
import '../app_scope.dart';
import '../auth/auth_page.dart';
import '../../core/motion.dart';
import '../widgets/common.dart';
import '../widgets/sheets.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final cs = context.cs;
    final u = app.user;
    return AppPage(
      title: 'Profile',
      slivers: [
        SliverList.list(children: [
          // account
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: u == null ? _SignedOut() : _SignedIn(),
            ),
          ),
          const SizedBox(height: 16),
          // stats
          Row(children: [
            Expanded(child: _Stat(label: 'Answered', value: app.answeredCount, icon: Icons.task_alt_rounded)),
            const SizedBox(width: 10),
            Expanded(child: _Stat(label: 'Accuracy', value: app.accuracy ?? 0, suffix: '%', icon: Icons.track_changes_rounded, dash: app.accuracy == null)),
            const SizedBox(width: 10),
            Expanded(child: _Stat(label: 'Day streak', value: app.streak, icon: Icons.local_fire_department_rounded)),
          ]),
          const SizedBox(height: 20),
          const SectionHeader('Settings'),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.school_outlined),
                title: const Text('Grade'),
                subtitle: Text('Grade ${app.grade}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showGradeSheet(context),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Icon(Icons.brightness_6_outlined, color: cs.onSurfaceVariant), const SizedBox(width: 16), Text('Appearance', style: context.tt.bodyLarge)]),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.phone_android_rounded), label: Text('System')),
                        ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Light')),
                        ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Dark')),
                      ],
                      selected: {app.themeMode},
                      onSelectionChanged: (s) => app.setThemeMode(s.first),
                    ),
                  ),
                ]),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.restart_alt_rounded, color: context.sq.bad),
                title: const Text('Reset progress'),
                subtitle: Text(u == null ? 'Clears answers and history on this phone. Bookmarks stay.' : 'Clears answers and history on this phone and your account. Bookmarks stay.'),
                onTap: () async {
                  final ok = await confirmDialog(context, title: 'Reset progress?', body: 'Your answers, accuracy, streak and session history will be cleared. This cannot be undone.', ok: 'Reset', danger: true);
                  if (!ok || !context.mounted) return;
                  try {
                    await app.resetProgress();
                    if (context.mounted) showSnack(context, 'Progress reset');
                  } on ApiException catch (e) {
                    if (context.mounted) showSnack(context, e.offline ? 'Connect to the internet to reset your account progress.' : e.message);
                  }
                },
              ),
            ]),
          ),
          const SizedBox(height: 20),
          const SectionHeader('History'),
          if (app.history.isEmpty)
            const EmptyState(icon: Icons.history_rounded, title: 'No sessions yet')
          else
            for (final h in app.history.take(15))
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(h.isExam ? Icons.timer_outlined : Icons.bolt_rounded, color: cs.primary),
                  title: Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${h.correct}/${h.total} · ${relativeTime(h.ts, DateTime.now().millisecondsSinceEpoch)}${h.seconds == null ? '' : ' · ${mmss(h.seconds!)}'}'),
                  trailing: Text('${h.percent}%', style: context.tt.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.primary)),
                ),
              ),
        ]),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.icon, this.suffix = '', this.dash = false});
  final String label, suffix;
  final int value;
  final IconData icon;
  final bool dash;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(children: [
            Icon(icon, color: context.cs.primary),
            const SizedBox(height: 6),
            dash ? Text('–', style: context.tt.titleLarge) : AnimatedCount(value: value, suffix: suffix, style: context.tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            Text(label, style: context.tt.labelSmall?.copyWith(color: context.cs.onSurfaceVariant)),
          ]),
        ),
      );
}

class _SignedOut extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 26, backgroundColor: context.cs.primary.withValues(alpha: .15), child: Icon(Icons.person_outline_rounded, color: context.cs.primary)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Guest', style: context.tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            Text('Progress is saved on this phone only.', style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
          ])),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: FilledButton(onPressed: () => pushPage(context, const AuthPage(startWithRegister: true)), child: const Text('Create account'))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton(onPressed: () => pushPage(context, const AuthPage()), child: const Text('Sign in'))),
        ]),
      ]);
}

class _SignedIn extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final u = app.user!;
    final (label, color, icon) = switch (app.syncStatus) {
      SyncStatus.syncing => ('Syncing…', context.cs.primary, Icons.sync_rounded),
      SyncStatus.ok => (app.lastSyncedMs == null ? 'Synced' : 'Synced ${relativeTime(app.lastSyncedMs!, DateTime.now().millisecondsSinceEpoch)}', context.sq.good, Icons.cloud_done_outlined),
      SyncStatus.error => (app.syncError ?? 'Sync failed. Will retry.', context.sq.warn, Icons.cloud_off_outlined),
      SyncStatus.idle => ('Not synced yet', context.cs.onSurfaceVariant, Icons.cloud_queue_rounded),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        CircleAvatar(radius: 26, backgroundColor: context.cs.primary, child: Text(u.initials, style: TextStyle(color: context.cs.onPrimary, fontWeight: FontWeight.w800))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(u.fullName, style: context.tt.titleMedium?.copyWith(fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(u.phone, style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
        ])),
      ]),
      const SizedBox(height: 14),
      Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: context.tt.bodySmall)),
        TextButton(onPressed: app.syncStatus == SyncStatus.syncing ? null : app.syncNow, child: const Text('Sync now')),
      ]),
      const Divider(),
      Wrap(spacing: 8, children: [
        TextButton.icon(icon: const Icon(Icons.key_rounded, size: 18), label: const Text('Change password'), onPressed: () => pushPage(context, const ChangePasswordPage())),
        TextButton.icon(
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text('Sign out'),
          onPressed: () async {
            final ok = await confirmDialog(context, title: 'Sign out?', body: 'Your progress is saved to your account. It is removed from this phone so the next person starts fresh.', ok: 'Sign out');
            if (ok) await app.signOut();
          },
        ),
        TextButton.icon(
          icon: Icon(Icons.delete_forever_outlined, size: 18, color: context.sq.bad),
          label: Text('Delete account', style: TextStyle(color: context.sq.bad)),
          onPressed: () => _delete(context),
        ),
      ]),
    ]);
  }

  Future<void> _delete(BuildContext context) async {
    final app = AppScope.read(context);
    final ctl = TextEditingController();
    final pw = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete account?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('This permanently deletes your account and synced progress. Enter your password to confirm.'),
          const SizedBox(height: 12),
          TextField(controller: ctl, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: c.sq.bad), onPressed: () => Navigator.pop(c, ctl.text), child: const Text('Delete')),
        ],
      ),
    );
    ctl.dispose();
    if (pw == null || pw.isEmpty) return;
    try {
      await app.deleteAccount(pw);
    } on ApiException catch (e) {
      if (context.mounted) showSnack(context, e.offline ? 'Connect to the internet to delete your account.' : e.message);
    }
  }
}
