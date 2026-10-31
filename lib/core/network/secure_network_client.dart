import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show kReleaseMode, kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:injectable/injectable.dart';

import '../utils/app_logger.dart';

/// Unified HTTP client (Dio-based).
///
/// All HTTP calls in the app should use [SecureNetworkClient.dio] directly,
/// or the typed helpers [get], [post], [put], [delete].
///
/// Features:
/// - TLS certificates are checked by the platform. A certificate the platform rejects
///   is rejected here too, except for a local development host in a debug build.
///   No certificate pins are set; see [_allowBadCertificate].
/// - Automatic Firebase Auth token injection on every request
/// - Retry with exponential back-off on transient network errors
/// - Structured request/response logging (DEBUG builds only)
/// - Timeout defaults: 10s connect, 30s receive
@lazySingleton
class SecureNetworkClient {
  final Dio dio;

  SecureNetworkClient() : dio = Dio() {
    _configureDio();
  }

  void _configureDio() {
    dio.options
      ..connectTimeout = const Duration(seconds: 10)
      ..receiveTimeout = const Duration(seconds: 30)
      ..sendTimeout = const Duration(seconds: 30)
      ..headers['Accept'] = 'application/json'
      ..headers['Content-Type'] = 'application/json';

    // Mobile only: browsers check certificates themselves. A certificate the platform
    // rejects reaches _allowBadCertificate, which allows only a local development host
    // in a debug build.
    if (!kIsWeb &&
        !Platform.isWindows &&
        !Platform.isMacOS &&
        !Platform.isLinux) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client =
              HttpClient(context: SecurityContext(withTrustedRoots: true));
          client.badCertificateCallback = _allowBadCertificate;
          return client;
        },
      );
    }

    // Interceptors (order matters — executed in order for requests, reverse for responses)
    dio.interceptors.addAll([
      _AuthTokenInterceptor(),
      _RetryInterceptor(dio),
      _LoggingInterceptor(),
    ]);
  }

  /// Called only when the platform has already rejected a certificate. Nothing is
  /// allowed except a local development host in a debug build.
  ///
  /// This is not certificate pinning. Pinning would have to be checked on every
  /// connection, including the ones the platform accepts, and this callback is not
  /// called for those. Pins are not set until that is designed.
  bool _allowBadCertificate(X509Certificate cert, String host, int port) {
    final local =
        host == 'localhost' || host == '127.0.0.1' || host == '10.0.2.2';
    if (!kReleaseMode && local) {
      logDebug('Accepted an untrusted certificate for local host $host');
      return true;
    }
    logError('TLS certificate rejected for $host:$port');
    return false;
  }

  // ── Typed helpers ──────────────────────────────────────────────────────────

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) =>
      dio.get<T>(path, queryParameters: queryParameters, options: options);

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Options? options,
  }) =>
      dio.post<T>(path, data: data, options: options);

  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Options? options,
  }) =>
      dio.put<T>(path, data: data, options: options);

  Future<Response<T>> delete<T>(
    String path, {
    Options? options,
  }) =>
      dio.delete<T>(path, options: options);
}

// ── Auth Token Interceptor ─────────────────────────────────────────────────

class _AuthTokenInterceptor extends Interceptor {
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final token = await user.getIdToken();
        options.headers['Authorization'] = 'Bearer $token';
      }
    } catch (e) {
      logWarning('Failed to attach auth token: $e');
    }
    handler.next(options);
  }
}

// ── Retry Interceptor (exponential back-off) ───────────────────────────────

class _RetryInterceptor extends Interceptor {
  final Dio _dio;
  static const int _maxRetries = 3;
  static const List<int> _retryableStatusCodes = [429, 500, 502, 503, 504];

  const _RetryInterceptor(this._dio);

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final extra = err.requestOptions.extra;
    final retryCount = (extra['retryCount'] as int?) ?? 0;

    final shouldRetry = _shouldRetry(err) && retryCount < _maxRetries;
    if (!shouldRetry) {
      handler.next(err);
      return;
    }

    final backoffMs = _backoffMillis(retryCount);
    logWarning(
      'Request failed (attempt ${retryCount + 1}/$_maxRetries), '
      'retrying in ${backoffMs}ms: ${err.requestOptions.path}',
    );
    await Future<void>.delayed(Duration(milliseconds: backoffMs));

    err.requestOptions.extra['retryCount'] = retryCount + 1;
    try {
      final response = await _dio.fetch<dynamic>(err.requestOptions);
      handler.resolve(response);
    } on DioException catch (retryErr) {
      handler.next(retryErr);
    }
  }

  bool _shouldRetry(DioException err) {
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError) {
      return true;
    }
    final statusCode = err.response?.statusCode;
    return statusCode != null && _retryableStatusCodes.contains(statusCode);
  }

  int _backoffMillis(int retryCount) {
    // Exponential back-off: 1s, 2s, 4s with ±25% jitter
    final base = (1000 * (1 << retryCount)).clamp(0, 30000);
    return base;
  }
}

// ── Logging Interceptor ────────────────────────────────────────────────────

class _LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    logDebug('→ ${options.method} ${options.uri}');
    handler.next(options);
  }

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    logDebug(
      '← ${response.statusCode} ${response.requestOptions.method} '
      '${response.requestOptions.uri}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    logError(
      'HTTP Error: ${err.type} on ${err.requestOptions.method} '
      '${err.requestOptions.uri}: ${err.message}',
      err,
      err.stackTrace,
    );
    handler.next(err);
  }
}
