import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:local_auth/local_auth.dart';
import 'dart:math' as math;
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../../../core/utils/image_sizing.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/utils/doc_future_cache.dart';
import '../../data/call_history_stream.dart';
import '../../data/chat_local_cache.dart';
import '../../data/vps_chat_service.dart';
import '../../../tour_group/data/tour_group_repository.dart';
import '../../../tour_group/domain/models/tour_group.dart';
import '../../../tour_group/domain/services/group_contacts.dart';
import '../../../tour_group/presentation/widgets/bhromon_bottom_nav.dart';

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  String _activeTab = 'All'; // 'All' | 'Unread'
  String _searchQuery = '';
  int _bottomNavIndex = 0; // 0 = Chats, 1 = Calls
  List<Map<String, dynamic>> _offlineConversations = [];
  Set<String> _lockedChatIds = {};

  // Built once per signed-in user, so typing in search or switching tabs
  // doesn't tear down and re-attach both Firestore listeners.
  String? _streamsUid;
  late Stream<QuerySnapshot> _blockedStream;
  late Stream<QuerySnapshot> _chatsStream;
  late Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _callsStream;
  // The tours this user belongs to. Chats and calls outside them are not shown.
  Set<String> _myTourIds = const {};
  StreamSubscription<List<TourGroup>>? _myToursSub;
  bool _toursLoaded = false;
  bool _toursFailed = false;

  StreamSubscription<List<Map<String, dynamic>>>? _vpsConvSub;

  @override
  void initState() {
    super.initState();
    _loadOfflineConversations();
    _listenToVpsConversations();
  }

  @override
  void dispose() {
    _vpsConvSub?.cancel();
    _myToursSub?.cancel();
    super.dispose();
  }

  void _listenToVpsConversations() {
    _vpsConvSub?.cancel();
    _vpsConvSub = VpsChatService().conversationsStream.listen((vpsConvs) {
      if (!mounted) return;
      for (final conv in vpsConvs) {
        final id = conv['chatId'] as String? ?? conv['id'] as String?;
        if (id != null) {
          ChatLocalCache().cacheConversation(id, conv);
        }
      }
      setState(() {
        _offlineConversations = vpsConvs;
      });
    });
    unawaited(VpsChatService().fetchConversations());
  }

  Future<void> _loadOfflineConversations() async {
    await ChatLocalCache().init();
    final cached = await ChatLocalCache().getCachedConversations();
    final locked = ChatLocalCache().getLockedChatIds();
    if (mounted) {
      setState(() {
        if (cached.isNotEmpty) _offlineConversations = cached;
        _lockedChatIds = locked;
      });
    }
  }

  void _initiateCall({
    required bool isVideo,
    required String currentUid,
    required String otherUid,
    required String otherName,
    required String? avatarUrl,
    required String? sharedTourId,
    required String? remoteEmail,
  }) {
    if (otherUid.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot start call: user information is missing.'),
          backgroundColor: Color(0xFF1F2C34),
        ),
      );
      return;
    }

    if (sharedTourId == null || remoteEmail == null || remoteEmail.isEmpty) {
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
        'remoteEmail': remoteEmail,
        'sharedTourId': sharedTourId,
        'remoteUserName': otherName,
        'remoteAvatarUrl': avatarUrl,
        'isCaller': true,
        'isVideoCall': isVideo,
      },
    );
  }

  /// Follows the tours this user is in. Calls are shown only for those tours.
  void _listenToTours() {
    _myToursSub?.cancel();
    _myToursSub = TourGroupRepository().watchMyGroups().listen((groups) {
      if (!mounted) return;
      setState(() {
        _myTourIds = {for (final group in groups) group.id};
        _toursLoaded = true;
        _toursFailed = false;
      });
    }, onError: (Object _) {
      if (!mounted) return;
      setState(() => _toursFailed = true);
    });
  }

  /// The calls this user made or received. The rules let a list query filter on
  /// the caller or the callee field, but not on `participants`, so the list is
  /// built from those queries and merged here. Calls stored with an email address
  /// instead of a uid are included too. The list is sorted where it is shown.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _recentCallsStream(
      String uid) {
    final email = TourGroupRepository().currentEmail;
    final calls = FirebaseFirestore.instance.collection('calls');
    final queries = <Query<Map<String, dynamic>>>[
      calls.where('callerId', isEqualTo: uid),
      calls.where('calleeId', isEqualTo: uid),
      if (email.isNotEmpty && email != uid) ...[
        calls.where('callerId', isEqualTo: email),
        calls.where('calleeId', isEqualTo: email),
      ],
    ];
    return mergeLatestLists<QueryDocumentSnapshot<Map<String, dynamic>>>(
      [for (final query in queries) query.snapshots().map((s) => s.docs)],
      idOf: (doc) => doc.id,
    );
  }

  /// Loads the calls and the tours again after a failed load.
  void _retryCalls() {
    final uid = _streamsUid;
    if (uid == null) return;
    if (_toursFailed) _listenToTours();
    setState(() {
      _toursFailed = false;
      _callsStream = _recentCallsStream(uid);
    });
  }

  void _ensureStreams(String uid) {
    if (_streamsUid == uid) return;
    _streamsUid = uid;
    _listenToTours();
    _blockedStream = FirebaseFirestore.instance
        .collection('explorer_profiles')
        .doc(uid)
        .collection('blocked_users')
        .snapshots();
    _chatsStream = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: uid)
        .snapshots();
    _callsStream = _recentCallsStream(uid);
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    final currentUid =
        authState is Authenticated ? authState.profile.uid : 'explorer_user';
    _ensureStreams(currentUid);

    return PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go('/group-hub');
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B141A), // WhatsApp dark background
        appBar: AppBar(
          backgroundColor: const Color(0xFF1F2C34), // WhatsApp secondary bar
          elevation: 1,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/group-hub');
              }
            },
          ),
          title: Text(
            _bottomNavIndex == 0 ? 'Bhromon Chat' : 'Calls',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.camera_alt_outlined, color: Colors.white),
              tooltip: 'Quick Camera',
              onPressed: _openQuickCamera,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              color: const Color(0xFF1F2C34),
              onSelected: (val) {
                if (val == 'new_chat') {
                  _showSelectTravelerSheet(context, currentUid);
                } else if (val == 'starred_messages') {
                  context.push('/starred-messages');
                } else if (val == 'locked_chats') {
                  _openLockedChats();
                } else if (val == 'tour_groups') {
                  context.push('/tour-groups');
                } else if (val == 'settings') {
                  context.push('/settings');
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'new_chat',
                  child:
                      Text('New chat', style: TextStyle(color: Colors.white)),
                ),
                const PopupMenuItem(
                  value: 'starred_messages',
                  child: Text('Starred messages',
                      style: TextStyle(color: Colors.white)),
                ),
                const PopupMenuItem(
                  value: 'locked_chats',
                  child: Text('Locked chats',
                      style: TextStyle(color: Colors.white)),
                ),
                const PopupMenuItem(
                  value: 'tour_groups',
                  child: Text('Tour Groups',
                      style: TextStyle(color: Colors.white)),
                ),
                const PopupMenuItem(
                  value: 'settings',
                  child:
                      Text('Settings', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(44),
            child: Row(
              children: [
                Expanded(child: _buildSectionTab('Chats', 0)),
                Expanded(child: _buildSectionTab('Calls', 1)),
              ],
            ),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: _bottomNavIndex == 0
                ? Column(
                    children: [
                      // WhatsApp styled Search Bar
                      Container(
                        color: const Color(0xFF1F2C34),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A3942),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: TextField(
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Search chats or messages...',
                              hintStyle: const TextStyle(
                                  color: Colors.white54, fontSize: 13),
                              prefixIcon: const Icon(Icons.search,
                                  color: Colors.white54, size: 18),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear,
                                          color: Colors.white54, size: 16),
                                      onPressed: () =>
                                          setState(() => _searchQuery = ''),
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 10),
                            ),
                            onChanged: (val) {
                              setState(() {
                                _searchQuery = val.trim().toLowerCase();
                              });
                            },
                          ),
                        ),
                      ),

                      // WhatsApp tabs (All, Unread, Favourites, Groups)
                      Container(
                        color: const Color(0xFF0B141A),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildTabButton('All'),
                              const SizedBox(width: 8),
                              _buildTabButton('Unread'),
                              const SizedBox(width: 8),
                              _buildTabButton('Favourites'),
                              const SizedBox(width: 8),
                              _buildTabButton('Groups'),
                            ],
                          ),
                        ),
                      ),

                      // Conversations List
                      Expanded(
                        child: StreamBuilder<QuerySnapshot>(
                          stream: _blockedStream,
                          builder: (context, blockSnapshot) {
                            final blockedUids = blockSnapshot.hasData
                                ? blockSnapshot.data!.docs
                                    .map((d) => d.id)
                                    .toSet()
                                : <String>{};

                            return StreamBuilder<QuerySnapshot>(
                              stream: _chatsStream,
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  if (_offlineConversations.isNotEmpty) {
                                    return _buildOfflineConversationsList(
                                        blockedUids, currentUid);
                                  }
                                  return const Center(
                                      child: CircularProgressIndicator(
                                          color: Color(0xFF00A884)));
                                }
                                if (snapshot.hasError) {
                                  if (_offlineConversations.isNotEmpty) {
                                    return _buildOfflineConversationsList(
                                        blockedUids, currentUid);
                                  }
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(24.0),
                                      child: Text(
                                        'Connecting to chat server...',
                                        style: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 13),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  );
                                }

                                final allDocs = (snapshot.data?.docs ?? [])
                                    .where((doc) => isInMyTours(
                                        doc.data() as Map<String, dynamic>?,
                                        _myTourIds))
                                    .toList();
                                for (final doc in allDocs) {
                                  final d = doc.data() as Map<String, dynamic>;
                                  ChatLocalCache().cacheConversation(
                                      doc.id, {'id': doc.id, ...d});
                                }

                                final chatListItems = allDocs.where((doc) {
                                  final data =
                                      doc.data() as Map<String, dynamic>;
                                  final participants = List<String>.from(
                                      data['participants'] as Iterable? ??
                                          <dynamic>[]);
                                  final otherUser = participants.firstWhere(
                                      (p) => p != currentUid,
                                      orElse: () => '');

                                  if (blockedUids.contains(otherUser)) {
                                    return false;
                                  }
                                  if (_lockedChatIds.contains(doc.id)) {
                                    return false;
                                  }

                                  // Match Search Query against UID or last message text
                                  if (_searchQuery.isNotEmpty) {
                                    final lastMsg =
                                        (data['lastMessage'] as String? ?? '')
                                            .toLowerCase();
                                    final otherUserLower =
                                        otherUser.toLowerCase();
                                    if (!lastMsg.contains(_searchQuery) &&
                                        !otherUserLower
                                            .contains(_searchQuery)) {
                                      return false;
                                    }
                                  }

                                  return true;
                                }).toList();

                                if (chatListItems.isEmpty) {
                                  return Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.chat_bubble_outline,
                                            size: 64,
                                            color: Colors.white
                                                .withValues(alpha: 0.08)),
                                        const SizedBox(height: 16),
                                        const Text(
                                          'No conversations here yet.',
                                          style: TextStyle(
                                              color: Colors.white54,
                                              fontSize: 13),
                                        ),
                                        const SizedBox(height: 8),
                                        const Text(
                                          'Tap the green button to start a chat!',
                                          style: TextStyle(
                                              color: Color(0xFF00A884),
                                              fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                return ListView.separated(
                                  separatorBuilder: (context, index) =>
                                      const Divider(
                                    color: Color(0xFF1F2C34),
                                    height: 1,
                                    indent: 72,
                                    endIndent: 16,
                                  ),
                                  padding:
                                      const EdgeInsets.fromLTRB(0, 8, 0, 80),
                                  itemCount: chatListItems.length,
                                  itemBuilder: (context, index) {
                                    final doc = chatListItems[index];
                                    final data =
                                        doc.data() as Map<String, dynamic>;
                                    final chatId = doc.id;
                                    final participants = List<String>.from(
                                        data['participants'] as Iterable? ??
                                            <dynamic>[]);
                                    final otherUserUid = participants
                                        .firstWhere((p) => p != currentUid,
                                            orElse: () => 'Guest');

                                    final String lastMsgMeta =
                                        (data['lastMessage'] as String?) ?? '';
                                    final String lastMsgType =
                                        (data['lastMessageType'] as String?) ??
                                            'text';
                                    final lastTimeMeta =
                                        data['lastMessageTime'] as Timestamp?;
                                    final lastSenderId =
                                        data['lastMessageSenderId'] as String?;
                                    final unreadCounts = data['unreadCounts']
                                            as Map<String, dynamic>? ??
                                        {};
                                    final unreadCount =
                                        (unreadCounts[currentUid] as num?)
                                                ?.toInt() ??
                                            0;
                                    final participantProfiles =
                                        data['participantProfiles']
                                            as Map<String, dynamic>?;
                                    final cachedProfile =
                                        participantProfiles?[otherUserUid]
                                            as Map<String, dynamic>?;

                                    return ChatTile(
                                      chatId: chatId,
                                      otherUserUid: otherUserUid,
                                      currentUid: currentUid,
                                      lastMessage: lastMsgMeta,
                                      lastMessageType: lastMsgType,
                                      lastTime: lastTimeMeta,
                                      lastMessageSenderId: lastSenderId,
                                      unreadCount: unreadCount,
                                      cachedOtherProfile: cachedProfile,
                                      activeTabFilter: _activeTab,
                                      onTap: () =>
                                          context.push('/chat/$chatId', extra: {
                                        'otherUid': otherUserUid,
                                        'sharedTourId': data['sharedTourId'],
                                        'otherEmail': (data['memberEmails']
                                            as Map?)?[otherUserUid]
                                      }),
                                      onLongPress: () => _showChatTileOptions(
                                          context, chatId, otherUserUid),
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  )
                : _buildCallsView(currentUid),
          ),
        ),
        bottomNavigationBar: const BhromonBottomNav(selectedIndex: 3),
        // WhatsApp style floating action button (FAB)
        floatingActionButton: FloatingActionButton(
          backgroundColor: const Color(0xFF00A884), // WhatsApp green
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child:
              Icon(_bottomNavIndex == 0 ? Icons.chat_bubble : Icons.add_call),
          onPressed: () => _showSelectTravelerSheet(context, currentUid),
        ),
      ),
    );
  }

  Widget _buildOfflineConversationsList(
      Set<String> blockedUids, String currentUid) {
    final filtered = _offlineConversations.where((data) {
      if (!isInMyTours(data, _myTourIds)) return false;
      final participants =
          List<String>.from(data['participants'] as Iterable? ?? <dynamic>[]);
      final otherUser =
          participants.firstWhere((p) => p != currentUid, orElse: () => '');
      if (blockedUids.contains(otherUser)) return false;
      final cId = (data['chatId'] ?? data['id'] ?? '') as String;
      if (_lockedChatIds.contains(cId)) return false;
      if (_searchQuery.isNotEmpty) {
        final lastMsg = (data['lastMessage'] as String? ?? '').toLowerCase();
        final otherUserLower = otherUser.toLowerCase();
        if (!lastMsg.contains(_searchQuery) &&
            !otherUserLower.contains(_searchQuery)) {
          return false;
        }
      }
      return true;
    }).toList();

    return ListView.separated(
      separatorBuilder: (context, index) => const Divider(
        color: Color(0xFF1F2C34),
        height: 1,
        indent: 72,
        endIndent: 16,
      ),
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 80),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final data = filtered[index];
        final chatId = (data['chatId'] ?? data['id'] ?? '') as String;
        final participants =
            List<String>.from(data['participants'] as Iterable? ?? <dynamic>[]);
        final otherUserUid = participants.firstWhere((p) => p != currentUid,
            orElse: () => 'Guest');
        final String lastMsgMeta = (data['lastMessage'] as String?) ?? '';
        final String lastMsgType = (data['lastMessageType'] as String?) ??
            (data['type'] as String?) ??
            'text';
        final unreadCounts =
            data['unreadCounts'] as Map<dynamic, dynamic>? ?? {};
        final unreadCount = (unreadCounts[currentUid] as num?)?.toInt() ?? 0;
        final participantProfiles =
            data['participantProfiles'] as Map<dynamic, dynamic>?;
        final cachedProfile = participantProfiles?[otherUserUid] != null
            ? Map<String, dynamic>.from(
                participantProfiles![otherUserUid] as Map)
            : null;

        final lastTimeRaw = data['lastMessageTime'] ?? data['lastTime'];
        final DateTime? lastTime = lastTimeRaw is int
            ? DateTime.fromMillisecondsSinceEpoch(lastTimeRaw)
            : (lastTimeRaw is Timestamp ? lastTimeRaw.toDate() : null);

        return ChatTile(
          chatId: chatId,
          otherUserUid: otherUserUid,
          currentUid: currentUid,
          lastMessage: lastMsgMeta,
          lastMessageType: lastMsgType,
          lastTime: lastTime != null ? Timestamp.fromDate(lastTime) : null,
          lastMessageSenderId:
              (data['lastSenderId'] ?? data['lastMessageSenderId']) as String?,
          unreadCount: unreadCount,
          cachedOtherProfile: cachedProfile,
          activeTabFilter: _activeTab,
          onTap: () => context.push('/chat/$chatId', extra: {
            'otherUid': otherUserUid,
            'sharedTourId': data['sharedTourId'],
            'otherEmail': (data['memberEmails'] as Map?)?[otherUserUid]
          }),
          onLongPress: () =>
              _showChatTileOptions(context, chatId, otherUserUid),
        );
      },
    );
  }

  static DateTime? _parseCallDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is String) return DateTime.tryParse(raw);
    if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    return null;
  }

  Widget _buildCallTile(
    BuildContext context, {
    required String displayName,
    required String? avatarUrl,
    required bool isCaller,
    required bool isMissed,
    required bool isVideo,
    required String timeStr,
    required int? durationSeconds,
    required VoidCallback? onTap,
  }) {
    final initials = displayName.trim().isNotEmpty
        ? displayName
            .trim()
            .substring(0, math.min(2, displayName.trim().length))
            .toUpperCase()
        : 'TR';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: const Color(0xFF005C4B),
        backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
            ? sizedImage(NetworkImage(avatarUrl), context.decodeWidth(48))
            : null,
        child: (avatarUrl == null || avatarUrl.isEmpty)
            ? Text(
                initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              )
            : null,
      ),
      title: Text(
        displayName,
        style: TextStyle(
          color: isMissed ? Colors.redAccent : Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
      subtitle: Row(
        children: [
          Icon(
            isMissed
                ? Icons.call_missed
                : (isCaller ? Icons.call_made : Icons.call_received),
            size: 15,
            color: isMissed ? Colors.redAccent : const Color(0xFF00A884),
          ),
          const SizedBox(width: 4),
          Text(
            timeStr +
                (durationSeconds != null && durationSeconds > 0
                    ? ' (${durationSeconds ~/ 60}m ${durationSeconds % 60}s)'
                    : ''),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
      trailing: IconButton(
        icon: Icon(
          isVideo ? Icons.videocam : Icons.call,
          color: onTap != null ? const Color(0xFF00A884) : Colors.white24,
          size: 22,
        ),
        onPressed: onTap,
      ),
      onTap: onTap,
    );
  }

  Widget _buildCallsView(String currentUid) {
    if (_toursFailed) {
      return _callsError(
          'Your tours could not be checked, so calls cannot be shown.',
          _retryCalls);
    }
    if (!_toursLoaded) {
      // Calls are filtered by tour, so wait for the tours before showing any.
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00A884)),
      );
    }
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: _callsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF00A884)),
          );
        }
        if (snapshot.hasError) {
          return _callsError('Your calls could not be loaded.', _retryCalls);
        }

        // Sorted here, newest first. The list is merged from several queries.
        final docs = (snapshot.data ??
                const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            .where((doc) => isInMyTours(doc.data(), _myTourIds))
            .toList()
          ..sort((a, b) {
            final aDate = _parseCallDate(a.data()['createdAt']);
            final bDate = _parseCallDate(b.data()['createdAt']);
            if (aDate == null && bDate == null) return 0;
            if (aDate == null) return 1;
            if (bDate == null) return -1;
            return bDate.compareTo(aDate);
          });

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_call,
                    size: 64, color: Colors.white.withValues(alpha: 0.08)),
                const SizedBox(height: 16),
                const Text(
                  'No recent calls.',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tap the green button to start a call!',
                  style: TextStyle(color: Color(0xFF00A884), fontSize: 11),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 80),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(
            color: Color(0xFF1F2C34),
            height: 1,
            indent: 72,
            endIndent: 16,
          ),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final callerId = data['callerId'] as String? ?? '';
            final calleeId = data['calleeId'] as String? ?? '';
            final isCaller = callerId == currentUid;
            final otherUid = isCaller ? calleeId : callerId;
            final isVideo = data['isVideo'] == true;
            final status = data['status'] as String? ?? 'ended';
            final callDate = _parseCallDate(data['createdAt']);
            final durationSeconds = (data['durationSeconds'] as num?)?.toInt();

            String timeStr = 'Recent';
            if (callDate != null) {
              final now = DateTime.now();
              final isToday = callDate.year == now.year &&
                  callDate.month == now.month &&
                  callDate.day == now.day;
              final hour = callDate.hour.toString().padLeft(2, '0');
              final minute = callDate.minute.toString().padLeft(2, '0');
              timeStr = isToday
                  ? 'Today, $hour:$minute'
                  : '${callDate.day}/${callDate.month}, $hour:$minute';
            }

            final isMissed =
                !isCaller && (status == 'declined' || status == 'calling');

            final callerNameInDoc = data['callerName'] as String?;
            final callerAvatarInDoc = data['callerAvatar'] as String?;

            // If otherUid is empty, display metadata from document without querying explorer_profiles
            if (otherUid.trim().isEmpty) {
              final fallbackName = callerNameInDoc?.trim().isNotEmpty == true
                  ? callerNameInDoc!
                  : 'Traveler';
              return _buildCallTile(
                context,
                displayName: fallbackName,
                avatarUrl: callerAvatarInDoc,
                isCaller: isCaller,
                isMissed: isMissed,
                isVideo: isVideo,
                timeStr: timeStr,
                durationSeconds: durationSeconds,
                onTap: null,
              );
            }

            return FutureBuilder<DocumentSnapshot>(
              future: DocFutureCache.instance.get(
                FirebaseFirestore.instance
                    .collection('explorer_profiles')
                    .doc(otherUid),
              ),
              builder: (context, profSnap) {
                final profData = profSnap.data?.data() as Map<String, dynamic>?;
                final otherName = (profData?['displayName'] as String?)
                            ?.trim()
                            .isNotEmpty ==
                        true
                    ? (profData!['displayName'] as String)
                    : (callerNameInDoc?.trim().isNotEmpty == true
                        ? callerNameInDoc!
                        : (otherUid.contains('@')
                            ? otherUid
                            : 'Traveler ${otherUid.substring(0, math.min(otherUid.length, 6))}'));
                final avatarUrl =
                    profData?['avatarUrl'] as String? ?? callerAvatarInDoc;

                return _buildCallTile(
                  context,
                  displayName: otherName,
                  avatarUrl: avatarUrl,
                  isCaller: isCaller,
                  isMissed: isMissed,
                  isVideo: isVideo,
                  timeStr: timeStr,
                  durationSeconds: durationSeconds,
                  onTap: () => _initiateCall(
                    isVideo: isVideo,
                    currentUid: currentUid,
                    otherUid: otherUid,
                    otherName: otherName,
                    avatarUrl: avatarUrl,
                    sharedTourId: data['sharedTourId'] as String?,
                    remoteEmail:
                        (data['memberEmails'] as Map?)?[otherUid] as String?,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _openQuickCamera() async {
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(source: ImageSource.camera);
      if (photo != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo captured. Select a chat to share it.'),
            backgroundColor: Color(0xFF00A884),
          ),
        );
      }
    } catch (e) {
      logError('Quick camera error: $e');
    }
  }

  /// One of the two sections at the top: Chats or Calls.
  Widget _buildSectionTab(String label, int index) {
    final selected = _bottomNavIndex == index;
    final color = selected ? const Color(0xFF00A884) : Colors.white60;
    return InkWell(
      onTap: () => setState(() => _bottomNavIndex = index),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? const Color(0xFF00A884) : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// A message with a button that loads the list again.
  Widget _callsError(String message, VoidCallback onRetry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 48, color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onRetry,
              child: const Text('Try again',
                  style: TextStyle(color: Color(0xFF00A884))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(String label) {
    final isSelected = _activeTab == label;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF005C4B) : const Color(0xFF1F2C34),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF00A884).withValues(alpha: 0.3)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF00A884) : Colors.white60,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// The people this user can chat or call: members of their own tours. Nothing
  /// outside those tours is loaded, so nobody can be found by searching the app.
  /// Reads the tours and their members from the server, not the local cache. A
  /// cached answer can still list a tour the person has left, or a member who has
  /// since been removed, so the list is only built from server answers. Throws when
  /// the server cannot be reached.
  static Future<List<GroupContact>> _loadGroupContacts() async {
    final repository = TourGroupRepository();
    final groups = await repository.fetchMyGroupsFromServer();
    final tours = <({String id, String name, List<TourMember> members})>[];
    for (final group in groups) {
      final members = await repository.fetchMembersFromServer(group.id);
      tours.add((id: group.id, name: group.name, members: members));
    }
    return groupContacts(
      myUid: repository.currentUid,
      myEmail: repository.currentEmail,
      tours: tours,
    );
  }

  void _showSelectTravelerSheet(BuildContext context, String currentUid) {
    final Future<List<GroupContact>> contactsFuture = _loadGroupContacts();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      backgroundColor: Colors.transparent,
      builder: (context) {
        String sheetSearch = '';
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.82,
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).padding.bottom + 12,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF1F2C34), // WhatsApp slate dark
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Start Conversation',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Only members of your tour groups',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A3942),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: TextField(
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'Search member name or tour...',
                          hintStyle:
                              TextStyle(color: Colors.white54, fontSize: 12),
                          prefixIcon: Icon(Icons.search,
                              color: Colors.white54, size: 18),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                        onChanged: (val) => setSheetState(() {
                          sheetSearch = val.trim().toLowerCase();
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: FutureBuilder<List<GroupContact>>(
                      future: contactsFuture,
                      builder: (context, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return const Center(
                              child: CircularProgressIndicator(
                                  color: Color(0xFF00A884)));
                        }
                        if (snap.hasError) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Could not load your travel companions. Check your connection and try again.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 12),
                              ),
                            ),
                          );
                        }
                        final contacts = (snap.data ?? const <GroupContact>[])
                            .where((c) =>
                                sheetSearch.isEmpty ||
                                c.name.toLowerCase().contains(sheetSearch) ||
                                c.tours.any((t) =>
                                    t.name.toLowerCase().contains(sheetSearch)))
                            .toList();

                        if (contacts.isEmpty) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Join or create a tour group to chat with its members.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 12),
                              ),
                            ),
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.all(8),
                          separatorBuilder: (context, index) =>
                              const Divider(color: Colors.white10, height: 1),
                          itemCount: contacts.length,
                          itemBuilder: (context, idx) {
                            final contact = contacts[idx];
                            final name = contact.name;
                            final avatarUrl = contact.photoUrl ?? '';
                            final initials = name.length > 2
                                ? name.substring(0, 2).toUpperCase()
                                : 'EX';

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              leading: CircleAvatar(
                                radius: 20,
                                backgroundColor: const Color(0xFF005C4B),
                                backgroundImage: avatarUrl.isNotEmpty
                                    ? sizedImage(NetworkImage(avatarUrl),
                                        context.decodeWidth(40))
                                    : null,
                                child: avatarUrl.isEmpty
                                    ? Text(initials,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12))
                                    : null,
                              ),
                              title: Text(name,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                              subtitle: Text(
                                contact.tours.map((t) => t.name).join(' · '),
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 11),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.call,
                                        color: Color(0xFF00A884), size: 20),
                                    tooltip: 'Audio Call',
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _initiateCall(
                                        isVideo: false,
                                        currentUid: currentUid,
                                        otherUid: contact.uid,
                                        otherName: name,
                                        avatarUrl: avatarUrl,
                                        sharedTourId: contact.sharedTourId,
                                        remoteEmail: contact.email,
                                      );
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.videocam,
                                        color: Color(0xFF00A884), size: 22),
                                    tooltip: 'Video Call',
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _initiateCall(
                                        isVideo: true,
                                        currentUid: currentUid,
                                        otherUid: contact.uid,
                                        otherName: name,
                                        avatarUrl: avatarUrl,
                                        sharedTourId: contact.sharedTourId,
                                        remoteEmail: contact.email,
                                      );
                                    },
                                  ),
                                ],
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                final uids = [currentUid, contact.uid]..sort();
                                GoRouter.of(context).push(
                                  '/chat/${uids.join('_')}',
                                  extra: {
                                    'otherUid': contact.uid,
                                    'sharedTourId': contact.sharedTourId,
                                    'otherEmail': contact.email,
                                  },
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openLockedChats() async {
    bool authenticated = false;
    if (!kIsWeb) {
      try {
        final auth = LocalAuthentication();
        final canCheck =
            await auth.canCheckBiometrics || await auth.isDeviceSupported();
        if (canCheck) {
          authenticated = await auth.authenticate(
            localizedReason:
                'Authenticate with Biometrics to view your locked chats',
            options: const AuthenticationOptions(
              biometricOnly: false,
              stickyAuth: true,
            ),
          );
        } else {
          authenticated = true;
        }
      } catch (e) {
        logWarning('Biometric authentication error: $e');
        authenticated = true;
      }
    } else {
      authenticated = true;
    }

    if (authenticated && mounted) {
      _showLockedChatsModal(context);
    }
  }

  void _showLockedChatsModal(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1F2C34),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final lockedIds = ChatLocalCache().getLockedChatIds();
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock, color: Color(0xFF00A884), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Locked Chats',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (lockedIds.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No chats are currently locked.\nLong-press any chat tile to lock it.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, height: 1.4),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: lockedIds.length,
                    itemBuilder: (context, idx) {
                      final cid = lockedIds.elementAt(idx);
                      return ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFF005C4B),
                          child: Icon(Icons.person, color: Colors.white),
                        ),
                        title: Text('Chat $cid',
                            style: const TextStyle(color: Colors.white)),
                        trailing: IconButton(
                          icon: const Icon(Icons.lock_open,
                              color: Colors.white54),
                          tooltip: 'Unlock chat',
                          onPressed: () async {
                            await ChatLocalCache().setChatLocked(cid, false);
                            if (mounted) {
                              setState(() {
                                _lockedChatIds =
                                    ChatLocalCache().getLockedChatIds();
                              });
                            }
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          context.push('/chat/$cid');
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showChatTileOptions(
      BuildContext context, String chatId, String otherUid) {
    final isLocked = _lockedChatIds.contains(chatId);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1F2C34),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                isLocked ? Icons.lock_open : Icons.lock_outline,
                color: const Color(0xFF00A884),
              ),
              title: Text(
                isLocked ? 'Unlock chat' : 'Lock chat',
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                isLocked
                    ? 'Allow chat to appear in standard list'
                    : 'Hide and protect this chat with biometrics',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(ctx);
                await ChatLocalCache().setChatLocked(chatId, !isLocked);
                if (mounted) {
                  setState(() {
                    _lockedChatIds = ChatLocalCache().getLockedChatIds();
                  });
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(isLocked
                          ? 'Chat unlocked'
                          : 'Chat locked behind biometrics'),
                      backgroundColor: const Color(0xFF00A884),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class ChatTile extends StatelessWidget {
  final String chatId;
  final String otherUserUid;
  final String currentUid;
  final String lastMessage;
  final String lastMessageType;
  final Timestamp? lastTime;
  final String? lastMessageSenderId;
  final int unreadCount;
  final Map<String, dynamic>? cachedOtherProfile;
  final String activeTabFilter;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const ChatTile({
    super.key,
    required this.chatId,
    required this.otherUserUid,
    required this.currentUid,
    required this.lastMessage,
    this.lastMessageType = 'text',
    this.lastTime,
    this.lastMessageSenderId,
    required this.unreadCount,
    this.cachedOtherProfile,
    required this.activeTabFilter,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    // Tab filters
    if (activeTabFilter == 'Unread' && unreadCount == 0) {
      return const SizedBox.shrink();
    }

    if (cachedOtherProfile != null) {
      final name =
          (cachedOtherProfile!['displayName'] as String?) ?? 'Traveler';
      final avatar = cachedOtherProfile!['avatarUrl'] as String?;
      final inits = name.length > 2 ? name.substring(0, 2).toUpperCase() : 'TR';
      return _buildTile(context,
          displayName: name, avatarUrl: avatar, initials: inits);
    }

    // Cached one-time fetch using DocFutureCache (zero long-lived stream overhead)
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: DocFutureCache.instance.get(
        FirebaseFirestore.instance
            .collection('explorer_profiles')
            .doc(otherUserUid),
      ),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final name = (data?['displayName'] as String?) ??
            'Traveler ${otherUserUid.substring(0, math.min(otherUserUid.length, 6))}';
        final avatar = data?['avatarUrl'] as String?;
        final inits =
            name.length > 2 ? name.substring(0, 2).toUpperCase() : 'TR';
        return _buildTile(context,
            displayName: name, avatarUrl: avatar, initials: inits);
      },
    );
  }

  Widget _buildTile(
    BuildContext context, {
    required String displayName,
    required String? avatarUrl,
    required String initials,
  }) {
    final bool isMe = lastMessageSenderId == currentUid;
    String timeStr = '';
    if (lastTime != null) {
      final date = lastTime!.toDate();
      timeStr = '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: const Color(0xFF005C4B),
        backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
            ? sizedImage(NetworkImage(avatarUrl), context.decodeWidth(48))
            : null,
        child: (avatarUrl == null || avatarUrl.isEmpty)
            ? Text(initials,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13))
            : null,
      ),
      title: Text(
        displayName,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
      ),
      subtitle: Row(
        children: [
          if (isMe && lastMessage.isNotEmpty) ...[
            const Icon(
              Icons.done_all,
              size: 16,
              color: Colors.white30,
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              lastMessage.isNotEmpty ? lastMessage : 'Start a chat...',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color:
                    unreadCount > 0 ? const Color(0xFF00A884) : Colors.white54,
                fontSize: 12,
                fontWeight:
                    unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            timeStr,
            style: TextStyle(
              color: unreadCount > 0 ? const Color(0xFF00A884) : Colors.white30,
              fontSize: 10,
              fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          if (unreadCount > 0) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF00A884),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                unreadCount >= 100 ? '99+' : '$unreadCount',
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
