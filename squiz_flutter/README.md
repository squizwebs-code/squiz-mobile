# SQUIZ — Flutter app v2

Redesigned, animated Material 3 front end. App colour **#428bca** is the `primary` colour in both the light and the dark theme (`lib/core/theme.dart`, checked by `test/theme_test.dart`).

## What changed
- New design system: brand colour, light/dark themes, rounded cards, `NavigationBar` with 5 tabs (Home, Subjects, Practice, Saved, Profile).
- Home: greeting, resume card, progress ring, 7-day activity, weakest-subject nudge, quick actions.
- Subjects: debounced search across subjects, units and questions.
- Quiz: animated question transitions, instant feedback in practice, exam mode with changeable answers, review marks, optional countdown, swipe navigation, resume after the app is closed.
- Results: animated score ring, retry wrong answers, filterable review.
- Profile: account, sync status, theme switch (system/light/dark), grade, history, reset progress.
- Animations respect the system "reduce motion" setting.
- Optional account: sign in to sync bookmarks, flags, answers and history through the FastAPI backend (`/app/*`). Guests keep everything on the phone. Signing out removes the progress from the phone.

## Run
```bash
flutter create . --platforms=android   # generates the android/ folder (not included)
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000     # emulator -> backend on your PC
flutter run --dart-define=API_BASE_URL=http://192.168.x.x:8000  # real phone on the same Wi-Fi
```
After `flutter create`, add `<uses-permission android:name="android.permission.INTERNET"/>` to `android/app/src/main/AndroidManifest.xml`. For local `http://` development only, also add `android:usesCleartextTraffic="true"` to `<application>`; remove it for release and use HTTPS.

Release APK: `flutter build apk --release --dart-define=API_BASE_URL=https://your-domain`.
Requires Flutter ≥ 3.27.

## Honest status
- **Not compiled, not run.** The Flutter SDK was not available where this was written. The only check done is a Dart syntax parse of every file in `lib/` and `test/` (0 errors). Expect to fix some compile errors on first `flutter run` / `flutter analyze`.
- The tests in `test/` were written but **not executed**. Run `flutter test`.
- Backend: 43 tests were run and pass against PostgreSQL.
- Exams are graded on the phone, so the answer key is inside the downloaded/bundled bank.

## Contrast (computed with the WCAG formula)
| Pair | Ratio |
|---|---|
| White on #428bca (filled buttons) | 3.63:1 — fine for large/bold UI text, **below 4.5:1** for small text |
| #428bca on dark surface #121a23 (links/accents) | 4.82:1 |
| #2a6496 on white (links in light theme) | 6.25:1 |

Because white-on-#428bca is 3.63:1, small text on brand-coloured buttons does not meet WCAG AA. If that matters, use a darker label colour or a larger label size.
