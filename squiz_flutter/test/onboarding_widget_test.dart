import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:squiz/core/theme.dart';
import 'package:squiz/ui/app_scope.dart';
import 'package:squiz/ui/auth/auth_page.dart';
import 'package:squiz/ui/onboarding_page.dart';
import 'helpers.dart';

void main() {
  testWidgets('onboarding shows grades', (t) async {
    final app = await makeApp();
    await t.pumpWidget(AppScope(state: app, child: MaterialApp(theme: buildTheme(Brightness.light), home: const OnboardingPage())));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('Grade'), findsWidgets);
  });

  testWidgets('register form validates before calling the server', (t) async {
    final app = await makeApp();
    await t.pumpWidget(AppScope(state: app, child: MaterialApp(theme: buildTheme(Brightness.dark), home: const AuthPage(startWithRegister: true))));
    await t.tap(find.text('Create account').last);
    await t.pump();
    expect(find.text('Enter your full name'), findsOneWidget);
    expect(find.text('At least 6 characters'), findsOneWidget);
  });

  test('validators', () {
    expect(validatePhone('0911223344'), isNull);
    expect(validatePhone('12'), isNotNull);
    expect(validatePassword('abcde'), isNotNull);
    expect(validatePassword('abcdef'), isNull); // 6 characters of any kind is enough
    expect(validatePassword('      '), isNull);
    expect(validateUsername('ab'), isNotNull);
  });
}
