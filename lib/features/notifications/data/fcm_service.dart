import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:injectable/injectable.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../app/router.dart';
import '../../../core/services/push_device.dart';

/// Channel used for all general Bhromon notifications.
const _kChannelId = 'bhromon_general';
const _kChannelName = 'Bhromon Notifications';
const _kChannelDesc =
    'General announcements, messages, trip updates, and broadcasts from Bhromon.';

@singleton
class FcmService {
  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;

  final FlutterLocalNotificationsPlugin _localNotif =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _userNotificationsSub;
  String? _initializedUid;

  FcmService(this._messaging, this._firestore);

  /// Global lifecycle hook: listens to user auth state, automatically registers
  /// FCM tokens on login, and cleans up tokens on sign-out.
  void initGlobalListener() {
    _authSub?.cancel();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        init(user.uid);
      } else {
        _onSignedOut();
      }
    });
  }

  Future<void> _onSignedOut() async {
    _initializedUid = null;
    await _userNotificationsSub?.cancel();
    _userNotificationsSub = null;
    try {
      await _messaging.deleteToken();
    } catch (_) {}
  }

  Future<void> init(String uid, [BuildContext? context]) async {
    if (_initializedUid == uid) return;
    _initializedUid = uid;

    // ── 1. Initialise flutter_local_notifications & channel immediately ──────
    // Initializing local notifications first guarantees that notifications
    // can always be posted even if FCM token fetching fails or times out.
    try {
      const androidInit =
          AndroidInitializationSettings('@mipmap/launcher_icon');
      const darwinInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _localNotif.initialize(
        const InitializationSettings(android: androidInit, iOS: darwinInit),
        onDidReceiveNotificationResponse: (details) {
          final ctx = AppRouter.navigatorKey.currentContext;
          if (ctx == null) return;
          final payload = details.payload;
          if (payload != null && payload.isNotEmpty) {
            try {
              final data = jsonDecode(payload) as Map<String, dynamic>;
              _routeFromPayload(
                data['action'] as String?,
                ctx,
                uid: data['uid'] as String?,
                itemId: data['itemId'] as String?,
                tourId: data['tourId'] as String?,
              );
            } catch (_) {
              _routeFromPayload(payload, ctx);
            }
          }
        },
      );

      final androidPlugin = _localNotif.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _kChannelId,
          _kChannelName,
          description: _kChannelDesc,
          importance: Importance.high,
          enableVibration: true,
          playSound: true,
        ),
      );

      // Request runtime notification permission on Android 13+ (API 33+)
      if (!kIsWeb && Platform.isAndroid) {
        await androidPlugin?.requestNotificationsPermission();
      }
    } catch (e) {
      debugPrint('[FcmService] Local notifications initialization error: $e');
    }

    // ── 2. Request FCM permissions & save device token ───────────────────────
    try {
      await _messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await _messaging.getToken();
      if (token != null) await _saveToken(uid, token);
      _messaging.onTokenRefresh.listen((t) => _saveToken(uid, t));
    } catch (e) {
      debugPrint('[FcmService] FCM token acquisition error: $e');
    }

    // ── 3. Listen for foreground FCM messages ─────────────────────────────
    try {
      FirebaseMessaging.onMessage.listen((message) {
        _handleForeground(message);
      });

      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final ctx = AppRouter.navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) _handleTap(message, ctx);
      });

      final initial = await _messaging.getInitialMessage();
      if (initial != null) {
        final ctx = AppRouter.navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) _handleTap(initial, ctx);
      }
    } catch (e) {
      debugPrint('[FcmService] FCM message listener error: $e');
    }

    // ── 4. Listen for realtime in-app notifications in Firestore ────────────
    _listenUserNotifications(uid);
  }

  void _listenUserNotifications(String uid) {
    _userNotificationsSub?.cancel();
    final sessionStart = Timestamp.now();
    _userNotificationsSub = _firestore
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .limit(10)
        .snapshots()
        .listen(
      (snapshot) {
        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final data = change.doc.data();
            if (data == null) continue;
            final ts = data['timestamp'] as Timestamp?;
            // Show new notifications arriving during this session (allowing 30s for server time diff)
            if (ts != null &&
                ts.millisecondsSinceEpoch >=
                    sessionStart.millisecondsSinceEpoch - 30000) {
              final title = (data['title'] as String?) ?? 'Bhromon Notification';
              final body = (data['body'] as String?) ?? '';
              final imageUrl = data['imageUrl'] as String?;
              showLocalNotification(
                id: change.doc.id.hashCode,
                title: title,
                body: body,
                payload: jsonEncode(data),
                imageUrl: imageUrl,
              );
            }
          }
        }
      },
      onError: (Object e) {
        debugPrint('[FcmService] user notifications listener error: $e');
      },
    );
  }

  /// Show a rich local notification immediately on the device.
  Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    String? imageUrl,
  }) async {
    StyleInformation? style;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final base64Str = await _fetchImageAsBase64(imageUrl);
      if (base64Str.isNotEmpty) {
        style = BigPictureStyleInformation(
          ByteArrayAndroidBitmap.fromBase64String(base64Str),
          largeIcon: ByteArrayAndroidBitmap.fromBase64String(base64Str),
          contentTitle: title,
          summaryText: body,
          htmlFormatContentTitle: false,
          htmlFormatSummaryText: false,
        );
      }
    }

    final androidDetails = AndroidNotificationDetails(
      _kChannelId,
      _kChannelName,
      channelDescription: _kChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: style,
      icon: '@mipmap/launcher_icon',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _localNotif.show(
      id,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload,
    );
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Saves this device's token for [uid]. Each device keeps its own document
  /// under `devices`, so a member with two phones gets pushes on both. The
  /// single document is also kept for the functions that read one token.
  Future<void> _saveToken(String uid, String token) async {
    final Map<String, dynamic> data = {
      'token': token,
      // Correctly record platform instead of hardcoding 'android'
      'platform': kIsWeb ? 'web' : (Platform.isAndroid ? 'android' : 'ios'),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final user = _firestore.collection('fcm_tokens').doc(uid);
    await user.set(data);
    await user.collection('devices').doc(pushDeviceId(token)).set(data);
  }

  /// Show a rich local notification when the app is in the foreground.
  Future<void> _handleForeground(RemoteMessage message) async {
    final n = message.notification;
    final title = n?.title ?? (message.data['title'] as String?) ?? 'Bhromon';
    final body = n?.body ?? (message.data['body'] as String?) ?? '';
    if (title.isEmpty && body.isEmpty) return;

    final String? imageUrl =
        n?.android?.imageUrl ?? (message.data['imageUrl'] as String?);

    await showLocalNotification(
      id: message.hashCode,
      title: title,
      body: body,
      payload: jsonEncode(message.data),
      imageUrl: imageUrl,
    );
  }

  void _handleTap(RemoteMessage message, BuildContext context) {
    _routeFromPayload(
      message.data['action'] as String?,
      context,
      uid: message.data['uid'] as String?,
      itemId: message.data['itemId'] as String?,
      tourId: message.data['tourId'] as String?,
    );
  }

  void _routeFromPayload(
    String? action,
    BuildContext context, {
    String? uid,
    String? itemId,
    String? tourId,
  }) {
    if (action == null || action.isEmpty) return;
    switch (action) {
      case 're_confirm_tips':
        GoRouter.of(context).go('/vault');
        break;
      case 'conflict':
        GoRouter.of(context).go('/vault?tab=conflicts');
        break;
      case 'flag_appeal':
        GoRouter.of(context).go('/trust/appeals');
        break;
      case 'tier_upgrade':
        if (uid != null) GoRouter.of(context).go('/profile/$uid');
        break;
      case 'helpful_vote':
        if (itemId != null) GoRouter.of(context).go('/trip/$itemId');
        break;
      case 'chat':
        if (itemId != null) {
          GoRouter.of(context).go('/chat/$itemId', extra: {'otherUid': uid});
        }
        break;
      case 'sos':
        if (tourId != null) GoRouter.of(context).go('/group/$tourId/safety');
        break;
      case 'channel':
        if (tourId != null) GoRouter.of(context).go('/group/$tourId/channels');
        break;
      case 'post':
      case 'comment':
      case 'like':
        if (tourId != null) GoRouter.of(context).go('/group/$tourId/feed');
        break;
      case 'notice':
        if (tourId != null) GoRouter.of(context).go('/group/$tourId/notices');
        break;
      case 'ledger':
      case 'expense':
        if (tourId != null) GoRouter.of(context).go('/group/$tourId/ledger');
        break;
      case 'journey':
        if (tourId != null) GoRouter.of(context).go('/group/$tourId/journey');
        break;
      case 'call':
        // Native CallNotificationService manages incoming call overlay/ringing
        break;
      case 'broadcast':
        break;
    }
  }

  /// Downloads an image from [url] and returns it as a base-64 string so
  /// [BigPictureStyleInformation] can consume it synchronously.
  Future<String> _fetchImageAsBase64(String url) async {
    try {
      final uri = Uri.parse(url);
      final client = HttpClient();
      final request = await client.getUrl(uri);
      final response = await request.close();
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      client.close();
      return base64Encode(bytes);
    } catch (_) {
      return '';
    }
  }
}
