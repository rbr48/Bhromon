import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

/// The page key for a screen that belongs to one tour.
///
/// go_router keys a page by its route pattern, so `/group/:tourId/feed` has the
/// same key for every tour. Flutter then reuses the screen's state when the user
/// moves from one tour to another on the same page, and the screen keeps loading
/// the old tour's data. Keying the page by its real address gives each tour its
/// own screen.
ValueKey<String> pageKeyFor(GoRouterState state) =>
    ValueKey<String>(state.uri.toString());
