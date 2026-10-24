import 'package:flutter/material.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../app_scope.dart';
import 'admin_content_page.dart';
import 'admin_dashboard_page.dart';
import 'admin_import_page.dart';
import 'admin_more_pages.dart';
import 'admin_users_page.dart';

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon, selectedIcon;
}

const _dests = [
  _Dest('Overview', Icons.dashboard_outlined, Icons.dashboard_rounded),
  _Dest('Users', Icons.people_outline_rounded, Icons.people_rounded),
  _Dest('Content', Icons.library_books_outlined, Icons.library_books_rounded),
  _Dest('Import', Icons.upload_file_outlined, Icons.upload_file_rounded),
  _Dest('Reports', Icons.report_gmailerrorred_outlined, Icons.report_rounded),
  _Dest('Announcements', Icons.campaign_outlined, Icons.campaign_rounded),
  _Dest('Audit log', Icons.history_outlined, Icons.history_rounded),
  _Dest('Settings', Icons.settings_outlined, Icons.settings_rounded),
];

/// The administrator app. Wide screens (web, tablet, desktop) get a side rail with every section;
/// phones get four main tabs plus a "More" list. The server checks the administrator role on every request.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0; // 0..7 a section; -1 = the "More" list on phones

  Widget _page(int i) => switch (i) {
        0 => const AdminDashboardPage(),
        1 => const AdminUsersPage(),
        2 => const AdminContentPage(),
        3 => const AdminImportPage(),
        4 => const AdminReportsPage(),
        5 => const AdminAnnouncementsPage(),
        6 => const AdminAuditPage(),
        _ => const AdminSettingsPage(),
      };

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final idx = wide && _index < 0 ? 0 : _index;
    final title = idx < 0 ? 'More' : _dests[idx].label;

    final actions = <Widget>[
      IconButton(
        tooltip: 'Switch to student mode',
        icon: const Icon(Icons.school_outlined),
        onPressed: () => app.chooseMode(AppMode.student),
      ),
      IconButton(
        tooltip: Theme.of(context).brightness == Brightness.dark ? 'Light theme' : 'Dark theme',
        icon: Icon(Theme.of(context).brightness == Brightness.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
        onPressed: () => app.setThemeMode(Theme.of(context).brightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark),
      ),
      PopupMenuButton<String>(
        tooltip: 'Account',
        icon: CircleAvatar(radius: 15, backgroundColor: context.cs.primary, child: Text(app.user?.initials ?? '?', style: TextStyle(fontSize: 12, color: context.cs.onPrimary, fontWeight: FontWeight.w800))),
        onSelected: (v) {
          if (v == 'out') app.signOut();
          if (v == 'student') app.chooseMode(AppMode.student);
        },
        itemBuilder: (_) => [
          PopupMenuItem(enabled: false, child: Text('${app.user?.fullName ?? ''}\n@${app.user?.username ?? ''}${app.user?.isOwner == true ? ' · owner' : ''}')),
          const PopupMenuItem(value: 'student', child: Text('Switch to student mode')),
          const PopupMenuItem(value: 'out', child: Text('Sign out')),
        ],
      ),
      const SizedBox(width: 8),
    ];

    final body = AnimatedSwitcher(
      duration: Motion.d(context, 220),
      child: KeyedSubtree(key: ValueKey(idx), child: idx < 0 ? _MoreList(onOpen: (i) => setState(() => _index = i)) : _page(idx)),
    );

    if (wide) {
      return Scaffold(
        appBar: AppBar(title: Text(title), actions: actions),
        body: Row(children: [
          NavigationRail(
            extended: MediaQuery.sizeOf(context).width >= 1100,
            selectedIndex: idx,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: MediaQuery.sizeOf(context).width >= 1100 ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            destinations: [for (final d in _dests) NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label))],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }

    final sub = idx >= 4; // a section reached through "More": show a back arrow
    return PopScope(
      canPop: !sub,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && sub) setState(() => _index = -1);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          leading: sub ? IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => setState(() => _index = -1)) : null,
          actions: actions,
        ),
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: (idx >= 0 && idx < 4) ? idx : 4,
          onDestinationSelected: (i) {
            Haptic.tap();
            setState(() => _index = i == 4 ? -1 : i);
          },
          destinations: [
            for (final d in _dests.take(4)) NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
            const NavigationDestination(icon: Icon(Icons.more_horiz_rounded), selectedIcon: Icon(Icons.more_horiz_rounded), label: 'More'),
          ],
        ),
      ),
    );
  }
}

class _MoreList extends StatelessWidget {
  const _MoreList({required this.onOpen});
  final ValueChanged<int> onOpen;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        for (var i = 4; i < _dests.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(leading: Icon(_dests[i].selectedIcon, color: context.cs.primary), title: Text(_dests[i].label), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => onOpen(i)),
          ),
      ]);
}
