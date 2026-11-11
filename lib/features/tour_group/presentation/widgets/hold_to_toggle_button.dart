import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The alert button. It turns the alert on or off only after the button has been held for
/// two seconds, so a brush of the screen never alerts the group. A short press shows a hint.
/// Assistive technology can switch it at once (its semantics tap), since holding is hard for
/// some people to do.
class HoldToToggleButton extends StatefulWidget {
  const HoldToToggleButton({
    super.key,
    required this.active,
    required this.label,
    required this.onToggle,
    required this.onTapHint,
  });

  final bool active;
  final String label;
  final VoidCallback onToggle;
  final VoidCallback onTapHint;

  @override
  State<HoldToToggleButton> createState() => HoldToToggleButtonState();
}

class HoldToToggleButtonState extends State<HoldToToggleButton>
    with SingleTickerProviderStateMixin {
  static const Duration _holdTime = Duration(seconds: 2);

  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: _holdTime,
  )..addStatusListener(_onHoldStatus);

  // Whether this press has already switched the alert. Releasing after that shows no hint.
  bool _switchedThisPress = false;

  void _onHoldStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_switchedThisPress) {
      _switchedThisPress = true;
      HapticFeedback.heavyImpact();
      widget.onToggle();
      _hold.value = 0;
    }
  }

  void _pointerDown(PointerDownEvent _) {
    _switchedThisPress = false;
    _hold.forward(from: 0);
  }

  void _pointerUp(PointerUpEvent _) {
    if (_switchedThisPress) return;
    _hold.reverse();
    widget.onTapHint();
  }

  void _pointerCancel(PointerCancelEvent _) {
    if (!_switchedThisPress) _hold.reverse();
  }

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final background = widget.active ? Colors.white : Colors.redAccent.shade700;
    final foreground = widget.active ? Colors.red.shade900 : Colors.white;
    return Semantics(
      button: true,
      label: widget.label,
      onTap: () {
        HapticFeedback.heavyImpact();
        widget.onToggle();
      },
      child: Listener(
        onPointerDown: _pointerDown,
        onPointerUp: _pointerUp,
        onPointerCancel: _pointerCancel,
        child: ExcludeSemantics(
          child: AnimatedBuilder(
            animation: _hold,
            builder: (context, _) => ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 52),
                    alignment: Alignment.center,
                    color: background,
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          widget.active
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                          color: foreground,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            widget.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: foreground,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // How far the hold has got: it fills from the left as the button is held.
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: _hold.value,
                        heightFactor: 1,
                        child: ColoredBox(
                          color: foreground.withValues(alpha: 0.25),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
