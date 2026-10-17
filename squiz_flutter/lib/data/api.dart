import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'models.dart';

/// Backend address. Set at build/run time:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000        (Android emulator -> your PC)
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000    (real phone on the same Wi-Fi)
///   flutter build apk --release --dart-define=API_BASE_URL=https://api.example.com
/// Without a reachable server the app still works fully offline; only sign-in and sync need it.
const String kApiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'https://squiz-a6ow.onrender.com');

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
  Future<AccountUser> register({required String fullName, required String phone, required String password, required String confirm}) =>
      api.call((d) => d.post('/auth/register', data: {'full_name': fullName, 'phone': phone, 'password': password, 'confirm_password': confirm}, options: _noAuth), (r) => r).then(_store);

  /// [identifier] is a phone number or full name. The server answers `ambiguous_name` when several students share a name.
  Future<AccountUser> login(String identifier, String password) => api.call((d) => d.post('/auth/login', data: {'identifier': identifier, 'password': password}, options: _noAuth), (r) => r).then(_store);

  Future<AccountUser?> restore() async {
    if (await api.tokens.access == null && await api.tokens.refresh == null) return null;
    return me();
  }

  Future<AccountUser> me() => api.call((d) => d.get('/me'), (r) => AccountUser.fromJson(r as Map<String, dynamic>));
  Future<AccountUser> setGrade(int grade) => api.call((d) => d.patch('/me', data: {'selected_grade': grade}), (r) => AccountUser.fromJson(r as Map<String, dynamic>));
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