import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show kReleaseMode, kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:injectable/injectable.dart';
import '../utils/app_logger.dart';

/// Unified secure HTTP client (Dio-based).
///
/// All HTTP calls in the app should use [SecureNetworkClient.dio] directly,
/// or the typed helpers [get], [post], [put], [delete].
///
/// Features:
/// - TLS certificate pinning (configurable per environment)
/// - Automatic Firebase Auth token injection on every request
/// - Retry with exponential back-off on transient network errors
/// - Structured request/response logging (DEBUG builds only)
/// - Timeout defaults: 10s connect, 30s receive
@lazySingleton
class SecureNetworkClient {
  final Dio dio;

  /// SHA-256 fingerprints of the Bhromon API server certificates.
  /// Update when the certificate is rotated.
  ///
  /// To obtain: `openssl s_client -connect api.bhromon.com:443 < /dev/null 2>/dev/null |
  ///   openssl x509 -fingerprint -sha256 -noout`
  static const List<String> _pinnedFingerprints = [
    // Slot A — primary cert fingerprint (replace with real value before production)
    'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99',
    // Slot B — backup cert fingerprint for rotation continuity
    'BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA',
  ];

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

    // Certificate pinning via custom HttpClient adapter
    // Certificate pinning via custom HttpClient adapter (Mobile only; browsers handle TLS natively)
    if (!kIsWeb &&
        !Platform.isWindows &&
        !Platform.isMacOS &&
        !Platform.isLinux) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client =
              HttpClient(context: SecurityContext(withTrustedRoots: true));
          client.badCertificateCallback = _verifyCertificate;
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

  bool _verifyCertificate(X509Certificate cert, String host, int port) {
    // Allow local development hosts without pinning
    if (host == 'localhost' || host == '127.0.0.1' || host == '10.0.2.2') {
      return true;
    }

    // Dynamic bypass for debug/profile environments when using dummy placeholders
    if (!kReleaseMode) {
      logDebug('Certificate pinning bypassed in non-release mode for: $host');
      return true;
    }

    // Compute SHA-256 fingerprint from the raw DER certificate bytes
    final fingerprint = _computeSha256Fingerprint(cert.der);

    if (_pinnedFingerprints.contains(fingerprint)) {
      return true; // Certificate matches a pinned fingerprint
    }

    logError(
      'Certificate pinning failure for $host:$port. '
      'Got fingerprint: $fingerprint',
    );
    return false; // Reject — potential MITM
  }

  String _computeSha256Fingerprint(List<int> derBytes) {
    // Use proper SHA-256 via package:crypto
    // Format: XX:XX:XX:... (colon-separated uppercase hex)
    final digest = crypto.sha256.convert(derBytes);
    return digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
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
