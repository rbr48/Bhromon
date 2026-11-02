import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/utils/logger.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../data/chat_deletion_service.dart';
import '../../domain/chat_deletion.dart';

/// WhatsApp-grade Starred Messages Screen.
///
/// Displays all messages bookmarked/starred across chats by the current user,
/// enabling instant retrieval of important trip notes, flight/train details,
/// shared coordinates, and payment records.
class StarredMessagesScreen extends StatelessWidget {
  const StarredMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    final currentUid = authState is Authenticated ? authState.profile.uid : '';

    return PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        context.go('/chats');
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B141A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1F2C34),
          elevation: 1,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/chats');
              }
            },
          ),
          title: Text(
            context.l10n.translate('chats_menu_starred'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: currentUid.isEmpty
            ? Center(
                child: Text(
                  context.l10n.translate('starred_sign_in'),
                  style: const TextStyle(color: Colors.white54),
                ),
              )
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                // The chats this person is in. Messages from a chat they deleted stay hidden.
                stream: FirebaseFirestore.instance
                    .collection('chats')
                    .where('participants', arrayContains: currentUid)
                    .snapshots(),
                builder: (context, chatsSnap) {
                  final cutoffs = <String, DateTime>{};
                  final chats = chatsSnap.data?.docs ??
                      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                  for (final chat in chats) {
                    final clearedAt = ChatDeletionService.clearedAtOf(
                        chat.data(), currentUid);
                    if (clearedAt != null) cutoffs[chat.id] = clearedAt;
                  }
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collectionGroup('messages')
                        .where('isStarred', isEqualTo: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF00A884),
                          ),
                        );
                      }

                      final allDocs = snapshot.data?.docs ?? [];
                      // Filter messages that belong to user or starred by user
                      final userStarredDocs = allDocs.where((doc) {
                        final data = doc.data();
                        if (isMessageHiddenByCutoff(
                          sentAt: ChatDeletionService.timestampOf(
                              data['timestamp']),
                          clearedAt: cutoffs[doc.reference.parent.parent?.id],
                        )) {
                          return false;
                        }
                        final starredBy =
                            data['starredBy'] as Map<String, dynamic>?;
                        if (starredBy != null &&
                            starredBy[currentUid] == true) {
                          return true;
                        }
                        // Fallback for single isStarred flag
                        final senderId = data['senderId'] as String?;
                        return senderId == currentUid ||
                            (data['isStarred'] == true);
                      }).toList();

                      if (userStarredDocs.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 40),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF1F2C34),
                                    border: Border.all(
                                      color:
                                          Colors.amber.withValues(alpha: 0.3),
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.star_outline_rounded,
                                    size: 54,
                                    color: Colors.amber,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  context.l10n.translate('starred_empty_title'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  context.l10n.translate('starred_empty_hint'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: userStarredDocs.length,
                        separatorBuilder: (_, __) => const Divider(
                          color: Colors.white10,
                          height: 1,
                        ),
                        itemBuilder: (context, index) {
                          final doc = userStarredDocs[index];
                          final data = doc.data();
                          final type = (data['type'] as String?) ?? 'text';
                          final text = (data['text'] as String?) ?? '';
                          final senderId = (data['senderId'] as String?) ?? '';
                          final isMe = senderId == currentUid;
                          final timestamp = data['timestamp'] as Timestamp?;
                          final date = timestamp?.toDate();
                          final timeStr = date != null
                              ? '${date.day}/${date.month}/${date.year} at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
                              : '';

                          // Extract chatId from document reference parent
                          final chatId = doc.reference.parent.parent?.id ?? '';

                          return InkWell(
                            onTap: () {
                              if (chatId.isNotEmpty) {
                                context.push(
                                  '/chat/$chatId',
                                  extra: {
                                    'chatId': chatId,
                                    'otherUserName': isMe ? 'Member' : 'Chat',
                                    'otherUserAvatar': '',
                                    'otherUid': isMe ? '' : senderId,
                                  },
                                );
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1F2C34),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      _typeIcon(type),
                                      color: const Color(0xFF00A884),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              isMe ? 'You' : 'Member',
                                              style: const TextStyle(
                                                color: Color(0xFF00A884),
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Text(
                                              timeStr,
                                              style: const TextStyle(
                                                color: Colors.white38,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _typeSnippet(type, text, data),
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            height: 1.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.star,
                                      color: Colors.amber,
                                      size: 20,
                                    ),
                                    tooltip: context.l10n
                                        .translate('starred_unstar'),
                                    onPressed: () async {
                                      try {
                                        await doc.reference.update({
                                          'isStarred': false,
                                          'starredBy.$currentUid':
                                              FieldValue.delete(),
                                        });
                                      } catch (e) {
                                        logError('Error unstarring: $e');
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
      ),
    );
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'image':
        return Icons.image_rounded;
      case 'video':
        return Icons.videocam_rounded;
      case 'audio':
        return Icons.mic_rounded;
      case 'document':
        return Icons.description_rounded;
      case 'location':
        return Icons.location_on_rounded;
      case 'expense':
        return Icons.receipt_long_rounded;
      default:
        return Icons.chat_bubble_outline_rounded;
    }
  }

  String _typeSnippet(String type, String text, Map<String, dynamic> data) {
    switch (type) {
      case 'image':
        return text.isNotEmpty ? '📷 $text' : '📷 Photo';
      case 'video':
        return text.isNotEmpty ? '🎥 $text' : '🎥 Video';
      case 'audio':
        return '🎤 Voice message';
      case 'document':
        final fileName = (data['fileName'] as String?) ?? 'Document';
        return '📄 $fileName';
      case 'location':
        final title = (data['title'] as String?) ?? 'Shared Location';
        return '📍 $title';
      case 'expense':
        final title = (data['expenseTitle'] as String?) ?? 'Expense Split';
        final amount = data['amount']?.toString() ?? '0';
        return '💰 $title • ৳$amount';
      default:
        return text;
    }
  }
}
