import 'dart:async';
import 'package:bhromon/features/chat/presentation/chat_palette.dart';
import 'package:bhromon/core/media/media_access.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:local_auth/local_auth.dart';
import 'dart:math' as math;
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../../../core/services/battery_guidance.dart';
import '../../../../core/utils/image_sizing.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/localized_date.dart';
import '../../../../core/utils/doc_future_cache.dart';
import '../../data/call_history_stream.dart';
import '../../data/chat_deletion_service.dart';
import '../../data/chat_local_cache.dart';
import '../../data/vps_chat_service.dart';
import '../../domain/chat_deletion.dart';
import '../widgets/chat_delete_dialogs.dart';
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
  late final PageController _pageController;
  List<Map<String, dynamic>> _offlineConversations = [];
  Set<String> _lockedChatIds = {};
  // The chat documents from the latest snapshot, so a locked chat can show
  // the other person's name instead of its id.
  Map<String, Map<String, dynamic>> _chatDataById = {};

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
    _pageController = PageController(initialPage: _bottomNavIndex);
    _loadOfflineConversations();
    _listenToVpsConversations();
    // The battery guidance waits until the list is on screen, so it never
    // covers a call that is connecting.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(BatteryGuidance.maybeShowDue(context));
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
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
        SnackBar(
          content: Text(context.l10n.translate('chats_call_no_user')),
          backgroundColor: const Color(0xFF1F2C34),
        ),
      );
      return;
    }

    if (sharedTourId == null || remoteEmail == null || remoteEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.translate('chats_call_members_only')),
          backgroundColor: const Color(0xFF1F2C34),
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
        backgroundColor: context.chat.wallpaper, // WhatsApp dark background
        appBar: AppBar(
          backgroundColor: context.chat.bar, // WhatsApp secondary bar
          elevation: 1,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: context.chat.text),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/group-hub');
              }
            },
          ),
          title: Text(
            _bottomNavIndex == 0
                ? context.l10n.translate('chats_title')
                : context.l10n.translate('chats_calls_title'),
            style: TextStyle(
              color: context.chat.text,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          actions: [
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: context.chat.text),
              color: context.chat.bar,
              onSelected: (val) {
                if (val == 'new_chat') {
                  _showSelectTravelerSheet(context, currentUid);
                } else if (val == 'starred_messages') {
                  context.push('/starred-messages');
                } else if (val == 'locked_chats') {
                  _openLockedChats(currentUid);
                } else if (val == 'tour_groups') {
                  context.push('/group-hub');
                } else if (val == 'settings') {
                  context.push('/settings');
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'new_chat',
                  child: Text(context.l10n.translate('chats_menu_new_chat'),
                      style: TextStyle(color: context.chat.text)),
                ),
                PopupMenuItem(
                  value: 'starred_messages',
                  child: Text(context.l10n.translate('chats_menu_starred'),
                      style: TextStyle(color: context.chat.text)),
                ),
                PopupMenuItem(
                  value: 'locked_chats',
                  child: Text(context.l10n.translate('chats_menu_locked'),
                      style: TextStyle(color: context.chat.text)),
                ),
                PopupMenuItem(
                  value: 'tour_groups',
                  child: Text(context.l10n.translate('chats_menu_groups'),
                      style: TextStyle(color: context.chat.text)),
                ),
                PopupMenuItem(
                  value: 'settings',
                  child: Text(context.l10n.translate('chats_menu_settings'),
                      style: TextStyle(color: context.chat.text)),
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
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) {
                if (_bottomNavIndex != index) {
                  setState(() => _bottomNavIndex = index);
                }
              },
              children: [
                Column(
                    children: [
                      // WhatsApp styled Search Bar
                      Container(
                        color: context.chat.bar,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: context.chat.field,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: TextField(
                            style: TextStyle(
                                color: context.chat.text, fontSize: 13),
                            decoration: InputDecoration(
                              hintText:
                                  context.l10n.translate('chats_search_hint'),
                              hintStyle: TextStyle(
                                  color: context.chat.text54, fontSize: 13),
                              prefixIcon: Icon(Icons.search,
                                  color: context.chat.text54, size: 18),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: Icon(Icons.clear,
                                          color: context.chat.text54, size: 16),
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
                        color: context.chat.wallpaper,
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
                                  return Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(24.0),
                                      child: Text(
                                        context.l10n
                                            .translate('chats_connecting'),
                                        style: TextStyle(
                                            color: context.chat.text54,
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
                                _chatDataById = {
                                  for (final doc in allDocs)
                                    doc.id: doc.data() as Map<String, dynamic>,
                                };
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
                                  // A chat this person deleted stays hidden until a newer message arrives.
                                  if (isChatHiddenByCutoff(
                                    clearedAt: ChatDeletionService.clearedAtOf(
                                        data, currentUid),
                                    lastMessageAt:
                                        ChatDeletionService.timestampOf(
                                            data['lastMessageTime']),
                                  )) {
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
                                            color: context.chat.text
                                                .withValues(alpha: 0.08)),
                                        const SizedBox(height: 16),
                                        Text(
                                          context.l10n
                                              .translate('chats_empty_title'),
                                          style: TextStyle(
                                              color: context.chat.text54,
                                              fontSize: 13),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          context.l10n
                                              .translate('chats_empty_hint'),
                                          style: TextStyle(
                                              color: context.chat.accentText,
                                              fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                return ListView.separated(
                                  key: const PageStorageKey<String>(
                                      'chats_list_scroll'),
                                  separatorBuilder: (context, index) => Divider(
                                    color: context.chat.bar,
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
                  ),
                _buildCallsView(currentUid),
              ],
            ),
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
      if (isChatHiddenByCutoff(
        clearedAt: ChatDeletionService.clearedAtOf(data, currentUid),
        lastMessageAt: ChatDeletionService.timestampOf(
            data['lastMessageTime'] ?? data['lastTime']),
      )) {
        return false;
      }
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
      separatorBuilder: (context, index) => Divider(
        color: context.chat.bar,
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
        backgroundColor: context.chat.outgoing,
        backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
            ? sizedImage(NetworkImage(signedMediaUrl(avatarUrl)),
                context.decodeWidth(48))
            : null,
        child: (avatarUrl == null || avatarUrl.isEmpty)
            ? Text(
                initials,
                style: TextStyle(
                  color: context.chat.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              )
            : null,
      ),
      title: Text(
        displayName,
        style: TextStyle(
          color: isMissed ? Colors.redAccent : context.chat.text,
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
            color: isMissed ? Colors.redAccent : context.chat.accentText,
          ),
          const SizedBox(width: 4),
          Text(
            timeStr +
                (durationSeconds != null && durationSeconds > 0
                    ? ' (${context.l10n.translate('chats_call_duration', args: {
                            'm': durationSeconds ~/ 60,
                            's': durationSeconds % 60
                          })})'
                    : ''),
            style: TextStyle(color: context.chat.text54, fontSize: 12),
          ),
        ],
      ),
      trailing: IconButton(
        icon: Icon(
          isVideo ? Icons.videocam : Icons.call,
          color: onTap != null ? context.chat.accentText : context.chat.text24,
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
          context.l10n.translate('chats_calls_error_tours'), _retryCalls);
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
          return _callsError(
              context.l10n.translate('chats_calls_error'), _retryCalls);
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
                    size: 64, color: context.chat.text.withValues(alpha: 0.08)),
                const SizedBox(height: 16),
                Text(
                  context.l10n.translate('chats_calls_empty_title'),
                  style: TextStyle(color: context.chat.text54, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.translate('chats_calls_empty_hint'),
                  style:
                      TextStyle(color: context.chat.accentText, fontSize: 11),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          key: const PageStorageKey<String>('calls_list_scroll'),
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 80),
          itemCount: docs.length,
          separatorBuilder: (_, __) => Divider(
            color: context.chat.bar,
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

            String timeStr = context.l10n.translate('chats_calls_recent');
            if (callDate != null) {
              timeStr = _chatTimeLabel(callDate);
            }

            final isMissed =
                !isCaller && (status == 'declined' || status == 'calling');

            final callerNameInDoc = data['callerName'] as String?;
            final callerAvatarInDoc = data['callerAvatar'] as String?;

            // If otherUid is empty, display metadata from document without querying explorer_profiles
            if (otherUid.trim().isEmpty) {
              final fallbackName = callerNameInDoc?.trim().isNotEmpty == true
                  ? callerNameInDoc!
                  : 'Member';
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
                final otherName =
                    (profData?['displayName'] as String?)?.trim().isNotEmpty ==
                            true
                        ? (profData!['displayName'] as String)
                        : (callerNameInDoc?.trim().isNotEmpty == true
                            ? callerNameInDoc!
                            : (otherUid.contains('@')
                                ? otherUid
                                : context.l10n.translate('chats_member')));
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

  /// One of the two sections at the top: Chats or Calls.
  /// The text of a section tab. The tab's id stays English.
  String _sectionLabel(BuildContext context, String id) => context.l10n
      .translate(id == 'Calls' ? 'chats_calls_title' : 'chats_tab_chats');

  /// The text of a filter tab. The id stays English, because the filters
  /// compare against it.
  String _tabLabel(BuildContext context, String id) {
    final key = switch (id) {
      'Unread' => 'chats_filter_unread',
      'Favourites' => 'chats_filter_favourites',
      'Groups' => 'chats_filter_groups',
      _ => 'chats_filter_all',
    };
    return context.l10n.translate(key);
  }

  Widget _buildSectionTab(String label, int index) {
    final selected = _bottomNavIndex == index;
    final color = selected ? const Color(0xFF00A884) : context.chat.text60;
    return InkWell(
      onTap: () {
        if (_bottomNavIndex != index) {
          setState(() => _bottomNavIndex = index);
          if (_pageController.hasClients) {
            _pageController.animateToPage(
              index,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        }
      },
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
          _sectionLabel(context, label),
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
                size: 48, color: context.chat.text.withValues(alpha: 0.15)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.chat.text54, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onRetry,
              child: Text(context.l10n.translate('chats_retry'),
                  style: TextStyle(color: context.chat.accentText)),
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
          color: isSelected ? context.chat.outgoing : context.chat.bar,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF00A884).withValues(alpha: 0.3)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          _tabLabel(context, label),
          style: TextStyle(
            color: isSelected ? context.chat.accentText : context.chat.text60,
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
              decoration: BoxDecoration(
                color: context.chat.bar, // WhatsApp slate dark
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.chat.divider12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      context.l10n.translate('chats_start_title'),
                      style: TextStyle(
                          color: context.chat.text,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      context.l10n.translate('chats_start_subtitle'),
                      style:
                          TextStyle(color: context.chat.text54, fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.chat.field,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: TextField(
                        style:
                            TextStyle(color: context.chat.text, fontSize: 13),
                        decoration: InputDecoration(
                          hintText:
                              context.l10n.translate('chats_start_search_hint'),
                          hintStyle: TextStyle(
                              color: context.chat.text54, fontSize: 12),
                          prefixIcon: Icon(Icons.search,
                              color: context.chat.text54, size: 18),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 10),
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
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                context.l10n.translate('chats_start_error'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: context.chat.text54, fontSize: 12),
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
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                context.l10n.translate('chats_start_empty'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: context.chat.text54, fontSize: 12),
                              ),
                            ),
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.all(8),
                          separatorBuilder: (context, index) =>
                              Divider(color: context.chat.divider10, height: 1),
                          itemCount: contacts.length,
                          itemBuilder: (context, idx) {
                            final contact = contacts[idx];
                            final name = contact.name;
                            final avatarUrl = contact.photoUrl ?? '';
                            final initials = _initialsOf(name);

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              leading: CircleAvatar(
                                radius: 20,
                                backgroundColor: context.chat.outgoing,
                                backgroundImage: avatarUrl.isNotEmpty
                                    ? sizedImage(
                                        NetworkImage(signedMediaUrl(avatarUrl)),
                                        context.decodeWidth(40))
                                    : null,
                                child: avatarUrl.isEmpty
                                    ? Text(initials,
                                        style: TextStyle(
                                            color: context.chat.text,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12))
                                    : null,
                              ),
                              title: Text(name,
                                  style: TextStyle(
                                      color: context.chat.text,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                              subtitle: Text(
                                contact.tours.map((t) => t.name).join(' · '),
                                style: TextStyle(
                                    color: context.chat.text54, fontSize: 11),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.call,
                                        color: context.chat.accentText,
                                        size: 20),
                                    tooltip: context.l10n
                                        .translate('chats_audio_call'),
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
                                    icon: Icon(Icons.videocam,
                                        color: context.chat.accentText,
                                        size: 22),
                                    tooltip: context.l10n
                                        .translate('chats_video_call'),
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

  Future<void> _openLockedChats(String currentUid) async {
    bool authenticated = false;
    if (!kIsWeb) {
      final biometricReason = context.l10n.translate('chats_biometric_reason');
      try {
        final auth = LocalAuthentication();
        final canCheck =
            await auth.canCheckBiometrics || await auth.isDeviceSupported();
        if (canCheck) {
          authenticated = await auth.authenticate(
            localizedReason: biometricReason,
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
      _showLockedChatsModal(context, currentUid);
    }
  }

  void _showLockedChatsModal(BuildContext context, String currentUid) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.chat.bar,
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
                  color: context.chat.text24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock, color: context.chat.accentText, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    context.l10n.translate('chats_locked_title'),
                    style: TextStyle(
                      color: context.chat.text,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (lockedIds.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    context.l10n.translate('chats_locked_empty'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.chat.text54, height: 1.4),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: lockedIds.length,
                    itemBuilder: (context, idx) {
                      final cid = lockedIds.elementAt(idx);
                      return _LockedChatTile(
                        data: _chatDataById[cid] ??
                            _offlineConversations.firstWhere(
                              (c) => (c['chatId'] ?? c['id']) == cid,
                              orElse: () => <String, dynamic>{},
                            ),
                        currentUid: currentUid,
                        onTap: () {
                          Navigator.pop(ctx);
                          context.push('/chat/$cid');
                        },
                        onUnlock: () async {
                          await ChatLocalCache().setChatLocked(cid, false);
                          if (mounted) {
                            setState(() {
                              _lockedChatIds =
                                  ChatLocalCache().getLockedChatIds();
                            });
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
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

  /// The other person's name in a chat, for the delete dialog.
  String _otherNameFor(String chatId, String otherUid) {
    final profiles =
        _chatDataById[chatId]?['participantProfiles'] as Map<String, dynamic>?;
    final name = (profiles?[otherUid] as Map?)?['displayName'] as String?;
    final clean = name?.trim() ?? '';
    return clean.isEmpty ? context.l10n.translate('chats_member') : clean;
  }

  void _showChatTileOptions(
      BuildContext context, String chatId, String otherUid) {
    final isLocked = _lockedChatIds.contains(chatId);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.chat.bar,
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
                color: context.chat.accentText,
              ),
              title: Text(
                isLocked
                    ? context.l10n.translate('chats_unlock')
                    : context.l10n.translate('chats_lock'),
                style: TextStyle(color: context.chat.text),
              ),
              subtitle: Text(
                isLocked
                    ? context.l10n.translate('chats_unlock_hint')
                    : context.l10n.translate('chats_lock_hint'),
                style: TextStyle(color: context.chat.text54, fontSize: 12),
              ),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(ctx);
                final unlockedMessage =
                    context.l10n.translate('chats_unlocked');
                final lockedMessage = context.l10n.translate('chats_locked');
                await ChatLocalCache().setChatLocked(chatId, !isLocked);
                if (mounted) {
                  setState(() {
                    _lockedChatIds = ChatLocalCache().getLockedChatIds();
                  });
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(isLocked ? unlockedMessage : lockedMessage),
                      backgroundColor: const Color(0xFF00A884),
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: Text(
                context.l10n.translate('chat_menu_delete_chat'),
                style: const TextStyle(color: Colors.redAccent),
              ),
              subtitle: Text(
                context.l10n.translate('chats_delete_chat_hint'),
                style: TextStyle(color: context.chat.text54, fontSize: 12),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                final uid = _streamsUid;
                if (uid == null || uid.isEmpty) return;
                final otherName = _otherNameFor(chatId, otherUid);
                final deleted = await showDeleteChatDialog(
                  context,
                  chatId: chatId,
                  uid: uid,
                  otherName: otherName,
                );
                if (deleted && mounted) {
                  setState(() {
                    _offlineConversations = _offlineConversations
                        .where((c) => (c['chatId'] ?? c['id']) != chatId)
                        .toList();
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The letters for an avatar: the first two of the name, or the whole name
/// when it is shorter.
String _initialsOf(String name) {
  final clean = name.trim();
  if (clean.isEmpty) return '?';
  return clean.substring(0, math.min(2, clean.length)).toUpperCase();
}

/// The time of a chat or call: the clock time when it is today, and the date
/// before that.
String _chatTimeLabel(DateTime date) {
  final now = DateTime.now();
  final isToday =
      date.year == now.year && date.month == now.month && date.day == now.day;
  return isToday
      ? localizedDateFormat('h:mm a').format(date)
      : localizedDateFormat('d MMM').format(date);
}

/// A locked chat in the locked-chats sheet: the other person's photo and
/// name, with actions to open the chat or unlock it.
class _LockedChatTile extends StatelessWidget {
  const _LockedChatTile({
    required this.data,
    required this.currentUid,
    required this.onTap,
    required this.onUnlock,
  });

  final Map<String, dynamic> data;
  final String currentUid;
  final VoidCallback onTap;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final participants =
        List<String>.from(data['participants'] as Iterable? ?? <dynamic>[]);
    final otherUid =
        participants.firstWhere((p) => p != currentUid, orElse: () => '');
    if (otherUid.isEmpty) {
      return _row(context,
          name: context.l10n.translate('chats_locked_unknown'),
          avatarUrl: null);
    }
    final profiles = data['participantProfiles'] as Map<String, dynamic>?;
    final cached = profiles?[otherUid] as Map<String, dynamic>?;
    if (cached != null) {
      return _row(context,
          name: (cached['displayName'] as String?) ??
              context.l10n.translate('chats_member'),
          avatarUrl: cached['avatarUrl'] as String?);
    }
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: DocFutureCache.instance.get(
        FirebaseFirestore.instance
            .collection('explorer_profiles')
            .doc(otherUid),
      ),
      builder: (context, snapshot) {
        final profile = snapshot.data?.data();
        return _row(context,
            name: (profile?['displayName'] as String?) ??
                context.l10n.translate('chats_member'),
            avatarUrl: profile?['avatarUrl'] as String?);
      },
    );
  }

  Widget _row(BuildContext context,
      {required String name, required String? avatarUrl}) {
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: context.chat.outgoing,
        backgroundImage: hasAvatar
            ? sizedImage(NetworkImage(signedMediaUrl(avatarUrl)),
                context.decodeWidth(40))
            : null,
        child: hasAvatar
            ? null
            : Text(_initialsOf(name),
                style: TextStyle(
                    color: context.chat.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
      ),
      title: Text(name, style: TextStyle(color: context.chat.text)),
      trailing: IconButton(
        icon: Icon(Icons.lock_open, color: context.chat.text54),
        tooltip: context.l10n.translate('chats_unlock'),
        onPressed: onUnlock,
      ),
      onTap: onTap,
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
      final name = (cachedOtherProfile!['displayName'] as String?) ??
          context.l10n.translate('chats_member');
      final avatar = cachedOtherProfile!['avatarUrl'] as String?;
      final inits = _initialsOf(name);
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
            context.l10n.translate('chats_member');
        final avatar = data?['avatarUrl'] as String?;
        final inits = _initialsOf(name);
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
      timeStr = _chatTimeLabel(lastTime!.toDate());
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: context.chat.outgoing,
        backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
            ? sizedImage(NetworkImage(signedMediaUrl(avatarUrl)),
                context.decodeWidth(48))
            : null,
        child: (avatarUrl == null || avatarUrl.isEmpty)
            ? Text(initials,
                style: TextStyle(
                    color: context.chat.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 13))
            : null,
      ),
      title: Text(
        displayName,
        style: TextStyle(
            color: context.chat.text,
            fontWeight: FontWeight.bold,
            fontSize: 14),
      ),
      subtitle: Row(
        children: [
          if (isMe && lastMessage.isNotEmpty) ...[
            Icon(
              Icons.done_all,
              size: 16,
              color: context.chat.text30,
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              lastMessage.isNotEmpty
                  ? lastMessage
                  : context.l10n.translate('chats_start_hint'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: unreadCount > 0
                    ? context.chat.accentText
                    : context.chat.text54,
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
              color: unreadCount > 0
                  ? context.chat.accentText
                  : context.chat.text30,
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
