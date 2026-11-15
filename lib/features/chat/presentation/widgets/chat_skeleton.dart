import 'package:flutter/material.dart';

import '../chat_palette.dart';

/// Grey bubble shapes shown while a chat's first messages load, in place of a spinner. They sit
/// where the messages will, so the screen does not jump when the messages arrive.
class ChatSkeleton extends StatelessWidget {
  const ChatSkeleton({super.key});

  // Width as a share of the screen, and whether the bubble is the viewer's own.
  static const List<(double, bool)> _bubbles = [
    (0.55, false),
    (0.38, false),
    (0.62, true),
    (0.30, true),
    (0.48, false),
    (0.58, true),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Semantics(
      label: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
      child: ListView(
        reverse: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          for (final (share, mine) in _bubbles.reversed)
            Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: width * share,
                height: 38,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: (mine ? context.chat.outgoing : context.chat.panel)
                      .withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
