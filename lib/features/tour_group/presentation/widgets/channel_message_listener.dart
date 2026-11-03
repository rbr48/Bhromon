import 'package:flutter/material.dart';

import '../../domain/models/channel_models.dart';

/// Counts the message listeners a channel screen holds, so a debug build fails
/// when they exceed the budget. Only the settled channel listens today, so the
/// count is at most one. The budget guards later changes, such as a neighbour
/// kept warm for an instant swipe.
class ChannelListenerBudget {
  ChannelListenerBudget._();

  /// The most message listeners a channel screen may hold at once.
  static const int maxLive = 3;

  static int _live = 0;

  /// The listeners held right now.
  static int get live => _live;

  static void attach() {
    _live++;
    assert(
      _live <= maxLive,
      'The channel screen holds $_live message listeners; the budget is $maxLive.',
    );
  }

  static void detach() {
    if (_live > 0) _live--;
  }

  /// Clears the count between tests.
  @visibleForTesting
  static void reset() => _live = 0;
}

/// Listens to one channel's messages while it is built, and counts that listener
/// against [ChannelListenerBudget]. It is built only for the settled channel, so
/// a page that is only passing on screen during a swipe holds nothing.
class ChannelMessageListener extends StatefulWidget {
  const ChannelMessageListener({
    super.key,
    required this.stream,
    required this.builder,
  });

  final Stream<List<ChannelMessage>> stream;
  final AsyncWidgetBuilder<List<ChannelMessage>> builder;

  @override
  State<ChannelMessageListener> createState() => _ChannelMessageListenerState();
}

class _ChannelMessageListenerState extends State<ChannelMessageListener> {
  @override
  void initState() {
    super.initState();
    ChannelListenerBudget.attach();
  }

  @override
  void dispose() {
    ChannelListenerBudget.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ChannelMessage>>(
      stream: widget.stream,
      builder: widget.builder,
    );
  }
}
