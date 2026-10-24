import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'models.dart';

/// Backend address. Set at build/run time:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000        (Android emulator -> your PC)
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000    (real phone on the same Wi-Fi)
///   flutter build apk --release --dart-define=API_BASE_URL=https://api.example.com
/// Without a reachable server the app still works fully offline; only sign-in and sync need it.
const String kApiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000');

class ApiException implements Exception {
  ApiException(this.message, {this.code, this.status, this.offline = false});
  final String message;
  final String? code;
  final int? status;
  final bool offline;
  @override
  String toString() => message;
}

ApiException toApiException(Object e) {
  if (e is ApiException) return e;
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      return ApiException((err['message'] ?? 'Something went wrong.').toString(), code: err['code']?.toString(), status: e.response?.statusCode);
    }
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException('Cannot reach the server. Check your internet connection.', offline: true);
      default:
        return ApiException('Something went wrong. Please try again.', status: e.response?.statusCode);
    }
  }
  return ApiException('Something went wrong. Please try again.');
}

/// Tokens live in the platform keystore. A password is never stored on the phone.
class TokenStore {
  TokenStore([FlutterSecureStorage? s]) : _s = s ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;
  Future<String?> get access => _s.read(key: 'access');
  Future<String?> get refresh => _s.read(key: 'refresh');
  Future<void> save(String access, String refresh) async {
    await _s.write(key: 'access', value: access);
    await _s.write(key: 'refresh', value: refresh);
  }

  Future<void> clear() async {
    await _s.delete(key: 'access');
    await _s.delete(key: 'refresh');
  }
}

/// Dio with a bearer token and ONE automatic refresh-and-retry on 401 (concurrent 401s share one refresh).
class Api {
  Api(this.tokens, {Dio? dio, this.onSessionExpired}) : dio = dio ?? Dio(BaseOptions(baseUrl: kApiBaseUrl, connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 25))) {
    this.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
      if (o.extra['auth'] != false) {
        final t = await tokens.access;
        if (t != null) o.headers['Authorization'] = 'Bearer $t';
      }
      h.next(o);
    }, onError: (e, h) async {
      final req = e.requestOptions;
      if (e.response?.statusCode == 401 && req.extra['auth'] != false && req.extra['retried'] != true) {
        if (await _refresh()) {
          req.extra['retried'] = true;
          try {
            return h.resolve(await this.dio.fetch(req));
          } on DioException catch (e2) {
            return h.next(e2);
          }
        }
        onSessionExpired?.call();
      }
      h.next(e);
    }));
  }

  final TokenStore tokens;
  final Dio dio;
  void Function()? onSessionExpired;
  Future<bool>? _inflight;

  Future<bool> _refresh() => _inflight ??= _doRefresh().whenComplete(() => _inflight = null);

  Future<bool> _doRefresh() async {
    final rt = await tokens.refresh;
    if (rt == null) return false;
    try {
      final r = await Dio(BaseOptions(baseUrl: kApiBaseUrl, connectTimeout: const Duration(seconds: 10))).post('/auth/refresh', data: {'refresh_token': rt});
      await tokens.save(r.data['access_token'] as String, r.data['refresh_token'] as String);
      return true;
    } on DioException catch (e) {
      // Only a real rejection ends the session. Being offline must NOT sign the student out.
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) await tokens.clear();
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<T> call<T>(Future<Response<dynamic>> Function(Dio d) f, T Function(dynamic data) parse) async {
    try {
      return parse((await f(dio)).data);
    } catch (e) {
      throw toApiException(e);
    }
  }
}

final _noAuth = Options(extra: {'auth': false});

class AuthApi {
  AuthApi(this.api);
  final Api api;

  Future<AccountUser> _store(dynamic d) async {
    await api.tokens.save(d['access_token'] as String, d['refresh_token'] as String);
    return AccountUser.fromJson(d['user'] as Map<String, dynamic>);
  }

  /// The app never sends a role: the server always creates a student account.
  Future<AccountUser> register({required String fullName, required String username, required String phone, required String password, required String confirm}) =>
      api.call((d) => d.post('/auth/register', data: {'full_name': fullName, 'username': username, 'phone': phone, 'password': password, 'confirm_password': confirm}, options: _noAuth), (r) => r).then(_store);

