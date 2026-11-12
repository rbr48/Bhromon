import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../data/notification_center_repository.dart';

/// The bell in the groups list's title bar. It opens the notification list. Its badge counts the
/// entries that arrived since the list was last opened and are still unread.
class NotificationBell extends StatefulWidget {
  /// The member whose list this is. Null reads the signed-in member from the auth state.
  final String? uid;
  final NotificationCenterRepository? repository;
  const NotificationBell({super.key, this.uid, this.repository});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  NotificationCenterRepository? _repo;
  String? _uid;
  Stream<List<AppNotification>>? _stream;
  DateTime? _seenAt;

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? NotificationCenterRepository();
    final uid = widget.uid ?? _signedInUid();
    if (uid == null) return;
    try {
      _stream = _repo!.watch(uid);
      _uid = uid;
    } catch (_) {
      // Firebase is not up: the bell is hidden.
      _stream = null;
      return;
    }
    _loadSeen();
  }

  String? _signedInUid() {
    try {
      final authState = context.read<AuthCubit>().state;
      return authState is Authenticated ? authState.profile.uid : null;
    } catch (_) {
      // No auth cubit above the bell: it stays hidden.
      return null;
    }
  }

  Future<void> _loadSeen() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final seen = await _repo?.seenAt(uid);
      if (mounted) setState(() => _seenAt = seen);
    } catch (_) {
      // Without the last-seen time the bell shows no count.
    }
  }

  /// Opens the list. The list clears the count when it opens, so the count is read again on return.
  Future<void> _openList() async {
    await context.push('/notifications');
    if (mounted) await _loadSeen();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final stream = _stream;
    if (stream == null) return const SizedBox.shrink();
    return StreamBuilder<List<AppNotification>>(
      stream: stream,
      builder: (context, snap) {
        final seen = _seenAt;
        final count =
            snap.hasData && seen != null ? unseenCount(snap.data!, seen) : 0;
        return IconButton(
          tooltip: l10n.translate('notif_bell_tooltip'),
          onPressed: _openList,
          icon: Badge(
            isLabelVisible: count > 0,
            label:
                Text(count > 99 ? '${l10n.number(99)}+' : l10n.number(count)),
            child: const Icon(Icons.notifications_none_rounded,
                color: AppColors.midGreen),
          ),
        );
      },
    );
  }
}
