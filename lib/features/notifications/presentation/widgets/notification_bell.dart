import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
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
///
/// The bell icon is always visible in the AppBar. If no member is signed in or notifications
/// are still connecting, it displays cleanly without an unread badge and opens the notification
/// center when tapped.
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
  StreamSubscription<User?>? _fbAuthSub;

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? NotificationCenterRepository();
    _initStream();
    _listenAuth();
  }

  @override
  void didUpdateWidget(covariant NotificationBell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.uid != oldWidget.uid) {
      _initStream();
    }
  }

  @override
  void dispose() {
    _fbAuthSub?.cancel();
    super.dispose();
  }

  void _listenAuth() {
    if (widget.uid != null) return;
    try {
      _fbAuthSub = FirebaseAuth.instance.authStateChanges().listen((user) {
        if (!mounted) return;
        final currentUid = user?.uid;
        if (currentUid != _uid) {
          _initStream();
        }
      });
    } catch (_) {
      // Firebase not initialized in unit tests or disabled.
    }
  }

  String? _resolveUid() {
    if (widget.uid != null) return widget.uid;
    try {
      final authState = context.read<AuthCubit>().state;
      if (authState is Authenticated) {
        return authState.profile.uid;
      }
    } catch (_) {
      // AuthCubit not in context.
    }
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      // Firebase not initialized.
    }
    return null;
  }

  void _initStream() {
    final uid = _resolveUid();
    if (uid == _uid && _stream != null) return;
    _uid = uid;
    if (uid == null) {
      if (mounted) setState(() => _stream = null);
      return;
    }
    try {
      final s = _repo!.watch(uid);
      if (mounted) {
        setState(() => _stream = s);
      } else {
        _stream = s;
      }
    } catch (_) {
      if (mounted) {
        setState(() => _stream = null);
      } else {
        _stream = null;
      }
      return;
    }
    _loadSeen();
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

  Widget _buildBellIcon({required BuildContext context, int count = 0}) {
    final l10n = context.l10n;
    return IconButton(
      tooltip: l10n.translate('notif_bell_tooltip'),
      onPressed: _openList,
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(count > 99 ? '${l10n.number(99)}+' : l10n.number(count)),
        child: const Icon(Icons.notifications_none_rounded,
            color: AppColors.midGreen),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // If auth state resolved after initial frame, connect the stream reactively.
    final currentResolvedUid = _resolveUid();
    if (currentResolvedUid != null && currentResolvedUid != _uid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _initStream();
      });
    }

    final stream = _stream;
    if (stream == null) {
      // Always keep the bell visible in the AppBar.
      return _buildBellIcon(context: context, count: 0);
    }

    return StreamBuilder<List<AppNotification>>(
      stream: stream,
      builder: (context, snap) {
        final seen = _seenAt;
        final count =
            snap.hasData && seen != null ? unseenCount(snap.data!, seen) : 0;
        return _buildBellIcon(context: context, count: count);
      },
    );
  }
}