  /// [identifier] is a username or a phone number. The same sign-in serves students and administrators; the reply carries the role.
  Future<AccountUser> login(String identifier, String password) => api.call((d) => d.post('/auth/login', data: {'identifier': identifier, 'password': password}, options: _noAuth), (r) => r).then(_store);

  Future<AccountUser?> restore() async {
    if (await api.tokens.access == null && await api.tokens.refresh == null) return null;
    return me();
  }

  Future<AccountUser> me() => api.call((d) => d.get('/me'), (r) => AccountUser.fromJson(r as Map<String, dynamic>));
  Future<AccountUser> setGrade(int grade) => api.call((d) => d.patch('/me', data: {'selected_grade': grade}), (r) => AccountUser.fromJson(r as Map<String, dynamic>));
  Future<AccountUser> setTrack(String? track) => api.call((d) => d.patch('/me', data: {'selected_track': track ?? 'all'}), (r) => AccountUser.fromJson(r as Map<String, dynamic>));
  Future<bool> usernameAvailable(String username) =>
      api.call((d) => d.get('/auth/username-available', queryParameters: {'username': username}, options: _noAuth), (r) => (r as Map)['available'] == true);
  Future<void> changePassword(String current, String next) => api.call((d) => d.post('/auth/change-password', data: {'current_password': current, 'new_password': next}), (_) {});

  Future<void> logout() async {
    final rt = await api.tokens.refresh;
    try {
      if (rt != null) await api.dio.post('/auth/logout', data: {'refresh_token': rt}, options: _noAuth);
    } catch (_) {/* signing out locally must always work, even offline */}
    await api.tokens.clear();
  }

  Future<void> deleteAccount(String password) async {
    await api.call((d) => d.delete('/me', data: {'password': password}), (_) {});
    await api.tokens.clear();
  }
}

class BankDownload {
  BankDownload(this.json, this.etag);
  final String json;
  final String? etag;
}

class SyncApi {
  SyncApi(this.api);
  final Api api;

  /// Returns null when the server copy is unchanged (HTTP 304).
  Future<BankDownload?> bank({String? etag}) async {
    try {
      final r = await api.dio.get<String>('/app/bank',
          options: Options(responseType: ResponseType.plain, headers: {if (etag != null) 'If-None-Match': etag}, validateStatus: (s) => s == 200 || s == 304, receiveTimeout: const Duration(minutes: 2)));
      if (r.statusCode == 304) return null;
      return BankDownload(r.data ?? '', r.headers.value('etag'));
    } catch (e) {
      throw toApiException(e);
    }
  }

  Future<Map<String, dynamic>> pushState(Map<String, dynamic> state) => api.call((d) => d.put('/app/state', data: {'state': state}), (r) => Map<String, dynamic>.from((r as Map)['state'] as Map));
  Future<void> resetState() => api.call((d) => d.delete('/app/state'), (_) {});
  Future<Map<String, dynamic>> pullState() => api.call((d) => d.get('/app/state'), (r) => Map<String, dynamic>.from((r as Map)['state'] as Map));
}


extension SyncExtras on SyncApi {
  Future<Map<String, dynamic>> config() => api.call((d) => d.get('/config', options: _noAuth), (r) => Map<String, dynamic>.from(r as Map));
  Future<List<Map<String, dynamic>>> announcements() => api.call((d) => d.get('/app/announcements'), (r) => [for (final x in (r as List)) Map<String, dynamic>.from(x as Map)]);
  Future<void> reportQuestion(String key, String reason, String? note) => api.call((d) => d.post('/app/reports', data: {'key': key, 'reason': reason, if (note != null && note.trim().isNotEmpty) 'note': note.trim()}), (_) {});
}

typedef Json = Map<String, dynamic>;

/// Everything the administrator screens need. Every call is checked again by the server, which reads the role from the database.
class AdminApi {
  AdminApi(this.api);
  final Api api;

  Json _m(dynamic r) => Map<String, dynamic>.from(r as Map);
  List<Json> _l(dynamic r) => [for (final x in (r as List)) Map<String, dynamic>.from(x as Map)];

