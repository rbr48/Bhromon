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
    try {
      await _messaging.deleteToken();
    } catch (_) {}
  }

  Future<void> init(String uid, [BuildContext? context]) async {
    if (_initializedUid == uid) return;
    _initializedUid = uid;

    // ── 1. Request FCM permission ──────────────────────────────────────────
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
    final token = await _messaging.getToken();
    if (token != null) await _saveToken(uid, token);
    _messaging.onTokenRefresh.listen((t) => _saveToken(uid, t));

    // ── 2. Initialise flutter_local_notifications ──────────────────────────
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false, // already requested above via FCM
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _localNotif.initialize(
      const InitializationSettings(android: androidInit, iOS: darwinInit),
      onDidReceiveNotificationResponse: (details) {
        // Use the global navigator key so the context is never stale,
        // even if the widget tree that called init() has been unmounted.
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

    // ── 3. Create Android notification channel ────────────────────────────
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

    // ── 3a. Request POST_NOTIFICATIONS at runtime (Android 13+ / API 33+) ─
    // FCM's requestPermission() handles iOS. On Android 13+ we must also ask
    // the OS-level notification permission via the local-notifications plugin.
    await androidPlugin?.requestNotificationsPermission();

    // ── 4. Listen for foreground FCM messages ─────────────────────────────
    FirebaseMessaging.onMessage.listen((message) {
      _handleForeground(message);
    });

    // ── 5. Background / terminated-state tap handling ─────────────────────
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final ctx = AppRouter.navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) _handleTap(message, ctx);
    });
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      final ctx = AppRouter.navigatorKey.currentContext;
      // ignore: use_build_context_synchronously
      if (ctx != null) _handleTap(initial, ctx);
    }
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
    if (n == null) return;

    final title = n.title ?? '';
    final body = n.body ?? '';

    // FCM sets imageUrl on the android-specific notification object; also
    // check the data payload for broadcast notifications sent by the admin.
    final String? imageUrl =
        n.android?.imageUrl ?? (message.data['imageUrl'] as String?);

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
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _localNotif.show(
      // Use a stable ID derived from the message so duplicates don't stack
      message.hashCode,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: jsonEncode(message.data),
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
