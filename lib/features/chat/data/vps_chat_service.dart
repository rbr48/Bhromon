import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Bhromon VPS Chat Service.
///
/// Exclusively uses the Bhromon Hostinger VPS (bhromon.fun) for 1-on-1 chat,
/// real-time WebSockets, WebRTC signaling, and push notifications.
/// Completely bypasses Firebase Firestore, eliminating all rate limits and quota errors.
class VpsChatService {
  static final VpsChatService _instance = VpsChatService._internal();
  factory VpsChatService() => _instance;
  VpsChatService._internal();

  static const String baseUrl = 'https://bhromon.fun/api/chat/';
  static const String wsUrl = 'wss://bhromon.fun/api/chat/ws';

  final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  WebSocketChannel? _wsChannel;
  StreamSubscription<dynamic>? _wsSubscription;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _isConnecting = false;
  int _reconnectAttempts = 0;

  String? _currentUid;
  StreamSubscription<User?>? _authSubscription;

  // Stream controllers for UI reactivity
  final _conversationsController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final _messagesControllers =
      <String, StreamController<Map<String, dynamic>>>{};
  final _typingControllers = <String, StreamController<Map<String, dynamic>>>{};
  final _callSignalController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<List<Map<String, dynamic>>> get conversationsStream =>
      _conversationsController.stream;
  Stream<Map<String, dynamic>> get callSignalStream =>
      _callSignalController.stream;

  Stream<Map<String, dynamic>> messageStream(String chatId) {
    return _messagesControllers
        .putIfAbsent(
          chatId,
          () => StreamController<Map<String, dynamic>>.broadcast(),
        )
        .stream;
  }

  Stream<Map<String, dynamic>> typingStream(String chatId) {
    return _typingControllers
        .putIfAbsent(
          chatId,
          () => StreamController<Map<String, dynamic>>.broadcast(),
        )
        .stream;
  }

