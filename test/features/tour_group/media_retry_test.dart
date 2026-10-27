import 'package:bhromon/features/tour_group/data/tour_media_uploader.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _failure(DioExceptionType type, {int? status}) {
  final options = RequestOptions(path: '/upload');
  return DioException(
    requestOptions: options,
    type: type,
    response: status == null
        ? null
        : Response<void>(requestOptions: options, statusCode: status),
  );
}

void main() {
  group('isRetryableUploadError', () {
    test('retries dropped connections and timeouts', () {
      for (final type in [
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        expect(isRetryableUploadError(_failure(type)), isTrue, reason: '$type');
      }
    });

    test('retries a briefly unavailable gateway', () {
      for (final code in [502, 503, 504]) {
        expect(
          isRetryableUploadError(
              _failure(DioExceptionType.badResponse, status: code)),
          isTrue,
          reason: '$code',
        );
      }
    });

    test('does not retry a refused upload or a cancellation', () {
      expect(
        isRetryableUploadError(
            _failure(DioExceptionType.badResponse, status: 413)),
        isFalse,
      );
      expect(
        isRetryableUploadError(
            _failure(DioExceptionType.badResponse, status: 409)),
        isFalse,
      );
      expect(
          isRetryableUploadError(_failure(DioExceptionType.cancel)), isFalse);
    });

    test('allows three attempts in total', () {
      expect(kUploadAttempts, 3);
    });
  });
}