  // ---- users
  Future<Json> users({String? q, String? role, String? status, int? grade, int page = 1, int size = 20}) => api.call(
      (d) => d.get('/admin/users', queryParameters: {if (q != null && q.trim().isNotEmpty) 'q': q.trim(), if (role != null) 'role': role, if (status != null) 'status': status, if (grade != null) 'grade': grade, 'page': page, 'size': size}),
      _m);
  Future<Json> user(int id) => api.call((d) => d.get('/admin/users/$id'), _m);
  Future<Json> setRole(int id, String role) => api.call((d) => d.post('/admin/users/$id/role', data: {'role': role}), _m);
  Future<Json> suspend(int id, {String? reason, int? days}) => api.call((d) => d.post('/admin/users/$id/suspend', data: {if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(), if (days != null) 'days': days}), _m);
  Future<Json> activate(int id) => api.call((d) => d.post('/admin/users/$id/activate'), _m);
  Future<String> resetPassword(int id) => api.call((d) => d.post('/admin/users/$id/reset-password'), (r) => (r as Map)['temporary_password'] as String);
  Future<Json> forcePasswordChange(int id) => api.call((d) => d.post('/admin/users/$id/force-password-change'), _m);
  Future<void> logoutEverywhere(int id) => api.call((d) => d.post('/admin/users/$id/logout-everywhere'), (_) {});
  Future<void> deleteUser(int id) => api.call((d) => d.delete('/admin/users/$id', queryParameters: {'confirm': true}), (_) {});

  // ---- statistics
  Future<Json> stats({DateTime? from, DateTime? to}) => api.call((d) => d.get('/admin/stats', queryParameters: {if (from != null) 'from': _date(from), if (to != null) 'to': _date(to)}), _m);
  Future<List<int>> exportStats({DateTime? from, DateTime? to}) => api.call(
      (d) => d.get<List<int>>('/admin/stats/export', queryParameters: {'format': 'xlsx', if (from != null) 'from': _date(from), if (to != null) 'to': _date(to)}, options: Options(responseType: ResponseType.bytes)),
      (r) => List<int>.from(r as List));
  static String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ---- content tree
  Future<List<Json>> grades({bool archived = false}) => api.call((d) => d.get('/admin/grades', queryParameters: {'include_archived': archived}), _l);
  Future<Json> createGrade(int number, String name) => api.call((d) => d.post('/admin/grades', data: {'number': number, 'name': name}), _m);
  Future<Json> patchGrade(int id, Json body) => api.call((d) => d.patch('/admin/grades/$id', data: body), _m);
  Future<Json> archiveGrade(int id) => api.call((d) => d.delete('/admin/grades/$id'), _m);
  Future<Json> restoreGrade(int id) => api.call((d) => d.post('/admin/grades/$id/restore'), _m);

  Future<List<Json>> subjects({bool archived = false}) => api.call((d) => d.get('/admin/subjects', queryParameters: {'include_archived': archived}), _l);
  Future<Json> createSubject(String key, String name, String track) => api.call((d) => d.post('/admin/subjects', data: {'key': key, 'name': name, 'track': track}), _m);
  Future<Json> patchSubject(int id, Json body) => api.call((d) => d.patch('/admin/subjects/$id', data: body), _m);
  Future<Json> archiveSubject(int id) => api.call((d) => d.delete('/admin/subjects/$id'), _m);
  Future<Json> restoreSubject(int id) => api.call((d) => d.post('/admin/subjects/$id/restore'), _m);
  Future<List<Json>> reorderSubjects(List<int> ids) => api.call((d) => d.post('/admin/subjects/reorder', data: {'subject_ids': ids}), _l);
  Future<Json> assignSubject(int gradeId, int subjectId, {bool published = true}) => api.call((d) => d.put('/admin/grades/$gradeId/subjects/$subjectId', data: {'published': published}), _m);

  Future<List<Json>> units({int? gradeId, int? subjectId, bool archived = false}) =>
      api.call((d) => d.get('/admin/units', queryParameters: {if (gradeId != null) 'grade_id': gradeId, if (subjectId != null) 'subject_id': subjectId, 'include_archived': archived}), _l);
  Future<Json> createUnit(int gradeId, int subjectId, String title, {String kind = 'unit'}) => api.call((d) => d.post('/admin/units', data: {'grade_id': gradeId, 'subject_id': subjectId, 'title': title, 'kind': kind}), _m);
  Future<Json> patchUnit(int id, Json body) => api.call((d) => d.patch('/admin/units/$id', data: body), _m);
  Future<Json> archiveUnit(int id) => api.call((d) => d.delete('/admin/units/$id'), _m);
  Future<Json> restoreUnit(int id) => api.call((d) => d.post('/admin/units/$id/restore'), _m);
  Future<List<Json>> reorderUnits(int gradeId, int subjectId, List<int> ids) => api.call((d) => d.post('/admin/units/reorder', data: {'grade_id': gradeId, 'subject_id': subjectId, 'unit_ids': ids}), _l);

