import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/utils/shared_latest_stream.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'dart:math' as math;
import '../../../../core/localization/app_localizations.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../widgets/chat_media_picker.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/chat_media_bubble.dart';
import '../widgets/voice_message_recorder.dart';
import '../widgets/voice_message_bubble.dart';
import '../widgets/swipe_to_reply.dart';
import '../widgets/chat_reply_preview.dart';
import '../widgets/chat_reaction_bar.dart';
import '../widgets/chat_document_bubble.dart';
import '../widgets/chat_location_bubble.dart';
import '../widgets/chat_attachment_sheet.dart';
import '../widgets/chat_forward_dialog.dart';
import '../widgets/chat_media_caption_screen.dart';
import '../widgets/chat_expense_bubble.dart';
import '../widgets/chat_emoji_picker.dart';
import '../../data/chat_local_cache.dart';
import '../../data/vps_chat_service.dart';
import '../../../tour_group/data/tour_group_repository.dart';
import '../../domain/call_log_entry.dart';
import '../../data/travel_ai_service.dart';
import '../../../../core/utils/image_sizing.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/services/media_upload_service.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String? otherUid;

  /// The tour this chat is opened in, and the other person's email. A chat from a
  /// tour passes both in; an older chat finds them in its own document.
  final String? sharedTourId;
  final String? otherEmail;

  const ChatScreen({
    super.key,
    required this.chatId,
    this.otherUid,
    this.sharedTourId,
    this.otherEmail,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

/// Represents an in-progress media upload shown optimistically in the chat list.
class _PendingUpload {
  final String id;
  File? file;
  Uint8List? bytes;
  final String type;
  double progress = 0.0;

  _PendingUpload({
    required this.id,
    this.file,
    this.bytes,
    required this.type,
  });
}

/// Represents an optimistic outgoing text message shown instantly in the chat list.
class _PendingTextMessage {
  final String id;
  final String text;
  final ReplyMessageInfo? replyTo;
  final DateTime createdAt;
  bool isFailed;

  _PendingTextMessage({
    required this.id,
    required this.text,
    this.replyTo,
    required this.createdAt,
  }) : isFailed = false;
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _isBlocked = false;
  bool _isLoadingBlock = true;

  bool _isTyping = false;
  Timer? _typingTimer;

  bool _isRecordingVoice = false;
  bool _showEmojiPicker = false;

  // ── WhatsApp Parity State ──────────────────────────────────────────────────
  ReplyMessageInfo? _replyingMessage;
  QueryDocumentSnapshot? _editingMessage;
  final Set<String> _selectedMessageIds = {};
  bool _isSearchingInChat = false;
  final TextEditingController _searchController = TextEditingController();
  int _searchMatchIndex = 0;
  final List<int> _matchingIndices = [];
  String? _highlightedMessageId;
  QueryDocumentSnapshot? _reactionTargetDoc;

  // Pending uploads shown optimistically before Firestore write completes.
  final List<_PendingUpload> _pendingUploads = [];
  final List<_PendingTextMessage> _pendingTextMessages = [];
  final Set<String> _markedSeenDocIds = {};

  // ── Pagination state ────────────────────────────────────────────────────────
  static const int _pageSize = 30;
  DocumentSnapshot? _oldestLoadedDoc; // cursor for the next page
  bool _hasMoreMessages = true; // false once all pages loaded
  bool _isLoadingMore = false; // prevents duplicate fetches
  final List<QueryDocumentSnapshot> _allMessages = [];

  // The header (online/typing) and the typing overlay both watch the chat
  // document: one shared listener, created once instead of in build().
  late final Stream<DocumentSnapshot> _chatDocStream =
      SharedLatestStream<DocumentSnapshot>(FirebaseFirestore.instance
              .collection('chats')
              .doc(widget.chatId)
              .snapshots())
          .stream;

  String? _otherProfileUid;
  Stream<DocumentSnapshot>? _otherProfileSnapshots;

  /// The other participant's profile stream, rebuilt only if they change.
  Stream<DocumentSnapshot> _otherProfileStream(String uid) {
    if (_otherProfileUid != uid || _otherProfileSnapshots == null) {
      _otherProfileUid = uid;
      _otherProfileSnapshots = FirebaseFirestore.instance
          .collection('explorer_profiles')
          .doc(uid)
          .snapshots();
    }
    return _otherProfileSnapshots!;
  }

  StreamSubscription<QuerySnapshot>? _messagesSub;
  StreamSubscription<Map<String, dynamic>>? _vpsTypingSub;
  bool _otherOnline = false;
  Timer? _onlinePoll;
  bool _vpsOtherIsTyping = false;
  int _disappearingTimerSeconds = 0;
  StreamSubscription<DocumentSnapshot>? _chatDocSub;

  @override
  void initState() {
    super.initState();
    _sharedTourId = widget.sharedTourId;
    _otherEmail = widget.otherEmail;
    _loadSharedContext();
    ChatLocalCache().init();
    _checkBlockStatus();
    _startOnlinePolling();
    _initVpsTypingListener();
    _messageController.addListener(_onTextChanged);
    _messageFocusNode.addListener(() {
      if (_messageFocusNode.hasFocus && _showEmojiPicker) {
        setState(() => _showEmojiPicker = false);
      }
    });
    _scrollController.addListener(_onScroll);
    _startChatOpenTrace();
    _subscribeToLatestMessages();
    _chatDocSub = _chatDocStream.listen((snap) {
      if (!mounted) return;
      final data = snap.data() as Map<String, dynamic>?;
      final secs = (data?['disappearingTimerSeconds'] as num?)?.toInt() ?? 0;
      if (secs != _disappearingTimerSeconds) {
        setState(() => _disappearingTimerSeconds = secs);
      }
    });
  }

  /// Starts a Firebase Performance trace for chat screen open → first message load.
  Future<void> _startChatOpenTrace() async {
    if (kIsWeb) return;
    try {
      final trace = FirebasePerformance.instance.newTrace('chat_open');
      await trace.start();
      // Stop the trace after first messages arrive or 30s timeout — whichever is first
      Future.delayed(const Duration(seconds: 30), () async {
        try {
          await trace.stop();
        } catch (_) {}
      });
    } catch (_) {}
  }

  /// Subscribes to the latest [_pageSize] messages in real-time.
  void _subscribeToLatestMessages() {
    _messagesSub?.cancel();
    _messagesSub = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(_pageSize)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final incoming = snap.docs;
      // Cache messages locally for offline viewing
      final cacheList = <Map<String, dynamic>>[];
      for (final doc in incoming) {
        cacheList.add({'id': doc.id, ...doc.data()});
      }
      if (cacheList.isNotEmpty) {
        ChatLocalCache().cacheMessages(widget.chatId, cacheList);
      }

      final incomingMap = {for (final d in incoming) d.id: d};
      final incomingIds = incomingMap.keys.toSet();

      setState(() {
        // Remove from optimistic pending text list once confirmed by snapshot
        _pendingTextMessages.removeWhere((p) => incomingIds.contains(p.id));

        // 1. Update any existing docs in-place (updates delivery ticks, reactions, seen status)
        for (int i = 0; i < _allMessages.length; i++) {
          final id = _allMessages[i].id;
          if (incomingMap.containsKey(id)) {
            _allMessages[i] = incomingMap[id]!;
          }
        }

        // 2. Insert any brand new incoming docs at the top
        final existingIds = _allMessages.map((d) => d.id).toSet();
        final fresh =
            incoming.where((d) => !existingIds.contains(d.id)).toList();
        if (fresh.isNotEmpty) {
          _allMessages.insertAll(0, fresh);
        }

        if (incoming.length < _pageSize) _hasMoreMessages = false;
        if (incoming.isNotEmpty) _oldestLoadedDoc = incoming.last;
      });

      // Automatically mark unread incoming messages as seen on snapshot receive
      try {
        final authState = context.read<AuthCubit>().state;
        final currentUid =
            authState is Authenticated ? authState.profile.uid : '';
        if (currentUid.isNotEmpty) {
          _markMessagesAsSeen(incoming, currentUid);
        }
      } catch (_) {}
    });
  }

  /// Called when the user scrolls near the top (oldest messages end).
  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        _hasMoreMessages &&
        !_isLoadingMore) {
      _loadEarlierMessages();
    }
  }

  /// Loads the next page of older messages.
  Future<void> _loadEarlierMessages() async {
    if (_isLoadingMore || !_hasMoreMessages || _oldestLoadedDoc == null) return;
    setState(() => _isLoadingMore = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .startAfterDocument(_oldestLoadedDoc!)
          .limit(_pageSize)
          .get();

      if (!mounted) return;
      setState(() {
        _allMessages.addAll(snap.docs);
        if (snap.docs.isEmpty || snap.docs.length < _pageSize) {
          _hasMoreMessages = false;
        } else {
          _oldestLoadedDoc = snap.docs.last;
        }
        _isLoadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _onTextChanged() {
    final authState = context.read<AuthCubit>().state;
    final currentUid = authState is Authenticated ? authState.profile.uid : '';
    if (currentUid.isEmpty) return;

    // Trigger UI updates for mic/send icon transition
    setState(() {});

    if (_messageController.text.isNotEmpty) {
      if (!_isTyping) {
        _isTyping = true;
        _updateTypingStatus(currentUid, true);
      }
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 2), () {
        if (_isTyping) {
          _isTyping = false;
          _updateTypingStatus(currentUid, false);
        }
      });
    } else {
      if (_isTyping) {
        _isTyping = false;
        _typingTimer?.cancel();
        _updateTypingStatus(currentUid, false);
      }
    }
  }

  void _updateTypingStatus(String uid, bool typing) {
    final otherUid = _resolveOtherUid(uid);
    if (otherUid != null && otherUid.isNotEmpty) {
      VpsChatService().sendTyping(
        chatId: widget.chatId,
        recipientId: otherUid,
        isTyping: typing,
      );
    }
    try {
      FirebaseFirestore.instance.collection('chats').doc(widget.chatId).set({
        'typing_$uid': typing,
      }, SetOptions(merge: true)).catchError((_) {});
    } catch (_) {}
  }

  void _checkBlockStatus() async {
    final authState = context.read<AuthCubit>().state;
    final currentUid =
        authState is Authenticated ? authState.profile.uid : 'explorer_user';
    final resolvedOtherUid = _resolveOtherUid(currentUid);

    if (currentUid.isNotEmpty &&
        resolvedOtherUid != null &&
        resolvedOtherUid.isNotEmpty) {
      try {
        final blockedOtherDoc = await FirebaseFirestore.instance
            .collection('explorer_profiles')
            .doc(currentUid)
            .collection('blocked_users')
            .doc(resolvedOtherUid)
            .get();

        final blockedByOtherDoc = await FirebaseFirestore.instance
            .collection('explorer_profiles')
            .doc(resolvedOtherUid)
            .collection('blocked_users')
            .doc(currentUid)
            .get();

        if (mounted) {
          setState(() {
            _isBlocked = blockedOtherDoc.exists || blockedByOtherDoc.exists;
            _isLoadingBlock = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _isLoadingBlock = false;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoadingBlock = false;
        });
      }
    }
  }

  void _initVpsTypingListener() {
    _vpsTypingSub?.cancel();
    _vpsTypingSub = VpsChatService().typingStream(widget.chatId).listen((data) {
      if (!mounted) return;
      final senderUid = data['uid'] as String?;
      final isTyping = data['isTyping'] == true;
      final authState = context.read<AuthCubit>().state;
      final currentUid =
          authState is Authenticated ? authState.profile.uid : '';
      final resolvedOther = _resolveOtherUid(currentUid);
      if (senderUid == resolvedOther && _vpsOtherIsTyping != isTyping) {
        setState(() => _vpsOtherIsTyping = isTyping);
      }
    });
  }

  @override
  void dispose() {
    _vpsTypingSub?.cancel();
    _messageController.removeListener(_onTextChanged);
    _scrollController.removeListener(_onScroll);
    _typingTimer?.cancel();
    _messagesSub?.cancel();
    _chatDocSub?.cancel();
    final authState = context.read<AuthCubit>().state;
    if (authState is Authenticated) {
      _updateTypingStatus(authState.profile.uid, false);
    }
    _onlinePoll?.cancel();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Asks the server whether the other person is connected, now and every 30
  /// seconds while this chat is open. A failed check keeps the last answer.
  void _startOnlinePolling() {
    final authState = context.read<AuthCubit>().state;
    final currentUid = authState is Authenticated ? authState.profile.uid : '';
    final otherUid = _resolveOtherUid(currentUid);
    if (currentUid.isEmpty || otherUid == null || otherUid.isEmpty) return;

    Future<void> check() async {
      final online = await VpsChatService().fetchOnlineStatus(otherUid);
      if (mounted && online != null && online != _otherOnline) {
        setState(() => _otherOnline = online);
      }
    }

    unawaited(check());
    _onlinePoll = Timer.periodic(const Duration(seconds: 30), (_) => check());
  }

  String? _sharedTourId;
  String? _otherEmail;

  String get _myEmail => TourGroupRepository().currentEmail;

  /// Fills in the tour and the other person's email from the chat document, for a
  /// chat that was not opened from a tour.
  void _loadSharedContext() {
    if (_sharedTourId != null && _otherEmail != null) return;
    FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .get()
        .then((snap) {
      if (!mounted) return;
      final data = snap.data();
      final other = _resolveOtherUid(TourGroupRepository().currentUid);
      final emails = data?['memberEmails'];
      setState(() {
        _sharedTourId ??= data?['sharedTourId'] as String?;
        if (_otherEmail == null && other != null && emails is Map) {
          _otherEmail = emails[other] as String?;
        }
      });
    }).catchError((Object _) {});
  }

  /// Creates the chat document, or upgrades an older one, before a message is
  /// written. The rules refuse a message in a chat that does not exist yet, and a
  /// chat between two people must name the tour they share. The write is queued
  /// rather than awaited; Firestore applies one client's writes in order, so the
  /// message follows the chat.
  void _ensureChatDocument(String currentUid) {
    final otherUid = _resolveOtherUid(currentUid);
    if (otherUid == null || otherUid.isEmpty) return;
    final Map<String, dynamic> tour;
    if (otherUid == 'bhromon_ai_advisor') {
      tour = const {};
    } else if (_sharedTourId != null && _otherEmail != null) {
      tour = {
        'sharedTourId': _sharedTourId,
        'memberEmails': {currentUid: _myEmail, otherUid: _otherEmail},
      };
    } else {
      return;
    }
    FirebaseFirestore.instance.collection('chats').doc(widget.chatId).set({
      'participants': FieldValue.arrayUnion([currentUid, otherUid]),
      ...tour,
    }, SetOptions(merge: true)).catchError((Object e) {
      logWarning('Chat document write error: $e');
    });
  }

  String? _resolveOtherUid(String currentUid) {
    if (widget.otherUid != null && widget.otherUid!.isNotEmpty) {
      return widget.otherUid;
    }
    if (widget.chatId.startsWith('${currentUid}_')) {
      return widget.chatId.substring(currentUid.length + 1);
    }
    if (widget.chatId.endsWith('_$currentUid')) {
      return widget.chatId
          .substring(0, widget.chatId.length - currentUid.length - 1);
    }
    final parts = widget.chatId.split('_');
    if (parts.length == 2) {
      return parts[0] == currentUid ? parts[1] : parts[0];
    }
    return null;
  }

  void _insertEmoji(String emoji) {
    final text = _messageController.text;
    final selection = _messageController.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final newText = text.replaceRange(start, end, emoji);
    _messageController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  void _backspaceEmoji() {
    final text = _messageController.text;
    final selection = _messageController.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    if (start == 0 && end == 0) return;
    if (start != end) {
      final newText = text.replaceRange(start, end, '');
      _messageController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start),
      );
    } else {
      final characters = text.characters;
      if (characters.isNotEmpty) {
        final newText = characters.skipLast(1).toString();
        _messageController.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );
      }
    }
  }

  void _toggleEmojiPicker() {
    if (_showEmojiPicker) {
      setState(() => _showEmojiPicker = false);
      _messageFocusNode.requestFocus();
    } else {
      _messageFocusNode.unfocus();
      setState(() => _showEmojiPicker = true);
    }
  }

  Map<String, dynamic> _buildChatMeta({
    required String lastMessage,
    required String lastMessageType,
    required String currentUid,
    required String currentName,
    required String? resolvedOtherUid,
  }) {
    return {
      // Chats between tour members carry their tour and both emails, which the
      // rules check before anyone can write to them.
      if (_sharedTourId != null) 'sharedTourId': _sharedTourId,
      if (_sharedTourId != null &&
          resolvedOtherUid != null &&
          _otherEmail != null)
        'memberEmails': {currentUid: _myEmail, resolvedOtherUid: _otherEmail},
      'lastMessage': lastMessage,
      'lastMessageType': lastMessageType,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastMessageSenderId': currentUid,
      'unreadCounts': {
        currentUid: 0,
        if (resolvedOtherUid != null && resolvedOtherUid.isNotEmpty)
          resolvedOtherUid: FieldValue.increment(1),
      },
      'participants': FieldValue.arrayUnion([
        currentUid,
        if (resolvedOtherUid != null && resolvedOtherUid.isNotEmpty)
          resolvedOtherUid,
      ]),
      'participantProfiles': {
        currentUid: {
          'displayName': currentName,
        },
      },
    };
  }

  void _sendNotificationToRecipient({
    required String? recipientUid,
    required String currentUid,
    required String currentName,
    required String body,
  }) {
    if (recipientUid != null &&
        recipientUid != 'guest' &&
        recipientUid != currentUid &&
        recipientUid != 'bhromon_ai_advisor') {
      FirebaseFirestore.instance
          .collection('users')
          .doc(recipientUid)
          .collection('notifications')
          .doc()
          .set({
        'title': 'New message from $currentName',
        'body': body,
        'action': 'chat',
        'uid': currentUid,
        'itemId': widget.chatId,
        'chatId': widget.chatId,
        'timestamp': FieldValue.serverTimestamp(),
      }).catchError((Object e) {
        logWarning('Notification dispatch skipped: $e');
      });
    }
  }

  Future<void> _retryPendingTextMessage(
    _PendingTextMessage pending,
    String currentUid,
    String currentName,
  ) async {
    setState(() => pending.isFailed = false);
    _ensureChatDocument(currentUid);
    final msgRef = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .doc(pending.id);

    final msgData = <String, dynamic>{
      'senderId': currentUid,
      'type': 'text',
      'text': pending.text,
      if (pending.replyTo != null) 'replyTo': pending.replyTo!.toMap(),
      'seen': false,
      'status': 'sent',
      'timestamp': FieldValue.serverTimestamp(),
    };

    final resolvedOtherUid = _resolveOtherUid(currentUid);
    if (resolvedOtherUid != null && resolvedOtherUid.isNotEmpty) {
      unawaited(VpsChatService().sendMessage(
        chatId: widget.chatId,
        recipientId: resolvedOtherUid,
        text: pending.text,
        type: 'text',
        senderName: currentName,
        replyTo: pending.replyTo?.toMap(),
      ));
    }

    try {
      await msgRef.set(msgData);
    } catch (_) {}

    if (mounted) {
      setState(
          () => _pendingTextMessages.removeWhere((p) => p.id == pending.id));
    }
  }

  /// A finished call, centred in the conversation: the direction or outcome,
  /// and the length when the call connected.
  Widget _buildCallLogEntry(Map<String, dynamic> data, String currentUid) {
    final l10n = context.l10n;
    final entry = CallLogEntry.fromData(data);
    final kind = entry.kindFor(currentUid);
    final isProblem = kind == CallLogKind.missed ||
        kind == CallLogKind.noAnswer ||
        kind == CallLogKind.declined;
    final label = l10n.translate(_callLogLabelKey(kind));
    final seconds = entry.durationSeconds;
    final String text;
    if (entry.connected && seconds != null) {
      final parts = callDurationParts(seconds);
      final length = l10n.translate('chat_call_duration', args: {
        'count': parts.minutes,
        'n': parts.seconds,
      });
      text = '$label · $length';
    } else {
      text = label;
    }
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2C34),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _callLogIcon(kind),
              size: 16,
              color: isProblem ? Colors.redAccent : const Color(0xFF00A884),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _callLogLabelKey(CallLogKind kind) => switch (kind) {
        CallLogKind.outgoing => 'chat_call_outgoing',
        CallLogKind.incoming => 'chat_call_incoming',
        CallLogKind.outgoingVideo => 'chat_call_outgoing_video',
        CallLogKind.incomingVideo => 'chat_call_incoming_video',
        CallLogKind.missed => 'chat_call_missed',
        CallLogKind.noAnswer => 'chat_call_no_answer',
        CallLogKind.declined => 'chat_call_declined',
      };

  static IconData _callLogIcon(CallLogKind kind) => switch (kind) {
        CallLogKind.outgoing => Icons.call_made_rounded,
        CallLogKind.incoming => Icons.call_received_rounded,
        CallLogKind.outgoingVideo ||
        CallLogKind.incomingVideo =>
          Icons.videocam_rounded,
        CallLogKind.missed || CallLogKind.noAnswer => Icons.call_missed_rounded,
        CallLogKind.declined => Icons.call_end_rounded,
      };

  Widget _buildPendingTextMessageBubble(_PendingTextMessage pending) {
    final timeStr = _formatTime(pending.createdAt);
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 48),
        child: PhysicalShape(
          clipper: SenderBubbleClipper(),
          color: const Color(0xFF005C4B),
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 16, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (pending.replyTo != null)
                  ChatQuotedBubble(
                    reply: pending.replyTo!,
                    isMe: true,
                    onTap: () {},
                  ),
                Text(
                  pending.text,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeStr,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 9.5),
                    ),
                    const SizedBox(width: 4),
                    if (pending.isFailed)
                      GestureDetector(
                        onTap: () {
                          final authState = context.read<AuthCubit>().state;
                          final currentUid = authState is Authenticated
                              ? authState.profile.uid
                              : '';
                          final currentName = authState is Authenticated
                              ? authState.profile.displayName
                              : 'You';
                          _retryPendingTextMessage(
                              pending, currentUid, currentName);
                        },
                        child: const Icon(Icons.error_outline,
                            size: 14, color: Colors.redAccent),
                      )
                    else
                      const Icon(Icons.access_time,
                          size: 11, color: Colors.white54),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _sendMessage(String currentUid, String currentName) async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    // Handle Edit Mode
    if (_editingMessage != null) {
      final editDoc = _editingMessage!;
      setState(() => _editingMessage = null);
      _messageController.clear();
      try {
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(widget.chatId)
            .collection('messages')
            .doc(editDoc.id)
            .update({
          'text': text,
          'isEdited': true,
          'editedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        logError('Error editing message: $e');
      }
      return;
    }

    // Handle /split command
    if (text.toLowerCase().startsWith('/split ')) {
      final parts = text.substring(7).trim().split(' ');
      final amount = double.tryParse(parts.first) ?? 0.0;
      final splitTitle =
          parts.length > 1 ? parts.sublist(1).join(' ') : 'Shared Expense';
      if (amount > 0) {
        _messageController.clear();
        _sendExpenseMessage(amount, splitTitle, currentUid, currentName);
        return;
      }
    }

    _messageController.clear();
    _typingTimer?.cancel();
    if (_isTyping) {
      _isTyping = false;
      _updateTypingStatus(currentUid, false);
    }

    final replyPayload = _replyingMessage?.toMap();
    final replyModel = _replyingMessage;
    setState(() => _replyingMessage = null);

    // Reference & unique doc ID
    _ensureChatDocument(currentUid);
    final msgRef = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .doc();
    final msgId = msgRef.id;

    // Add optimistic pending message so user sees it in 0ms!
    final pendingMsg = _PendingTextMessage(
      id: msgId,
      text: text,
      replyTo: replyModel,
      createdAt: DateTime.now(),
    );
    setState(() {
      _pendingTextMessages.add(pendingMsg);
    });

    _scrollController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );

    final msgData = <String, dynamic>{
      'senderId': currentUid,
      'type': 'text',
      'text': text,
      if (replyPayload != null) 'replyTo': replyPayload,
      'seen': false,
      'status': 'sent', // delivery states: sent → delivered → read
      'timestamp': FieldValue.serverTimestamp(),
    };

    final resolvedOtherUid = _resolveOtherUid(currentUid);
    final chatRef =
        FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
    final chatMeta = _buildChatMeta(
      lastMessage: text,
      lastMessageType: 'text',
      currentUid: currentUid,
      currentName: currentName,
      resolvedOtherUid: resolvedOtherUid,
    );

    // 1. Direct VPS dispatch - 100% reliable, zero Firestore quota consumption
    if (resolvedOtherUid != null && resolvedOtherUid.isNotEmpty) {
      unawaited(VpsChatService().sendMessage(
        chatId: widget.chatId,
        recipientId: resolvedOtherUid,
        text: text,
        type: 'text',
        senderName: currentName,
        replyTo: replyPayload,
      ));
    }

    try {
      // 2. Direct write message to Firestore (best-effort)
      await msgRef.set(msgData);

      // Clean up optimistic pending entry
      if (mounted) {
        setState(() {
          _pendingTextMessages.removeWhere((p) => p.id == msgId);
        });
      }

      // Update chat metadata asynchronously without blocking
      chatRef.set(chatMeta, SetOptions(merge: true)).catchError((Object e) {
        logWarning('Chat metadata update failed: $e');
      });

      // Send in-app notification in background
      _sendNotificationToRecipient(
        recipientUid: resolvedOtherUid,
        currentUid: currentUid,
        currentName: currentName,
        body: text,
      );

      if (resolvedOtherUid == 'bhromon_ai_advisor') {
        _processAiResponse(currentUid, text);
      }
    } catch (e) {
      logWarning('Firestore message write error (delivered via VPS): $e');
      // If Firestore failed due to quota or network, clear pending message since VPS delivered it
      if (mounted) {
        setState(() {
          _pendingTextMessages.removeWhere((p) => p.id == msgId);
        });
      }
    }
  }

  void _processAiResponse(String currentUid, String userText) async {
    _updateTypingStatus('bhromon_ai_advisor', true);

    try {
      final responseText = await TravelAiService().getTravelAdvice(userText);

      final replyRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc();

      await replyRef.set({
        'senderId': 'bhromon_ai_advisor',
        'type': 'text',
        'text': responseText,
        'seen': false,
        'status': 'read',
        'timestamp': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .set({
        'lastMessage': responseText,
        'lastMessageType': 'text',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSenderId': 'bhromon_ai_advisor',
        'unreadCounts': {
          currentUid: FieldValue.increment(1),
        },
        'participantProfiles': {
          'bhromon_ai_advisor': {
            'displayName': 'Bhromon AI Guide',
          },
        },
      }, SetOptions(merge: true));
    } catch (e) {
      logError('Error in TravelAiService: $e');
    } finally {
      _updateTypingStatus('bhromon_ai_advisor', false);
    }
  }

  /// Uploads media picked via [pickResult] to Firebase Storage and writes a message.
  Future<void> _sendMediaMessage(
    MediaPickResult pickResult,
    String currentUid,
    String currentName, {
    String? caption,
    bool isViewOnce = false,
  }) async {
    final uploadId = const Uuid().v4();
    final type = pickResult.type;
    final file = pickResult.file;
    final xFile = pickResult.xFile;

    File? fileToUpload =
        file ?? (!kIsWeb && xFile.path.isNotEmpty ? File(xFile.path) : null);

    Uint8List? fileBytes;
    if (kIsWeb || fileToUpload == null) {
      try {
        fileBytes = await xFile.readAsBytes();
      } catch (e) {
        logWarning('Error reading media bytes for optimistic preview: $e');
      }
    }

    final pending = _PendingUpload(
      id: uploadId,
      file: fileToUpload,
      bytes: fileBytes,
      type: type,
    );
    setState(() => _pendingUploads.add(pending));

    Trace? uploadTrace;
    if (!kIsWeb) {
      try {
        uploadTrace = FirebasePerformance.instance.newTrace('media_upload');
        await uploadTrace.start();
        uploadTrace.putAttribute('mediaType', type);
      } catch (_) {}
    }

    try {
      // Ensure Firebase Auth token is fresh before uploading
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        try {
          await currentUser.getIdToken();
        } catch (e) {
          logWarning('Auth token refresh error: $e');
        }
      }

      if (!kIsWeb &&
          type == 'image' &&
          fileToUpload != null &&
          fileToUpload.existsSync()) {
        try {
          final tempDir = await getTemporaryDirectory();
          final compressedPath = '${tempDir.path}/${uploadId}_compressed.jpg';
          final compressed = await FlutterImageCompress.compressAndGetFile(
            fileToUpload.absolute.path,
            compressedPath,
            minWidth: 1200,
            minHeight: 1200,
            quality: 82,
            format: CompressFormat.jpeg,
          );
          if (compressed != null) {
            fileToUpload = File(compressed.path);
            pending.file = fileToUpload;
            logInfo('Image compressed: ${fileToUpload.lengthSync()} bytes');
          }
        } catch (e) {
          logWarning('Compression failed, using original: $e');
        }
      }

      final downloadUrl = await MediaUploadService.uploadXFile(
        file: xFile,
        tourOrChatId: widget.chatId,
        folder: 'chat_media',
        onProgress: (progress) {
          if (mounted) setState(() => pending.progress = progress);
        },
      );

      final resolvedOtherUid = _resolveOtherUid(currentUid);
      _ensureChatDocument(currentUid);
      final msgRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc();

      final replyPayload = _replyingMessage?.toMap();
      setState(() => _replyingMessage = null);

      final msgData = <String, dynamic>{
        'senderId': currentUid,
        'type': type,
        'text': caption ?? '',
        'mediaUrl': downloadUrl,
        if (replyPayload != null) 'replyTo': replyPayload,
        if (isViewOnce) 'isViewOnce': true,
        if (isViewOnce) 'isOpened': false,
        'seen': false,
        'status': 'sent',
        'timestamp': FieldValue.serverTimestamp(),
      };

      final lastMsg = type == 'image'
          ? (caption != null && caption.isNotEmpty ? '📷 $caption' : '📷 Photo')
          : (caption != null && caption.isNotEmpty
              ? '🎬 $caption'
              : '🎬 Video');
      final chatRef =
          FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
      final chatMeta = _buildChatMeta(
        lastMessage: lastMsg,
        lastMessageType: type,
        currentUid: currentUid,
        currentName: currentName,
        resolvedOtherUid: resolvedOtherUid,
      );

      if (resolvedOtherUid != null && resolvedOtherUid.isNotEmpty) {
        unawaited(VpsChatService().sendMessage(
          chatId: widget.chatId,
          recipientId: resolvedOtherUid,
          text: caption ?? '',
          type: type,
          senderName: currentName,
          mediaUrl: downloadUrl,
          replyTo: replyPayload,
        ));
      }

      try {
        await msgRef.set(msgData);
        chatRef.set(chatMeta, SetOptions(merge: true)).catchError((Object e) {
          logWarning('Chat metadata update failed: $e');
        });

        _sendNotificationToRecipient(
          recipientUid: resolvedOtherUid,
          currentUid: currentUid,
          currentName: currentName,
          body: lastMsg,
        );
      } catch (e) {
        logWarning('Firestore media write skipped/quota: $e');
      }
    } catch (e) {
      logError('Media upload error: $e');
      String msg = 'Failed to send media.';
      if (e is FirebaseException &&
          e.message != null &&
          e.message!.isNotEmpty) {
        msg = 'Failed to send media: ${e.message}';
      } else {
        msg =
            'Failed to send media: ${e.toString().replaceAll(RegExp(r'\[.*?\]'), '').trim()}';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      try {
        await uploadTrace?.stop();
      } catch (_) {}
      if (mounted) {
        setState(() => _pendingUploads.removeWhere((p) => p.id == uploadId));
      }
    }
  }

  /// Uploads a recorded voice message to Firebase Storage and records it in Firestore.
  Future<void> _sendVoiceMessage(
    String filePath,
    Duration duration,
    String currentUid,
    String currentName,
  ) async {
    final uploadId = const Uuid().v4();
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        try {
          await currentUser.getIdToken();
        } catch (e) {
          logWarning('Auth token refresh error: $e');
        }
      }

      final Uint8List voiceBytes = kIsWeb
          ? await XFile(filePath).readAsBytes()
          : await File(filePath).readAsBytes();

      final cleanUploadId = uploadId.replaceAll('-', '');
      final downloadUrl = await MediaUploadService.uploadBytes(
        bytes: voiceBytes,
        path: 'chat_voice/${widget.chatId}/$cleanUploadId.m4a',
        contentType: 'audio/mp4',
      );

      final resolvedOtherUid = _resolveOtherUid(currentUid);
      _ensureChatDocument(currentUid);
      final msgRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc();

      final replyPayload = _replyingMessage?.toMap();
      setState(() => _replyingMessage = null);

      final msgData = <String, dynamic>{
        'senderId': currentUid,
        'type': 'audio',
        'text': '',
        'mediaUrl': downloadUrl,
        'durationSeconds': duration.inSeconds,
        if (replyPayload != null) 'replyTo': replyPayload,
        'seen': false,
        'status': 'sent',
        'timestamp': FieldValue.serverTimestamp(),
      };

      final chatRef =
          FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
      final chatMeta = _buildChatMeta(
        lastMessage: '🎤 Voice message',
        lastMessageType: 'audio',
        currentUid: currentUid,
        currentName: currentName,
        resolvedOtherUid: resolvedOtherUid,
      );

      if (resolvedOtherUid != null && resolvedOtherUid.isNotEmpty) {
        unawaited(VpsChatService().sendMessage(
          chatId: widget.chatId,
          recipientId: resolvedOtherUid,
          text: '🎤 Voice message',
          type: 'audio',
          senderName: currentName,
          mediaUrl: downloadUrl,
          replyTo: replyPayload,
          metadata: {'durationSeconds': duration.inSeconds},
        ));
      }

      try {
        await msgRef.set(msgData);
        chatRef.set(chatMeta, SetOptions(merge: true)).catchError((Object e) {
          logWarning('Chat metadata update failed: $e');
        });

        _sendNotificationToRecipient(
          recipientUid: resolvedOtherUid,
          currentUid: currentUid,
          currentName: currentName,
          body: '🎤 Voice message (${duration.inSeconds}s)',
        );
      } catch (e) {
        logWarning('Firestore voice message skipped/quota: $e');
      }
    } catch (e) {
      logError('Error sending voice message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Failed to send voice message: ${e.toString().replaceAll(RegExp(r'\[.*?\]'), '').trim()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _sendDocumentMessage(
    PlatformFile pFile,
    String currentUid,
    String currentName,
  ) async {
    final uploadId = const Uuid().v4();
    try {
      final Uint8List docBytes;
      if (pFile.bytes != null) {
        docBytes = pFile.bytes!;
      } else if (!kIsWeb && pFile.path != null && pFile.path!.isNotEmpty) {
        docBytes = await File(pFile.path!).readAsBytes();
      } else {
        logError('Could not read the picked file: ${pFile.name}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not read this file. Please try again.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      final cleanUploadId = uploadId.replaceAll('-', '');
      final ext = pFile.extension != null && pFile.extension!.isNotEmpty
          ? '.${pFile.extension!.toLowerCase()}'
          : (pFile.name.contains('.')
              ? '.${pFile.name.split('.').last.toLowerCase()}'
              : '.bin');
      final downloadUrl = await MediaUploadService.uploadBytes(
        bytes: docBytes,
        path: 'chat_docs/${widget.chatId}/$cleanUploadId$ext',
        contentType: 'application/octet-stream',
      );

      final resolvedOtherUid = _resolveOtherUid(currentUid);
      _ensureChatDocument(currentUid);
      final msgRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc();

      final replyPayload = _replyingMessage?.toMap();
      setState(() => _replyingMessage = null);

      final msgData = <String, dynamic>{
        'senderId': currentUid,
        'type': 'document',
        'text': pFile.name,
        'fileName': pFile.name,
        'fileSizeBytes': pFile.size,
        'documentUrl': downloadUrl,
        if (replyPayload != null) 'replyTo': replyPayload,
        'seen': false,
        'status': 'sent',
        'timestamp': FieldValue.serverTimestamp(),
      };

      final chatRef =
          FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
      final chatMeta = _buildChatMeta(
        lastMessage: '📄 ${pFile.name}',
        lastMessageType: 'document',
        currentUid: currentUid,
        currentName: currentName,
        resolvedOtherUid: resolvedOtherUid,
      );

      if (resolvedOtherUid != null && resolvedOtherUid.isNotEmpty) {
        unawaited(VpsChatService().sendMessage(
          chatId: widget.chatId,
          recipientId: resolvedOtherUid,
          text: pFile.name,
          type: 'document',
          senderName: currentName,
          mediaUrl: downloadUrl,
          replyTo: replyPayload,
          metadata: {'fileName': pFile.name, 'fileSizeBytes': pFile.size},
        ));
      }

      try {
        await msgRef.set(msgData);
        chatRef.set(chatMeta, SetOptions(merge: true)).catchError((Object e) {
          logWarning('Chat metadata update failed: $e');
        });

        _sendNotificationToRecipient(
          recipientUid: resolvedOtherUid,
          currentUid: currentUid,
          currentName: currentName,
          body: '📄 ${pFile.name}',
        );
      } catch (e) {
        logWarning('Firestore document message skipped/quota: $e');
      }
    } catch (e) {
      logError('Error sending document: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send document: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _sendLocationMessage(
    Position pos,
    String title,
    String currentUid,
    String currentName,
  ) async {
    try {
      final resolvedOtherUid = _resolveOtherUid(currentUid);
      _ensureChatDocument(currentUid);
      final msgRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc();

      final replyPayload = _replyingMessage?.toMap();
      setState(() => _replyingMessage = null);

      final msgData = <String, dynamic>{
        'senderId': currentUid,
        'type': 'location',
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'title': title,
        'address':
            '${pos.latitude.toStringAsFixed(4)}° N, ${pos.longitude.toStringAsFixed(4)}° E',
        if (replyPayload != null) 'replyTo': replyPayload,
        'seen': false,
        'status': 'sent',
        'timestamp': FieldValue.serverTimestamp(),
      };

      final chatRef =
          FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
      final chatMeta = _buildChatMeta(
        lastMessage: '📍 Shared location: $title',
        lastMessageType: 'location',
        currentUid: currentUid,
        currentName: currentName,
        resolvedOtherUid: resolvedOtherUid,
      );

      if (resolvedOtherUid != null && resolvedOtherUid.isNotEmpty) {
        unawaited(VpsChatService().sendMessage(
          chatId: widget.chatId,
          recipientId: resolvedOtherUid,
          text: '📍 Shared location: $title',
          type: 'location',
          senderName: currentName,
          replyTo: replyPayload,
          metadata: {
            'latitude': pos.latitude,
            'longitude': pos.longitude,
            'title': title,
            'address':
                '${pos.latitude.toStringAsFixed(4)}° N, ${pos.longitude.toStringAsFixed(4)}° E',
          },
        ));
      }

      try {
        await msgRef.set(msgData);
        chatRef.set(chatMeta, SetOptions(merge: true)).catchError((Object e) {
          logWarning('Chat metadata update failed: $e');
        });

        _sendNotificationToRecipient(
          recipientUid: resolvedOtherUid,
          currentUid: currentUid,
          currentName: currentName,
          body: '📍 Shared location: $title',
        );
      } catch (e) {
        logWarning('Firestore location message skipped/quota: $e');
      }
    } catch (e) {
      logError('Error sending location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share location: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _sendExpenseMessage(
    double amount,
    String expenseTitle,
    String currentUid,
    String currentName,
  ) async {
    try {
      final resolvedOtherUid = _resolveOtherUid(currentUid);
      _ensureChatDocument(currentUid);
      final msgRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc();

      final replyPayload = _replyingMessage?.toMap();
      setState(() => _replyingMessage = null);

      final msgData = <String, dynamic>{
        'senderId': currentUid,
        'type': 'expense',
        'amount': amount,
        'expenseTitle': expenseTitle,
        'paidById': currentUid,
        'paidByName': currentName,
        'isSettled': false,
        if (replyPayload != null) 'replyTo': replyPayload,
        'seen': false,
        'status': 'sent',
        'timestamp': FieldValue.serverTimestamp(),
      };

      final chatRef =
          FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
      final chatMeta = _buildChatMeta(
        lastMessage: '৳${amount.toStringAsFixed(0)} Split: $expenseTitle',
        lastMessageType: 'expense',
        currentUid: currentUid,
        currentName: currentName,
        resolvedOtherUid: resolvedOtherUid,
      );

      if (resolvedOtherUid != null && resolvedOtherUid.isNotEmpty) {
        unawaited(VpsChatService().sendMessage(
          chatId: widget.chatId,
          recipientId: resolvedOtherUid,
          text: '৳${amount.toStringAsFixed(0)} Split: $expenseTitle',
          type: 'expense',
          senderName: currentName,
          replyTo: replyPayload,
          metadata: {
            'amount': amount,
            'expenseTitle': expenseTitle,
            'paidById': currentUid,
            'paidByName': currentName,
          },
        ));
      }

      try {
        await msgRef.set(msgData);
        chatRef.set(chatMeta, SetOptions(merge: true)).catchError((Object e) {
          logWarning('Chat metadata update failed: $e');
        });

        _sendNotificationToRecipient(
          recipientUid: resolvedOtherUid,
          currentUid: currentUid,
          currentName: currentName,
          body: '৳${amount.toStringAsFixed(0)} Split: $expenseTitle',
        );
      } catch (e) {
        logWarning('Firestore expense message skipped/quota: $e');
      }
    } catch (e) {
      logError('Error sending expense split: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send expense: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _openAttachmentSheet(String currentUid, String currentName) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ChatAttachmentSheet(
        onDocumentPicked: (file) =>
            _sendDocumentMessage(file, currentUid, currentName),
        onMediaPicked: (file, isVideo) =>
            _openMediaCaptionFlow(file, isVideo, currentUid, currentName),
        onAudioPicked: (audioFile) =>
            _sendDocumentMessage(audioFile, currentUid, currentName),
        onLocationPicked: (pos, title) =>
            _sendLocationMessage(pos, title, currentUid, currentName),
        onExpenseSplit: () => _showSplitBillDialog(currentUid, currentName),
      ),
    );
  }

  void _openMediaCaptionFlow(
    XFile file,
    bool isVideo,
    String currentUid,
    String currentName,
  ) async {
    final result = await Navigator.of(context).push<MediaCaptionResult>(
      MaterialPageRoute(
        builder: (ctx) => ChatMediaCaptionScreen(
          file: file,
          isVideo: isVideo,
        ),
      ),
    );

    if (result != null) {
      _sendMediaMessage(
        MediaPickResult(
          file: !kIsWeb ? File(result.file.path) : null,
          xFile: result.file,
          type: isVideo ? 'video' : 'image',
        ),
        currentUid,
        currentName,
        caption: result.caption,
        isViewOnce: result.isViewOnce,
      );
    }
  }

  Future<void> _openCameraDirect(String currentUid, String currentName) async {
    try {
      final picker = ImagePicker();
      final photo =
          await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (photo != null) {
        _openMediaCaptionFlow(photo, false, currentUid, currentName);
      }
    } catch (e) {
      logError('Error opening camera: $e');
    }
  }

  void _showSplitBillDialog(String currentUid, String currentName) {
    final amountController = TextEditingController();
    final titleController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2C34),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.payments_outlined, color: Color(0xFF00A884)),
            SizedBox(width: 8),
            Text('Split Travel Bill',
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Total Amount (BDT)',
                labelStyle: TextStyle(color: Colors.white70),
                prefixText: '৳ ',
                prefixStyle: TextStyle(
                    color: Color(0xFF00A884), fontWeight: FontWeight.bold),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF00A884))),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: titleController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Expense Title (e.g. Dinner, Boat Ride)',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF00A884))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child:
                const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A884),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              final amt = double.tryParse(amountController.text.trim()) ?? 0.0;
              final t = titleController.text.trim();
              if (amt > 0) {
                Navigator.pop(dialogCtx);
                _sendExpenseMessage(amt, t.isNotEmpty ? t : 'Travel Expense',
                    currentUid, currentName);
              }
            },
            child: const Text('SPLIT 50/50',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showDisappearingMessagesSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1F2C34),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StreamBuilder<DocumentSnapshot>(
          stream: _chatDocStream,
          builder: (context, snapshot) {
            final data = snapshot.data?.data() as Map<String, dynamic>?;
            final currentSeconds =
                (data?['disappearingTimerSeconds'] as num?)?.toInt() ?? 0;

            final options = [
              {'label': '24 hours', 'seconds': 86400},
              {'label': '7 days', 'seconds': 604800},
              {'label': '90 days', 'seconds': 7776000},
              {'label': 'Off', 'seconds': 0},
            ];

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.timer_outlined,
                          color: Color(0xFF00A884), size: 24),
                      SizedBox(width: 12),
                      Text(
                        'Disappearing messages',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'For more privacy and storage, new messages will disappear from this chat for everyone after the selected duration.',
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  ...options.map((opt) {
                    final isSelected = currentSeconds == opt['seconds'];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        opt['label'] as String,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 15),
                      ),
                      trailing: Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: isSelected
                            ? const Color(0xFF00A884)
                            : Colors.white38,
                      ),
                      onTap: () {
                        FirebaseFirestore.instance
                            .collection('chats')
                            .doc(widget.chatId)
                            .update({
                          'disappearingTimerSeconds': opt['seconds'],
                        });
                        Navigator.pop(ctx);
                      },
                    );
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _setReplyToMessage(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final type = (data['type'] as String?) ?? 'text';
    final text = (data['text'] as String?) ?? '';
    final mediaUrl = data['mediaUrl'] as String?;
    final senderId = (data['senderId'] as String?) ?? '';
    final authState = context.read<AuthCubit>().state;
    final currentUid = authState is Authenticated ? authState.profile.uid : '';

    final senderName = senderId == currentUid
        ? 'You'
        : (data['senderName'] as String? ?? 'Traveler');

    setState(() {
      _replyingMessage = ReplyMessageInfo(
        messageId: doc.id,
        senderId: senderId,
        senderName: senderName,
        text: text,
        type: type,
        mediaUrl: mediaUrl,
      );
    });
  }

  void _startEditingMessage(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final text = (data['text'] as String?) ?? '';
    setState(() {
      _editingMessage = doc;
      _messageController.text = text;
      _selectedMessageIds.clear();
    });
  }

  void _scrollToMessage(String messageId) {
    final idx = _visibleMessages.indexWhere((d) => d.id == messageId);
    if (idx != -1) {
      _scrollController.animateTo(
        idx * 60.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _highlightedMessageId = messageId);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _highlightedMessageId = null);
      });
    }
  }

  void _toggleReaction(
      QueryDocumentSnapshot doc, String emoji, String currentUid) async {
    setState(() => _reactionTargetDoc = null);
    final data = doc.data() as Map<String, dynamic>?;
    final reactions = Map<String, dynamic>.from(
        (data?['reactions'] as Map<String, dynamic>?) ?? {});
    final currentReaction = reactions[currentUid];

    if (currentReaction == emoji) {
      try {
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(widget.chatId)
            .collection('messages')
            .doc(doc.id)
            .update({'reactions.$currentUid': FieldValue.delete()});
      } catch (e) {
        logError('Error removing reaction: $e');
      }
    } else {
      try {
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(widget.chatId)
            .collection('messages')
            .doc(doc.id)
            .update({'reactions.$currentUid': emoji});
      } catch (e) {
        logError('Error adding reaction: $e');
      }
    }
  }

  void _toggleStarSelectedMessages(String currentUid) async {
    for (final docId in _selectedMessageIds) {
      try {
        final doc = _allMessages.firstWhere((d) => d.id == docId);
        final data = doc.data() as Map<String, dynamic>?;
        final starredBy = (data?['starredBy'] as Map<String, dynamic>?) ?? {};
        final isStarred = starredBy[currentUid] == true;

        await FirebaseFirestore.instance
            .collection('chats')
            .doc(widget.chatId)
            .collection('messages')
            .doc(docId)
            .update({
          'isStarred': !isStarred,
          'starredBy.$currentUid': isStarred ? FieldValue.delete() : true,
        });
      } catch (e) {
        logError('Error toggling star: $e');
      }
    }
    setState(() => _selectedMessageIds.clear());
  }

  void _copySelectedMessages() {
    final texts = <String>[];
    for (final docId in _selectedMessageIds) {
      try {
        final doc = _allMessages.firstWhere((d) => d.id == docId);
        final data = doc.data() as Map<String, dynamic>?;
        final text = data?['text'] as String? ?? '';
        if (text.isNotEmpty) texts.add(text);
      } catch (_) {}
    }
    if (texts.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: texts.join('\n\n')));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copied to clipboard'),
          backgroundColor: Color(0xFF00A884),
          duration: Duration(seconds: 2),
        ),
      );
    }
    setState(() => _selectedMessageIds.clear());
  }

  void _pinSelectedMessage() async {
    if (_selectedMessageIds.isEmpty) return;
    final docId = _selectedMessageIds.first;
    try {
      final doc = _allMessages.firstWhere((d) => d.id == docId);
      final data = doc.data() as Map<String, dynamic>?;
      final text = (data?['text'] as String?) ?? 'Media';

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .set({
        'pinnedMessage': {
          'id': docId,
          'text': text,
          'pinnedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message pinned to top'),
            backgroundColor: Color(0xFF00A884),
          ),
        );
      }
    } catch (e) {
      logError('Error pinning message: $e');
    }
    setState(() => _selectedMessageIds.clear());
  }

  void _openForwardDialog(String currentUid) {
    if (_selectedMessageIds.isEmpty) return;
    final docId = _selectedMessageIds.first;
    final doc = _allMessages.firstWhere((d) => d.id == docId);
    final data = doc.data() as Map<String, dynamic>;
    final text = (data['text'] as String?) ?? '';
    final type = (data['type'] as String?) ?? 'text';
    final mediaUrl = data['mediaUrl'] as String?;

    showDialog<void>(
      context: context,
      builder: (ctx) => ChatForwardDialog(
        currentUid: currentUid,
        forwardText: text,
        forwardType: type,
        forwardMediaUrl: mediaUrl,
        onForward: (targetChatId) =>
            _forwardMessage(targetChatId, text, type, mediaUrl, currentUid),
      ),
    );
  }

  void _forwardMessage(String targetChatId, String text, String type,
      String? mediaUrl, String currentUid) async {
    setState(() => _selectedMessageIds.clear());
    try {
      _ensureChatDocument(currentUid);
      final msgRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(targetChatId)
          .collection('messages')
          .doc();

      await msgRef.set({
        'senderId': currentUid,
        'type': type,
        'text': text,
        if (mediaUrl != null && mediaUrl.isNotEmpty) 'mediaUrl': mediaUrl,
        'isForwarded': true,
        'seen': false,
        'status': 'sent',
        'timestamp': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(targetChatId)
          .set({
        'lastMessage':
            text.isNotEmpty ? text : (type == 'image' ? '📷 Photo' : 'Message'),
        'lastMessageType': type,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSenderId': currentUid,
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message forwarded!'),
            backgroundColor: Color(0xFF00A884),
          ),
        );
      }
    } catch (e) {
      logError('Error forwarding message: $e');
    }
  }

  void _deleteSelectedMessages(String currentUid) {
    if (_selectedMessageIds.isEmpty) return;
    final docId = _selectedMessageIds.first;
    final doc = _allMessages.firstWhere((d) => d.id == docId);
    final data = doc.data() as Map<String, dynamic>;
    final isMe = data['senderId'] == currentUid;
    setState(() => _selectedMessageIds.clear());
    _showDeleteMessageDialog(doc, isMe);
  }

  void _onSearchQueryChanged(String query) {
    final q = query.trim().toLowerCase();
    _matchingIndices.clear();
    if (q.isNotEmpty) {
      final docs = _visibleMessages;
      for (int i = 0; i < docs.length; i++) {
        final data = docs[i].data() as Map<String, dynamic>;
        final text = (data['text'] as String?)?.toLowerCase() ?? '';
        if (text.contains(q)) {
          _matchingIndices.add(i);
        }
      }
    }
    setState(() {
      _searchMatchIndex = 0;
    });
    if (_matchingIndices.isNotEmpty) {
      _scrollToSearchMatch();
    }
  }

  void _navigateSearchMatch(bool next) {
    if (_matchingIndices.isEmpty) return;
    setState(() {
      if (next) {
        _searchMatchIndex = (_searchMatchIndex + 1) % _matchingIndices.length;
      } else {
        _searchMatchIndex = (_searchMatchIndex - 1 + _matchingIndices.length) %
            _matchingIndices.length;
      }
    });
    _scrollToSearchMatch();
  }

  void _scrollToSearchMatch() {
    if (_matchingIndices.isEmpty) return;
    final listIdx = _matchingIndices[_searchMatchIndex];
    _scrollController.animateTo(
      listIdx * 60.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// Initiates an outgoing WebRTC P2P audio or video call.
  void _initiateCall({
    required bool isVideo,
    required String currentUid,
    required String otherUid,
    required String otherName,
    required String? avatarUrl,
    String? localUserName,
    String? localAvatarUrl,
  }) {
    if (otherUid == 'bhromon_ai_advisor') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Voice and Video calls with the AI Guide are coming soon! Chat with text anytime.'),
          backgroundColor: Color(0xFF1F2C34),
        ),
      );
      return;
    }

    if (_sharedTourId == null || _otherEmail == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can only call members of a tour you share.'),
          backgroundColor: Color(0xFF1F2C34),
        ),
      );
      return;
    }

    final callId = const Uuid().v4();
    context.push(
      '/call/$callId',
      extra: {
        'localUid': currentUid,
        'remoteUid': otherUid,
        'remoteEmail': _otherEmail,
        'sharedTourId': _sharedTourId,
        'remoteUserName': otherName,
        'remoteAvatarUrl': avatarUrl,
        'isCaller': true,
        'isVideoCall': isVideo,
        'localUserName': localUserName,
        'localAvatarUrl': localAvatarUrl,
      },
    );
  }

  /// Marks all unread incoming messages as seen and updates delivery status to 'read'.
  void _markMessagesAsSeen(
      List<QueryDocumentSnapshot> docs, String currentUid) {
    if (currentUid.isEmpty) return;
    final unreadDocs = docs.where((doc) {
      if (_markedSeenDocIds.contains(doc.id)) return false;
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return false;
      final senderId = data['senderId'] ?? '';
      final bool seen = data['seen'] as bool? ?? false;
      return senderId != currentUid && !seen;
    }).toList();

    if (unreadDocs.isNotEmpty) {
      for (final doc in unreadDocs) {
        _markedSeenDocIds.add(doc.id);
      }
      final resolvedOther = _resolveOtherUid(currentUid);
      VpsChatService().markRead(
        widget.chatId,
        recipientId: resolvedOther,
        messageIds: unreadDocs.map((d) => d.id).toList(),
      );
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in unreadDocs) {
        batch.update(doc.reference, {
          'seen': true,
          'status': 'read',
          'readAt': FieldValue.serverTimestamp(),
        });
      }
      final chatRef =
          FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
      batch.set(
          chatRef,
          {
            'unreadCounts': {
              currentUid: 0,
            }
          },
          SetOptions(merge: true));
      batch.commit().catchError((Object e) {
        logWarning('Error marking messages as seen: $e');
      });
    }
  }

  /// Returns a human-readable time string, e.g. "6:42 PM".
  String _formatTime(DateTime date) {
    final hour = date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:$minute $suffix';
  }

  List<QueryDocumentSnapshot> get _visibleMessages {
    final authState = context.read<AuthCubit>().state;
    final currentUid = authState is Authenticated ? authState.profile.uid : '';
    return _allMessages.where((doc) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return true;
      final deletedFor = data['deletedFor'] as List<dynamic>? ?? [];
      if (deletedFor.contains(currentUid)) return false;

      // Disappearing message filter
      if (_disappearingTimerSeconds > 0) {
        final ts = (data['timestamp'] as Timestamp?)?.toDate();
        if (ts != null &&
            DateTime.now().difference(ts).inSeconds >
                _disappearingTimerSeconds) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  void _showDeleteMessageDialog(QueryDocumentSnapshot doc, bool isMe) {
    final authState = context.read<AuthCubit>().state;
    final currentUid = authState is Authenticated ? authState.profile.uid : '';
    final data = doc.data() as Map<String, dynamic>?;
    final bool isAlreadyDeleted =
        (data?['type'] == 'deleted' || data?['isDeleted'] == true);

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1F2C34),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Message?',
            style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        content: const Text(
          'Do you want to delete this message?',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL',
                style: TextStyle(color: Color(0xFF00A884))),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await FirebaseFirestore.instance
                    .collection('chats')
                    .doc(widget.chatId)
                    .collection('messages')
                    .doc(doc.id)
                    .update({
                  'deletedFor': FieldValue.arrayUnion([currentUid])
                });
                setState(() {
                  _allMessages.removeWhere((d) => d.id == doc.id);
                });
              } catch (e) {
                logError('Error deleting for me: $e');
              }
            },
            child: const Text('DELETE FOR ME',
                style: TextStyle(color: Colors.redAccent)),
          ),
          if (isMe && !isAlreadyDeleted)
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                try {
                  await FirebaseFirestore.instance
                      .collection('chats')
                      .doc(widget.chatId)
                      .collection('messages')
                      .doc(doc.id)
                      .update({
                    'type': 'deleted',
                    'text': 'This message was deleted',
                    'isDeleted': true,
                    'deletedAt': FieldValue.serverTimestamp(),
                  });
                } catch (e) {
                  logError('Error deleting for everyone: $e');
                }
              },
              child: const Text('DELETE FOR EVERYONE',
                  style: TextStyle(color: Colors.redAccent)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    final currentUid =
        authState is Authenticated ? authState.profile.uid : 'explorer_user';
    final currentName =
        authState is Authenticated ? authState.profile.displayName : 'Explorer';
    final currentAvatarUrl =
        authState is Authenticated ? authState.profile.avatarUrl : null;
    final resolvedOtherUid = _resolveOtherUid(currentUid) ?? 'guest';

    // ── Stream: Retrieve profile of the other explorer ──
    final profileStream = _otherProfileStream(resolvedOtherUid);

    return StreamBuilder<DocumentSnapshot>(
      stream: profileStream,
      builder: (context, profileSnap) {
        final profileData = profileSnap.data?.data() as Map<String, dynamic>?;
        final String otherName = resolvedOtherUid == 'bhromon_ai_advisor'
            ? 'Bhromon AI Guide'
            : (profileData?['displayName'] as String? ??
                'Traveler ${resolvedOtherUid.substring(0, math.min(resolvedOtherUid.length, 6))}');
        final String? avatarUrl = resolvedOtherUid == 'bhromon_ai_advisor'
            ? null
            : (profileData?['avatarUrl'] as String?);
        final initials = resolvedOtherUid == 'bhromon_ai_advisor'
            ? 'AI'
            : (otherName.length > 2
                ? otherName.substring(0, 2).toUpperCase()
                : 'TR');

        final bool hasSubState = _showEmojiPicker ||
            _selectedMessageIds.isNotEmpty ||
            _isSearchingInChat;

        return PopScope(
          canPop: !hasSubState && context.canPop(),
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_showEmojiPicker) {
              setState(() => _showEmojiPicker = false);
              return;
            }
            if (_selectedMessageIds.isNotEmpty) {
              setState(() {
                _selectedMessageIds.clear();
                _reactionTargetDoc = null;
              });
              return;
            }
            if (_isSearchingInChat) {
              setState(() {
                _isSearchingInChat = false;
                _searchController.clear();
                _matchingIndices.clear();
              });
              return;
            }
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/chats');
            }
          },
          child: Scaffold(
            backgroundColor:
                const Color(0xFF0B141A), // WhatsApp wallpaper base color
            appBar: _selectedMessageIds.isNotEmpty
                ? AppBar(
                    backgroundColor: const Color(0xFF1F2C34),
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => setState(() {
                        _selectedMessageIds.clear();
                        _reactionTargetDoc = null;
                      }),
                    ),
                    title: Text(
                      '${_selectedMessageIds.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    actions: [
                      if (_selectedMessageIds.length == 1) ...[
                        IconButton(
                          icon: const Icon(Icons.reply, color: Colors.white),
                          tooltip: 'Reply',
                          onPressed: () {
                            final doc = _allMessages.firstWhere(
                                (d) => d.id == _selectedMessageIds.first);
                            _setReplyToMessage(doc);
                            setState(() {
                              _selectedMessageIds.clear();
                              _reactionTargetDoc = null;
                            });
                          },
                        ),
                        Builder(builder: (context) {
                          final doc = _allMessages.firstWhere(
                              (d) => d.id == _selectedMessageIds.first);
                          final data = doc.data() as Map<String, dynamic>;
                          final isMe = data['senderId'] == currentUid;
                          final isText = data['type'] == 'text';
                          final ts = data['timestamp'] as Timestamp?;
                          final isWithin15Min = ts != null &&
                              DateTime.now()
                                      .difference(ts.toDate())
                                      .inMinutes <=
                                  15;
                          if (isMe && isText && isWithin15Min) {
                            return IconButton(
                              icon: const Icon(Icons.edit, color: Colors.white),
                              tooltip: 'Edit',
                              onPressed: () => _startEditingMessage(doc),
                            );
                          }
                          return const SizedBox.shrink();
                        }),
                        IconButton(
                          icon: const Icon(Icons.push_pin_outlined,
                              color: Colors.white),
                          tooltip: 'Pin',
                          onPressed: _pinSelectedMessage,
                        ),
                      ],
                      IconButton(
                        icon:
                            const Icon(Icons.star_outline, color: Colors.white),
                        tooltip: 'Star',
                        onPressed: () =>
                            _toggleStarSelectedMessages(currentUid),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.white),
                        tooltip: 'Delete',
                        onPressed: () => _deleteSelectedMessages(currentUid),
                      ),
                      IconButton(
                        icon: const Icon(Icons.forward, color: Colors.white),
                        tooltip: 'Forward',
                        onPressed: () => _openForwardDialog(currentUid),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, color: Colors.white),
                        tooltip: 'Copy',
                        onPressed: _copySelectedMessages,
                      ),
                    ],
                  )
                : _isSearchingInChat
                    ? AppBar(
                        backgroundColor: const Color(0xFF1F2C34),
                        leading: IconButton(
                          icon:
                              const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => setState(() {
                            _isSearchingInChat = false;
                            _searchController.clear();
                            _matchingIndices.clear();
                          }),
                        ),
                        title: TextField(
                          controller: _searchController,
                          autofocus: true,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                          decoration: const InputDecoration(
                            hintText: 'Search in conversation...',
                            hintStyle:
                                TextStyle(color: Colors.white38, fontSize: 14),
                            border: InputBorder.none,
                          ),
                          onChanged: _onSearchQueryChanged,
                        ),
                        actions: [
                          if (_matchingIndices.isNotEmpty) ...[
                            Center(
                              child: Text(
                                '${_searchMatchIndex + 1}/${_matchingIndices.length}',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.keyboard_arrow_up,
                                  color: Colors.white),
                              onPressed: () => _navigateSearchMatch(false),
                            ),
                            IconButton(
                              icon: const Icon(Icons.keyboard_arrow_down,
                                  color: Colors.white),
                              onPressed: () => _navigateSearchMatch(true),
                            ),
                          ],
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => setState(() {
                              _isSearchingInChat = false;
                              _searchController.clear();
                              _matchingIndices.clear();
                            }),
                          ),
                        ],
                      )
                    : AppBar(
                        backgroundColor:
                            const Color(0xFF1F2C34), // WhatsApp slate dark
                        elevation: 1.5,
                        leadingWidth: 90,
                        leading: Row(
                          children: [
                            const SizedBox(width: 4),
                            IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.arrow_back,
                                  color: Colors.white),
                              onPressed: () {
                                if (context.canPop()) {
                                  context.pop();
                                } else {
                                  context.go('/chats');
                                }
                              },
                            ),
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: const Color(0xFF005C4B),
                              backgroundImage:
                                  (avatarUrl != null && avatarUrl.isNotEmpty)
                                      ? sizedImage(NetworkImage(avatarUrl),
                                          context.decodeWidth(36))
                                      : null,
                              child: (avatarUrl == null || avatarUrl.isEmpty)
                                  ? Text(initials,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11))
                                  : null,
                            ),
                          ],
                        ),
                        titleSpacing: 8,
                        title: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  otherName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (_disappearingTimerSeconds > 0)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 4),
                                    child: Icon(Icons.timer_outlined,
                                        size: 13, color: Colors.white70),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            // Typing / Online status stream
                            StreamBuilder<DocumentSnapshot>(
                              stream: _chatDocStream,
                              builder: (context, chatSnap) {
                                final data = chatSnap.data?.data()
                                    as Map<String, dynamic>?;
                                final bool isOtherTyping =
                                    (data?['typing_$resolvedOtherUid']
                                            as bool?) ??
                                        false;
                                return Text(
                                  isOtherTyping
                                      ? context.l10n
                                          .translate('chat_status_typing')
                                      : context.l10n.translate(_otherOnline
                                          ? 'chat_status_online'
                                          : 'chat_status_offline'),
                                  style: TextStyle(
                                    color: isOtherTyping
                                        ? const Color(0xFF00A884)
                                        : Colors.white54,
                                    fontSize: 10,
                                    fontWeight: isOtherTyping
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        actions: [
                          IconButton(
                            icon: const Icon(Icons.call,
                                color: Colors.white, size: 21),
                            tooltip: 'Audio Call',
                            onPressed: () => _initiateCall(
                              isVideo: false,
                              currentUid: currentUid,
                              otherUid: resolvedOtherUid,
                              otherName: otherName,
                              avatarUrl: avatarUrl,
                              localUserName: currentName,
                              localAvatarUrl: currentAvatarUrl,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.videocam,
                                color: Colors.white, size: 23),
                            tooltip: 'Video Call',
                            onPressed: () => _initiateCall(
                              isVideo: true,
                              currentUid: currentUid,
                              otherUid: resolvedOtherUid,
                              otherName: otherName,
                              avatarUrl: avatarUrl,
                              localUserName: currentName,
                              localAvatarUrl: currentAvatarUrl,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.search,
                                color: Colors.white, size: 21),
                            tooltip: 'Search in conversation',
                            onPressed: () =>
                                setState(() => _isSearchingInChat = true),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert,
                                color: Colors.white, size: 20),
                            color: const Color(0xFF1F2C34),
                            onSelected: (val) {
                              if (val == 'search') {
                                setState(() => _isSearchingInChat = true);
                              } else if (val == 'split') {
                                _showSplitBillDialog(currentUid, currentName);
                              } else if (val == 'disappearing') {
                                _showDisappearingMessagesSheet(context);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'search',
                                child: Text('Search',
                                    style: TextStyle(color: Colors.white)),
                              ),
                              const PopupMenuItem(
                                value: 'split',
                                child: Text('Split Travel Bill',
                                    style: TextStyle(color: Colors.white)),
                              ),
                              const PopupMenuItem(
                                value: 'disappearing',
                                child: Text('Disappearing messages',
                                    style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        ],
                      ),
            body: WhatsappWallpaper(
              child: Column(
                children: [
                  // Pinned message & disappearing messages banner
                  StreamBuilder<DocumentSnapshot>(
                    stream: _chatDocStream,
                    builder: (context, chatSnap) {
                      final data =
                          chatSnap.data?.data() as Map<String, dynamic>?;
                      final pinned =
                          data?['pinnedMessage'] as Map<String, dynamic>?;
                      final disappearingSeconds =
                          (data?['disappearingTimerSeconds'] as num?)
                                  ?.toInt() ??
                              0;

                      String? disappearingLabel;
                      if (disappearingSeconds >= 7776000) {
                        disappearingLabel = '90 days';
                      } else if (disappearingSeconds >= 604800) {
                        disappearingLabel = '7 days';
                      } else if (disappearingSeconds >= 86400) {
                        disappearingLabel = '24 hours';
                      }

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (pinned != null) ...[
                            InkWell(
                              onTap: () => _scrollToMessage(
                                  (pinned['id'] as String?) ?? ''),
                              child: Container(
                                color: const Color(0xFF1F2C34),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                child: Row(
                                  children: [
                                    const Icon(Icons.push_pin,
                                        color: Color(0xFF00A884), size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Pinned: ${(pinned['text'] as String?) ?? ''}',
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 12),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close,
                                          color: Colors.white54, size: 16),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () {
                                        FirebaseFirestore.instance
                                            .collection('chats')
                                            .doc(widget.chatId)
                                            .update({
                                          'pinnedMessage': FieldValue.delete(),
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          if (disappearingLabel != null) ...[
                            InkWell(
                              onTap: () =>
                                  _showDisappearingMessagesSheet(context),
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF182229),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: Colors.white12, width: 0.5),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.timer_outlined,
                                        size: 15, color: Colors.white70),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        'Messages disappear after $disappearingLabel. Tap to change.',
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),

                  // Floating quick reaction bar
                  if (_reactionTargetDoc != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: ChatReactionBar(
                        onSelectEmoji: (emoji) => _toggleReaction(
                            _reactionTargetDoc!, emoji, currentUid),
                        onMore: () {
                          _toggleReaction(
                              _reactionTargetDoc!, '❤️', currentUid);
                        },
                      ),
                    ),
                  Expanded(
                    child: RepaintBoundary(
                      child: () {
                        final docs = _visibleMessages;
                        final hasAnyMessages = docs.isNotEmpty ||
                            _pendingUploads.isNotEmpty ||
                            _pendingTextMessages.isNotEmpty;
                        if (!hasAnyMessages && _messagesSub == null) {
                          return const Center(
                              child: CircularProgressIndicator(
                                  color: Color(0xFF00A884)));
                        }
                        if (!hasAnyMessages) {
                          return Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1F2C34),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Start the conversation with $otherName!',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                            ),
                          );
                        }

                        return ListView.builder(
                          reverse: true,
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                          itemCount: docs.length +
                              _pendingUploads.length +
                              _pendingTextMessages.length +
                              (_isLoadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            // ── Loading more indicator at the bottom (oldest end) ──
                            if (index ==
                                docs.length +
                                    _pendingUploads.length +
                                    _pendingTextMessages.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Color(0xFF00A884),
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              );
                            }

                            // ── Pending text message bubbles (newest outgoing) ──
                            if (index < _pendingTextMessages.length) {
                              final pending = _pendingTextMessages[
                                  _pendingTextMessages.length - 1 - index];
                              return _buildPendingTextMessageBubble(pending);
                            }

                            // ── Pending upload bubbles ──────────────────────
                            final uploadIndex =
                                index - _pendingTextMessages.length;
                            if (uploadIndex < _pendingUploads.length) {
                              final pending = _pendingUploads[
                                  _pendingUploads.length - 1 - uploadIndex];
                              return Semantics(
                                label:
                                    'Uploading ${pending.type}. ${((pending.progress) * 100).toInt()}% complete.',
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                        bottom: 8, left: 48),
                                    child: ChatMediaBubble(
                                      localFile: pending.file,
                                      bytes: pending.bytes,
                                      type: pending.type,
                                      uploadProgress: pending.progress,
                                      isMe: true,
                                    ),
                                  ),
                                ),
                              );
                            }

                            // ── Real Firestore messages ─────────────────────
                            final realIndex =
                                uploadIndex - _pendingUploads.length;
                            final doc = docs[realIndex];
                            final data = doc.data() as Map<String, dynamic>;
                            final String msgType =
                                (data['type'] as String?) ?? 'text';
                            // A call log is a record, not a message: it sits
                            // centred in the conversation.
                            if (msgType == 'call') {
                              return _buildCallLogEntry(data, currentUid);
                            }
                            final String text = (data['text'] as String?) ?? '';
                            final String mediaUrl =
                                (data['mediaUrl'] as String?) ?? '';
                            final senderId = data['senderId'] ?? '';
                            final isMe = senderId == currentUid;
                            final bool seen = data['seen'] as bool? ?? false;
                            // Delivery status: 'pending' (clock) | 'sent' (single check) | 'delivered' (double grey) | 'read' (double blue)
                            final bool hasPendingWrites =
                                doc.metadata.hasPendingWrites;
                            final String status = hasPendingWrites
                                ? 'pending'
                                : ((data['status'] as String?) ??
                                    (seen ? 'read' : 'sent'));
                            final timestamp = data['timestamp'] as Timestamp?;

                            // Locale-aware time string
                            String timeStr = '';
                            if (timestamp != null) {
                              final date = timestamp.toDate();
                              try {
                                timeStr = _formatTime(date);
                              } catch (_) {
                                timeStr =
                                    '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
                              }
                            }

                            // Delivery tick icon: WhatsApp 4-phase delivery status
                            Widget deliveryIcon() {
                              if (status == 'pending') {
                                return const Icon(Icons.access_time,
                                    size: 11,
                                    color: Colors.white54); // pending / clock
                              } else if (status == 'read' || seen) {
                                return const Icon(Icons.done_all,
                                    size: 13, color: Color(0xFF53BDEB)); // blue
                              } else if (status == 'delivered') {
                                return const Icon(Icons.done_all,
                                    size: 13, color: Colors.white54); // grey
                              } else {
                                return const Icon(Icons.done,
                                    size: 13, color: Colors.white54); // single
                              }
                            }

                            final isSelected =
                                _selectedMessageIds.contains(doc.id);
                            final isHighlighted =
                                _highlightedMessageId == doc.id;
                            final replyData =
                                data['replyTo'] as Map<String, dynamic>?;
                            final replyModel = replyData != null
                                ? ReplyMessageInfo.fromMap(replyData)
                                : null;
                            final reactions =
                                (data['reactions'] as Map<String, dynamic>?) ??
                                    {};
                            final starredBy =
                                (data['starredBy'] as Map<String, dynamic>?) ??
                                    {};
                            final isStarred = starredBy[currentUid] == true;
                            final isEdited = data['isEdited'] == true;
                            final isForwarded = data['isForwarded'] == true;

                            Widget metaRow() {
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isEdited) ...[
                                    const Text(' (edited)',
                                        style: TextStyle(
                                            color: Colors.white38,
                                            fontSize: 9)),
                                    const SizedBox(width: 3),
                                  ],
                                  Text(
                                    timeStr,
                                    style: const TextStyle(
                                        color: Colors.white54, fontSize: 9.5),
                                  ),
                                  if (isStarred) ...[
                                    const SizedBox(width: 3),
                                    const Icon(Icons.star,
                                        size: 10, color: Colors.white60),
                                  ],
                                  if (isMe) ...[
                                    const SizedBox(width: 4),
                                    deliveryIcon(),
                                  ],
                                ],
                              );
                            }

                            Widget bubbleBody;

                            // ── Deleted Message Tombstone (WhatsApp Style) ──
                            if (msgType == 'deleted' ||
                                data['isDeleted'] == true) {
                              bubbleBody = Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1F2C34),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white10,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.block_flipped,
                                      size: 14,
                                      color: Colors.white38,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isMe
                                          ? 'You deleted this message'
                                          : 'This message was deleted',
                                      style: const TextStyle(
                                        fontStyle: FontStyle.italic,
                                        color: Colors.white54,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      timeStr,
                                      style: const TextStyle(
                                        color: Colors.white30,
                                        fontSize: 9.5,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            // ── Document Message ──────────────────────────────
                            else if (msgType == 'document') {
                              bubbleBody = Column(
                                crossAxisAlignment: isMe
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  if (replyModel != null)
                                    ChatQuotedBubble(
                                      reply: replyModel,
                                      isMe: isMe,
                                      onTap: () => _scrollToMessage(
                                          replyModel.messageId),
                                    ),
                                  ChatDocumentBubble(
                                    documentUrl:
                                        (data['documentUrl'] as String?) ?? '',
                                    fileName: (data['fileName'] as String?) ??
                                        'Document',
                                    fileSizeBytes:
                                        (data['fileSizeBytes'] as num?)
                                                ?.toInt() ??
                                            0,
                                    isMe: isMe,
                                    timeStr: timeStr,
                                    deliveryIcon: isMe ? deliveryIcon() : null,
                                  ),
                                ],
                              );
                            }
                            // ── Location Message ──────────────────────────────
                            else if (msgType == 'location') {
                              bubbleBody = Column(
                                crossAxisAlignment: isMe
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  if (replyModel != null)
                                    ChatQuotedBubble(
                                      reply: replyModel,
                                      isMe: isMe,
                                      onTap: () => _scrollToMessage(
                                          replyModel.messageId),
                                    ),
                                  ChatLocationBubble(
                                    latitude: (data['latitude'] as num?)
                                            ?.toDouble() ??
                                        0.0,
                                    longitude: (data['longitude'] as num?)
                                            ?.toDouble() ??
                                        0.0,
                                    title: (data['title'] as String?) ??
                                        'Shared Location',
                                    address: (data['address'] as String?) ?? '',
                                    isMe: isMe,
                                    timeStr: timeStr,
                                    deliveryIcon: isMe ? deliveryIcon() : null,
                                  ),
                                ],
                              );
                            }
                            // ── Travel Expense / Split Message ────────────────
                            else if (msgType == 'expense') {
                              bubbleBody = Column(
                                crossAxisAlignment: isMe
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  if (replyModel != null)
                                    ChatQuotedBubble(
                                      reply: replyModel,
                                      isMe: isMe,
                                      onTap: () => _scrollToMessage(
                                          replyModel.messageId),
                                    ),
                                  ChatExpenseBubble(
                                    title: (data['expenseTitle'] as String?) ??
                                        'Travel Split',
                                    amount:
                                        (data['amount'] as num?)?.toDouble() ??
                                            0.0,
                                    paidByName:
                                        (data['paidByName'] as String?) ??
                                            'Traveler',
                                    isPaidByMe: data['paidById'] == currentUid,
                                    isSettled: data['isSettled'] == true,
                                    timeStr: timeStr,
                                    deliveryIcon: isMe ? deliveryIcon() : null,
                                    onSettle: data['isSettled'] == true
                                        ? null
                                        : () {
                                            doc.reference
                                                .update({'isSettled': true});
                                          },
                                  ),
                                ],
                              );
                            }
                            // ── Media Message (Photo / Video with Caption) ───
                            else if (msgType == 'image' || msgType == 'video') {
                              final bool isViewOnce =
                                  data['isViewOnce'] == true;
                              final bool isOpened = data['isOpened'] == true;

                              if (isViewOnce) {
                                if (isOpened) {
                                  bubbleBody = Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isMe
                                          ? const Color(0xFF005C4B)
                                          : const Color(0xFF202C33),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.looks_one_outlined,
                                            color: Colors.white54, size: 18),
                                        const SizedBox(width: 6),
                                        const Text('Opened',
                                            style: TextStyle(
                                                color: Colors.white54,
                                                fontStyle: FontStyle.italic,
                                                fontSize: 13)),
                                        const SizedBox(width: 8),
                                        Text(timeStr,
                                            style: const TextStyle(
                                                color: Colors.white38,
                                                fontSize: 10)),
                                        if (isMe) ...[
                                          const SizedBox(width: 4),
                                          deliveryIcon(),
                                        ],
                                      ],
                                    ),
                                  );
                                } else {
                                  bubbleBody = InkWell(
                                    onTap: () {
                                      if (isMe) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content: Text(
                                                  'You sent a view-once media')),
                                        );
                                        return;
                                      }
                                      Navigator.of(context)
                                          .push(
                                        MaterialPageRoute<void>(
                                          builder: (ctx) => Scaffold(
                                            backgroundColor: Colors.black,
                                            appBar: AppBar(
                                              backgroundColor: Colors.black,
                                              iconTheme: const IconThemeData(
                                                  color: Colors.white),
                                              title: Text(
                                                  msgType == 'video'
                                                      ? 'View Once Video'
                                                      : 'View Once Photo',
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 16)),
                                            ),
                                            body: Center(
                                              child: InteractiveViewer(
                                                child: kIsWeb
                                                    ? Image.network(
                                                        mediaUrl,
                                                        fit: BoxFit.contain,
                                                      )
                                                    : CachedNetworkImage(
                                                        imageUrl: mediaUrl,
                                                        fit: BoxFit.contain,
                                                        errorWidget:
                                                            (_, __, ___) =>
                                                                Image.network(
                                                          mediaUrl,
                                                          fit: BoxFit.contain,
                                                        ),
                                                      ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                          .then((_) {
                                        doc.reference.update({
                                          'isOpened': true,
                                          'openedAt':
                                              FieldValue.serverTimestamp(),
                                        });
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: isMe
                                            ? const Color(0xFF005C4B)
                                            : const Color(0xFF202C33),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 22,
                                            height: 22,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                  color:
                                                      const Color(0xFF00A884),
                                                  width: 1.5),
                                            ),
                                            child: const Center(
                                              child: Text('1',
                                                  style: TextStyle(
                                                      color: Color(0xFF00A884),
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 11)),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                              msgType == 'video'
                                                  ? 'Video'
                                                  : 'Photo',
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13)),
                                          const SizedBox(width: 8),
                                          Text(timeStr,
                                              style: const TextStyle(
                                                  color: Colors.white54,
                                                  fontSize: 10)),
                                          if (isMe) ...[
                                            const SizedBox(width: 4),
                                            deliveryIcon(),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                }
                              } else {
                                bubbleBody = Container(
                                  decoration: BoxDecoration(
                                    color: isMe
                                        ? const Color(0xFF005C4B)
                                        : const Color(0xFF202C33),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: isMe
                                        ? CrossAxisAlignment.end
                                        : CrossAxisAlignment.start,
                                    children: [
                                      if (isForwarded)
                                        const Padding(
                                          padding:
                                              EdgeInsets.fromLTRB(6, 4, 6, 2),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.forward,
                                                  size: 11,
                                                  color: Colors.white54),
                                              SizedBox(width: 3),
                                              Text('Forwarded',
                                                  style: TextStyle(
                                                      fontStyle:
                                                          FontStyle.italic,
                                                      color: Colors.white54,
                                                      fontSize: 10)),
                                            ],
                                          ),
                                        ),
                                      if (replyModel != null)
                                        ChatQuotedBubble(
                                          reply: replyModel,
                                          isMe: isMe,
                                          onTap: () => _scrollToMessage(
                                              replyModel.messageId),
                                        ),
                                      ChatMediaBubble(
                                        mediaUrl: mediaUrl,
                                        type: msgType,
                                        isMe: isMe,
                                      ),
                                      if (text.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                              6, 6, 6, 2),
                                          child: Text(
                                            text,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13.5),
                                          ),
                                        ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            6, 2, 6, 4),
                                        child: metaRow(),
                                      ),
                                    ],
                                  ),
                                );
                              }
                            }
                            // ── Voice / Audio message ────────────────────────
                            else if (msgType == 'audio') {
                              bubbleBody = Container(
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? const Color(0xFF005C4B)
                                      : const Color(0xFF202C33),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(12),
                                    topRight: const Radius.circular(12),
                                    bottomLeft: isMe
                                        ? const Radius.circular(12)
                                        : Radius.zero,
                                    bottomRight: isMe
                                        ? Radius.zero
                                        : const Radius.circular(12),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: isMe
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  children: [
                                    if (replyModel != null)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            8, 8, 8, 0),
                                        child: ChatQuotedBubble(
                                          reply: replyModel,
                                          isMe: isMe,
                                          onTap: () => _scrollToMessage(
                                              replyModel.messageId),
                                        ),
                                      ),
                                    VoiceMessageBubble(
                                      audioUrl: mediaUrl,
                                      durationSeconds:
                                          (data['durationSeconds'] as num?)
                                              ?.toInt(),
                                      isMe: isMe,
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          10, 0, 10, 6),
                                      child: metaRow(),
                                    ),
                                  ],
                                ),
                              );
                            }
                            // ── Text bubble ─────────────────────────────────
                            else {
                              bubbleBody = PhysicalShape(
                                clipper: isMe
                                    ? SenderBubbleClipper()
                                    : ReceiverBubbleClipper(),
                                color: isMe
                                    ? const Color(0xFF005C4B)
                                    : const Color(0xFF202C33),
                                elevation: 1,
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                      isMe ? 10 : 16, 6, isMe ? 16 : 10, 6),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: isMe
                                        ? CrossAxisAlignment.end
                                        : CrossAxisAlignment.start,
                                    children: [
                                      if (isForwarded)
                                        const Padding(
                                          padding: EdgeInsets.only(bottom: 2),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.forward,
                                                  size: 11,
                                                  color: Colors.white54),
                                              SizedBox(width: 3),
                                              Text('Forwarded',
                                                  style: TextStyle(
                                                      fontStyle:
                                                          FontStyle.italic,
                                                      color: Colors.white54,
                                                      fontSize: 10)),
                                            ],
                                          ),
                                        ),
                                      if (replyModel != null)
                                        ChatQuotedBubble(
                                          reply: replyModel,
                                          isMe: isMe,
                                          onTap: () => _scrollToMessage(
                                              replyModel.messageId),
                                        ),
                                      Text(
                                        text,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13.5),
                                      ),
                                      const SizedBox(height: 2),
                                      metaRow(),
                                    ],
                                  ),
                                ),
                              );
                            }

                            return SwipeToReply(
                              isMe: isMe,
                              onReply: () => _setReplyToMessage(doc),
                              child: GestureDetector(
                                onTap: () {
                                  if (_selectedMessageIds.isNotEmpty) {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedMessageIds.remove(doc.id);
                                      } else {
                                        _selectedMessageIds.add(doc.id);
                                      }
                                    });
                                  } else if (_reactionTargetDoc != null) {
                                    setState(() => _reactionTargetDoc = null);
                                  }
                                },
                                onLongPress: () {
                                  HapticFeedback.mediumImpact();
                                  setState(() {
                                    _selectedMessageIds.add(doc.id);
                                    _reactionTargetDoc = doc;
                                  });
                                },
                                child: Container(
                                  color: isSelected
                                      ? const Color(0xFF00A884)
                                          .withValues(alpha: 0.18)
                                      : isHighlighted
                                          ? const Color(0xFF00A884)
                                              .withValues(alpha: 0.28)
                                          : Colors.transparent,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 2),
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Align(
                                        alignment: isMe
                                            ? Alignment.centerRight
                                            : Alignment.centerLeft,
                                        child: Padding(
                                          padding: EdgeInsets.only(
                                            bottom: 8,
                                            left: isMe ? 48 : 0,
                                            right: isMe ? 0 : 48,
                                          ),
                                          child: bubbleBody,
                                        ),
                                      ),
                                      if (reactions.isNotEmpty)
                                        Positioned(
                                          bottom: 0,
                                          right: isMe ? 8 : null,
                                          left: isMe ? null : 8,
                                          child: ChatReactionBadge(
                                            reactions: reactions,
                                            onTap: () =>
                                                showReactionDetailsSheet(
                                              context,
                                              reactions: reactions,
                                              currentUid: currentUid,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      }(),
                    ),
                  ),

                  // Typing indicator message overlay
                  StreamBuilder<DocumentSnapshot>(
                    stream: _chatDocStream,
                    builder: (context, chatSnap) {
                      final data =
                          chatSnap.data?.data() as Map<String, dynamic>?;
                      final bool isOtherTyping =
                          (data?['typing_$resolvedOtherUid'] as bool?) ?? false;

                      if (isOtherTyping) {
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(left: 20, bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF202C33),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$otherName is typing...',
                              style: const TextStyle(
                                color: Color(0xFF00A884),
                                fontSize: 10.5,
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),

                  // Input bar
                  _isLoadingBlock
                      ? const SizedBox.shrink()
                      : _isBlocked
                          ? Container(
                              width: double.infinity,
                              padding: EdgeInsets.fromLTRB(16, 16, 16,
                                  16 + MediaQuery.of(context).padding.bottom),
                              color: Colors.redAccent.withValues(alpha: 0.08),
                              child: const Center(
                                child: Text(
                                  'Messaging is disabled because one of you has blocked the other.',
                                  style: TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : _isRecordingVoice
                              ? Container(
                                  padding: EdgeInsets.fromLTRB(
                                      8,
                                      6,
                                      8,
                                      8 +
                                          MediaQuery.of(context)
                                              .padding
                                              .bottom),
                                  child: VoiceMessageRecorder(
                                    onVoiceSent: (path, dur) {
                                      setState(() => _isRecordingVoice = false);
                                      _sendVoiceMessage(
                                          path, dur, currentUid, currentName);
                                    },
                                    onCancel: () {
                                      setState(() => _isRecordingVoice = false);
                                    },
                                  ),
                                )
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_replyingMessage != null)
                                      ChatReplyInputBanner(
                                        reply: _replyingMessage!,
                                        onCancel: () => setState(
                                            () => _replyingMessage = null),
                                      ),
                                    if (_editingMessage != null)
                                      Container(
                                        margin: const EdgeInsets.fromLTRB(
                                            10, 0, 10, 4),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1F2C34),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: const Border(
                                            left: BorderSide(
                                                color: Color(0xFF00A884),
                                                width: 4),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.edit,
                                                color: Color(0xFF00A884),
                                                size: 16),
                                            const SizedBox(width: 8),
                                            const Expanded(
                                              child: Text(
                                                'Editing message',
                                                style: TextStyle(
                                                  color: Color(0xFF00A884),
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.close,
                                                  color: Colors.white60,
                                                  size: 18),
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                              onPressed: () {
                                                setState(() =>
                                                    _editingMessage = null);
                                                _messageController.clear();
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    Container(
                                      padding: EdgeInsets.fromLTRB(
                                          8,
                                          6,
                                          8,
                                          8 +
                                              MediaQuery.of(context)
                                                  .padding
                                                  .bottom),
                                      color:
                                          Colors.transparent, // Floating look
                                      child: Row(
                                        children: [
                                          // WhatsApp left rounded input container
                                          Expanded(
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF202C33),
                                                borderRadius:
                                                    BorderRadius.circular(24),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8),
                                              child: Row(
                                                children: [
                                                  Semantics(
                                                    label: _showEmojiPicker
                                                        ? 'Open keyboard'
                                                        : 'Open emoji picker',
                                                    button: true,
                                                    child: SizedBox(
                                                      width: 48,
                                                      height: 48,
                                                      child: IconButton(
                                                        icon: Icon(
                                                            _showEmojiPicker
                                                                ? Icons
                                                                    .keyboard_outlined
                                                                : Icons
                                                                    .sentiment_satisfied_alt_outlined,
                                                            color: const Color(
                                                                0xFF8696A0)),
                                                        onPressed:
                                                            _toggleEmojiPicker,
                                                      ),
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: TextField(
                                                      controller:
                                                          _messageController,
                                                      focusNode:
                                                          _messageFocusNode,
                                                      onTap: () {
                                                        if (_showEmojiPicker) {
                                                          setState(() =>
                                                              _showEmojiPicker =
                                                                  false);
                                                        }
                                                      },
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 14),
                                                      decoration:
                                                          InputDecoration(
                                                        hintText: context.l10n
                                                            .translate(
                                                                'chat_message_placeholder'),
                                                        hintStyle:
                                                            const TextStyle(
                                                                color: Color(
                                                                    0xFF8696A0),
                                                                fontSize: 14),
                                                        border:
                                                            InputBorder.none,
                                                        contentPadding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                vertical: 10),
                                                      ),
                                                      onSubmitted: (_) =>
                                                          _sendMessage(
                                                              currentUid,
                                                              currentName),
                                                    ),
                                                  ),
                                                  Semantics(
                                                    label:
                                                        'Attach document, photo, video, or location',
                                                    button: true,
                                                    child: SizedBox(
                                                      width: 48,
                                                      height: 48,
                                                      child: IconButton(
                                                        icon: const Icon(
                                                            Icons.attach_file,
                                                            color: Color(
                                                                0xFF8696A0)),
                                                        onPressed: () =>
                                                            _openAttachmentSheet(
                                                                currentUid,
                                                                currentName),
                                                      ),
                                                    ),
                                                  ),
                                                  Semantics(
                                                    label: 'Open camera',
                                                    button: true,
                                                    child: SizedBox(
                                                      width: 48,
                                                      height: 48,
                                                      child: IconButton(
                                                        icon: const Icon(
                                                            Icons
                                                                .camera_alt_outlined,
                                                            color: Color(
                                                                0xFF8696A0)),
                                                        onPressed: () =>
                                                            _openCameraDirect(
                                                                currentUid,
                                                                currentName),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          // WhatsApp right circular action button
                                          ValueListenableBuilder<
                                              TextEditingValue>(
                                            valueListenable: _messageController,
                                            builder: (context, val, child) {
                                              final hasText =
                                                  val.text.trim().isNotEmpty;
                                              final isEditing =
                                                  _editingMessage != null;
                                              return GestureDetector(
                                                onTap: () {
                                                  if (hasText || isEditing) {
                                                    _sendMessage(currentUid,
                                                        currentName);
                                                  } else {
                                                    setState(() =>
                                                        _isRecordingVoice =
                                                            true);
                                                  }
                                                },
                                                child: CircleAvatar(
                                                  radius: 22,
                                                  backgroundColor:
                                                      const Color(0xFF00A884),
                                                  child: Icon(
                                                    isEditing
                                                        ? Icons.check
                                                        : (hasText
                                                            ? Icons.send
                                                            : Icons.mic),
                                                    color: Colors.white,
                                                    size: 19,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_showEmojiPicker)
                                      ChatEmojiPicker(
                                        onEmojiSelected: _insertEmoji,
                                        onBackspace: _backspaceEmoji,
                                      ),
                                  ],
                                ),
                ],
              ),
            ),
          ),
        );
      },
    );
  } // build
} // _ChatScreenState

// ── CUSTOM CLIPPERS & BACKGROUND WALLPAPER ───────────────────────────────────

class SenderBubbleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(12, 0);
    path.lineTo(size.width - 12, 0);
    // top-right tail shape
    path.lineTo(size.width, 0);
    path.lineTo(size.width - 6, 8);
    path.lineTo(size.width - 6, size.height - 12);
    path.quadraticBezierTo(
        size.width - 6, size.height, size.width - 18, size.height);
    path.lineTo(12, size.height);
    path.quadraticBezierTo(0, size.height, 0, size.height - 12);
    path.lineTo(0, 12);
    path.quadraticBezierTo(0, 0, 12, 0);
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class ReceiverBubbleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(18, 0);
    // top-left tail shape
    path.lineTo(6, 0);
    path.lineTo(0, 0);
    path.lineTo(6, 8);
    path.lineTo(6, size.height - 12);
    path.quadraticBezierTo(6, size.height, 18, size.height);
    path.lineTo(size.width - 12, size.height);
    path.quadraticBezierTo(
        size.width, size.height, size.width, size.height - 12);
    path.lineTo(size.width, 12);
    path.quadraticBezierTo(size.width, 0, size.width - 12, 0);
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class WhatsappWallpaper extends StatelessWidget {
  final Widget child;
  const WhatsappWallpaper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Background base color
        Container(color: const Color(0xFF0B141A)),
        // Background custom doodle painter
        Positioned.fill(
          child: CustomPaint(
            painter: WhatsappWallpaperPainter(),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class WhatsappWallpaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.015)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    const double step = 90.0;
    int index = 0;
    for (double x = 20; x < size.width; x += step) {
      for (double y = 20; y < size.height; y += step) {
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate((index % 4 - 2) * 0.15);
        _drawIcon(canvas, paint, index % 6);
        canvas.restore();
        index++;
      }
    }
  }

  void _drawIcon(Canvas canvas, Paint paint, int type) {
    switch (type) {
      case 0: // Star
        final path = Path()
          ..moveTo(0, -8)
          ..lineTo(2.5, -2.5)
          ..lineTo(8, -2.5)
          ..lineTo(3.5, 1)
          ..lineTo(5.5, 6.5)
          ..lineTo(0, 3)
          ..lineTo(-5.5, 6.5)
          ..lineTo(-3.5, 1)
          ..lineTo(-8, -2.5)
          ..lineTo(-2.5, -2.5)
          ..close();
        canvas.drawPath(path, paint);
        break;
      case 1: // Chat bubble
        final path = Path()
          ..moveTo(-6, -6)
          ..lineTo(6, -6)
          ..quadraticBezierTo(8, -6, 8, -4)
          ..lineTo(8, 2)
          ..quadraticBezierTo(8, 4, 6, 4)
          ..lineTo(2, 4)
          ..lineTo(-2, 8)
          ..lineTo(-2, 4)
          ..lineTo(-6, 4)
          ..quadraticBezierTo(-8, 4, -8, 2)
          ..lineTo(-8, -4)
          ..quadraticBezierTo(-8, -6, -6, -6);
        canvas.drawPath(path, paint);
        break;
      case 2: // Heart
        final path = Path()
          ..moveTo(0, -4)
          ..cubicTo(-3, -7, -7, -4, -4, 0)
          ..lineTo(0, 4)
          ..lineTo(4, 0)
          ..cubicTo(7, -4, 3, -7, 0, -4);
        canvas.drawPath(path, paint);
        break;
      case 3: // Cloud
        final path = Path()
          ..moveTo(-6, 2)
          ..arcToPoint(const Offset(-2, -2), radius: const Radius.circular(4))
          ..arcToPoint(const Offset(4, -1), radius: const Radius.circular(5))
          ..arcToPoint(const Offset(6, 2), radius: const Radius.circular(3))
          ..lineTo(-6, 2)
          ..close();
        canvas.drawPath(path, paint);
        break;
      case 4: // Coffee Mug
        final path = Path()
          ..moveTo(-4, -5)
          ..lineTo(4, -5)
          ..lineTo(3, 4)
          ..quadraticBezierTo(2, 6, -2, 6)
          ..lineTo(-3, 4)
          ..close();
        path.moveTo(4, -3);
        path.quadraticBezierTo(7, -2, 4, 1);
        canvas.drawPath(path, paint);
        break;
      case 5: // Leaf
        final path = Path()
          ..moveTo(0, -6)
          ..quadraticBezierTo(5, -2, 0, 5)
          ..quadraticBezierTo(-5, -2, 0, -6);
        canvas.drawPath(path, paint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
