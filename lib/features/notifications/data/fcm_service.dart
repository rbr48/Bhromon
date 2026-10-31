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
import '../../../core/utils/app_logger.dart';
import '../../chat/data/vps_chat_service.dart';

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
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _userNotificationsSub;
  String? _initializedUid;
  final Set<String> _processedNotificationIds = {};
  bool _initialSnapshotLoaded = false;

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
      // Push targets are still FCM tokens, and the functions send to them. FID mode
      // needs the server to send FID messages first, so the token calls stay for now.
      // ignore: deprecated_member_use
      await _messaging.deleteToken();
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
  }

  Future<void> init(String uid, [BuildContext? context]) async {
    if (_initializedUid == uid) return;
    _initializedUid = uid;

    // ── 1. Initialise flutter_local_notifications & channel immediately (Mobile only)
    try {
      if (!kIsWeb) {
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
                routeFromPayload(
                  data['action'] as String?,
                  ctx,
                  uid: data['uid'] as String?,
                  itemId: (data['itemId'] as String?) ??
                      (data['chatId'] as String?),
                  tourId: data['tourId'] as String?,
                );
              } catch (_) {
                routeFromPayload(payload, ctx);
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
        if (Platform.isAndroid) {
          await androidPlugin?.requestNotificationsPermission();
        }
      }
    } catch (e, st) {
      logWarning(
          '[FcmService] Local notifications initialization error', e, st);
    }

    // ── 2. Request FCM permissions & save device token ───────────────────────
    try {
      await _messaging.requestPermission(alert: true, badge: true, sound: true);
      // ignore: deprecated_member_use
      final token = await _messaging.getToken();
      if (token != null) await _saveToken(uid, token);
      // ignore: deprecated_member_use
      _messaging.onTokenRefresh.listen((t) => _saveToken(uid, t));
    } catch (e, st) {
      logWarning('[FcmService] FCM token acquisition error', e, st);
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
    } catch (e, st) {
      logWarning('[FcmService] FCM message listener error', e, st);
    }

    // ── 4. Listen for realtime in-app notifications in Firestore ────────────
    _listenUserNotifications(uid);
  }

  void _listenUserNotifications(String uid) {
    _userNotificationsSub?.cancel();
    _processedNotificationIds.clear();
    _initialSnapshotLoaded = false;

    _userNotificationsSub = _firestore
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .limit(20)
        .snapshots()
        .listen(
      (snapshot) {
        if (!_initialSnapshotLoaded) {
          // On app launch / login, populate historical IDs so old items aren't alerted
          for (final doc in snapshot.docs) {
            _processedNotificationIds.add(doc.id);
          }
          _initialSnapshotLoaded = true;
          return;
        }

        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added ||
              change.type == DocumentChangeType.modified) {
            final doc = change.doc;
            if (_processedNotificationIds.contains(doc.id)) continue;
            _processedNotificationIds.add(doc.id);

            final data = doc.data();
            if (data == null) continue;

            final title = (data['title'] as String?) ?? 'Bhromon Notification';
            final body = (data['body'] as String?) ?? '';
            final imageUrl = data['imageUrl'] as String?;
            final action = data['action'] as String?;
            final notifUid = data['uid'] as String?;
            final itemId =
                (data['itemId'] as String?) ?? (data['chatId'] as String?);
            final tourId = data['tourId'] as String?;

            // 1. Post local system tray notification (Android/iOS)
            if (!kIsWeb) {
              showLocalNotification(
                id: doc.id.hashCode,
                title: title,
                body: body,
                payload: jsonEncode(data),
                imageUrl: imageUrl,
              );
            }

            // 2. Display instant floating in-app notification banner across all platforms
            _showInAppBanner(
              title: title,
              body: body,
              action: action,
              uid: notifUid,
              itemId: itemId,
              tourId: tourId,
            );
          }
        }
      },
      onError: (Object e) {
        logWarning('[FcmService] user notifications listener error', e);
      },
    );
  }

  /// Show a rich local notification immediately on mobile devices.
  Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    String? imageUrl,
  }) async {
    if (kIsWeb) return;

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

  /// Display an instant, modern in-app floating banner when a notification arrives.
  void _showInAppBanner({
    required String title,
    required String body,
    String? action,
    String? uid,
    String? itemId,
    String? tourId,
  }) {
    final ctx = AppRouter.navigatorKey.currentContext;
    if (ctx == null) return;
    try {
      final scaffold = ScaffoldMessenger.maybeOf(ctx);
      if (scaffold != null) {
        scaffold.hideCurrentSnackBar();
        scaffold.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFF00A884), width: 1),
            ),
            backgroundColor: const Color(0xFF1F2C34),
            duration: const Duration(seconds: 4),
            content: InkWell(
              onTap: () {
                scaffold.hideCurrentSnackBar();
                routeFromPayload(
                  action,
                  ctx,
                  uid: uid,
                  itemId: itemId,
                  tourId: tourId,
                );
              },
              child: Row(
                children: [
                  const Icon(Icons.notifications_active,
                      color: Color(0xFF00A884), size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (body.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            body,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    } catch (e, st) {
      logWarning('[FcmService] _showInAppBanner error', e, st);
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Saves this device's token for [uid]. Each device keeps its own document
  /// under `devices`, so a member with two phones gets pushes on both. The
  /// single document is also kept for the functions that read one token.
  Future<void> _saveToken(String uid, String token) async {
    final platform = kIsWeb ? 'web' : (Platform.isAndroid ? 'android' : 'ios');
    final Map<String, dynamic> data = {
      'token': token,
      'platform': platform,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // 1. Immediately register with VPS for instant server-direct push notifications
    try {
      await VpsChatService().registerDeviceToken(token, platform: platform);
    } catch (e, st) {
      logWarning('[FcmService] VPS token registration error', e, st);
    }

    // 2. Best-effort registration with Firestore (silently catch quota errors)
    try {
      final user = _firestore.collection('fcm_tokens').doc(uid);
      await user.set(data);
      await user.collection('devices').doc(pushDeviceId(token)).set(data);
    } catch (e) {
      logDebug('[FcmService] Firestore token registration ignored/quota: $e');
    }
  }

  /// Show a rich local notification when the app is in the foreground.
  Future<void> _handleForeground(RemoteMessage message) async {
    // A call is shown by CallNotificationService, from the relay and the call
    // document. A banner here would ring the same call twice.
    if (message.data['action'] == 'call') return;

    final n = message.notification;
    final title = n?.title ?? (message.data['title'] as String?) ?? 'Bhromon';
    final body = n?.body ?? (message.data['body'] as String?) ?? '';
    if (title.isEmpty && body.isEmpty) return;

    final String? imageUrl =
        n?.android?.imageUrl ?? (message.data['imageUrl'] as String?);

    if (!kIsWeb) {
      await showLocalNotification(
        id: message.hashCode,
        title: title,
        body: body,
        payload: jsonEncode(message.data),
        imageUrl: imageUrl,
      );
    }

    _showInAppBanner(
      title: title,
      body: body,
      action: message.data['action'] as String?,
      uid: message.data['uid'] as String?,
      itemId: (message.data['itemId'] as String?) ??
          (message.data['chatId'] as String?),
      tourId: message.data['tourId'] as String?,
    );
  }

  void _handleTap(RemoteMessage message, BuildContext context) {
    routeFromPayload(
      message.data['action'] as String?,
      context,
      uid: message.data['uid'] as String?,
      itemId: (message.data['itemId'] as String?) ??
          (message.data['chatId'] as String?),
      tourId: message.data['tourId'] as String?,
    );
  }

  /// Opens the screen a notification points to.
  static void routeFromPayload(
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
        final targetChatId = itemId ?? uid;
        if (targetChatId != null && targetChatId.isNotEmpty) {
          GoRouter.of(context)
              .go('/chat/$targetChatId', extra: {'otherUid': uid});
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
      case 'family_date':
        if (tourId != null) {
          GoRouter.of(context).go('/group/$tourId/family-dates');
        }
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
    if (kIsWeb) return '';
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
