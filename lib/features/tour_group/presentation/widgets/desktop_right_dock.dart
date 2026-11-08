import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/media/media_access.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/doc_future_cache.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../data/active_group.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/date_codec.dart';
import '../../domain/models/tour_group.dart';
import 'tour_group_dialogs.dart';

/// The right-side dock displayed on wide desktop screens (>= 900px).
/// Features:
/// 1. Upper half: "My Groups & Circles" list with 1-click active group switching,
///    create group (+ নতুন) and join with code (🔑).
/// 2. Lower half: "Direct Messages" (1-on-1 chats) with online presence indicators,
///    unread counts, and 1-click chat launcher.
class DesktopRightDock extends StatelessWidget {
  final String? activeTourId;
  final TourGroupRepository? repository;
  final double width;
  final String? currentLocation;

  const DesktopRightDock({
    super.key,
    this.activeTourId,
    this.repository,
    this.width = 320,
    this.currentLocation,
  });

  @override
  Widget build(BuildContext context) {
    final repo = repository ?? TourGroupRepository();
    String currentUid = '';
    try {
      final authState = context.watch<AuthCubit>().state;
      if (authState is Authenticated) {
        currentUid = authState.profile.uid;
      }
    } catch (_) {
      // Fallback in tests where AuthCubit is not in the widget tree
    }
    if (currentUid.isEmpty) {
      try {
        currentUid = repo.currentUid;
      } catch (_) {
        currentUid = '';
      }
    }

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: context.forest.surfaceFor(const Color(0xFF0C1611)),
        border: Border(left: BorderSide(color: context.forest.divider10)),
      ),
      child: Column(
        children: [
          // Upper Half: My Groups & Circles (~50% height)
          Expanded(
            flex: 5,
            child: DesktopGroupListPanel(
              activeTourId: activeTourId,
              repository: repo,
              currentLocation: currentLocation,
            ),
          ),

          // Subtle horizontal divider between panels
          Container(
            height: 1,
            color: context.forest.divider10,
          ),

          // Lower Half: 1-on-1 Direct Chats (~50% height)
          Expanded(
            flex: 5,
            child: DesktopDirectChatsPanel(
              currentUid: currentUid,
            ),
          ),
        ],
      ),
    );
  }
}

/// The upper panel of the desktop right dock: streams and displays the user's groups.
class DesktopGroupListPanel extends StatelessWidget {
  final String? activeTourId;
  final TourGroupRepository repository;
  final String? currentLocation;

  const DesktopGroupListPanel({
    super.key,
    required this.activeTourId,
    required this.repository,
    this.currentLocation,
  });

  String _groupIcon(TourGroup g) {
    if (g.isMess) return '🍛';
    if (g.isSamity) return '🪙';
    if (g.isOffice) return '🏢';
    if (g.isSociety) return '🏘️';
    if (g.isCampus) return '🎓';
    if (g.kind == GroupKind.family) return '👨‍👩‍👧';
    return '🌴';
  }

  void _onGroupTap(BuildContext context, TourGroup group) async {
    await ActiveGroup.instance.select(group.id);
    if (!context.mounted) return;

    final loc = currentLocation ?? '';
    if (loc.startsWith('/group/')) {
      // Replaces the old tourId in the current sub-screen route
      final segments = loc.split('/');
      if (segments.length >= 4) {
        final subPath = segments.sublist(3).join('/');
        context.go('/group/${group.id}/$subPath');
        return;
      }
    }
    context.go('/group/${group.id}/channels');
  }

