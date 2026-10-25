import 'package:flutter/material.dart';

import '../../../../core/theme/colors.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/tour_activity_models.dart';

class GroupChannelsScreen extends StatefulWidget {
  final String tourId;

  const GroupChannelsScreen({super.key, required this.tourId});

  @override
  State<GroupChannelsScreen> createState() => _GroupChannelsScreenState();
}

class _GroupChannelsScreenState extends State<GroupChannelsScreen>
    with SingleTickerProviderStateMixin {
  static const List<String> _channels = [
    'general',
    'food',
    'sightseeing',
    'emergency',
  ];

  final TourGroupRepository _repository = TourGroupRepository();
  late final TabController _tabController =
      TabController(length: _channels.length, vsync: this);

  // Each channel keeps its own draft and stream, so a draft typed in one
  // channel never appears in another, and a rebuild does not re-subscribe.
  final Map<String, TextEditingController> _drafts = {};
  final Map<String, Stream<List<ChannelMessage>>> _streams = {};
  final Set<String> _sending = {};

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in _drafts.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _draftFor(String channel) =>
      _drafts.putIfAbsent(channel, TextEditingController.new);

  Stream<List<ChannelMessage>> _streamFor(String channel) =>
      _streams.putIfAbsent(channel,
          () => _repository.watchChannelMessages(widget.tourId, channel));

  String _title(String channel) {
    switch (channel) {
      case 'general':
        return '# সাধারণ আড্ডা';
      case 'food':
        return '# খাবার ও রেস্তোরাঁ';
      case 'sightseeing':
        return '# ঘোরাঘুরি ও স্পট';
      case 'emergency':
        return '# জরুরি ও নিরাপত্তা';
      default:
        return '# $channel';
    }
  }

  Future<void> _send(String channel) async {
    final draft = _draftFor(channel);
    final text = draft.text.trim();
    if (text.isEmpty || _sending.contains(channel)) return;

    setState(() => _sending.add(channel));
    try {
      await _repository.sendChannelMessage(widget.tourId, channel, text);
      // Cleared only after the message is accepted, so a failure keeps the text.
      if (draft.text.trim() == text) draft.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('বার্তা পাঠানো যায়নি। লেখাটি রইল: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending.remove(channel));
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
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.mintGreen,
          labelColor: AppColors.mintGreen,
          unselectedLabelColor: Colors.white60,
          isScrollable: true,
          tabs: _channels.map((ch) => Tab(text: _title(ch))).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _channels.map(_buildChannel).toList(),
      ),
    );
  }

  Widget _buildChannel(String channel) {
    final draft = _draftFor(channel);
    final me = _repository.currentEmail;

    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<ChannelMessage>>(
            stream: _streamFor(channel),
            builder: (context, snapshot) {
              if (snapshot.hasError && !snapshot.hasData) {
                return const Center(
                  child: Text('বার্তা লোড করা যায়নি।',
                      style: TextStyle(color: Colors.white54)),
                );
              }
              if (!snapshot.hasData) {
                return const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.midGreen));
              }
              final messages = snapshot.data!;
              if (messages.isEmpty) {
                return const Center(
                  child: Text(
                    'এখনও কোনো বার্তা নেই। সবাইকে হ্যালো বলুন!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38),
                  ),
                );
              }

              return ListView.builder(
                reverse: true,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                itemCount: messages.length,
                itemBuilder: (context, i) {
                  final m = messages[i];
                  final isMe = m.isSentBy(me);
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
                              m.senderName,
                              style: const TextStyle(
                                  color: AppColors.gold,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold),
                            ),
                          const SizedBox(height: 2),
                          Text(
                            m.text,
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
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: draft,
                    maxLength: 1000,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(channel),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'বার্তা লিখুন...',
                      hintStyle:
                          const TextStyle(color: Colors.white30, fontSize: 13),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'পাঠান',
                  icon: _sending.contains(channel)
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: AppColors.mintGreen, strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded,
                          color: AppColors.mintGreen),
                  onPressed:
                      _sending.contains(channel) ? null : () => _send(channel),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
