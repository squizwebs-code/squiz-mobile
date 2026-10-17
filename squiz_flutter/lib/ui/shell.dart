import 'package:flutter/material.dart';
import '../core/motion.dart';
import 'app_scope.dart';
import 'browse/browse_page.dart';
import 'home/home_page.dart';
import 'practice/practice_page.dart';
import 'profile/profile_page.dart';
import 'saved/saved_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  int _tab = 0;
  void goTo(int i) => setState(() => _tab = i);

  static AppShellState? of(BuildContext c) => c.findAncestorStateOfType<AppShellState>();

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pages = <Widget>[const HomePage(), const BrowsePage(), const PracticePage(), const SavedPage(), const ProfilePage()];
    final saved = app.bookmarked().length + app.flagged().length;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(children: [
          for (final (i, p) in pages.indexed)
            Offstage(
              offstage: _tab != i,
              child: TickerMode(
                enabled: _tab == i,
                child: AnimatedOpacity(opacity: _tab == i ? 1 : 0, duration: Motion.d(context, 220), child: p),
              ),
            ),
        ]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          Haptic.tap();
          setState(() => _tab = i);
        },
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          const NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore_rounded), label: 'Subjects'),
          const NavigationDestination(icon: Icon(Icons.bolt_outlined), selectedIcon: Icon(Icons.bolt_rounded), label: 'Practice'),
          NavigationDestination(
            icon: Badge(isLabelVisible: saved > 0, label: Text('$saved'), child: const Icon(Icons.bookmark_border_rounded)),
            selectedIcon: Badge(isLabelVisible: saved > 0, label: Text('$saved'), child: const Icon(Icons.bookmark_rounded)),
            label: 'Saved',
          ),
          const NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Profile'),
        ],
      ),
    );
  }
}