  Stream<List<TourGroup>> _safeGroupsStream() {
    try {
      return repository.watchMyGroups().handleError((_) => <TourGroup>[]);
    } catch (_) {
      return Stream.value(<TourGroup>[]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isBn = l10n.locale.languageCode == 'bn';

    return StreamBuilder<List<TourGroup>>(
      stream: _safeGroupsStream(),
      builder: (context, snapshot) {
        final groups = snapshot.data ?? [];
        final count = groups.length;

        return Column(
          children: [
            // Panel Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: context.forest.surfaceFor(const Color(0xFF0F1C16)),
                border: Border(
                  bottom: BorderSide(color: context.forest.divider10),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🏢', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            isBn ? 'আমার গ্রুপসমূহ' : 'My Groups',
                            style: TextStyle(
                              color: context.forest.text,
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.mintGreen.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.mintGreen.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            isBn ? '$countটি' : '$count',
                            style: TextStyle(
                              color: context.forest.accentText,
                              fontWeight: FontWeight.bold,
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      InkWell(
                        onTap: () =>
                            TourGroupDialogs.showCreateGroupChoiceDialog(
                          context,
                          repository: repository,
                        ),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: AppColors.mintGreen.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppColors.mintGreen.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            isBn ? '+ নতুন' : '+ New',
                            style: TextStyle(
                              color: context.forest.accentText,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 26,
                          minHeight: 26,
                        ),
                        icon: const Text('🔑', style: TextStyle(fontSize: 12)),
                        tooltip: isBn ? 'কোড দিয়ে যোগ দিন' : 'Join with code',
                        onPressed: () => TourGroupDialogs.showJoinDialog(
                          context,
                          repository: repository,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Groups List
            Expanded(
              child: groups.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.group_add_outlined,
                                size: 36, color: context.forest.text38),
                            const SizedBox(height: 8),
                            Text(
                              isBn
                                  ? 'কোনো গ্রুপ পাওয়া যায়নি'
                                  : 'No groups found',
                              style: TextStyle(
                                  color: context.forest.text54, fontSize: 12),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                    color: AppColors.mintGreen
                                        .withValues(alpha: 0.5)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                              ),
                              onPressed: () =>
                                  TourGroupDialogs.showCreateGroupChoiceDialog(
                                context,
                                repository: repository,
                              ),
                              child: Text(
                                isBn
                                    ? '+ নতুন গ্রুপ তৈরি করুন'
                                    : '+ Create Group',
                                style: TextStyle(
                                  color: context.forest.accentText,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      itemCount: groups.length,
                      itemBuilder: (context, index) {
                        final g = groups[index];
                        final isActive = g.id == activeTourId;

                        String subtitle = g.kind == GroupKind.family
                            ? (g.isMess
                                ? (isBn ? 'মেস ও ফ্ল্যাট' : 'Mess & Flat')
                                : (g.isSamity
                                    ? (isBn ? 'সঞ্চয় সমিতি' : 'Savings Samity')
                                    : (g.isOffice
                                        ? (isBn ? 'অফিস টিম' : 'Office Team')
                                        : (isBn
                                            ? 'পারিবারিক সার্কেল'
                                            : 'Family Circle'))))
                            : '${g.originCity.isNotEmpty ? g.originCity : (isBn ? 'ঢাকা' : 'Dhaka')} ➔ ${g.destination.isNotEmpty ? g.destination : (isBn ? 'কক্সবাজার' : "Cox's Bazar")}';

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: InkWell(
                            onTap: () => _onGroupTap(context, g),
                            borderRadius: BorderRadius.circular(10),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? AppColors.mintGreen
                                        .withValues(alpha: 0.12)
                                    : context.forest.surfaceFor(
                                        const Color(0xFF132219),
                                      ),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isActive
                                      ? AppColors.mintGreen
                                          .withValues(alpha: 0.7)
                                      : context.forest.divider10,
                                  width: isActive ? 1.4 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Group Icon / Avatar
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: context.forest
                                          .surfaceFor(const Color(0xFF183123)),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isActive
                                            ? AppColors.mintGreen
                                                .withValues(alpha: 0.4)
                                            : context.forest.divider10,
                                      ),
                                    ),
                                    child: Center(
                                      child: g.photoUrl != null &&
                                              g.photoUrl!.isNotEmpty
                                          ? ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Image.network(
                                                signedMediaUrl(g.photoUrl!),
                                                width: 34,
                                                height: 34,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) =>
                                                    Text(
                                                  _groupIcon(g),
                                                  style: const TextStyle(
                                                      fontSize: 16),
                                                ),
                                              ),
                                            )
                                          : Text(
                                              _groupIcon(g),
                                              style:
                                                  const TextStyle(fontSize: 16),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 9),

                                  // Name and Subtitle
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                g.name,
                                                style: TextStyle(
                                                  color: context.forest.text,
                                                  fontWeight: isActive
                                                      ? FontWeight.w800
                                                      : FontWeight.w600,
                                                  fontSize: 12,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (isActive)
                                              Container(
                                                margin: const EdgeInsets.only(
                                                    left: 4),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 4.5,
                                                        vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: AppColors.mintGreen,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  isBn ? 'সক্রিয়' : 'Active',
                                                  style: const TextStyle(
                                                    color: Colors.black,
                                                    fontSize: 8.5,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          subtitle,
                                          style: TextStyle(
                                            color: isActive
                                                ? context.forest.text70
                                                : context.forest.text38,
                                            fontSize: 10.5,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),

                                  if (isActive) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: AppColors.mintGreen,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// The lower panel of the desktop right dock: streams and displays 1-on-1 direct conversations.
class DesktopDirectChatsPanel extends StatelessWidget {
  final String currentUid;

  const DesktopDirectChatsPanel({
    super.key,
    required this.currentUid,
  });

  Stream<QuerySnapshot<Map<String, dynamic>>>? _safeChatsStream() {
    try {
      if (Firebase.apps.isEmpty || currentUid.isEmpty) {
        return null;
      }
      return FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: currentUid)
          .snapshots();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isBn = l10n.locale.languageCode == 'bn';
    final stream = _safeChatsStream();

    return Column(
      children: [
        // Panel Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: context.forest.surfaceFor(const Color(0xFF0F1C16)),
            border: Border(
              bottom: BorderSide(color: context.forest.divider10),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('💬', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        isBn ? 'সরাসরি বার্তা' : 'Direct Messages',
                        style: TextStyle(
                          color: context.forest.text,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isBn ? '(১-অন-১)' : '(1-on-1)',
                      style: TextStyle(
                        color: context.forest.text54,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 24,
                  minHeight: 24,
                ),
                icon: Icon(Icons.open_in_new_rounded,
                    size: 15, color: context.forest.text54),
                tooltip: isBn ? 'সকল চ্যাট দেখুন' : 'View all chats',
                onPressed: () => context.push('/chats'),
              ),
            ],
          ),
        ),

        // Contacts List
        Expanded(
          child: stream == null
              ? Center(
                  child: Text(
                    isBn ? 'চ্যাট লোড করা যায়নি' : 'Chats unavailable',
                    style:
                        TextStyle(color: context.forest.text38, fontSize: 11),
                  ),
                )
              : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: stream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.mintGreen,
                          ),
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          isBn ? 'চ্যাট লোড করা যায়নি' : 'Failed to load chats',
                          style: TextStyle(color: context.forest.text38, fontSize: 11),
                        ),
                      );
                    }

                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.chat_bubble_outline_rounded,
                                  size: 32, color: context.forest.text38),
                              const SizedBox(height: 6),
                              Text(
                                isBn
                                    ? 'কোনো সরাসরি বার্তা নেই'
                                    : 'No direct messages',
                                style: TextStyle(
                                    color: context.forest.text54, fontSize: 11),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: () => context.push('/chats'),
                                child: Text(
                                  isBn ? 'চ্যাট শুরু করুন' : 'Start Chat',
                                  style: TextStyle(
                                    color: context.forest.accentText,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data();
                        final chatId = docs[index].id;
                        final participants = List<String>.from(
                            data['participants'] as Iterable? ?? <dynamic>[]);
                        final otherUid = participants.firstWhere(
                            (p) => p != currentUid,
                            orElse: () => '');

                        return _DesktopDirectChatItem(
                          key: ValueKey(chatId),
                          chatId: chatId,
                          data: data,
                          currentUid: currentUid,
                          otherUid: otherUid,
                          isBn: isBn,
                        );
                      },
                    );
                  },
                ),
        ),

        // Dock Footer
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: context.forest.surfaceFor(const Color(0xFF0F1C16)),
            border: Border(
              top: BorderSide(color: context.forest.divider10),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isBn ? 'বন্ধুগণ সক্রিয়' : 'Friends active',
                    style:
                        TextStyle(color: context.forest.text54, fontSize: 10.5),
                  ),
                ],
              ),
              InkWell(
                onTap: () => context.push('/chats'),
                child: Text(
                  isBn ? 'সব চ্যাট দেখুন ➔' : 'View all ➔',
                  style: TextStyle(
                    color: context.forest.accentText,
                    fontWeight: FontWeight.bold,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DesktopDirectChatItem extends StatelessWidget {
  final String chatId;
  final Map<String, dynamic> data;
  final String currentUid;
  final String otherUid;
  final bool isBn;

  const _DesktopDirectChatItem({
    super.key,
    required this.chatId,
    required this.data,
    required this.currentUid,
    required this.otherUid,
    required this.isBn,
  });

  @override
  Widget build(BuildContext context) {
    final profiles = data['participantProfiles'] as Map<String, dynamic>?;
    final cached = profiles?[otherUid] as Map?;
    final cachedName = (cached?['displayName'] as String?)?.trim();
    final cachedAvatar = (cached?['avatarUrl'] as String?) ??
        (cached?['photoUrl'] as String?) ??
        (cached?['photoURL'] as String?);
    final lastMsg = (data['lastMessage'] as String?)?.trim() ?? '';
    final unreadCounts = data['unreadCounts'] as Map<String, dynamic>? ?? {};
    final unread = (unreadCounts[currentUid] as num?)?.toInt() ?? 0;

    Stream<DocumentSnapshot<Map<String, dynamic>>>? profileStream;
    if (Firebase.apps.isNotEmpty && otherUid.isNotEmpty) {
      try {
        profileStream = FirebaseFirestore.instance
            .collection('explorer_profiles')
            .doc(otherUid)
            .snapshots()
            .handleError((_) {});
      } catch (_) {
        profileStream = null;
      }
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: profileStream,
      builder: (context, profileSnap) {
        final pData = profileSnap.data?.data();
        final pName = (pData?['displayName'] as String?)?.trim() ??
            (pData?['name'] as String?)?.trim();
        final pAvatar = (pData?['avatarUrl'] as String?)?.trim() ??
            (pData?['photoUrl'] as String?)?.trim() ??
            (pData?['photoURL'] as String?)?.trim();
        final isOnline = (pData?['isOnline'] as bool?) ??
            (cached?['isOnline'] as bool? ?? false);

        final displayName = (pName != null && pName.isNotEmpty)
            ? pName
            : ((cachedName != null && cachedName.isNotEmpty)
                ? cachedName
                : (isBn ? 'সদস্য' : 'Member'));

        final avatarUrl =
            (pAvatar != null && pAvatar.isNotEmpty) ? pAvatar : cachedAvatar;
        final sharedTourId = data['sharedTourId'] as String?;
        final otherEmail = (data['memberEmails'] as Map?)?[otherUid] as String?;

        Widget buildAvatarImage(String? url) {
          final hasUrl = url != null && url.isNotEmpty;
          return Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: context.forest.surfaceFor(const Color(0xFF1D3B2A)),
              shape: BoxShape.circle,
            ),
            clipBehavior: Clip.antiAlias,
            child: hasUrl
                ? Image.network(
                    signedMediaUrl(url),
                    width: 32,
                    height: 32,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _avatarFallback(context, displayName),
                  )
                : _avatarFallback(context, displayName),
          );
        }

        Widget avatarDisplay;
        if (avatarUrl != null && avatarUrl.isNotEmpty) {
          avatarDisplay = buildAvatarImage(avatarUrl);
        } else if (sharedTourId != null &&
            sharedTourId.isNotEmpty &&
            otherEmail != null &&
            otherEmail.isNotEmpty) {
          final memId = '${sharedTourId}__${normalizeEmail(otherEmail)}';
          avatarDisplay = FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: DocFutureCache.instance.get(
              FirebaseFirestore.instance.collection('memberships').doc(memId),
            ),
            builder: (context, memSnap) {
              final memPhoto = memSnap.data?.data()?['photoUrl'] as String?;
              return buildAvatarImage(memPhoto);
            },
          );
        } else {
          avatarDisplay = buildAvatarImage(null);
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: InkWell(
            onTap: () {
              context.push('/chat/$chatId', extra: {
                'otherUid': otherUid,
                'sharedTourId': data['sharedTourId'],
                'otherEmail': (data['memberEmails'] as Map?)?[otherUid],
              });
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: context.forest.surfaceFor(const Color(0xFF132219)),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.forest.divider10),
              ),
              child: Row(
                children: [
                  // User Avatar with Online Dot
                  Stack(
                    children: [
                      avatarDisplay,
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isOnline
                                ? const Color(0xFF10B981)
                                : Colors.grey[600],
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: context.forest.surfaceFor(
                                const Color(0xFF0C1611),
                              ),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),

                  // Name and last message snippet
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: TextStyle(
                            color: context.forest.text,
                            fontWeight: FontWeight.bold,
                            fontSize: 11.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          lastMsg.isNotEmpty
                              ? lastMsg
                              : (isBn ? 'কোনো বার্তা নেই' : 'No messages yet'),
                          style: TextStyle(
                            color: unread > 0
                                ? context.forest.accentText
                                : context.forest.text38,
                            fontWeight: unread > 0
                                ? FontWeight.w600
                                : FontWeight.normal,
                            fontSize: 10,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // Unread Count Badge
                  if (unread > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: AppColors.mintGreen,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$unread',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _avatarFallback(BuildContext context, String name) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'U';
    return Center(
      child: Text(
        initial,
        style: TextStyle(
          color: context.forest.text,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
