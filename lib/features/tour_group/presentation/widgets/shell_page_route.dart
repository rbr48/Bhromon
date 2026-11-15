import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/breakpoints.dart';
import '../../data/active_group.dart';
import '../../data/tour_group_repository.dart';
import 'trip_shell.dart';

/// A page opened over a group tool: a subject from the subjects list, a chapter from a book,
/// a quiz from a chapter.
///
/// On a phone it is a plain page. On a desktop window it is drawn inside the shell, between
/// the sidebar and the dock, like the tool it was opened from. Before this, such a page
/// covered the whole window and stretched a phone layout across it.
class ShellPageRoute<T> extends MaterialPageRoute<T> {
  ShellPageRoute({
    required WidgetBuilder builder,
    TourGroupRepository? repository,
    super.settings,
    super.fullscreenDialog,
  }) : super(
          builder: (context) => ShellPageFrame(
            repository: repository,
            child: builder(context),
          ),
        );
}

/// Draws [child] inside the desktop shell on a desktop window, and as it is on a phone.
class ShellPageFrame extends StatelessWidget {
  const ShellPageFrame({super.key, required this.child, this.repository});

  final Widget child;

  /// Lets tests supply a repository that does not touch Firebase.
  final TourGroupRepository? repository;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopShellWidth(MediaQuery.sizeOf(context).width)) return child;
    final router = GoRouter.maybeOf(context);
    if (router == null) return child;
    // The page under this one names the tool and the group, so the sidebar keeps that tool
    // marked.
    final path = router.routerDelegate.currentConfiguration.uri.path;
    return TripShell(
      tourId: shellTourIdOf(path) ?? ActiveGroup.instance.current ?? '',
      location: path,
      repository: repository,
      guardMembership: false,
      ownMobileScaffold: true,
      child: child,
    );
  }
}

/// The group a path belongs to: `/group/x/study-subjects` gives `x`. Null when the path is
/// not under a group.
String? shellTourIdOf(String path) {
  final segments = path.split('/');
  if (segments.length < 3 || segments[1] != 'group') return null;
  return segments[2].isEmpty ? null : segments[2];
}
