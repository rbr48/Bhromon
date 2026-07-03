import 'package:flutter/material.dart';
import '../sync_status_notifier.dart';

/// A small widget that renders sync state as an icon/badge in app bars or
/// toolbars. Attach a [SyncStatusNotifier] and drop this anywhere a status
/// indicator is needed. It rebuilds only when the notifier changes.
class SyncStatusIndicator extends StatelessWidget {
  final SyncStatusNotifier notifier;

  const SyncStatusIndicator({super.key, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: notifier,
      builder: (context, _) {
        return switch (notifier.state) {
          SyncState.idle => const SizedBox.shrink(),
          SyncState.syncing => const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          SyncState.pendingItems => Badge(
              label: Text('${notifier.pendingCount}'),
              child: const Icon(Icons.cloud_upload_outlined),
            ),
          SyncState.error => Tooltip(
              message: notifier.lastError ?? 'Sync error',
              child: const Icon(Icons.cloud_off, color: Colors.orange),
            ),
        };
      },
    );
  }
}
