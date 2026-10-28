import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_error.dart';

/// Token storage backed by the platform keystore / keychain.
class TokenStore {
  TokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';

  Future<String?> readAccess() => _storage.read(key: _accessKey);
  Future<String?> readRefresh() => _storage.read(key: _refreshKey);

  Future<void> save({required String access, required String refresh}) async {
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}

/// Dio client with auth, single-flight refresh, and retry.
class ApiClient {
  ApiClient({required this.baseUrl, TokenStore? tokens, Dio? dio})
      : _tokens = tokens ?? TokenStore() {
    _dio = dio ?? Dio();
    _dio.options
      ..baseUrl = baseUrl
      ..connectTimeout = const Duration(seconds: 45)
      ..receiveTimeout = const Duration(seconds: 90)
      ..sendTimeout = const Duration(seconds: 90)
      ..headers['Accept'] = 'application/json';

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (!_isPublic(options.path)) {
            final token = await _tokens.readAccess();
            if (token != null) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401 &&
              !_isPublic(error.requestOptions.path) &&
              error.requestOptions.extra['retried'] != true) {
            final refreshed = await _refresh();
            if (refreshed) {
              final request = error.requestOptions
                ..extra['retried'] = true
                ..headers['Authorization'] =
                    'Bearer ${await _tokens.readAccess()}';
              try {
                final response = await _dio.fetch(request);
                return handler.resolve(response);
              } on DioException catch (e) {
                return handler.next(e);
              }
            }
            await onSessionExpired?.call();
          }
          handler.next(error);
        },
      ),
    );
  }

  final String baseUrl;
  final TokenStore _tokens;
  late final Dio _dio;

  /// Called when refresh fails; the app should log out.
  Future<void> Function()? onSessionExpired;

  /// Set by the auth feature so refresh uses the same client.
  Future<Map<String, dynamic>?> Function(String refreshToken)? refreshHandler;

  Future<bool>? _inFlight;

  Future<bool> _refresh() {
    // Single-flight: parallel 401s share one refresh.
    return _inFlight ??= _doRefresh().whenComplete(() => _inFlight = null);
  }

  Future<bool> _doRefresh() async {
    final refresh = await _tokens.readRefresh();
    if (refresh == null) return false;
    try {
      final Map<String, dynamic>? data;
      if (refreshHandler != null) {
        data = await refreshHandler!(refresh);
      } else {
        final res = await _dio.post<Map<String, dynamic>>(
          '/auth/refresh',
          data: {'refresh_token': refresh},
          options: Options(extra: {'retried': true}),
        );
        data = res.data;
      }
      final access = data?['access_token'] as String?;
      final newRefresh = data?['refresh_token'] as String?;
      if (access == null) return false;
      await _tokens.save(access: access, refresh: newRefresh ?? refresh);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _isPublic(String path) =>
      path.contains('/auth/login') ||
      path.contains('/auth/register') ||
      path.contains('/auth/forgot-password') ||
      path.contains('/auth/reset-password');

  Dio get dio => _dio;

  /// Maps any Dio failure into a single [ApiError].
  static ApiError toApiError(Object error) {
    if (error is ApiError) return error;
    if (error is DioException) {
      final status = error.response?.statusCode;
      final data = error.response?.data;
      String? code;
      String? message;
      if (data is Map) {
        code = data['code'] as String? ?? data['error'] as String?;
        message = data['message'] as String?;
      }
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
          return const ApiError(
            code: 'timeout',
            message: 'The connection is slow. Please try again.',
            retryable: true,
          );
        case DioExceptionType.connectionError:
          return const ApiError.network();
        case DioExceptionType.cancel:
          return const ApiError(code: 'cancelled', message: 'Cancelled.');
        default:
          break;
      }
      if (status == 401) return const ApiError.unauthorized();
      return ApiError(
        code: code ?? 'http_$status',
        message: message ?? _defaultMessage(status),
        httpStatus: status,
        retryable: status == null || status >= 500 || status == 429,
      );
    }
    return const ApiError.unknown();
  }

  static String _defaultMessage(int? status) {
    if (status == null) return 'We could not reach the server.';
    if (status >= 500) return 'The server had a problem. Please try again.';
    if (status == 403) return 'You do not have access to this.';
    if (status == 404) return 'We could not find that.';
    if (status == 413) return 'That file is too large.';
    if (status == 429) return 'Too many requests. Please wait a moment.';
    return 'Something went wrong. Please try again.';
  }
}
