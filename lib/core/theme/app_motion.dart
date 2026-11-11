import 'package:flutter/material.dart';

/// The app's motion in one place: how long things take and how a page arrives.
///
/// The router's pages and the routes pushed with `Navigator` use the same
/// transition, so moving around the app feels like one product. With the
/// system's reduced-motion setting on, a page appears without moving.
abstract final class AppMotion {
  /// Small state changes: a chip, a toggle, a tick.
  static const Duration fast = Duration(milliseconds: 150);

  /// Content arriving in place: a list replacing its placeholder.
  static const Duration medium = Duration(milliseconds: 220);

  /// A page arriving.
  static const Duration page = Duration(milliseconds: 320);

  static const Curve curve = Curves.fastOutSlowIn;

  /// Whether the system asks for reduced motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// The page transition: a fade with a short slide in from the side the
  /// text ends on.
  static Widget pageTransition(
    BuildContext context,
    Animation<double> animation,
    Widget child,
  ) {
    if (reduced(context)) return child;
    final bool rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    return FadeTransition(
      opacity: CurveTween(curve: Curves.easeInOut).animate(animation),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(rtl ? -0.06 : 0.06, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: curve)),
        child: child,
      ),
    );
  }
}

/// [AppMotion.pageTransition] for routes pushed with `Navigator`, on the
/// platforms that have no system transition of their own to follow.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Duration get transitionDuration => AppMotion.page;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return AppMotion.pageTransition(context, animation, child);
  }
}

/// Fades its child in once, when it first appears. Used where content takes
/// the place of a loading placeholder, so the swap is not a hard cut.
class FadeIn extends StatefulWidget {
  final Widget child;
  const FadeIn({super.key, required this.child});

  @override
  State<FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<FadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: AppMotion.medium);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.status == AnimationStatus.dismissed) {
      if (AppMotion.reduced(context)) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
      child: widget.child,
    );
  }
}
