import 'package:bhromon/core/widgets/skeleton.dart';

import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/localized_date.dart';
import '../../../../core/theme/colors.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../data/fcm_service.dart';
import '../../data/notification_center_repository.dart';

enum _ListMenu { markAllRead, clearRead }

/// The member's notification list, newest first. A tap marks an entry read and opens what it is
/// about. Its menu marks an entry read or unread, and a swipe deletes it.
class NotificationCenterScreen extends StatefulWidget {
  /// The member whose list this is. Null reads the signed-in member from the auth state.
  final String? uid;
  final NotificationCenterRepository? repository;
  const NotificationCenterScreen({super.key, this.repository, this.uid});

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  NotificationCenterRepository? _repo;
  String _uid = '';
  Stream<List<AppNotification>>? _stream;
  List<AppNotification> _latest = const [];
  bool _unreadOnly = false;

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? NotificationCenterRepository();
    final uid = widget.uid ?? _signedInUid();
    if (uid != null) {
      try {
        _stream = _repo!.watch(uid);
        _uid = uid;
        _openList();
      } catch (_) {
        // Firebase is not up: the list reads as signed out.
        _stream = null;
      }
    }
  }

  String? _signedInUid() {
    try {
      final authState = context.read<AuthCubit>().state;
      return authState is Authenticated ? authState.profile.uid : null;
    } catch (_) {
      // No auth cubit above this screen: the list reads as signed out.
      return null;
    }
  }

  /// Opening the list clears the bell's count. The entries stay unread until they are read.
  Future<void> _openList() async {
    try {
      await _repo?.markSeen(_uid);
    } catch (_) {
      // The bell's count is optional; the list still works without clearing it.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else if (context.canPop()) {
          context.pop();
        } else {
          context.go('/group-hub');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else if (context.canPop()) {
                context.pop();
              } else {
                context.go('/group-hub');
              }
            },
          ),
          title: Text(l10n.translate('notif_center_title')),
          actions: [
            if (_stream != null)
              PopupMenuButton<_ListMenu>(
                key: const Key('notif_list_menu'),
                onSelected: (v) => v == _ListMenu.markAllRead
                    ? _markAllRead()
                    : _confirmClearRead(),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: _ListMenu.markAllRead,
                    child: Text(l10n.translate('notif_mark_all_read')),
                  ),
                  PopupMenuItem(
                    value: _ListMenu.clearRead,
                    child: Text(l10n.translate('notif_clear_read')),
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
                          onSelected: (_) =>
                              setState(() => _unreadOnly = false),
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
          return const ListRowsSkeleton();
        }
        _latest = snap.data!;
        final items =
            _unreadOnly ? _latest.where((n) => !n.read).toList() : _latest;
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
    final l10n = context.l10n;
    return Dismissible(
      key: ValueKey(n.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.redAccent,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) => _delete(n.id),
      child: ListTile(
        tileColor: n.read ? null : AppColors.mintGreen.withValues(alpha: 0.08),
        leading: CircleAvatar(
          backgroundColor: AppColors.mintGreen.withValues(alpha: 0.15),
          child: Icon(_iconFor(n.action),
              color: context.forest.accentText, size: 20),
        ),
        title: Text(
          n.title,
          style: TextStyle(
              fontWeight: n.read ? FontWeight.normal : FontWeight.bold),
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
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!n.read)
              CircleAvatar(
                key: Key('notif_unread_${n.id}'),
                radius: 4,
                backgroundColor: AppColors.mintGreen,
              ),
            PopupMenuButton<bool>(
              key: Key('notif_menu_${n.id}'),
              tooltip: l10n.translate('notif_item_menu'),
              // The value is the read state the entry will have after the choice.
              onSelected: (read) => _setRead(n, read),
              itemBuilder: (_) => [
                PopupMenuItem<bool>(
                  value: !n.read,
                  child: Text(l10n.translate(
                      n.read ? 'notif_mark_unread' : 'notif_mark_read')),
                ),
              ],
            ),
          ],
        ),
        onTap: () => _open(n),
      ),
    );
  }

  /// Marks the entry read, then opens what it is about.
  Future<void> _open(AppNotification n) async {
    if (!n.read) {
      try {
        await _repo?.markRead(_uid, n.id);
      } catch (_) {
        // Opening the target matters more than the read mark.
      }
    }
    if (!mounted) return;
    FcmService.routeFromPayload(n.action, context,
        uid: n.uid, itemId: n.itemId, tourId: n.tourId);
  }

  Future<void> _setRead(AppNotification n, bool read) async {
    try {
      if (read) {
        await _repo?.markRead(_uid, n.id);
      } else {
        await _repo?.markUnread(_uid, n.id);
      }
    } catch (_) {
      _showFailed();
    }
  }

  Future<void> _markAllRead() async {
    try {
      await _repo?.markAllRead(_uid, _latest);
    } catch (_) {
      _showFailed();
    }
  }

  Future<void> _delete(String id) async {
    try {
      await _repo?.deleteMany(_uid, [id]);
    } catch (_) {
      _showFailed();
    }
  }

  /// Removes the read entries after the member confirms. Unread entries are never removed here.
  Future<void> _confirmClearRead() async {
    final l10n = context.l10n;
    if (readIds(_latest).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('notif_clear_read_none'))),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('notif_clear_read_title')),
        content: Text(l10n.translate('notif_clear_read_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.translate('notif_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.translate('notif_clear_read')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _repo?.clearRead(_uid, _latest);
    } catch (_) {
      _showFailed();
    }
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
        'chat' => Icons.chat_bubble_outline_rounded,
        'channel' => Icons.forum_outlined,
        'sos' => Icons.warning_amber_rounded,
        'call' => Icons.call_outlined,
        'post' || 'comment' || 'like' => Icons.favorite_border_rounded,
        'notice' => Icons.campaign_outlined,
        'ledger' || 'expense' => Icons.receipt_long_outlined,
        'journey' => Icons.route_outlined,
        'bazar_duty' => Icons.restaurant_outlined,
        'family_date' => Icons.event_outlined,
        'study_subject' ||
        'problem_set' ||
        'session' =>
          Icons.menu_book_outlined,
        'study_reply' => Icons.question_answer_outlined,
        'study_material' => Icons.folder_outlined,
        _ => Icons.notifications_none_outlined,
      };
}
