import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../tour_routes.dart';

/// Navigates back if possible, otherwise returns to the active group hub.
/// Checks the standard [Navigator] first, then [GoRouter], ensuring both
/// nested routes and top-level deep-linked routes handle back gestures gracefully.
void navigateBackOrToGroup(BuildContext context, String tourId) {
  if (Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
    return;
  }
  try {
    if (context.canPop()) {
      context.pop();
      return;
    }
  } catch (_) {
    // GoRouter might not be in the widget tree in isolated tests or standalone roots
  }
  try {
    if (tourId.isNotEmpty) {
      context.go(tourHubPath(tourId));
    } else {
      context.go('/group-hub');
    }
  } catch (_) {
    Navigator.of(context).maybePop();
  }
}

/// Standardized leading back button for all group module screens.
/// Guarantees a prominent back icon in the AppBar and graceful fallback
/// to the active group hub.
class GroupBackButton extends StatelessWidget {
  final String tourId;
  final Color? color;
  final VoidCallback? onCustomBack;

  const GroupBackButton({
    super.key,
    required this.tourId,
    this.color,
    this.onCustomBack,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.arrow_back, color: color ?? context.forest.text),
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: onCustomBack ?? () => navigateBackOrToGroup(context, tourId),
    );
  }
}

/// Standardized PopScope wrapper for group module screens so that pressing the
/// phone/hardware back button gracefully navigates back to the active group hub
/// rather than closing the group or exiting the app.
class GroupPopScope extends StatelessWidget {
  final String tourId;
  final Widget child;
  final bool Function()? canPopCustom;
  final VoidCallback? onCustomPop;

  const GroupPopScope({
    super.key,
    required this.tourId,
    required this.child,
    this.canPopCustom,
    this.onCustomPop,
  });

  @override
  Widget build(BuildContext context) {
    final allowSystemPop = canPopCustom?.call() ?? false;
    return PopScope(
      canPop: allowSystemPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (onCustomPop != null) {
          onCustomPop!();
        } else {
          navigateBackOrToGroup(context, tourId);
        }
      },
      child: child,
    );
  }
}
