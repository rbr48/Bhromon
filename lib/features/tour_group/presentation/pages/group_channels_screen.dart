import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../../data/tour_group_repository.dart';
import '../../../../core/theme/colors.dart';

class GroupChannelsScreen extends StatefulWidget {
  final String tourId;

  const GroupChannelsScreen({super.key, required this.tourId});

  @override
  State<GroupChannelsScreen> createState() => _GroupChannelsScreenState();
}

class _GroupChannelsScreenState extends State<GroupChannelsScreen>
    with SingleTickerProviderStateMixin {
  final TourGroupRepository _repository = TourGroupRepository();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _msgController = TextEditingController();
  final Uuid _uuid = const Uuid();

  final List<String> _channels = [
    'general',
    'food',
    'sightseeing',
    'emergency'
  ];
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _channels.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _msgController.dispose();
    super.dispose();
  }

  String _getChannelTitle(String ch) {
    switch (ch) {
      case 'general':
        return '# সাধারণ আড্ডা';
      case 'food':
        return '# খাবার ও রেস্তোরাঁ';
      case 'sightseeing':
        return '# ঘোরাঘুরি ও স্পট';
      case 'emergency':
        return '# জরুরি ও নিরাপত্তা';
      default:
        return '# $ch';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1A12),
        elevation: 0,
        title: const Text(
          'Group Channels (আলোচনা চ্যানেল)',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.mintGreen,
          labelColor: AppColors.mintGreen,
          unselectedLabelColor: Colors.white60,
          isScrollable: true,
          tabs: _channels.map((ch) => Tab(text: _getChannelTitle(ch))).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _channels.map((channelId) {
          return _buildChannelChatView(channelId);
        }).toList(),
      ),
    );
  }

  Widget _buildChannelChatView(String channelId) {
    final messagesStream = _firestore
        .collection('tours')
        .doc(widget.tourId)
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();

    return Column(
      children: [
        // Message list
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: messagesStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.midGreen));
              }

              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return Center(
                  child: Text(
                    'No messages in ${_getChannelTitle(channelId)} yet.\nSay hello to everyone!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white38),
                  ),
                );
              }

              return ListView.builder(
                reverse: true,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final data = docs[i].data();
                  final senderEmail = data['senderEmail'] as String? ?? '';
                  final senderName = data['senderName'] as String? ?? 'Member';
                  final text = data['text'] as String? ?? '';
                  final isMe = senderEmail == _repository.currentEmail;

                  return Align(
                    alignment:
                        isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.78),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color:
                            isMe ? AppColors.midGreen : const Color(0xFF1E3326),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(14),
                          topRight: const Radius.circular(14),
                          bottomLeft: Radius.circular(isMe ? 14 : 2),
                          bottomRight: Radius.circular(isMe ? 2 : 14),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isMe)
                            Text(
                              senderName,
                              style: const TextStyle(
                                color: AppColors.mintGreen,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          const SizedBox(height: 2),
                          Text(
                            text,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),

        // Input field bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            color: Color(0xFF14241B),
            border: Border(top: BorderSide(color: Colors.white10)),
          ),
          child: SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: TextField(
                      controller: _msgController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle:
                            TextStyle(color: Colors.white30, fontSize: 13),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send_rounded,
                      color: AppColors.mintGreen),
                  onPressed: () => _sendMessage(channelId),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _sendMessage(String channelId) async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    _msgController.clear();

    final msgId = _uuid.v4();
    await _firestore
        .collection('tours')
        .doc(widget.tourId)
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .doc(msgId)
        .set({
      'id': msgId,
      'text': text,
      'senderEmail': _repository.currentEmail,
      'senderName': _repository.currentDisplayName,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
