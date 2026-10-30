import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/localized_date.dart';
import '../../../../core/theme/colors.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../data/fcm_service.dart';
import '../../data/notification_center_repository.dart';

enum _ListMenu { markAllRead, clearAll }

/// The member's notification history, newest first. Unread items are marked,
/// a tap opens what the notification is about, and a swipe deletes one.
class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  final NotificationCenterRepository _repo = NotificationCenterRepository();
  String _uid = '';
  Stream<List<AppNotification>>? _stream;

  /// The last time the list was opened before this visit. Items newer than it
  /// are highlighted for the whole visit, even though the badge has cleared.
  DateTime? _previousSeenAt;
  List<AppNotification> _latest = const [];
  bool _unreadOnly = false;

  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthCubit>().state;
    if (authState is Authenticated) {
      _uid = authState.profile.uid;
      _stream = _repo.watch(_uid);
      _openList();
    }
  }

  Future<void> _openList() async {
    try {
      final previous = await _repo.seenAtOrSeed(_uid);
      await _repo.markSeen(_uid);
      if (mounted) setState(() => _previousSeenAt = previous);
    } catch (_) {
      // The highlight is optional; the list still works without it.
    }
  }

  bool _isUnread(AppNotification n) =>
      _previousSeenAt != null && notificationIsUnread(n, _previousSeenAt!);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('notif_center_title')),
        actions: [
          if (_stream != null)
            PopupMenuButton<_ListMenu>(
              onSelected: (v) => v == _ListMenu.markAllRead
                  ? _markAllRead()
                  : _confirmClearAll(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _ListMenu.markAllRead,
                  child: Text(l10n.translate('notif_mark_all_read')),
                ),
                PopupMenuItem(
                  value: _ListMenu.clearAll,
                  child: Text(l10n.translate('notif_clear_all')),
                ),
              ],
            ),
        ],
      ),
      body: _stream == null
          ? Center(child: Text(l10n.translate('notif_signed_out')))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: Text(l10n.translate('notif_filter_all')),
                        selected: !_unreadOnly,
                        onSelected: (_) => setState(() => _unreadOnly = false),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text(l10n.translate('notif_filter_unread')),
                        selected: _unreadOnly,
                        onSelected: (_) => setState(() => _unreadOnly = true),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _buildList()),
              ],
            ),
    );
  }

  Widget _buildList() {
    final l10n = context.l10n;
    return StreamBuilder<List<AppNotification>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text(l10n.translate('notif_load_failed')));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        _latest = snap.data!;
        final items = _unreadOnly ? _latest.where(_isUnread).toList() : _latest;
        if (items.isEmpty) {
          return Center(
            child: Text(l10n
                .translate(_unreadOnly ? 'notif_empty_unread' : 'notif_empty')),
          );
        }
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) => _buildTile(items[i]),
        );
      },
    );
  }

  Widget _buildTile(AppNotification n) {
    final unread = _isUnread(n);
    return Dismissible(
      key: ValueKey(n.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.redAccent,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => _delete([n.id]),
      child: ListTile(
        tileColor: unread ? AppColors.mintGreen.withValues(alpha: 0.08) : null,
        leading: CircleAvatar(
          backgroundColor: AppColors.mintGreen.withValues(alpha: 0.15),
          child: Icon(_iconFor(n.action), color: AppColors.mintGreen, size: 20),
        ),
        title: Text(
          n.title,
          style: TextStyle(
              fontWeight: unread ? FontWeight.bold : FontWeight.normal),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (n.body.isNotEmpty)
              Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(
              _timeLabel(n.timestamp),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        trailing: unread
            ? const CircleAvatar(
                radius: 4, backgroundColor: AppColors.mintGreen)
            : null,
        onTap: () => _open(n),
      ),
    );
  }

  Future<void> _open(AppNotification n) async {
    if (!n.read) {
      try {
        await _repo.markRead(_uid, n.id);
      } catch (_) {
        // Opening the target matters more than the read mark.
      }
    }
    if (!mounted) return;
    FcmService.routeFromPayload(n.action, context,
        uid: n.uid, itemId: n.itemId, tourId: n.tourId);
  }

  Future<void> _markAllRead() async {
    try {
      await _repo.markAllRead(_uid, _latest);
    } catch (_) {
      _showFailed();
    }
  }

  Future<void> _delete(List<String> ids) async {
    try {
      await _repo.deleteAll(_uid, ids);
    } catch (_) {
      _showFailed();
    }
  }

  Future<void> _confirmClearAll() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('notif_clear_all_title')),
        content: Text(l10n.translate('notif_clear_all_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.translate('notif_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.translate('notif_clear_all')),
          ),
        ],
      ),
    );
    if (confirmed == true) await _delete([for (final n in _latest) n.id]);
  }

  void _showFailed() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.translate('notif_action_failed'))),
    );
  }

  String _timeLabel(DateTime t) {
    final l10n = context.l10n;
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return l10n.translate('notif_just_now');
    if (diff.inMinutes < 60) {
      return l10n
          .translate('notif_minutes_ago', args: {'count': diff.inMinutes});
    }
    if (diff.inHours < 24) {
      return l10n.translate('notif_hours_ago', args: {'count': diff.inHours});
    }
    return localizedDateFormat('d MMM').format(t);
  }

  static IconData _iconFor(String? action) => switch (action) {
        'chat' => Icons.chat_bubble_outline,
        'channel' => Icons.forum_outlined,
        'sos' => Icons.warning_amber_rounded,
        'call' => Icons.call_outlined,
        'post' || 'comment' || 'like' => Icons.favorite_border,
        'notice' => Icons.campaign_outlined,
        'ledger' || 'expense' => Icons.receipt_long_outlined,
        'journey' => Icons.route_outlined,
        _ => Icons.notifications_none_outlined,
      };
}
