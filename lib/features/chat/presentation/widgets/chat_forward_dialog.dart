import 'package:flutter/material.dart';
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
      backgroundColor: const Color(0xFF1F2C34),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        height: 480,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Text(
                  'Forward to...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Search field
            TextField(
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search chats...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                prefixIcon:
                    const Icon(Icons.search, color: Colors.white38, size: 18),
                filled: true,
                fillColor: const Color(0xFF2A3942),
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
                    return const Center(
                      child: Text(
                        'No other conversations found',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
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
                        orElse: () => 'Traveler',
                      );
                      final otherProfile =
                          (profiles[otherUid] as Map<String, dynamic>?) ?? {};
                      final name = (otherProfile['displayName'] as String?) ??
                          'Traveler ${otherUid.toString().substring(0, 4)}';

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
                          backgroundColor: const Color(0xFF005C4B),
                          radius: 18,
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'T',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                        ),
                        trailing: Icon(
                          _selectedChatId == doc.id
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: _selectedChatId == doc.id
                              ? const Color(0xFF00A884)
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
                  child: const Text('CANCEL',
                      style: TextStyle(color: Colors.white54)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00A884),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.send, size: 16, color: Colors.white),
                  label: const Text('FORWARD',
                      style: TextStyle(color: Colors.white)),
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
