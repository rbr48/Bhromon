import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'dart:math' as math;
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../../../core/utils/image_sizing.dart';

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  String _activeTab = 'All'; // 'All' | 'Unread'
  String _searchQuery = '';

  // Built once per signed-in user, so typing in search or switching tabs
  // doesn't tear down and re-attach both Firestore listeners.
  String? _streamsUid;
  late Stream<QuerySnapshot> _blockedStream;
  late Stream<QuerySnapshot> _chatsStream;

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
          title: const Text(
            'Bhromon Chat',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.camera_alt_outlined, color: Colors.white),
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onPressed: () {},
            ),
          ],
        ),
        body: Column(
          children: [
            // WhatsApp styled Search Bar
            Container(
              color: const Color(0xFF1F2C34),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF2A3942),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextField(
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search chats or messages...',
                    hintStyle:
                        const TextStyle(color: Colors.white54, fontSize: 13),
                    prefixIcon: const Icon(Icons.search,
                        color: Colors.white54, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear,
                                color: Colors.white54, size: 16),
                            onPressed: () => setState(() => _searchQuery = ''),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val.trim().toLowerCase();
                    });
                  },
                ),
              ),
            ),

            // WhatsApp tabs (All, Unread)
            Container(
              color: const Color(0xFF0B141A),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _buildTabButton('All'),
                  const SizedBox(width: 8),
                  _buildTabButton('Unread'),
                ],
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
                      if (snapshot.connectionState == ConnectionState.waiting) {
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
                      final chatListItems = allDocs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final participants = List<String>.from(
                            data['participants'] as Iterable? ?? <dynamic>[]);
                        final otherUser = participants.firstWhere(
                            (p) => p != currentUid,
                            orElse: () => '');

                        if (blockedUids.contains(otherUser)) return false;

                        // Match Search Query against UID or last message text
                        if (_searchQuery.isNotEmpty) {
                          final lastMsg = (data['lastMessage'] as String? ?? '')
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
                                  color: Colors.white.withValues(alpha: 0.08)),
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
                                    color: Color(0xFF00A884), fontSize: 11),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.separated(
                        separatorBuilder: (context, index) => const Divider(
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
                              data['participants'] as Iterable? ?? <dynamic>[]);
                          final otherUserUid = participants.firstWhere(
                              (p) => p != currentUid,
                              orElse: () => 'Guest');

                          final String lastMsgMeta =
                              (data['lastMessage'] as String?) ?? '';
                          final lastTimeMeta =
                              data['lastMessageTime'] as Timestamp?;

                          return ChatTile(
                            chatId: chatId,
                            otherUserUid: otherUserUid,
                            currentUid: currentUid,
                            lastMessageMeta: lastMsgMeta,
                            lastTimeMeta: lastTimeMeta,
                            activeTabFilter: _activeTab,
                            onTap: () => context.push('/chat/$chatId',
                                extra: {'otherUid': otherUserUid}),
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
        // WhatsApp style floating action button (FAB)
        floatingActionButton: FloatingActionButton(
          backgroundColor: const Color(0xFF00A884), // WhatsApp green
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: const Icon(Icons.chat_bubble),
          onPressed: () => _showSelectTravelerSheet(context, currentUid),
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
}

class ChatTile extends StatefulWidget {
  final String chatId;
  final String otherUserUid;
  final String currentUid;
  final String lastMessageMeta;
  final Timestamp? lastTimeMeta;
  final String activeTabFilter;
  final VoidCallback onTap;

  const ChatTile({
    super.key,
    required this.chatId,
    required this.otherUserUid,
    required this.currentUid,
    required this.lastMessageMeta,
    this.lastTimeMeta,
    required this.activeTabFilter,
    required this.onTap,
  });

  @override
  State<ChatTile> createState() => _ChatTileState();
}

/// The unread badge shows "99+" past this, so the listener never needs more.
const int _kUnreadCap = 100;

class _ChatTileState extends State<ChatTile> {
  String get chatId => widget.chatId;
  String get otherUserUid => widget.otherUserUid;
  String get currentUid => widget.currentUid;
  String get lastMessageMeta => widget.lastMessageMeta;
  Timestamp? get lastTimeMeta => widget.lastTimeMeta;
  String get activeTabFilter => widget.activeTabFilter;
  VoidCallback get onTap => widget.onTap;

  // Listeners are created once per conversation. Building them in build()
  // re-subscribed three Firestore listeners per tile on every list update.
  late Stream<QuerySnapshot> lastMsgStream;
  late Stream<QuerySnapshot> unreadStream;
  late Stream<DocumentSnapshot> profileStream;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(ChatTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatId != chatId || oldWidget.otherUserUid != otherUserUid) {
      _subscribe();
    }
  }

  void _subscribe() {
    final messages = FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages');

    // ── Stream 1: Get latest message details directly from the sub-collection ──
    lastMsgStream =
        messages.orderBy('timestamp', descending: true).limit(1).snapshots();

    // ── Stream 2: Count unread messages from this other user ──
    unreadStream = messages
        .where('senderId', isEqualTo: otherUserUid)
        .where('seen', isEqualTo: false)
        .limit(_kUnreadCap)
        .snapshots();

    // ── Stream 3: Retrieve profile of the other explorer ──
    profileStream = FirebaseFirestore.instance
        .collection('explorer_profiles')
        .doc(otherUserUid)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: profileStream,
      builder: (context, profileSnap) {
        final profileData = profileSnap.data?.data() as Map<String, dynamic>?;
        final String displayName = otherUserUid == 'bhromon_ai_advisor'
            ? 'Bhromon AI Guide'
            : (profileData?['displayName'] as String? ??
                'Traveler ${otherUserUid.substring(0, math.min(otherUserUid.length, 6))}');
        final String? avatarUrl = otherUserUid == 'bhromon_ai_advisor'
            ? null
            : (profileData?['avatarUrl'] as String?);

        final initials = otherUserUid == 'bhromon_ai_advisor'
            ? 'AI'
            : (displayName.length > 2
                ? displayName.substring(0, 2).toUpperCase()
                : 'TR');

        return StreamBuilder<QuerySnapshot>(
          stream: unreadStream,
          builder: (context, unreadSnap) {
            final int unreadCount = unreadSnap.data?.docs.length ?? 0;

            // Apply tab filter: if tab is 'Unread' and unreadCount is 0, render nothing
            if (activeTabFilter == 'Unread' && unreadCount == 0) {
              return const SizedBox.shrink();
            }

            return StreamBuilder<QuerySnapshot>(
              stream: lastMsgStream,
              builder: (context, msgSnap) {
                String lastText = lastMessageMeta;
                Timestamp? lastTime = lastTimeMeta;
                bool isMe = false;
                bool seen = false;

                if (msgSnap.hasData && msgSnap.data!.docs.isNotEmpty) {
                  final mDoc = msgSnap.data!.docs.first;
                  final mData = mDoc.data() as Map<String, dynamic>;
                  lastText = mData['text'] as String? ?? '';
                  lastTime = mData['timestamp'] as Timestamp?;
                  isMe = mData['senderId'] == currentUid;
                  seen = mData['seen'] as bool? ?? false;
                }

                String timeStr = '';
                if (lastTime != null) {
                  final date = lastTime.toDate();
                  timeStr =
                      '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
                }

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
                    displayName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                  subtitle: Row(
                    children: [
                      if (isMe && lastText.isNotEmpty) ...[
                        Icon(
                          seen ? Icons.done_all : Icons.done,
                          size: 16,
                          color:
                              seen ? const Color(0xFF53BDEB) : Colors.white30,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          lastText.isNotEmpty ? lastText : 'Start a chat...',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: unreadCount > 0
                                ? const Color(0xFF00A884)
                                : Colors.white54,
                            fontSize: 12,
                            fontWeight: unreadCount > 0
                                ? FontWeight.bold
                                : FontWeight.normal,
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
                              ? const Color(0xFF00A884)
                              : Colors.white30,
                          fontSize: 10,
                          fontWeight: unreadCount > 0
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      if (unreadCount > 0) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(
                            color: Color(0xFF00A884),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            unreadCount >= _kUnreadCap ? '99+' : '$unreadCount',
                            style: const TextStyle(
                                color: Colors.black,
                                fontSize: 9,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                  onTap: onTap,
                );
              },
            );
          },
        );
      },
    );
  }
}
