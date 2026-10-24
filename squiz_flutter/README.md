# SQUIZ — Flutter app v3

Redesigned, animated Material 3 front end. App colour **#428bca** is the `primary` colour in both the light and the dark theme (`lib/core/theme.dart`, checked by `test/theme_test.dart`).

## What is new in v3
- **One login page for everyone.** Sign in with **username or phone number**. Registration has full name, username, phone and a password of **6 or more characters of any kind**. Public registration always creates a student.
- **Admin mode in the same app.** An admin who signs in chooses *Continue as admin* or *Continue as student* (the last choice is remembered, and the mode can be switched from the profile or the admin menu). A student only ever gets the student app. The server checks the role on every `/admin/*` call; hiding screens in the app is only convenience.
- **Admin screens** (`lib/ui/admin/`, same theme and #428bca brand colour as the student app, light and dark): Dashboard (all statistics, date range, Excel export), Users (search/filter, role change, suspend/activate, reset password, force change, log out everywhere, delete), Content (grade → subject → unit → question, drag to reorder, publish/hide, archive/restore, image upload), Excel import (template, check, policy skip/update/add, drafts by default, history with undo, export), Reports, Announcements, Audit log, Settings (app name, tagline, exam countdown).
- **Matric focus.** Grades 11 and 12 choose **Natural Science** or **Social Science** (onboarding and profile). Subjects carry a stream tag (`all`/`natural`/`social`) set by the admin; the app hides the other stream's subjects for grades 11–12 only. Grades 9–10 are unchanged. The stream is a convenience filter, not a security boundary. Also: exam countdown, mock Matric exam with per-subject results, and student question reports.
- Admin rules: the first admin is the *owner* (created with the CLI). An admin can promote students and can demote only admins they promoted (directly or through the chain); the owner can demote anyone; nobody can demote themselves or the owner; demoting an admin moves the admins they promoted up to the demoter's promoter.

## What changed in v2
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
Requires Flutter ≥ 3.27. For the browser: `flutter create . --platforms=android,web`. `file_picker` is used for the Excel import and for saving exports.
First admin: see `backend/README.md` (`create-admin`).

## Honest status
- **Not compiled, not run.** The Flutter SDK was not available where this was written. The only check done is a Dart syntax parse of every file in `lib/` and `test/` (0 errors). Expect to fix some compile errors on first `flutter run` / `flutter analyze`.
- The tests in `test/` were written but **not executed**. Run `flutter test`.
- Backend: 70 tests were run and pass against PostgreSQL (`pytest`).
- The admin screens in `lib/ui/admin/` have never been compiled or looked at on a screen. Code that is most likely to need a small fix on first build: record/`indexed` loops, `FilledButton.tonalIcon`, `file_picker` calls (`saveFile(bytes:)`, `pickFiles(withData: true)`), `PopScope`, layout at the 840 px breakpoint.
- Weak spot: a 6-character password is also allowed for admin accounts. Use a long password for admins (the CLI requires 10+ for the owner); two-factor sign-in and stricter admin rules are not implemented.
- No database backup/restore screen: use `pg_dump` plus the question export.
- Statistics come from the synced app-state documents (answers and history), so only signed-in students who synced are counted.
- No Aptitude subject or Social-Science-specific Mathematics was invented; add real content through the admin screens.
- Exams are graded on the phone, so the answer key is inside the downloaded/bundled bank.

## Contrast (computed with the WCAG formula)
| Pair | Ratio |
|---|---|
| White on #428bca (filled buttons) | 3.63:1 — fine for large/bold UI text, **below 4.5:1** for small text |
| #428bca on dark surface #121a23 (links/accents) | 4.82:1 |
| #2a6496 on white (links in light theme) | 6.25:1 |

Because white-on-#428bca is 3.63:1, small text on brand-coloured buttons does not meet WCAG AA. If that matters, use a darker label colour or a larger label size.
