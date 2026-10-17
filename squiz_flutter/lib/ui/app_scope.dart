import 'package:flutter/widgets.dart';
import '../state/app_state.dart';

/// Gives every screen access to [AppState] and rebuilds it when the state changes.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);
  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext context) => (context.getInheritedWidgetOfExactType<AppScope>()!).notifier!;
}

extension AppContext on BuildContext {
  AppState get app => AppScope.of(this);
}
