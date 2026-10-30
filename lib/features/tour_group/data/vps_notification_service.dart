import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/utils/app_logger.dart';
import 'tour_media_uploader.dart';

/// Direct client for triggering background notifications via the Bhromon VPS
/// service (`https://bhromon.fun/api/media/notify/...`), completely bypassing
/// Firebase Cloud Functions and the Firebase Blaze plan.
class VpsNotificationService {
  static final VpsNotificationService _instance =
      VpsNotificationService._internal();
  factory VpsNotificationService() => _instance;
  VpsNotificationService._internal();

  final Dio _dio = Dio(BaseOptions(
    baseUrl: '${TourMediaUploader.baseUrl}/api/media',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  Future<String?> _getIdToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      return await user?.getIdToken();
    } catch (_) {
      return null;
    }
  }

  /// Direct trigger for an emergency SOS alert.
  Future<void> notifySos({
    required String tourId,
    required String alertId,
    required String senderName,
  }) async {
    try {
      final token = await _getIdToken();
      if (token == null) return;
      await _dio.post<dynamic>(
        '/notify/sos',
        data: {
          'tourId': tourId,
          'alertId': alertId,
          'senderName': senderName,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e, st) {
      logWarning('[VpsNotificationService] notifySos error', e, st);
    }
  }

  /// Direct trigger for emergency channel messages or mentions.
  Future<void> notifyChannelMessage({
    required String tourId,
    required String channelId,
    required String messageId,
    required String senderName,
    String text = '',
    List<String> mentions = const [],
    List<Map<String, dynamic>> attachments = const [],
    String kind = 'text',
  }) async {
    try {
      final token = await _getIdToken();
      if (token == null) return;
      await _dio.post<dynamic>(
        '/notify/channel',
        data: {
          'tourId': tourId,
          'channelId': channelId,
          'messageId': messageId,
          'senderName': senderName,
          'text': text,
          'mentions': mentions,
          'attachments': attachments,
          'kind': kind,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e, st) {
      logWarning('[VpsNotificationService] notifyChannelMessage error', e, st);
    }
  }
}
