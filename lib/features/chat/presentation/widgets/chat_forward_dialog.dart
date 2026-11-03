import 'package:flutter/material.dart';
import 'package:bhromon/features/chat/presentation/chat_palette.dart';
import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// WhatsApp-style Forward Message Dialog.
class ChatForwardDialog extends StatefulWidget {
  final String currentUid;
  final String forwardText;
  final String forwardType;
  final String? forwardMediaUrl;
  final void Function(String targetChatId) onForward;

  const ChatForwardDialog({
    super.key,
    required this.currentUid,
    required this.forwardText,
    required this.forwardType,
    this.forwardMediaUrl,
    required this.onForward,
  });

  @override
  State<ChatForwardDialog> createState() => _ChatForwardDialogState();
}

class _ChatForwardDialogState extends State<ChatForwardDialog> {
  String? _selectedChatId;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.chat.bar,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        height: 480,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  'Forward to...',
                  style: TextStyle(
                    color: context.chat.text,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close, color: context.chat.text70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Search field
            TextField(
              style: TextStyle(color: context.chat.text, fontSize: 13),
              decoration: InputDecoration(
                hintText: context.l10n.translate('chat_search_chats_hint'),
                hintStyle: TextStyle(color: context.chat.text38, fontSize: 13),
                prefixIcon:
                    Icon(Icons.search, color: context.chat.text38, size: 18),
                filled: true,
                fillColor: context.chat.field,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) =>
                  setState(() => _searchQuery = val.trim().toLowerCase()),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('chats')
                    .where('participants', arrayContains: widget.currentUid)
                    .snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(
                      child:
                          CircularProgressIndicator(color: Color(0xFF00A884)),
                    );
                  }
                  final docs = snap.data!.docs;
                  if (docs.isEmpty) {
                    return Center(
                      child: Text(
                        context.l10n.translate('chat_no_other_conversations'),
                        style:
                            TextStyle(color: context.chat.text54, fontSize: 12),
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, idx) {
                      final doc = docs[idx];
                      final data = doc.data() as Map<String, dynamic>;
                      final profiles = (data['participantProfiles']
                              as Map<String, dynamic>?) ??
                          {};
                      final participants =
                          (data['participants'] as List<dynamic>?) ?? [];
                      final otherUid = participants.firstWhere(
                        (p) => p != widget.currentUid,
                        orElse: () => context.l10n.translate('chats_member'),
                      );
                      final otherProfile =
                          (profiles[otherUid] as Map<String, dynamic>?) ?? {};
                      final name = (otherProfile['displayName'] as String?) ??
                          'Member ${otherUid.toString().substring(0, 4)}';

                      if (_searchQuery.isNotEmpty &&
                          !name.toLowerCase().contains(_searchQuery)) {
                        return const SizedBox.shrink();
                      }

                      final isSelected = _selectedChatId == doc.id;

                      return ListTile(
                        dense: true,
                        selected: isSelected,
                        selectedTileColor:
                            const Color(0xFF00A884).withValues(alpha: 0.15),
                        leading: CircleAvatar(
                          backgroundColor: context.chat.outgoing,
                          radius: 18,
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'T',
                            style: TextStyle(
                              color: context.chat.text,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        title: Text(
                          name,
                          style:
                              TextStyle(color: context.chat.text, fontSize: 13),
                        ),
                        trailing: Icon(
                          _selectedChatId == doc.id
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: _selectedChatId == doc.id
                              ? context.chat.accentText
                              : Colors.grey,
                        ),
                        onTap: () => setState(() => _selectedChatId = doc.id),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.l10n.translate('chat_cancel_action'),
                      style: TextStyle(color: context.chat.text54)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00A884),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.send, size: 16, color: Colors.white),
                  label: Text(context.l10n.translate('chat_forward_action'),
                      style: const TextStyle(color: Colors.white)),
                  onPressed: _selectedChatId == null
                      ? null
                      : () {
                          final targetId = _selectedChatId!;
                          Navigator.pop(context);
                          widget.onForward(targetId);
                        },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
