import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/router.dart';
import '../../../core/localization/app_localizations.dart';
import '../../auth/presentation/cubit/auth_cubit.dart';
import '../../auth/presentation/cubit/auth_state.dart';
import '../data/share_intake_channel.dart';
import 'share_destination_sheet.dart';

/// Offers the files another app shared into Bhromon. It sits above the navigator, so the
/// sheet opens on the root navigator found through [AppRouter]. A share waits on the
/// native side until someone is signed in, because the sheet sends from an account.
class ShareIntakeHost extends StatefulWidget {
  const ShareIntakeHost({super.key, required this.child});

  final Widget child;

  @override
  State<ShareIntakeHost> createState() => _ShareIntakeHostState();
}

class _ShareIntakeHostState extends State<ShareIntakeHost>
    with WidgetsBindingObserver {
  StreamSubscription<void>? _changes;
  bool _taking = false;
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _changes = ShareIntakeChannel.instance.changes
        .listen((_) => unawaited(_offerPending()));
    WidgetsBinding.instance
        .addPostFrameCallback((_) => unawaited(_offerPending()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_changes?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_offerPending());
  }

  /// Takes the waiting shares and offers them. The await holds no context: the sheet is
  /// opened by [_present], which reads the navigator itself.
  Future<void> _offerPending() async {
    if (!mounted || _taking || _sheetOpen) return;
    if (!ShareIntakeChannel.instance.supported) return;
    final auth = context.read<AuthCubit>().state;
    if (auth is! Authenticated) return;
    if (AppRouter.navigatorKey.currentContext == null) return;
    final uid = auth.profile.uid;
    final name = auth.profile.displayName;

    _taking = true;
    ShareBatch batch = const ShareBatch();
    try {
      batch = await ShareIntakeChannel.instance.takePending();
    } finally {
      _taking = false;
    }
    if (!mounted || batch.isEmpty) return;
    await _present(batch, uid: uid, name: name);
  }

  /// Shows the sheet for [batch] on the root navigator, then offers any share that came in
  /// while the sheet was open.
  Future<void> _present(
    ShareBatch batch, {
    required String uid,
    required String name,
  }) async {
    final root = AppRouter.navigatorKey.currentContext;
    if (root == null) return;
    if (batch.files.isEmpty) {
      _showTextNotice(root);
      return;
    }
    _sheetOpen = true;
    try {
      await showShareDestinationSheet(
        root,
        files: batch.files,
        currentUid: uid,
        fallbackName: name,
        textSkipped: batch.hasText,
      );
    } finally {
      _sheetOpen = false;
    }
    unawaited(_offerPending());
  }

  void _showTextNotice(BuildContext root) {
    ScaffoldMessenger.maybeOf(root)?.showSnackBar(
      SnackBar(content: Text(root.l10n.translate('share_text_not_supported'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthCubit, AuthState>(
      listenWhen: (_, current) => current is Authenticated,
      listener: (_, __) => unawaited(_offerPending()),
      child: widget.child,
    );
  }
}
