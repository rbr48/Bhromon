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

  /// Direct trigger for a new Moments post (photo or reel).
  Future<void> notifyPost({
    required String tourId,
    required String postId,
    required String authorName,
    String caption = '',
    bool isReel = false,
    String? imageUrl,
  }) async {
    try {
      final token = await _getIdToken();
      if (token == null) return;
      await _dio.post<dynamic>(
        '/notify/post',
        data: {
          'tourId': tourId,
          'postId': postId,
          'authorName': authorName,
          'caption': caption,
          'isReel': isReel,
          'imageUrl': imageUrl,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e, st) {
      logWarning('[VpsNotificationService] notifyPost error', e, st);
    }
  }

  /// Direct trigger for a comment on a Moments post.
  Future<void> notifyComment({
    required String tourId,
    required String postId,
    required String commentId,
    required String commenterName,
    required String text,
    String? postAuthorEmail,
  }) async {
    try {
      final token = await _getIdToken();
      if (token == null) return;
      await _dio.post<dynamic>(
        '/notify/comment',
        data: {
          'tourId': tourId,
          'postId': postId,
          'commentId': commentId,
          'commenterName': commenterName,
          'text': text,
          'postAuthorEmail': postAuthorEmail,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e, st) {
      logWarning('[VpsNotificationService] notifyComment error', e, st);
    }
  }

  /// Direct trigger for a reaction / like on a Moments post.
  Future<void> notifyReaction({
    required String tourId,
    required String postId,
    required String reactorName,
    String reaction = 'like',
    String? postAuthorEmail,
  }) async {
    try {
      final token = await _getIdToken();
      if (token == null) return;
      await _dio.post<dynamic>(
        '/notify/reaction',
        data: {
          'tourId': tourId,
          'postId': postId,
          'reactorName': reactorName,
          'reaction': reaction,
          'postAuthorEmail': postAuthorEmail,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e, st) {
      logWarning('[VpsNotificationService] notifyReaction error', e, st);
    }
  }

  /// Direct trigger for a group notice.
  Future<void> notifyNotice({
    required String tourId,
    required String noticeId,
    required String title,
    String body = '',
    String priority = 'normal',
  }) async {
    try {
      final token = await _getIdToken();
      if (token == null) return;
      await _dio.post<dynamic>(
        '/notify/notice',
        data: {
          'tourId': tourId,
          'noticeId': noticeId,
          'title': title,
          'body': body,
          'priority': priority,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e, st) {
      logWarning('[VpsNotificationService] notifyNotice error', e, st);
    }
  }

  /// Direct trigger for an expense recorded in Trip Ledger.
  Future<void> notifyLedger({
    required String tourId,
    required String expenseId,
    required String payerName,
    required String title,
    required int amountPaisa,
  }) async {
    try {
      final token = await _getIdToken();
      if (token == null) return;
      await _dio.post<dynamic>(
        '/notify/ledger',
        data: {
          'tourId': tourId,
          'expenseId': expenseId,
          'payerName': payerName,
          'title': title,
          'amountPaisa': amountPaisa,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e, st) {
      logWarning('[VpsNotificationService] notifyLedger error', e, st);
    }
  }
}