  /// Initialize the service and bind to Firebase Auth state.
  void init() {
    _authSubscription?.cancel();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _currentUid = user.uid;
        _connectWebSocket();
        unawaited(fetchConversations());
      } else {
        _currentUid = null;
        _disconnectWebSocket();
      }
    });
  }

  Future<String?> _getIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return await user.getIdToken();
  }

  Options _authHeader(String token) {
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  // ── WebSocket Connection & Lifecycle ───────────────────────────────────────

  void _connectWebSocket() async {
    if (_isConnecting || _currentUid == null) return;
    _isConnecting = true;

    try {
      final token = await _getIdToken();
      if (token == null) {
        _isConnecting = false;
        return;
      }

      final uri = Uri.parse('$wsUrl?token=${Uri.encodeComponent(token)}');
      _wsChannel = WebSocketChannel.connect(uri);
      await _wsChannel!.ready;

      _reconnectAttempts = 0;
      _isConnecting = false;
      debugPrint('[VpsChat] WebSocket connected for uid: $_currentUid');

      // Start ping keep-alive
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
        sendWsEvent({'type': 'ping'});
      });

      _wsSubscription?.cancel();
      _wsSubscription = _wsChannel!.stream.listen(
        _handleWsMessage,
        onError: (Object error) {
          debugPrint('[VpsChat] WebSocket error: $error');
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('[VpsChat] WebSocket closed');
          _scheduleReconnect();
        },
      );
    } catch (e) {
      debugPrint('[VpsChat] WebSocket connection failed: $e');
      _isConnecting = false;
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    if (_currentUid == null) return;

    _reconnectAttempts++;
    final delaySeconds = (_reconnectAttempts * 2).clamp(1, 20);
    debugPrint('[VpsChat] Scheduling reconnect in ${delaySeconds}s...');
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      _connectWebSocket();
    });
  }

  void _disconnectWebSocket() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _wsSubscription?.cancel();
    _wsSubscription = null;
    try {
      _wsChannel?.sink.close();
    } catch (_) {}
    _wsChannel = null;
    _isConnecting = false;
  }

  void sendWsEvent(Map<String, dynamic> event) {
    try {
      if (_wsChannel != null) {
        _wsChannel!.sink.add(jsonEncode(event));
      }
    } catch (e) {
      debugPrint('[VpsChat] Failed to send WS event: $e');
    }
  }

  void _handleWsMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw.toString()) as Map<String, dynamic>;
      final type = data['type'] as String?;

      switch (type) {
        case 'new_message':
          final msg = data['message'] as Map<String, dynamic>?;
          if (msg != null) {
            final chatId = msg['chatId'] as String?;
            if (chatId != null) {
              _messagesControllers[chatId]?.add(msg);
            }
            unawaited(fetchConversations());
          }
          break;

        case 'typing':
          final chatId = data['chatId'] as String?;
          if (chatId != null) {
            _typingControllers[chatId]?.add(data);
          }
          break;

        case 'read':
          final chatId = data['chatId'] as String?;
          if (chatId != null) {
            _messagesControllers[chatId]?.add(data);
          }
          unawaited(fetchConversations());
          break;

        case 'reaction':
          final chatId = data['chatId'] as String?;
          if (chatId != null) {
            _messagesControllers[chatId]?.add(data);
          }
          break;

        case 'message_deleted':
          final chatId = data['chatId'] as String?;
          if (chatId != null) {
            _messagesControllers[chatId]?.add(data);
          }
          unawaited(fetchConversations());
          break;

        case 'call_signal':
          _callSignalController.add(data);
          break;

        case 'pong':
          break;

        default:
          break;
      }
    } catch (e) {
      debugPrint('[VpsChat] Error handling WS message: $e');
    }
  }

  // ── Device Token Registration (Push Notifications) ─────────────────────────

  Future<void> registerDeviceToken(String token, {String? platform}) async {
    try {
      final idToken = await _getIdToken();
      if (idToken == null) return;

      await _dio.post<Map<String, dynamic>>(
        'token',
        data: {
          'token': token,
          'platform': platform ?? (kIsWeb ? 'web' : 'mobile'),
        },
        options: _authHeader(idToken),
      );
      debugPrint('[VpsChat] Registered device token to VPS');
    } catch (e) {
      debugPrint('[VpsChat] Failed to register device token: $e');
    }
  }

  // ── Conversations ──────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchConversations() async {
    try {
      final idToken = await _getIdToken();
      if (idToken == null) return [];

      final res = await _dio.get<Map<String, dynamic>>(
        'conversations',
        options: _authHeader(idToken),
      );

      final list = (res.data?['conversations'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      _conversationsController.add(list);
      return list;
    } catch (e) {
      debugPrint('[VpsChat] Failed to fetch conversations: $e');
      return [];
    }
  }

  // ── Messages ───────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchMessages(
    String chatId, {
    int? before,
    int limit = 50,
  }) async {
    try {
      final idToken = await _getIdToken();
      if (idToken == null) return [];

      final res = await _dio.get<Map<String, dynamic>>(
        'messages/$chatId',
        queryParameters: {
          if (before != null) 'before': before,
          'limit': limit,
        },
        options: _authHeader(idToken),
      );

      return (res.data?['messages'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      debugPrint('[VpsChat] Failed to fetch messages: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> sendMessage({
    required String chatId,
    required String recipientId,
    String? text,
    String type = 'text',
    String? senderName,
    String? senderAvatar,
    String? mediaUrl,
    String? mediaPath,
    String? thumbnailUrl,
    Map<String, dynamic>? replyTo,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final idToken = await _getIdToken();
      if (idToken == null) return null;

      final payload = {
        'chatId': chatId,
        'recipientId': recipientId,
        'text': text ?? '',
        'type': type,
        'senderName': senderName,
        'senderAvatar': senderAvatar,
        'mediaUrl': mediaUrl,
        'mediaPath': mediaPath,
        'thumbnailUrl': thumbnailUrl,
        'replyTo': replyTo,
        'metadata': metadata,
      };

      final res = await _dio.post<Map<String, dynamic>>(
        'message',
        data: payload,
        options: _authHeader(idToken),
      );

      final saved = res.data?['message'] as Map<String, dynamic>?;
      if (saved != null) {
        _messagesControllers[chatId]?.add(saved);
        unawaited(fetchConversations());
      }
      return saved;
    } catch (e) {
      debugPrint('[VpsChat] Failed to send message: $e');
      return null;
    }
  }

  Future<void> sendTyping({
    required String chatId,
    required String recipientId,
    required bool isTyping,
  }) async {
    sendWsEvent({
      'type': 'typing',
      'chatId': chatId,
      'recipientId': recipientId,
      'isTyping': isTyping,
    });
  }

  Future<void> markRead(String chatId, {List<String>? messageIds, String? recipientId}) async {
    // Send via WebSocket for instant update
    sendWsEvent({
      'type': 'read',
      'chatId': chatId,
      'recipientId': recipientId,
      'messageIds': messageIds,
    });

    try {
      final idToken = await _getIdToken();
      if (idToken == null) return;

      await _dio.post<Map<String, dynamic>>(
        'read',
        data: {'chatId': chatId, 'messageIds': messageIds},
        options: _authHeader(idToken),
      );
    } catch (e) {
      debugPrint('[VpsChat] Failed to mark read: $e');
    }
  }

  Future<void> toggleReaction({
    required String chatId,
    required String messageId,
    required String emoji,
  }) async {
    try {
      final idToken = await _getIdToken();
      if (idToken == null) return;

      await _dio.post<Map<String, dynamic>>(
        'reaction',
        data: {
          'chatId': chatId,
          'messageId': messageId,
          'emoji': emoji,
        },
        options: _authHeader(idToken),
      );
    } catch (e) {
      debugPrint('[VpsChat] Failed to toggle reaction: $e');
    }
  }

  Future<void> deleteMessage({
    required String chatId,
    required String messageId,
    bool forEveryone = false,
  }) async {
    try {
      final idToken = await _getIdToken();
      if (idToken == null) return;

      await _dio.post<Map<String, dynamic>>(
        'delete',
        data: {
          'chatId': chatId,
          'messageId': messageId,
          'forEveryone': forEveryone,
        },
        options: _authHeader(idToken),
      );
    } catch (e) {
      debugPrint('[VpsChat] Failed to delete message: $e');
    }
  }

  // ── WebRTC Call Signaling (Instant Relay) ──────────────────────────────────

  void sendCallSignal({
    required String recipientId,
    required String signalType,
    required dynamic payload,
    String? callId,
    bool isVideo = false,
    String? callerName,
    String? avatarUrl,
  }) {
    sendWsEvent({
      'type': 'call_signal',
      'recipientId': recipientId,
      'signalType': signalType,
      'payload': payload,
      'callId': callId,
      'isVideo': isVideo,
      'callerName': callerName,
      'avatarUrl': avatarUrl,
    });
  }
}
