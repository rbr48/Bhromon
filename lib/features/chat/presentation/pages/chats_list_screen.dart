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
import '../../../../core/utils/doc_future_cache.dart';
import '../../data/chat_local_cache.dart';

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
  late Stream<QuerySnapshot> _callsStream;

  @override
  void initState() {
    super.initState();
    _loadOfflineConversations();
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
  }) {
    if (otherUid == 'bhromon_ai_advisor') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Voice and Video calls with the AI Guide are coming soon!'),
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
        'remoteUserName': otherName,
        'remoteAvatarUrl': avatarUrl,
        'isCaller': true,
        'isVideoCall': isVideo,
      },
    );
  }

  void _ensureStreams(String uid) {
    if (_streamsUid == uid) return;
    _streamsUid = uid;
    _blockedStream = FirebaseFirestore.instance
        .collection('explorer_profiles')
        .doc(uid)
        .collection('blocked_users')
        .snapshots();
    _chatsStream = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: uid)
        .snapshots();
    _callsStream = FirebaseFirestore.instance
        .collection('calls')
        .where('participants', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    final currentUid =
        authState is Authenticated ? authState.profile.uid : 'explorer_user';
    _ensureStreams(currentUid);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go('/feed');
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B141A), // WhatsApp dark background
        appBar: AppBar(
          backgroundColor: const Color(0xFF1F2C34), // WhatsApp secondary bar
          elevation: 1,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => context.go('/feed'),
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
        ),
        body: _bottomNavIndex == 0
            ? Column(
                children: [
                  // WhatsApp styled Search Bar
                  Container(
                    color: const Color(0xFF1F2C34),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A3942),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: TextField(
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                            ? blockSnapshot.data!.docs.map((d) => d.id).toSet()
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
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Text(
                                    'Error loading chats: ${snapshot.error}',
                                    style: const TextStyle(
                                        color: Colors.redAccent, fontSize: 13),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              );
                            }

                            final allDocs = snapshot.data?.docs ?? [];
                            for (final doc in allDocs) {
                              final d = doc.data() as Map<String, dynamic>;
                              ChatLocalCache().cacheConversation(
                                  doc.id, {'id': doc.id, ...d});
                            }

                            final chatListItems = allDocs.where((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              final participants = List<String>.from(
                                  data['participants'] as Iterable? ??
                                      <dynamic>[]);
                              final otherUser = participants.firstWhere(
                                  (p) => p != currentUid,
                                  orElse: () => '');

                              if (blockedUids.contains(otherUser)) return false;
                              if (_lockedChatIds.contains(doc.id)) return false;

                              // Match Search Query against UID or last message text
                              if (_searchQuery.isNotEmpty) {
                                final lastMsg =
                                    (data['lastMessage'] as String? ?? '')
                                        .toLowerCase();
                                final otherUserLower = otherUser.toLowerCase();
                                if (!lastMsg.contains(_searchQuery) &&
                                    !otherUserLower.contains(_searchQuery)) {
                                  return false;
                                }
                              }

                              return true;
                            }).toList();

                            if (chatListItems.isEmpty) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.chat_bubble_outline,
                                        size: 64,
                                        color: Colors.white
                                            .withValues(alpha: 0.08)),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'No conversations here yet.',
                                      style: TextStyle(
                                          color: Colors.white54, fontSize: 13),
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
                              padding: const EdgeInsets.fromLTRB(0, 8, 0, 80),
                              itemCount: chatListItems.length,
                              itemBuilder: (context, index) {
                                final doc = chatListItems[index];
                                final data = doc.data() as Map<String, dynamic>;
                                final chatId = doc.id;
                                final participants = List<String>.from(
                                    data['participants'] as Iterable? ??
                                        <dynamic>[]);
                                final otherUserUid = participants.firstWhere(
                                    (p) => p != currentUid,
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
                                  onTap: () => context.push('/chat/$chatId',
                                      extra: {'otherUid': otherUserUid}),
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
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _bottomNavIndex,
          onTap: (index) => setState(() => _bottomNavIndex = index),
          backgroundColor: const Color(0xFF1F2C34),
          selectedItemColor: const Color(0xFF00A884),
          unselectedItemColor: Colors.white54,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.chat),
              label: 'Chats',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.call),
              label: 'Calls',
            ),
          ],
        ),
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
      final participants =
          List<String>.from(data['participants'] as Iterable? ?? <dynamic>[]);
      final otherUser =
          participants.firstWhere((p) => p != currentUid, orElse: () => '');
      if (blockedUids.contains(otherUser)) return false;
      if (_lockedChatIds.contains(data['id'] as String? ?? '')) return false;
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
        final chatId = data['id'] as String? ?? '';
        final participants =
            List<String>.from(data['participants'] as Iterable? ?? <dynamic>[]);
        final otherUserUid = participants.firstWhere((p) => p != currentUid,
            orElse: () => 'Guest');
        final String lastMsgMeta = (data['lastMessage'] as String?) ?? '';
        final String lastMsgType =
            (data['lastMessageType'] as String?) ?? 'text';
        final unreadCounts =
            data['unreadCounts'] as Map<dynamic, dynamic>? ?? {};
        final unreadCount = (unreadCounts[currentUid] as num?)?.toInt() ?? 0;
        final participantProfiles =
            data['participantProfiles'] as Map<dynamic, dynamic>?;
        final cachedProfile = participantProfiles?[otherUserUid] != null
            ? Map<String, dynamic>.from(
                participantProfiles![otherUserUid] as Map)
            : null;

        return ChatTile(
          chatId: chatId,
          otherUserUid: otherUserUid,
          currentUid: currentUid,
          lastMessage: lastMsgMeta,
          lastMessageType: lastMsgType,
          lastTime: null,
          lastMessageSenderId: data['lastMessageSenderId'] as String?,
          unreadCount: unreadCount,
          cachedOtherProfile: cachedProfile,
          activeTabFilter: _activeTab,
          onTap: () =>
              context.push('/chat/$chatId', extra: {'otherUid': otherUserUid}),
          onLongPress: () =>
              _showChatTileOptions(context, chatId, otherUserUid),
        );
      },
    );
  }

  Widget _buildCallsView(String currentUid) {
    return StreamBuilder<QuerySnapshot>(
      stream: _callsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF00A884)),
          );
        }
        final docs = snapshot.data?.docs ?? [];
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
            final data = doc.data() as Map<String, dynamic>;
            final callerId = data['callerId'] as String? ?? '';
            final calleeId = data['calleeId'] as String? ?? '';
            final isCaller = callerId == currentUid;
            final otherUid = isCaller ? calleeId : callerId;
            final isVideo = data['isVideo'] == true;
            final status = data['status'] as String? ?? 'ended';
            final createdAt = data['createdAt'] as Timestamp?;
            final durationSeconds = (data['durationSeconds'] as num?)?.toInt();

            String timeStr = 'Recent';
            if (createdAt != null) {
              final dt = createdAt.toDate();
              final now = DateTime.now();
              final isToday = dt.year == now.year &&
                  dt.month == now.month &&
                  dt.day == now.day;
              final hour = dt.hour.toString().padLeft(2, '0');
              final minute = dt.minute.toString().padLeft(2, '0');
              timeStr = isToday
                  ? 'Today, $hour:$minute'
                  : '${dt.day}/${dt.month}, $hour:$minute';
            }

            final isMissed =
                !isCaller && (status == 'declined' || status == 'calling');

            return FutureBuilder<DocumentSnapshot>(
              future: DocFutureCache.instance.get(
                FirebaseFirestore.instance
                    .collection('explorer_profiles')
                    .doc(otherUid),
              ),
              builder: (context, profSnap) {
                final profData = profSnap.data?.data() as Map<String, dynamic>?;
                final otherName =
                    (profData?['displayName'] as String?) ?? 'Traveler';
                final avatarUrl = profData?['avatarUrl'] as String?;
                final initials =
                    otherName.isNotEmpty ? otherName[0].toUpperCase() : 'T';

                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0xFF005C4B),
                    backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                        ? sizedImage(
                            NetworkImage(avatarUrl), context.decodeWidth(48))
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
                    otherName,
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
                            : (isCaller
                                ? Icons.call_made
                                : Icons.call_received),
                        size: 15,
                        color: isMissed
                            ? Colors.redAccent
                            : const Color(0xFF00A884),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        timeStr +
                            (durationSeconds != null && durationSeconds > 0
                                ? ' (${durationSeconds ~/ 60}m ${durationSeconds % 60}s)'
                                : ''),
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      isVideo ? Icons.videocam : Icons.call,
                      color: const Color(0xFF00A884),
                      size: 22,
                    ),
                    onPressed: () => _initiateCall(
                      isVideo: isVideo,
                      currentUid: currentUid,
                      otherUid: otherUid,
                      otherName: otherName,
                      avatarUrl: avatarUrl,
                    ),
                  ),
                  onTap: () => _initiateCall(
                    isVideo: isVideo,
                    currentUid: currentUid,
                    otherUid: otherUid,
                    otherName: otherName,
                    avatarUrl: avatarUrl,
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
      debugPrint('Quick camera error: $e');
    }
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

  /// How many travelers the picker loads before any search.
  static const int _kTravelerPickerLimit = 100;

  /// Name-prefix lookups so travelers outside the first page can be found.
  static Future<List<QueryDocumentSnapshot>> _searchTravelersByName(
      String raw) async {
    final variants = {
      raw,
      raw[0].toUpperCase() + raw.substring(1),
    };
    final profiles = FirebaseFirestore.instance.collection('explorer_profiles');
    final snaps = await Future.wait(variants.map((prefix) => profiles
        .where('displayName', isGreaterThanOrEqualTo: prefix)
        .where('displayName', isLessThan: '$prefix\uf8ff')
        .limit(20)
        .get()));
    return [for (final snap in snaps) ...snap.docs];
  }

  void _showSelectTravelerSheet(BuildContext context, String currentUid) {
    // One bounded read when the sheet opens. This used to be a live listener
    // on every profile in the app, re-subscribed on each keystroke.
    final Future<List<QueryDocumentSnapshot>> baseDocs = FirebaseFirestore
        .instance
        .collection('explorer_profiles')
        .orderBy('explorerScore.value', descending: true)
        .limit(_kTravelerPickerLimit)
        .get()
        .then((snap) => snap.docs);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      backgroundColor: Colors.transparent,
      builder: (context) {
        String sheetSearch = '';
        Future<List<QueryDocumentSnapshot>> docsFuture = baseDocs;
        Timer? searchDebounce;
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
                  const SizedBox(height: 12),
                  // Search bar in bottom sheet
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
                          hintText: 'Search traveler name or division...',
                          hintStyle:
                              TextStyle(color: Colors.white54, fontSize: 12),
                          prefixIcon: Icon(Icons.search,
                              color: Colors.white54, size: 18),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                        onChanged: (val) {
                          setSheetState(() {
                            sheetSearch = val.trim().toLowerCase();
                          });
                          // Ask the server only once typing pauses.
                          searchDebounce?.cancel();
                          final raw = val.trim();
                          searchDebounce =
                              Timer(const Duration(milliseconds: 350), () {
                            if (!ctx.mounted) return;
                            setSheetState(() {
                              docsFuture = raw.length < 2
                                  ? baseDocs
                                  : Future.wait([
                                      baseDocs,
                                      _searchTravelersByName(raw),
                                    ]).then((lists) {
                                      final seen = <String>{};
                                      return [
                                        for (final doc
                                            in lists.expand((l) => l))
                                          if (seen.add(doc.id)) doc,
                                      ];
                                    });
                            });
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: FutureBuilder<List<QueryDocumentSnapshot>>(
                      future: docsFuture,
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return const Center(
                              child: CircularProgressIndicator(
                                  color: Color(0xFF00A884)));
                        }
                        final travelers = snap.data!.where((doc) {
                          if (doc.id == currentUid) return false;
                          final data = doc.data() as Map<String, dynamic>;
                          final name = (data['displayName'] as String? ?? '')
                              .toLowerCase();
                          final div =
                              (data['division'] as String? ?? '').toLowerCase();
                          return sheetSearch.isEmpty ||
                              name.contains(sheetSearch) ||
                              div.contains(sheetSearch);
                        }).toList();

                        final List<Map<String, dynamic>> travelerList =
                            travelers.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return <String, dynamic>{
                            'uid': doc.id,
                            'displayName': (data['displayName'] as String?)
                                        ?.trim()
                                        .isNotEmpty ==
                                    true
                                ? data['displayName'] as String
                                : 'Traveler',
                            'avatarUrl': (data['avatarUrl'] as String?) ?? '',
                            'division':
                                (data['division'] as String?) ?? 'Explorer',
                          };
                        }).toList();

                        // Add AI Companion at the top if search is empty or matches
                        if (sheetSearch.isEmpty ||
                            'bhromon ai guide'.contains(sheetSearch)) {
                          travelerList.insert(0, {
                            'uid': 'bhromon_ai_advisor',
                            'displayName': 'Bhromon AI Guide',
                            'avatarUrl': '',
                            'division': '✨ AI Assistant',
                          });
                        }

                        if (travelerList.isEmpty) {
                          return const Center(
                            child: Text('No other travelers registered yet.',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 12)),
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.all(8),
                          separatorBuilder: (context, index) =>
                              const Divider(color: Colors.white10, height: 1),
                          itemCount: travelerList.length,
                          itemBuilder: (context, idx) {
                            final traveler = travelerList[idx];
                            final String name =
                                traveler['displayName'] as String;
                            final String avatarUrl =
                                traveler['avatarUrl'] as String;
                            final String division =
                                traveler['division'] as String;
                            final String targetUid = traveler['uid'] as String;

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
                              subtitle: Text(division,
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 11)),
                              trailing: targetUid == 'bhromon_ai_advisor'
                                  ? null
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.call,
                                              color: Color(0xFF00A884),
                                              size: 20),
                                          tooltip: 'Audio Call',
                                          onPressed: () {
                                            Navigator.pop(context);
                                            _initiateCall(
                                              isVideo: false,
                                              currentUid: currentUid,
                                              otherUid: targetUid,
                                              otherName: name,
                                              avatarUrl: avatarUrl,
                                            );
                                          },
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.videocam,
                                              color: Color(0xFF00A884),
                                              size: 22),
                                          tooltip: 'Video Call',
                                          onPressed: () {
                                            Navigator.pop(context);
                                            _initiateCall(
                                              isVideo: true,
                                              currentUid: currentUid,
                                              otherUid: targetUid,
                                              otherName: name,
                                              avatarUrl: avatarUrl,
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                              onTap: () {
                                Navigator.pop(context); // close sheet
                                final uids = [currentUid, targetUid]..sort();
                                final chatId = uids.join('_');
                                GoRouter.of(context).push('/chat/$chatId',
                                    extra: {'otherUid': targetUid});
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
        debugPrint('Biometric authentication error: $e');
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

    if (otherUserUid == 'bhromon_ai_advisor') {
      return _buildTile(
        context,
        displayName: 'Bhromon AI Guide',
        avatarUrl: null,
        initials: 'AI',
      );
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
