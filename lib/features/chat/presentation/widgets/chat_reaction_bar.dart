import 'package:flutter/material.dart';

/// WhatsApp-style emoji reaction bar and message reaction badge.
class ChatReactionBar extends StatelessWidget {
  final void Function(String emoji) onSelectEmoji;
  final VoidCallback onMore;

  const ChatReactionBar({
    super.key,
    required this.onSelectEmoji,
    required this.onMore,
  });

  static const List<String> kQuickEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2C34),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...kQuickEmojis.map(
            (emoji) => InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => onSelectEmoji(emoji),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  emoji,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onMore,
            child: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Color(0xFF2A3942),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add,
                color: Colors.white70,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill displayed below a message bubble showing aggregated reactions.
class ChatReactionBadge extends StatelessWidget {
  final Map<String, dynamic> reactions; // { uid: emoji }
  final VoidCallback? onTap;

  const ChatReactionBadge({
    super.key,
    required this.reactions,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    // Aggregate unique emojis and counts
    final Map<String, int> counts = {};
    for (final val in reactions.values) {
      final emoji = val.toString();
      if (emoji.isNotEmpty) {
        counts[emoji] = (counts[emoji] ?? 0) + 1;
      }
    }

    if (counts.isEmpty) return const SizedBox.shrink();

    // Sort by most frequent
    final sortedEmojis = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    final displayEmojis = sortedEmojis.take(3).toList();
    final total = reactions.length;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2C34),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF2A3942),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...displayEmojis.map(
              (e) => Text(e, style: const TextStyle(fontSize: 12)),
            ),
            if (total > 1) ...[
              const SizedBox(width: 3),
              Text(
                '$total',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// WhatsApp-style reaction details bottom sheet.
void showReactionDetailsSheet(
  BuildContext context, {
  required Map<String, dynamic> reactions,
  required String currentUid,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1F2C34),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final entries = reactions.entries.toList();
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Text(
                      'Reactions',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${entries.length}',
                      style: const TextStyle(
                        color: Color(0xFF00A884),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  itemBuilder: (context, idx) {
                    final uid = entries[idx].key;
                    final emoji = entries[idx].value.toString();
                    final isSelf = uid == currentUid;
                    return ListTile(
                      dense: true,
                      leading: Text(emoji, style: const TextStyle(fontSize: 24)),
                      title: Text(
                        isSelf ? 'You' : 'Traveler ${uid.substring(0, uid.length > 5 ? 5 : uid.length)}',
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                      trailing: isSelf
                          ? const Text(
                              'Tap to remove',
                              style: TextStyle(color: Colors.white38, fontSize: 11),
                            )
                          : null,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
