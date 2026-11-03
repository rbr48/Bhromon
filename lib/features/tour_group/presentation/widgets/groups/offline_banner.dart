import 'dart:async';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Says that the groups on screen come from this device, not from the server.
///
/// It appears only after [fromCache] has stayed true for [delay]: 8 seconds, the same
/// wait AGENTS.md gives a write before it is reported as syncing. A connection that
/// comes back hides it at once. While it is hidden it takes no space.
class GroupsOfflineBanner extends StatefulWidget {
  const GroupsOfflineBanner({
    super.key,
    required this.fromCache,
    this.delay = const Duration(seconds: 8),
  });

  /// True while the groups list is answered from the device's cache.
  final ValueListenable<bool> fromCache;

  /// How long the answer must stay cache-only before the banner shows.
  final Duration delay;

  @override
  State<GroupsOfflineBanner> createState() => _GroupsOfflineBannerState();
}

class _GroupsOfflineBannerState extends State<GroupsOfflineBanner> {
  Timer? _timer;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    widget.fromCache.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(GroupsOfflineBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fromCache != widget.fromCache) {
      oldWidget.fromCache.removeListener(_changed);
      widget.fromCache.addListener(_changed);
      _changed();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.fromCache.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (widget.fromCache.value) {
      _timer ??= Timer(widget.delay, () {
        _timer = null;
        if (mounted && widget.fromCache.value) setState(() => _shown = true);
      });
      return;
    }
    _timer?.cancel();
    _timer = null;
    if (_shown && mounted) setState(() => _shown = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_shown) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: context.forest.text.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 18,
              color: context.forest.text70,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.l10n.translate('groups_offline_banner'),
                style: TextStyle(color: context.forest.text70, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
