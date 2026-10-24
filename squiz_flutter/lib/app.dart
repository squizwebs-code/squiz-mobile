import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'state/app_state.dart';
import 'ui/app_scope.dart';
import 'ui/admin/admin_shell.dart';
import 'ui/admin/mode_choice_page.dart';
import 'ui/onboarding_page.dart';
import 'ui/shell.dart';

class SquizApp extends StatelessWidget {
  const SquizApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => AppScope(
        state: state,
        child: Builder(builder: (context) {
          final app = context.app;
          return MaterialApp(
            title: 'SQUIZ',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light),
            darkTheme: buildTheme(Brightness.dark),
            themeMode: app.themeMode,
            home: const _Gate(),
          );
        }),
      );
}

class _Gate extends StatelessWidget {
  const _Gate();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final Widget child;
    if (app.loading) {
      child = const _Splash(key: ValueKey('splash'));
    } else if (app.loadError != null || app.bank == null) {
      child = Scaffold(key: const ValueKey('error'), body: Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(app.loadError ?? 'Something went wrong while starting SQUIZ.', textAlign: TextAlign.center))));
    } else if (app.needsModeChoice) {
      child = const ModeChoicePage(key: ValueKey('mode'));
    } else if (app.adminMode) {
      child = const AdminShell(key: ValueKey('admin'));
    } else if (app.needsOnboarding) {
      child = const OnboardingPage(key: ValueKey('onboarding'));
    } else {
      child = const AppShell(key: ValueKey('shell'));
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 400), child: child);
  }
}

class _Splash extends StatelessWidget {
  const _Splash({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Image.asset('assets/images/logo.png', width: 88, height: 88),
            const SizedBox(height: 20),
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          ]),
        ),
      );
}