  // ---- questions
  Future<Json> questions({int? unitId, String? status, String? q, int page = 1, int size = 20}) =>
      api.call((d) => d.get('/admin/questions', queryParameters: {if (unitId != null) 'unit_id': unitId, if (status != null) 'status': status, if (q != null && q.trim().isNotEmpty) 'q': q.trim(), 'page': page, 'size': size}), _m);
  Future<Json> createQuestion(Json body) => api.call((d) => d.post('/admin/questions', data: body), _m);
  Future<Json> patchQuestion(int id, Json body) => api.call((d) => d.patch('/admin/questions/$id', data: body), _m);
  Future<Json> setQuestionStatus(int id, String action) => api.call((d) => d.post('/admin/questions/$id/$action'), _m); // publish | unpublish | archive
  Future<void> deleteQuestion(int id) => api.call((d) => d.delete('/admin/questions/$id', queryParameters: {'confirm': true}), (_) {});
  Future<String> uploadImage(List<int> bytes, String filename) =>
      api.call((d) => d.post('/admin/uploads', data: FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: filename)})), (r) => (r as Map)['url'] as String);

  // ---- excel import / export
  Future<List<int>> template() => api.call((d) => d.get<List<int>>('/admin/questions/import/template', options: Options(responseType: ResponseType.bytes)), (r) => List<int>.from(r as List));
  Future<List<int>> exportQuestions(String format) =>
      api.call((d) => d.get<List<int>>('/admin/questions/export', queryParameters: {'format': format}, options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(minutes: 2))), (r) => List<int>.from(r as List));
  FormData _importForm(List<int> bytes, String name, Map<String, dynamic> fields) => FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: name), ...fields});
  Future<Json> importValidate(List<int> bytes, String name, {required bool createMissing}) =>
      api.call((d) => d.post('/admin/questions/import/validate', data: _importForm(bytes, name, {'create_missing': createMissing})), _m);
  Future<Json> importCommit(List<int> bytes, String name, {required bool createMissing, required String policy, required bool publish}) =>
      api.call((d) => d.post('/admin/questions/import/commit', data: _importForm(bytes, name, {'create_missing': createMissing, 'policy': policy, 'publish': publish})), _m);
  Future<Json> importHistory({int page = 1}) => api.call((d) => d.get('/admin/questions/import/history', queryParameters: {'page': page}), _m);
  Future<Json> importUndo(int id) => api.call((d) => d.post('/admin/questions/import/$id/undo'), _m);

  // ---- announcements, reports, audit, settings
  Future<List<Json>> announcements() => api.call((d) => d.get('/admin/announcements'), _l);
  Future<Json> createAnnouncement(String title, String body) => api.call((d) => d.post('/admin/announcements', data: {'title': title, 'body': body}), _m);
  Future<Json> patchAnnouncement(int id, Json body) => api.call((d) => d.patch('/admin/announcements/$id', data: body), _m);
  Future<void> deleteAnnouncement(int id) => api.call((d) => d.delete('/admin/announcements/$id'), (_) {});
  Future<Json> reports({String status = 'open', int page = 1}) => api.call((d) => d.get('/admin/reports', queryParameters: {'status': status, 'page': page}), _m);
  Future<Json> closeReport(int id, bool resolve) => api.call((d) => d.post('/admin/reports/$id/${resolve ? 'resolve' : 'dismiss'}'), _m);
  Future<Json> audit({String? action, int page = 1}) => api.call((d) => d.get('/admin/audit', queryParameters: {if (action != null && action.isNotEmpty) 'action': action, 'page': page, 'size': 30}), _m);
  Future<Json> settings() => api.call((d) => d.get('/admin/settings'), _m);
  Future<Json> saveSettings(Json body) => api.call((d) => d.put('/admin/settings', data: body), _m);
}
