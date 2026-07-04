import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'dart:math' as math;
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  String _activeTab = 'All'; // 'All' | 'Unread'
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    final currentUid =
        authState is Authenticated ? authState.profile.uid : 'explorer_user';

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
                        const TextStyle(color: Colors.white30, fontSize: 13),
                    prefixIcon: const Icon(Icons.search,
                        color: Colors.white30, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear,
                                color: Colors.white30, size: 16),
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
                stream: FirebaseFirestore.instance
                    .collection('explorer_profiles')
                    .doc(currentUid)
                    .collection('blocked_users')
                    .snapshots(),
                builder: (context, blockSnapshot) {
                  final blockedUids = blockSnapshot.hasData
                      ? blockSnapshot.data!.docs.map((d) => d.id).toSet()
                      : <String>{};

                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('chats')
                        .where('participants', arrayContains: currentUid)
                        .snapshots(),
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
                                    color: Colors.white24, fontSize: 13),
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
                        padding: const EdgeInsets.symmetric(vertical: 8),
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

  void _showSelectTravelerSheet(BuildContext context, String currentUid) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        String sheetSearch = '';
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              height: MediaQuery.of(ctx).size.height * 0.8,
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
                              TextStyle(color: Colors.white30, fontSize: 12),
                          prefixIcon: Icon(Icons.search,
                              color: Colors.white30, size: 18),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                        onChanged: (val) {
                          setSheetState(() {
                            sheetSearch = val.trim().toLowerCase();
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('explorer_profiles')
                          .snapshots(),
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return const Center(
                              child: CircularProgressIndicator(
                                  color: Color(0xFF00A884)));
                        }
                        final travelers = snap.data!.docs.where((doc) {
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
                                    color: Colors.white24, fontSize: 12)),
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
                                    ? NetworkImage(avatarUrl)
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
                                      color: Colors.white30, fontSize: 11)),
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

class ChatTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    // ── Stream 1: Get latest message details directly from the sub-collection ──
    final lastMsgStream = FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots();

    // ── Stream 2: Count unread messages from this other user ──
    final unreadStream = FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('senderId', isEqualTo: otherUserUid)
        .where('seen', isEqualTo: false)
        .snapshots();

    // ── Stream 3: Retrieve profile of the other explorer ──
    final profileStream = FirebaseFirestore.instance
        .collection('explorer_profiles')
        .doc(otherUserUid)
        .snapshots();

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
                        ? NetworkImage(avatarUrl)
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
                            '$unreadCount',
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
