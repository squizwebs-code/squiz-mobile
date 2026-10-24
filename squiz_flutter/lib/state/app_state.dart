import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/api.dart';
import '../data/bank.dart';
import '../data/models.dart';

enum SyncStatus { idle, syncing, ok, error }

/// An administrator account can use the app as a student or as an administrator.
enum AppMode { student, admin }

/// Pure merge helpers (same rules as the server) so they can be unit-tested without Flutter.
class Merge {
  /// Per-key last-write-wins. Ties keep [a] (the local value).
  static Map<String, Entry> entries(Map<String, Entry> a, Map<String, Entry> b) {
    final out = Map<String, Entry>.of(a);
    b.forEach((k, v) {
      final cur = out[k];
      if (cur == null || v.ts > cur.ts) out[k] = v;
    });
    return out;
  }

  static List<HistoryItem> history(List<HistoryItem> a, List<HistoryItem> b, {int cap = 200}) {
    final byId = {for (final h in a) h.id: h};
    for (final h in b) {
      byId.putIfAbsent(h.id, () => h);
    }
    final all = byId.values.toList()..sort((x, y) => y.ts.compareTo(x.ts));
    return all.length > cap ? all.sublist(0, cap) : all;
  }
}

/// A quiz that was started and not finished. Saved after every change so it survives the app being closed.
class SavedSession {
  SavedSession({required this.mode, required this.title, required this.keys, required this.choices, required this.marked, required this.index, required this.startedMs, this.endsMs, this.limitSeconds});
  final String mode, title;
  final List<String> keys;
  final Map<int, int> choices;
  final Set<int> marked;
  final int index, startedMs;
  final int? endsMs, limitSeconds;

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'title': title,
        'keys': keys,
        'choices': choices.map((k, v) => MapEntry('$k', v)),
        'marked': marked.toList(),
        'index': index,
        'started': startedMs,
        if (endsMs != null) 'ends': endsMs,
        if (limitSeconds != null) 'limit': limitSeconds,
      };

  static SavedSession? fromJson(dynamic j) {
    if (j is! Map) return null;
    try {
      return SavedSession(
        mode: j['mode'] as String,
        title: j['title'] as String,
        keys: [for (final k in (j['keys'] as List)) k as String],
        choices: {for (final e in (j['choices'] as Map).entries) int.parse(e.key as String): (e.value as num).toInt()},
        marked: {for (final m in (j['marked'] as List)) (m as num).toInt()},
        index: (j['index'] as num).toInt(),
        startedMs: (j['started'] as num).toInt(),
        endsMs: (j['ends'] as num?)?.toInt(),
        limitSeconds: (j['limit'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}

class SubjectStat {
  const SubjectStat(this.subject, this.total, this.answered, this.correct);
  final Subject subject;
  final int total, answered, correct;
  double get progress => total == 0 ? 0 : answered / total;
  int? get accuracy => answered == 0 ? null : (correct * 100 / answered).round();
}

class AppState extends ChangeNotifier {
  AppState({required this.prefs, required this.bankRepo, required this.auth, required this.syncApi, this.admin, int Function()? nowMs}) : nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final SharedPreferences prefs;
  final BankRepository bankRepo;
  final AuthApi auth;
  final SyncApi syncApi;
  final AdminApi? admin;
  final int Function() nowMs;

  static const _kState = 'squiz.v2.state';
  static const _kSession = 'squiz.v2.session';
  static const _kGrade = 'squiz.v2.grade';
  static const _kTheme = 'squiz.v2.theme';
  static const _kTrack = 'squiz.v2.track';
  static const _kMode = 'squiz.v2.mode';
  static const _kConfig = 'squiz.v2.config';

  // ---- content
  QuestionBank? bank;
  bool loading = true;
  String? loadError;

  // ---- preferences
  int? _grade;
  ThemeMode themeMode = ThemeMode.system;

  // ---- learning state (synced)
  Map<String, Entry> bookmarks = {};
  Map<String, Entry> flags = {};
  Map<String, Entry> answers = {};
  List<HistoryItem> history = [];
  // ---- local only
  Map<String, int> days = {};
  SavedSession? resumable;

  // ---- account / sync
  AccountUser? user;
  SyncStatus syncStatus = SyncStatus.idle;
  String? syncError;
  int? lastSyncedMs;
  bool _dirty = false;
  bool _syncing = false;
  int _version = 0;
  Timer? _saveTimer, _syncTimer;

  // ---- Matric stream (grades 11 and 12) and administrator mode
  String? _track; // 'natural' | 'social' | null = everything
  String? get track => _track;
  String? get effectiveTrack => grade >= 11 ? _track : null;
  AppMode? mode;
  AppMode? _lastMode;
  bool get isAdmin => user?.isAdmin ?? false;
  bool get adminMode => isAdmin && mode == AppMode.admin;
  bool get needsModeChoice => isAdmin && mode == null;

  // ---- public configuration and announcements
  Map<String, dynamic> remoteConfig = {};
  List<Map<String, dynamic>> announcements = [];
  DateTime? get examDate => DateTime.tryParse((remoteConfig['exam_date'] ?? '').toString());
  String get examName => (remoteConfig['exam_name'] ?? 'Matric exam').toString();

  @override
  void notifyListeners() {
    bank?.activeTrack = effectiveTrack; // every screen reads the bank through the student's stream
    super.notifyListeners();
  }

  int get grade => _grade ?? 11;
  bool get needsOnboarding => _grade == null;
  bool get signedIn => user != null;

  // ------------------------------------------------------------------ start-up
  Future<void> init() async {
    _loadLocal();
    notifyListeners();
    try {
      bank = await bankRepo.load();
    } catch (e) {
      loadError = 'The question bank could not be loaded.';
    }
    loading = false;
    notifyListeners();
    // Restore the account in the background; being offline keeps the student working with local data.
    unawaited(_restoreAccount());
    unawaited(loadConfig());
  }

  void _loadLocal() {
    _grade = prefs.getInt(_kGrade);
    _track = prefs.getString(_kTrack);
    _lastMode = prefs.getString(_kMode) == 'admin' ? AppMode.admin : (prefs.getString(_kMode) == 'student' ? AppMode.student : null);
    try {
      final c = prefs.getString(_kConfig);
      if (c != null) remoteConfig = Map<String, dynamic>.from(jsonDecode(c) as Map);
    } catch (_) {}
    themeMode = switch (prefs.getString(_kTheme)) { 'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system };
    final raw = prefs.getString(_kState);
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        bookmarks = _entries(j['b']);
        flags = _entries(j['f']);
        answers = _entries(j['a']);
        history = [for (final h in (j['h'] as List? ?? const [])) if (HistoryItem.fromJson(h) != null) HistoryItem.fromJson(h)!];
        days = {for (final e in ((j['days'] as Map?) ?? const {}).entries) e.key as String: (e.value as num).toInt()};
        lastSyncedMs = (j['sync'] as num?)?.toInt();
        _dirty = j['dirty'] == true;
      } catch (_) {/* corrupted local state: start clean rather than crash */}
    }
    final s = prefs.getString(_kSession);
    if (s != null) {
      try {
        resumable = SavedSession.fromJson(jsonDecode(s));
      } catch (_) {
        resumable = null;
      }
    }
  }

  static Map<String, Entry> _entries(dynamic m) {
    final out = <String, Entry>{};
    if (m is Map) {
      m.forEach((k, v) {
        final e = Entry.fromJson(v);
        if (e != null) out['$k'] = e;
      });
    }
    return out;
  }

  Map<String, dynamic> exportState() => {
        'b': bookmarks.map((k, v) => MapEntry(k, v.toJson())),
        'f': flags.map((k, v) => MapEntry(k, v.toJson())),
        'a': answers.map((k, v) => MapEntry(k, v.toJson())),
        'h': [for (final h in history) h.toJson()],
      };

  void _persist() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), flushNow);
  }

  Future<void> flushNow() async {
    _saveTimer?.cancel();
    final j = {...exportState(), 'days': days, if (lastSyncedMs != null) 'sync': lastSyncedMs, 'dirty': _dirty};
    await prefs.setString(_kState, jsonEncode(j));
  }

  void _changed() {
    _version++;
    _dirty = true;
    _persist();
    notifyListeners();
    _scheduleSync();
  }

  // ------------------------------------------------------------------ preferences
  Future<void> setGrade(int g) async {
    _grade = g;
    await prefs.setInt(_kGrade, g);
    notifyListeners();
    if (signedIn) {
      try {
        await auth.setGrade(g);
      } catch (_) {/* the grade is also kept on the phone; the account copy is best-effort */}
    }
  }

  Future<void> setTrack(String? t) async {
    _track = t;
    if (t == null) {
      await prefs.remove(_kTrack);
    } else {
      await prefs.setString(_kTrack, t);
    }
    notifyListeners();
    if (signedIn) {
      try {
        await auth.setTrack(t);
      } catch (_) {/* kept on the phone either way */}
    }
  }

  Future<void> chooseMode(AppMode m) async {
    mode = m;
    _lastMode = m;
    await prefs.setString(_kMode, m.name);
    notifyListeners();
  }

  /// Exam date, exam name and similar settings an administrator controls. Cached so the countdown also works offline.
  Future<void> loadConfig() async {
    try {
      remoteConfig = await syncApi.config();
      await prefs.setString(_kConfig, jsonEncode(remoteConfig));
      notifyListeners();
    } catch (_) {/* offline: keep the cached copy */}
  }

  Future<void> loadAnnouncements() async {
    if (!signedIn) return;
    try {
      announcements = await syncApi.announcements();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    await prefs.setString(_kTheme, m.name);
    notifyListeners();
  }

  // ------------------------------------------------------------------ learning state
  bool isBookmarked(String key) => bookmarks[key]?.on ?? false;
  bool isFlagged(String key) => flags[key]?.on ?? false;

  void toggleBookmark(Question q) {
    bookmarks = {...bookmarks, q.key: Entry(nowMs(), !isBookmarked(q.key))};
    _changed();
  }

  void toggleFlag(Question q) {
    flags = {...flags, q.key: Entry(nowMs(), !isFlagged(q.key))};
    _changed();
  }

  void recordAnswer(Question q, bool correct) {
    final t = nowMs();
    answers = {...answers, q.key: Entry(t, correct)};
    final d = dayKey(DateTime.fromMillisecondsSinceEpoch(t));
    days = {...days, d: (days[d] ?? 0) + 1};
    _changed();
  }

  void addHistory(HistoryItem h) {
    history = Merge.history([h], history);
    _changed();
  }

  static String dayKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String newId() => '${nowMs().toRadixString(36)}${Random().nextInt(1 << 30).toRadixString(36)}';

  // ---- derived
  int get answeredCount => answers.length;
  int get correctCount => answers.values.where((e) => e.on).length;
  int? get accuracy => answers.isEmpty ? null : (correctCount * 100 / answers.length).round();

  List<Question> _lookup(Iterable<String> keys) {
    final b = bank;
    if (b == null) return const [];
    return [for (final k in keys) if (b.byKey[k] != null) b.byKey[k]!];
  }

  List<Question> bookmarked() => _lookup([for (final e in bookmarks.entries) if (e.value.on) e.key]);
  List<Question> flagged() => _lookup([for (final e in flags.entries) if (e.value.on) e.key]);

  /// Questions whose most recent answer was wrong, for the current grade.
  List<Question> mistakes() {
    final b = bank;
    if (b == null) return const [];
    final inGrade = {for (final q in b.questionsFor(grade)) q.key};
    final wrong = [for (final e in answers.entries) if (!e.value.on && inGrade.contains(e.key)) e.key];
    wrong.sort((x, y) => answers[y]!.ts.compareTo(answers[x]!.ts));
    return _lookup(wrong);
  }

  List<SubjectStat> subjectStats() {
    final b = bank;
    if (b == null) return const [];
    final out = <SubjectStat>[];
    for (final s in b.subjectsFor(grade)) {
      final qs = b.questionsFor(grade, subject: s.id);
      var answered = 0, correct = 0;
      for (final q in qs) {
        final a = answers[q.key];
        if (a != null) {
          answered++;
          if (a.on) correct++;
        }
      }
      out.add(SubjectStat(s, qs.length, answered, correct));
    }
    return out;
  }

  /// The subject with the lowest accuracy once there is enough data to say anything (at least 5 answers).
  SubjectStat? weakestSubject() {
    final cands = subjectStats().where((s) => s.answered >= 5 && s.accuracy != null).toList();
    if (cands.isEmpty) return null;
    cands.sort((a, b) => a.accuracy!.compareTo(b.accuracy!));
    return cands.first.accuracy! < 80 ? cands.first : null;
  }

  int get streak {
    var d = DateTime.fromMillisecondsSinceEpoch(nowMs());
    if ((days[dayKey(d)] ?? 0) == 0) d = d.subtract(const Duration(days: 1)); // today not started yet: the streak is still alive
    var n = 0;
    while ((days[dayKey(d)] ?? 0) > 0) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  List<MapEntry<DateTime, int>> last7() {
    final today = DateTime.fromMillisecondsSinceEpoch(nowMs());
    return [
      for (var i = 6; i >= 0; i--)
        () {
          final d = DateTime(today.year, today.month, today.day).subtract(Duration(days: i));
          return MapEntry(d, days[dayKey(d)] ?? 0);
        }()
    ];
  }

  // ------------------------------------------------------------------ resumable session
  Future<void> saveSession(SavedSession? s) async {
    resumable = s;
    if (s == null) {
      await prefs.remove(_kSession);
    } else {
      await prefs.setString(_kSession, jsonEncode(s.toJson()));
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------ account
  Future<void> _restoreAccount() async {
    try {
      user = await auth.restore();
      _enterAccount();
      notifyListeners();
      if (user != null) unawaited(syncNow());
    } on ApiException catch (e) {
      if (!e.offline && (e.status == 401 || e.status == 403)) {
        user = null;
        notifyListeners();
      }
      // offline: keep working; account state is re-checked on the next sync
    }
  }

  /// Decides where a signed-in account starts. Students always use the student app; an administrator chooses.
  void _enterAccount({bool fresh = false}) {
    final u = user;
    if (u == null) {
      mode = null;
      return;
    }
    if (!u.isAdmin) {
      mode = AppMode.student;
    } else {
      mode = fresh ? null : _lastMode;
    }
    if (_grade == null && u.grade != null) {
      _grade = u.grade; // signing in on a new phone: start at the grade saved on the account
      unawaited(prefs.setInt(_kGrade, u.grade!));
    }
    if (_track == null && u.track != null) {
      _track = u.track;
      unawaited(prefs.setString(_kTrack, u.track!));
    }
  }

  Future<void> signIn(String identifier, String password) async {
    user = await auth.login(identifier, password);
    _enterAccount(fresh: true);
    notifyListeners();
    unawaited(syncNow());
  }

  Future<void> register(String name, String username, String phone, String password, String confirm) async {
    user = await auth.register(fullName: name, username: username, phone: phone, password: password, confirm: confirm);
    _enterAccount(fresh: true);
    notifyListeners();
    unawaited(syncNow());
  }

  /// Changing the password signs every device out on the server, so this device signs straight back in with the new one.
  Future<void> changePassword(String current, String next) async {
    final phone = user!.phone;
    await auth.changePassword(current, next);
    user = await auth.login(phone, next);
    _enterAccount();
    notifyListeners();
    unawaited(syncNow());
  }

  /// The refresh token was rejected by the server: the account is signed out, learning data stays on the phone.
  void sessionExpired() {
    if (user == null) return;
    user = null;
    mode = null;
    syncStatus = SyncStatus.idle;
    notifyListeners();
  }

  Future<void> signOut() async {
    await auth.logout();
    await _wipeLearningState();
    user = null;
    mode = null;
    announcements = [];
    syncStatus = SyncStatus.idle;
    notifyListeners();
  }

  Future<void> deleteAccount(String password) async {
    await auth.deleteAccount(password);
    await _wipeLearningState();
    user = null;
    mode = null;
    syncStatus = SyncStatus.idle;
    notifyListeners();
  }

  /// Signing out removes the previous student's progress from the phone so the next person does not inherit or sync it.
  Future<void> _wipeLearningState() async {
    _syncTimer?.cancel();
    bookmarks = {};
    flags = {};
    answers = {};
    history = [];
    days = {};
    lastSyncedMs = null;
    _dirty = false;
    await saveSession(null);
    await bankRepo.deleteServerBank();
    bank = await bankRepo.load();
    await flushNow();
  }

  /// "Reset progress" on this phone. When signed in the account copy is reset too.
  Future<void> resetProgress() async {
    if (signedIn) await syncApi.resetState();
    answers = {};
    history = [];
    days = {};
    await saveSession(null);
    _version++;
    _dirty = false;
    await flushNow();
    notifyListeners();
  }

  // ------------------------------------------------------------------ sync
  void _scheduleSync() {
    if (!signedIn) return;
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 4), () => unawaited(syncNow()));
  }

  Future<void> syncNow() async {
    if (!signedIn || _syncing) return;
    _syncing = true;
    syncStatus = SyncStatus.syncing;
    syncError = null;
    notifyListeners();
    final startedVersion = _version;
    try {
      // role or suspension changed by an administrator since the last sync? (a rejected token ends the session below)
      final fresh = await auth.me();
      user = fresh;
      if (!fresh.isAdmin) mode = AppMode.student;
      final remote = await syncApi.pushState(exportState());
      bookmarks = Merge.entries(bookmarks, _entries(remote['b']));
      flags = Merge.entries(flags, _entries(remote['f']));
      answers = Merge.entries(answers, _entries(remote['a']));
      history = Merge.history(history, [for (final h in (remote['h'] as List? ?? const [])) if (HistoryItem.fromJson(h) != null) HistoryItem.fromJson(h)!]);
      lastSyncedMs = nowMs();
      if (_version == startedVersion) _dirty = false; // something changed while we were syncing -> stay dirty and go again
      syncStatus = SyncStatus.ok;
      unawaited(flushNow());
    } on ApiException catch (e) {
      syncStatus = SyncStatus.error;
      syncError = e.offline ? 'Offline. Your progress is saved on this phone and will sync later.' : e.message;
      if (e.status == 401 || e.status == 403 && e.code == 'account_inactive') {
        user = null;
        mode = null;
      }
    } finally {
      _syncing = false;
      notifyListeners();
    }
    if (syncStatus == SyncStatus.ok) {
      unawaited(loadAnnouncements());
      await refreshBank();
      if (_dirty) _scheduleSync();
    }
  }

  /// Downloads the server's question bank when it changed (ETag). Failures are silent: the current bank keeps working.
  Future<void> refreshBank() async {
    if (!signedIn) return;
    try {
      final dl = await syncApi.bank(etag: await bankRepo.savedEtag());
      if (dl == null || dl.json.isEmpty) return;
      final parsed = QuestionBank.fromJson(jsonDecode(dl.json) as Map<String, dynamic>, BankSource.server);
      if (parsed.questionCount == 0) return; // an empty server bank must never replace the bundled one
      await bankRepo.saveServerBank(dl.json, dl.etag);
      bank = parsed;
      notifyListeners();
    } catch (_) {/* keep using the current bank */}
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }
}
