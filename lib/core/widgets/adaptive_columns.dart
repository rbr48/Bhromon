import 'package:flutter/material.dart';

/// Lays [children] out in one column, or in two from [breakpoint] wide.
///
/// Two columns are built as rows of pairs rather than a grid, so each row is
/// as tall as its taller card and long text or large font sizes never clip.
class AdaptiveColumns extends StatelessWidget {
  const AdaptiveColumns({
    super.key,
    required this.children,
    this.breakpoint = 600,
    this.spacing = 10,
  });

  /// The width, in logical pixels, from which two columns are used.
  final double breakpoint;

  /// The gap between rows, and between the two columns.
  final double spacing;

  final List<Widget> children;

  /// Whether a box [width] wide gets two columns.
  bool usesTwoColumns(double width) => width >= breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!usesTwoColumns(constraints.maxWidth)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: spacing),
                children[i],
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i += 2) ...[
              if (i > 0) SizedBox(height: spacing),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: children[i]),
                  SizedBox(width: spacing),
                  Expanded(
                    child: i + 1 < children.length
                        ? children[i + 1]
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}
