import 'package:flutter/material.dart';

import '../../data/channel_message_cache.dart';
import '../../domain/models/channel_models.dart';

/// Reads one channel's cached messages when the channel is shown, and gives them
/// to [builder] while the live query connects. The read happens once per visit,
/// because the page is built again on each visit.
///
/// [cached] is null while the read is pending. An empty list means nothing is
/// cached.
class CachedChannelMessages extends StatefulWidget {
  const CachedChannelMessages({
    super.key,
    required this.tourId,
    required this.channelId,
    required this.builder,
    this.cache,
  });

  final String tourId;
  final String channelId;
  final Widget Function(BuildContext context, List<ChannelMessage>? cached)
      builder;

  /// The cache to read from. Tests pass their own.
  final ChannelMessageCache? cache;

  @override
  State<CachedChannelMessages> createState() => _CachedChannelMessagesState();
}

class _CachedChannelMessagesState extends State<CachedChannelMessages> {
  late final Future<List<ChannelMessage>> _cached =
      (widget.cache ?? ChannelMessageCache())
          .read(widget.tourId, widget.channelId);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ChannelMessage>>(
      future: _cached,
      builder: (context, snapshot) => widget.builder(context, snapshot.data),
    );
  }
}
