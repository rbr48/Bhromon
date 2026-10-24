import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/utils/shared_latest_stream.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'dart:math' as math;
import '../../../../core/localization/app_localizations.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../widgets/chat_media_picker.dart';
import '../widgets/chat_media_bubble.dart';
import '../../../../core/utils/image_sizing.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String? otherUid;

  const ChatScreen({super.key, required this.chatId, this.otherUid});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

/// Represents an in-progress media upload shown optimistically in the chat list.
class _PendingUpload {
  final String id;
  final File file;
  final String type;
  double progress = 0.0;

  _PendingUpload({
    required this.id,
    required this.file,
    required this.type,
  });
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isBlocked = false;
  bool _isLoadingBlock = true;

  bool _isTyping = false;
  Timer? _typingTimer;

  // Pending uploads shown optimistically before Firestore write completes.
  final List<_PendingUpload> _pendingUploads = [];

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

  @override
  void initState() {
    super.initState();
    _checkBlockStatus();
    _messageController.addListener(_onTextChanged);
    _scrollController.addListener(_onScroll);
    _startChatOpenTrace();
    _subscribeToLatestMessages();
  }

  /// Starts a Firebase Performance trace for chat screen open → first message load.
  Future<void> _startChatOpenTrace() async {
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
      // Merge the live page into _allMessages (deduplication by doc ID)
      final incoming = snap.docs;
      final ids = _allMessages.map((d) => d.id).toSet();
      final fresh = incoming.where((d) => !ids.contains(d.id)).toList();
      setState(() {
        _allMessages.insertAll(0, fresh);
        if (incoming.length < _pageSize) _hasMoreMessages = false;
        if (incoming.isNotEmpty) _oldestLoadedDoc = incoming.last;
      });
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
    FirebaseFirestore.instance.collection('chats').doc(widget.chatId).set({
      'typing_$uid': typing,
    }, SetOptions(merge: true));
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

  @override
  void dispose() {
    _messageController.removeListener(_onTextChanged);
    _scrollController.removeListener(_onScroll);
    _typingTimer?.cancel();
    _messagesSub?.cancel();
    final authState = context.read<AuthCubit>().state;
    if (authState is Authenticated) {
      _updateTypingStatus(authState.profile.uid, false);
    }
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String? _resolveOtherUid(String currentUid) {
    if (widget.otherUid != null && widget.otherUid!.isNotEmpty) {
      return widget.otherUid;
    }
    final parts = widget.chatId.split('_');
    if (parts.length == 2) {
      return parts[0] == currentUid ? parts[1] : parts[0];
    }
    return null;
  }

  void _sendMessage(String currentUid, String currentName) async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    _typingTimer?.cancel();
    if (_isTyping) {
      _isTyping = false;
      _updateTypingStatus(currentUid, false);
    }

    final batch = FirebaseFirestore.instance.batch();

    // Add message
    final msgRef = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .doc();

    batch.set(msgRef, {
      'senderId': currentUid,
      'type': 'text',
      'text': text,
      'seen': false,
      'status': 'sent', // delivery states: sent → delivered → read
      'timestamp': FieldValue.serverTimestamp(),
    });

    final resolvedOtherUid = _resolveOtherUid(currentUid);

    // Update chat meta
    final chatRef =
        FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
    batch.set(
        chatRef,
        {
          'lastMessage': text,
          'lastMessageTime': FieldValue.serverTimestamp(),
          'participants':
              FieldValue.arrayUnion([currentUid, resolvedOtherUid ?? 'guest']),
        },
        SetOptions(merge: true));

    // Write in-app notification for the recipient
    if (resolvedOtherUid != null &&
        resolvedOtherUid != 'guest' &&
        resolvedOtherUid != currentUid) {
      final notifRef = FirebaseFirestore.instance
          .collection('users')
          .doc(resolvedOtherUid)
          .collection('notifications')
          .doc();
      batch.set(notifRef, {
        'title': 'New message from $currentName',
        'body': text,
        'action': 'chat',
        'uid': currentUid,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }

    try {
      await batch.commit();
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      if (resolvedOtherUid == 'bhromon_ai_advisor') {
        _processAiResponse(currentUid, text);
      }
    } catch (e) {
      debugPrint('Error sending message: $e');
    }
  }

  void _processAiResponse(String currentUid, String userText) async {
    _updateTypingStatus('bhromon_ai_advisor', true);

    await Future<void>.delayed(const Duration(milliseconds: 1500));

    final responseText = _generateAiReply(userText);

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
      'lastMessageTime': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _updateTypingStatus('bhromon_ai_advisor', false);
  }

  String _generateAiReply(String message) {
    final query = message.toLowerCase();

    if (query.contains('sajek')) {
      return "Sajek Valley is located in Rangamati district. It is known as the Queen of Hills, surrounded by valleys and floating clouds. Recommended activities: watching sunrise from Konglak Para, visiting the stone garden.";
    }
    if (query.contains('cox') || query.contains('beach')) {
      return "Cox's Bazar Beach is the world's longest natural sandy beach (120km). Make sure to visit Himchari waterfalls and take a drive on the Marine Drive!";
    }
    if (query.contains('st. martin') ||
        query.contains('martin') ||
        query.contains('coral')) {
      return "St. Martin's Island is the only coral island in Bangladesh. Take a ferry from Teknaf, visit Chera Dwip, and enjoy fresh coconut water.";
    }
    if (query.contains('jaflong')) {
      return "Jaflong is a beautiful hill station and stone quarry tourist destination nestled at the base of the Khasi hills in Sylhet.";
    }
    if (query.contains('ratargul')) {
      return "Ratargul Swamp Forest is the only freshwater swamp forest in Bangladesh, often referred to as the Amazon of Bangla.";
    }
    if (query.contains('sundarban') || query.contains('tiger')) {
      return "Sundarbans in Khulna is the world's largest coastal mangrove forest and home of the magnificent Royal Bengal Tiger. Perfect for boat tours!";
    }
    if (query.contains('lalbagh') || query.contains('fort')) {
      return "Lalbagh Fort is an incomplete 17th-century Mughal fort complex that stands as a majestic monument of history in Old Dhaka.";
    }
    if (query.contains('ahsan') ||
        query.contains('palace') ||
        query.contains('manzil')) {
      return "Ahsan Manzil (the Pink Palace) was formerly the official residential palace of the Nawab of Dhaka, sitting on the Buriganga River.";
    }
    if (query.contains('kuakata')) {
      return "Kuakata Beach is known as the Daughter of the Ocean. This rare beach allows viewing both sunrise and sunset over the Bay of Bengal.";
    }
    if (query.contains('nilgiri')) {
      return "Nilgiri Hills is a scenic high-altitude hill resort in Bandarban offering panoramic views of the cloud ocean.";
    }
    if (query.contains('boga')) {
      return "Boga Lake is a high-altitude deep blue volcanic crater lake in Bandarban, perfect for hiking and adventure.";
    }
    if (query.contains('lawachara') || query.contains('forest')) {
      return "Lawachara National Park is a semi-evergreen rain forest in Sreemangal famous for its rich biodiversity and endangered hoolock gibbons.";
    }
    if (query.contains('mahasthan')) {
      return "Mahasthangarh is one of the earliest urban archaeological sites in Bangladesh, containing ruins dating back to the 3rd century BCE.";
    }
    if (query.contains('paharpur') || query.contains('monastery')) {
      return "Somapura Mahavihara (Paharpur) is a UNESCO World Heritage site and one of the most famous Buddhist monasteries in South Asia.";
    }
    if (query.contains('sixty') ||
        query.contains('dome') ||
        query.contains('mosque')) {
      return "Sixty Dome Mosque is a UNESCO World Heritage site and a historic Mughal-era mosque located in Bagerhat, built by Khan Jahan Ali.";
    }
    if (query.contains('bisnakandi')) {
      return "Bisnakandi is a scenic sub-branch of the Khasi hills in Sylhet where multiple steps of the mountain meet at a single point with a stream.";
    }
    if (query.contains('tanguar') || query.contains('haor')) {
      return "Tanguar Haor is a unique wetland ecosystem (Ramsar site) in Sunamganj with crystal clear water and rich avian life.";
    }
    if (query.contains('weather')) {
      return "I can fetch current weather and forecasts for you! Let me know which spot you are visiting (e.g. Sajek weather or Cox's Bazar weather).";
    }
    if (query.contains('hello') ||
        query.contains('hi') ||
        query.contains('hey') ||
        query.contains('help') ||
        query.contains('guide')) {
      return "Hello traveler! I am your Bhromon AI Travel Guide. Ask me about travel spots in Bangladesh (like Sajek, Cox's Bazar, St. Martin's, Sylhet, Sundarbans, or Lalbagh Fort)!";
    }

    return "That sounds like an amazing trip! To explore spots in Bangladesh, ask me about Sajek, Cox's Bazar, St. Martin's, Sylhet, Sundarbans, or Lalbagh Fort!";
  }

  /// Uploads [file] to Firebase Storage and writes a media message to Firestore.
  Future<void> _sendMediaMessage(
    File file,
    String type,
    String currentUid,
    String currentName,
  ) async {
    final uploadId = const Uuid().v4();
    final pending = _PendingUpload(id: uploadId, file: file, type: type);

    setState(() => _pendingUploads.add(pending));

    // Start Firebase Performance trace for media upload
    Trace? uploadTrace;
    try {
      uploadTrace = FirebasePerformance.instance.newTrace('media_upload');
      await uploadTrace.start();
      uploadTrace.putAttribute('mediaType', type);
    } catch (_) {}

    try {
      // ── Compress images before upload ───────────────────────────────────
      File fileToUpload = file;
      if (type == 'image') {
        try {
          final compressed = await FlutterImageCompress.compressAndGetFile(
            file.absolute.path,
            '${file.parent.path}/${uploadId}_compressed.jpg',
            minWidth: 1200,
            minHeight: 1200,
            quality: 82,
            format: CompressFormat.jpeg,
          );
          if (compressed != null) {
            fileToUpload = File(compressed.path);
            debugPrint(
                'Image compressed: ${file.lengthSync()} → ${fileToUpload.lengthSync()} bytes');
          }
        } catch (e) {
          debugPrint('Compression failed, using original: $e');
        }
      }

      // ── Upload to Firebase Storage ──────────────────────────────────────
      final ext = type == 'video' ? 'mp4' : 'jpg';
      final storageRef = FirebaseStorage.instance
          .ref('chat_media/${widget.chatId}/$uploadId.$ext');

      final uploadTask = storageRef.putFile(
        fileToUpload,
        SettableMetadata(
            contentType: type == 'video' ? 'video/mp4' : 'image/jpeg'),
      );

      uploadTask.snapshotEvents.listen((snap) {
        if (!mounted) return;
        final progress =
            snap.bytesTransferred / (snap.totalBytes > 0 ? snap.totalBytes : 1);
        setState(() => pending.progress = progress);
      });

      await uploadTask;
      final downloadUrl = await storageRef.getDownloadURL();

      // ── Write Firestore message ─────────────────────────────────────────
      final resolvedOtherUid = _resolveOtherUid(currentUid);
      final batch = FirebaseFirestore.instance.batch();

      final msgRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc();

      batch.set(msgRef, {
        'senderId': currentUid,
        'type': type,
        'text': '',
        'mediaUrl': downloadUrl,
        'seen': false,
        'status': 'sent', // delivery states: sent → delivered → read
        'timestamp': FieldValue.serverTimestamp(),
      });

      final lastMsg = type == 'image' ? '📷 Photo' : '🎬 Video';
      final chatRef =
          FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
      batch.set(
          chatRef,
          {
            'lastMessage': lastMsg,
            'lastMessageTime': FieldValue.serverTimestamp(),
            'participants': FieldValue.arrayUnion(
                [currentUid, resolvedOtherUid ?? 'guest']),
          },
          SetOptions(merge: true));

      if (resolvedOtherUid != null &&
          resolvedOtherUid != 'guest' &&
          resolvedOtherUid != currentUid) {
        final notifRef = FirebaseFirestore.instance
            .collection('users')
            .doc(resolvedOtherUid)
            .collection('notifications')
            .doc();
        batch.set(notifRef, {
          'title': 'New message from $currentName',
          'body': lastMsg,
          'action': 'chat',
          'uid': currentUid,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Media upload error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send media. Please try again.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      // Stop the performance trace
      try {
        await uploadTrace?.stop();
      } catch (_) {}
      if (mounted) {
        setState(() => _pendingUploads.removeWhere((p) => p.id == uploadId));
      }
    }
  }

  /// Opens the media picker bottom sheet and starts an upload if the user picks media.
  Future<void> _openMediaPicker(String currentUid, String currentName) async {
    final result = await showChatMediaPicker(context);
    if (result == null || !mounted) return;
    await _sendMediaMessage(result.file, result.type, currentUid, currentName);
  }

  /// Marks all unread incoming messages as seen and updates delivery status to 'read'.
  void _markMessagesAsSeen(
      List<QueryDocumentSnapshot> docs, String currentUid) {
    final unreadDocs = docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final senderId = data['senderId'] ?? '';
      final bool seen = data['seen'] as bool? ?? false;
      return senderId != currentUid && !seen;
    }).toList();

    if (unreadDocs.isNotEmpty) {
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in unreadDocs) {
        batch.update(doc.reference, {
          'seen': true,
          'status': 'read',
          'readAt': FieldValue.serverTimestamp(),
        });
      }
      batch.commit().catchError((Object e) {
        debugPrint('Error marking messages as seen: $e');
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
      return !deletedFor.contains(currentUid);
    }).toList();
  }

  void _showDeleteMessageDialog(QueryDocumentSnapshot doc, bool isMe) {
    final authState = context.read<AuthCubit>().state;
    final currentUid = authState is Authenticated ? authState.profile.uid : '';

    showDialog<void>(
      context: context,
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
                debugPrint('Error deleting for me: $e');
              }
            },
            child: const Text('DELETE FOR ME',
                style: TextStyle(color: Colors.redAccent)),
          ),
          if (isMe)
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                try {
                  await FirebaseFirestore.instance
                      .collection('chats')
                      .doc(widget.chatId)
                      .collection('messages')
                      .doc(doc.id)
                      .delete();
                  setState(() {
                    _allMessages.removeWhere((d) => d.id == doc.id);
                  });
                } catch (e) {
                  debugPrint('Error deleting for everyone: $e');
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

        return Scaffold(
          backgroundColor:
              const Color(0xFF0B141A), // WhatsApp wallpaper base color
          appBar: AppBar(
            backgroundColor: const Color(0xFF1F2C34), // WhatsApp slate dark
            elevation: 1.5,
            leadingWidth: 90,
            leading: Row(
              children: [
                const SizedBox(width: 4),
                IconButton(
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => context.pop(),
                ),
                CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0xFF005C4B),
                  backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                      ? sizedImage(
                          NetworkImage(avatarUrl), context.decodeWidth(36))
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
                Text(
                  otherName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                // Typing / Online status stream
                StreamBuilder<DocumentSnapshot>(
                  stream: _chatDocStream,
                  builder: (context, chatSnap) {
                    final data = chatSnap.data?.data() as Map<String, dynamic>?;
                    final bool isOtherTyping =
                        (data?['typing_$resolvedOtherUid'] as bool?) ?? false;
                    return Text(
                      isOtherTyping ? 'typing...' : 'online',
                      style: TextStyle(
                        color: isOtherTyping
                            ? const Color(0xFF00A884)
                            : Colors.white54,
                        fontSize: 10,
                        fontWeight:
                            isOtherTyping ? FontWeight.bold : FontWeight.normal,
                      ),
                    );
                  },
                ),
              ],
            ),
            actions: [
              IconButton(
                icon:
                    const Icon(Icons.more_vert, color: Colors.white, size: 20),
                onPressed: () {},
              ),
            ],
          ),
          body: WhatsappWallpaper(
            child: Column(
              children: [
                Expanded(
                  child: RepaintBoundary(
                    child: () {
                      final docs = _visibleMessages;
                      if (docs.isEmpty && _messagesSub == null) {
                        return const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFF00A884)));
                      }
                      if (docs.isEmpty) {
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

                      // Automatically mark unread messages as read/seen
                      _markMessagesAsSeen(docs, currentUid);

                      return ListView.builder(
                        reverse: true,
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        itemCount: docs.length +
                            _pendingUploads.length +
                            (_isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          // ── Loading more indicator at the bottom ────────
                          if (index == docs.length + _pendingUploads.length) {
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

                          // ── Pending upload bubbles ──────────────────────
                          if (index < _pendingUploads.length) {
                            final pending = _pendingUploads[
                                _pendingUploads.length - 1 - index];
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
                                    type: pending.type,
                                    uploadProgress: pending.progress,
                                    isMe: true,
                                  ),
                                ),
                              ),
                            );
                          }

                          // ── Real Firestore messages ─────────────────────
                          final realIndex = index - _pendingUploads.length;
                          final data =
                              docs[realIndex].data() as Map<String, dynamic>;
                          final String msgType =
                              (data['type'] as String?) ?? 'text';
                          final String text = (data['text'] as String?) ?? '';
                          final String mediaUrl =
                              (data['mediaUrl'] as String?) ?? '';
                          final senderId = data['senderId'] ?? '';
                          final isMe = senderId == currentUid;
                          final bool seen = data['seen'] as bool? ?? false;
                          // Delivery status: 'sent' | 'delivered' | 'read'
                          final String status = (data['status'] as String?) ??
                              (seen ? 'read' : 'sent');
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

                          // Delivery tick icon
                          Widget deliveryIcon() {
                            if (status == 'read' || seen) {
                              return const Icon(Icons.done_all,
                                  size: 13, color: Color(0xFF53BDEB)); // blue
                            } else if (status == 'delivered') {
                              return const Icon(Icons.done_all,
                                  size: 13, color: Colors.white30); // grey
                            } else {
                              return const Icon(Icons.done,
                                  size: 13, color: Colors.white30); // single
                            }
                          }

                          // ── Media bubble ────────────────────────────────
                          if (msgType == 'image' || msgType == 'video') {
                            final semanticLabel =
                                '${msgType == 'image' ? 'Image' : 'Video'} message '
                                '${isMe ? 'sent by you' : 'from $otherName'} at $timeStr. '
                                'Tap to view full screen.';
                            return Semantics(
                              label: semanticLabel,
                              button: true,
                              child: Align(
                                alignment: isMe
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    bottom: 8,
                                    left: isMe ? 48 : 0,
                                    right: isMe ? 0 : 48,
                                  ),
                                  child: GestureDetector(
                                    onLongPress: () => _showDeleteMessageDialog(
                                        docs[realIndex], isMe),
                                    child: Column(
                                      crossAxisAlignment: isMe
                                          ? CrossAxisAlignment.end
                                          : CrossAxisAlignment.start,
                                      children: [
                                        ChatMediaBubble(
                                          mediaUrl: mediaUrl,
                                          type: msgType,
                                          isMe: isMe,
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              timeStr,
                                              style: const TextStyle(
                                                  color: Colors.white38,
                                                  fontSize: 9.5),
                                            ),
                                            if (isMe) ...[
                                              const SizedBox(width: 4),
                                              deliveryIcon(),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }

                          // ── Text bubble ─────────────────────────────────
                          final statusLabel = isMe
                              ? (status == 'read' || seen
                                  ? 'Read'
                                  : status == 'delivered'
                                      ? 'Delivered'
                                      : 'Sent')
                              : '';
                          final semanticLabel =
                              'Message ${isMe ? "sent by you" : "from $otherName"}: '
                              '$text. $timeStr'
                              '${isMe ? ". $statusLabel" : ""}';

                          if (isMe) {
                            return Semantics(
                              label: semanticLabel,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Container(
                                  margin: const EdgeInsets.only(
                                      bottom: 8, left: 48),
                                  child: GestureDetector(
                                    onLongPress: () => _showDeleteMessageDialog(
                                        docs[realIndex], true),
                                    child: PhysicalShape(
                                      clipper: SenderBubbleClipper(),
                                      color: const Color(0xFF005C4B),
                                      elevation: 1,
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            10, 6, 16, 6),
                                        child: Stack(
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 12, right: 46),
                                              child: Text(
                                                text,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13.5),
                                              ),
                                            ),
                                            Positioned(
                                              bottom: 0,
                                              right: 0,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    timeStr,
                                                    style: const TextStyle(
                                                        color: Colors.white38,
                                                        fontSize: 9.5),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  deliveryIcon(),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          } else {
                            return Semantics(
                              label: semanticLabel,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(
                                      bottom: 8, right: 48),
                                  child: GestureDetector(
                                    onLongPress: () => _showDeleteMessageDialog(
                                        docs[realIndex], false),
                                    child: PhysicalShape(
                                      clipper: ReceiverBubbleClipper(),
                                      color: const Color(0xFF202C33),
                                      elevation: 1,
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            16, 6, 10, 6),
                                        child: Stack(
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 12, right: 38),
                                              child: Text(
                                                text,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13.5),
                                              ),
                                            ),
                                            Positioned(
                                              bottom: 0,
                                              right: 0,
                                              child: Text(
                                                timeStr,
                                                style: const TextStyle(
                                                    color: Colors.white38,
                                                    fontSize: 9.5),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }
                        },
                      );
                    }(),
                  ),
                ),

                // Typing indicator message overlay
                StreamBuilder<DocumentSnapshot>(
                  stream: _chatDocStream,
                  builder: (context, chatSnap) {
                    final data = chatSnap.data?.data() as Map<String, dynamic>?;
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
                        : Container(
                            padding: EdgeInsets.fromLTRB(8, 6, 8,
                                8 + MediaQuery.of(context).padding.bottom),
                            color: Colors.transparent, // Floating look
                            child: Row(
                              children: [
                                // WhatsApp left rounded input container
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF202C33),
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    child: Row(
                                      children: [
                                        Semantics(
                                          label: 'Open emoji picker',
                                          button: true,
                                          child: SizedBox(
                                            width: 48,
                                            height: 48,
                                            child: IconButton(
                                              icon: const Icon(
                                                  Icons
                                                      .sentiment_satisfied_alt_outlined,
                                                  color: Color(0xFF8696A0)),
                                              onPressed: () {},
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: TextField(
                                            controller: _messageController,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14),
                                            decoration: InputDecoration(
                                              hintText: context.l10n.translate(
                                                  'chat_message_placeholder'),
                                              hintStyle: const TextStyle(
                                                  color: Color(0xFF8696A0),
                                                  fontSize: 14),
                                              border: InputBorder.none,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 10),
                                            ),
                                            onSubmitted: (_) => _sendMessage(
                                                currentUid, currentName),
                                          ),
                                        ),
                                        Semantics(
                                          label: 'Attach photo or video',
                                          button: true,
                                          child: SizedBox(
                                            width: 48,
                                            height: 48,
                                            child: IconButton(
                                              icon: const Icon(
                                                  Icons.attach_file,
                                                  color: Color(0xFF8696A0)),
                                              onPressed: () => _openMediaPicker(
                                                  currentUid, currentName),
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
                                                  Icons.camera_alt_outlined,
                                                  color: Color(0xFF8696A0)),
                                              onPressed: () => _openMediaPicker(
                                                  currentUid, currentName),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // WhatsApp right circular action button
                                ValueListenableBuilder<TextEditingValue>(
                                  valueListenable: _messageController,
                                  builder: (context, val, child) {
                                    final hasText = val.text.trim().isNotEmpty;
                                    return GestureDetector(
                                      onTap: () {
                                        if (hasText) {
                                          _sendMessage(currentUid, currentName);
                                        } else {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                  'Hold button to record voice note (mock mode).'),
                                              duration:
                                                  Duration(milliseconds: 1500),
                                            ),
                                          );
                                        }
                                      },
                                      child: CircleAvatar(
                                        radius: 22,
                                        backgroundColor:
                                            const Color(0xFF00A884),
                                        child: Icon(
                                          hasText ? Icons.send : Icons.mic,
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
              ],
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
