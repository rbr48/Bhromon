import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/utils/logger.dart';
import '../../tour_group/data/tour_channel_repository.dart';
import '../../tour_group/data/tour_group_repository.dart';
import '../../tour_group/domain/services/channel_titles.dart';
import '../data/channel_share_sender.dart';
import '../data/share_destinations_loader.dart';
import '../domain/share_plan.dart';
import '../domain/shared_file.dart';

/// Opens the sheet that picks where shared files go: a one-to-one chat or a group
/// channel. [rootContext] sits under the app's root navigator. The sheet closes before
/// anything is sent, so the send and its messages use [rootContext], not the sheet.
/// [loadDestinations] replaces the real reads, for tests.
Future<void> showShareDestinationSheet(
  BuildContext rootContext, {
  required List<SharedFile> files,
  required String currentUid,
  bool textSkipped = false,
  Future<ShareDestinations> Function()? loadDestinations,
}) {
  return showModalBottomSheet<void>(
    context: rootContext,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ShareDestinationSheet(
      rootContext: rootContext,
      files: files,
      currentUid: currentUid,
      textSkipped: textSkipped,
      loadDestinations: loadDestinations,
    ),
  );
}

class _ShareDestinationSheet extends StatefulWidget {
  const _ShareDestinationSheet({
    required this.rootContext,
    required this.files,
    required this.currentUid,
    required this.textSkipped,
    this.loadDestinations,
  });

  final BuildContext rootContext;
  final List<SharedFile> files;
  final String currentUid;
  final bool textSkipped;
  final Future<ShareDestinations> Function()? loadDestinations;

  @override
  State<_ShareDestinationSheet> createState() => _ShareDestinationSheetState();
}

class _ShareDestinationSheetState extends State<_ShareDestinationSheet> {
  late final List<SharedFile> _sendable = [
    for (final file in widget.files)
      if (sharedFileIssue(file) == null) file,
  ];
  late final List<(SharedFile, SharedFileIssue)> _skipped = [
    for (final file in widget.files)
      if (sharedFileIssue(file) case final issue?) (file, issue),
  ];
  late Future<ShareDestinations> _destinations = _load();

  Future<ShareDestinations> _load() {
    final override = widget.loadDestinations;
    final load = override != null
        ? override()
        : ShareDestinationsLoader().load(currentUid: widget.currentUid);
    return load.catchError((Object error, StackTrace stack) {
      logWarning('[ShareIntake] could not load the destinations', error, stack);
      throw error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.translate('share_sheet_title'),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(_countLabel(l10n), style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          if (widget.textSkipped)
            _note(theme, l10n.translate('share_text_not_supported')),
          if (_skipped.isNotEmpty) _skippedNotice(context),
          Flexible(child: _destinationList(context)),
        ],
      ),
    );
  }

  String _countLabel(AppLocalizations l10n) {
    final count = _sendable.length;
    if (count == 0) return l10n.translate('share_none_sendable');
    if (count == 1) return l10n.translate('share_one_file');
    return l10n.translate(
      'share_many_files',
      args: {'count': l10n.number(count)},
    );
  }

  Widget _note(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Text(text, style: theme.textTheme.bodySmall),
      );

  Widget _skippedNotice(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.translate(
              'share_skipped_heading',
              args: {'count': l10n.number(_skipped.length)},
            ),
            style: theme.textTheme.labelLarge,
          ),
          for (final (file, issue) in _skipped)
            Text(
              '${file.name}: ${_reason(context, file, issue)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  String _reason(BuildContext context, SharedFile file, SharedFileIssue issue) {
    final l10n = context.l10n;
    return switch (issue) {
      SharedFileIssue.unsupported => l10n.translate('share_reason_unsupported'),
      SharedFileIssue.tooLarge => l10n.translate(
          'share_reason_too_large',
          args: {'limit': l10n.number(_limitMb(file))},
        ),
      SharedFileIssue.unreadable => l10n.translate('share_reason_unreadable'),
      SharedFileIssue.empty => l10n.translate('share_reason_empty'),
    };
  }

  int _limitMb(SharedFile file) {
    final kind = sharedFileKind(file.name);
    return kind == null ? 0 : maxBytesFor(kind) ~/ (1024 * 1024);
  }

  Widget _destinationList(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    if (_sendable.isEmpty) {
      return _message(theme, l10n.translate('share_none_sendable'));
    }
    return FutureBuilder<ShareDestinations>(
      future: _destinations,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final destinations = snapshot.data;
        if (snapshot.hasError || destinations == null) {
          return _errorView(theme, l10n);
        }
        if (destinations.chats.isEmpty &&
            destinations.channels.isEmpty &&
            !destinations.incomplete) {
          return _message(theme, l10n.translate('share_none_destinations'));
        }
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            if (destinations.incomplete) _incompleteNotice(theme, l10n),
            if (destinations.chats.isNotEmpty) ...[
              _heading(theme, l10n.translate('share_chats_heading')),
              for (final chat in destinations.chats)
                _chatRow(theme, l10n, chat),
            ],
            if (destinations.channels.isNotEmpty) ...[
              _heading(theme, l10n.translate('share_channels_heading')),
              ..._channelRows(theme, l10n, destinations.channels),
            ],
          ],
        );
      },
    );
  }

  Widget _chatRow(
      ThemeData theme, AppLocalizations l10n, ChatDestination chat) {
    final title = chat.title ?? l10n.translate('chats_member');
    final tour = chat.tourName;
    return ListTile(
      leading: CircleAvatar(child: Text(_initial(title))),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: tour == null
          ? null
          : Text(tour, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => _sendToChat(chat),
    );
  }

  /// The channels, under a heading for each group, so two groups with a channel of the same
  /// name can be told apart.
  List<Widget> _channelRows(
    ThemeData theme,
    AppLocalizations l10n,
    List<ChannelDestination> channels,
  ) {
    final rows = <Widget>[];
    String? currentTour;
    for (final channel in channels) {
      if (channel.tourId != currentTour) {
        currentTour = channel.tourId;
        rows.add(_heading(theme, channel.tourName));
      }
      rows.add(ListTile(
        leading: const CircleAvatar(child: Icon(Icons.forum_outlined)),
        title: Text(
          _channelTitle(l10n, channel),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => _sendToChannel(channel),
      ));
    }
    return rows;
  }

  Widget _incompleteNotice(ThemeData theme, AppLocalizations l10n) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.translate('share_some_missing'),
                style: theme.textTheme.bodySmall,
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _destinations = _load()),
              child: Text(l10n.translate('share_try_again')),
            ),
          ],
        ),
      );

  Widget _message(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
      );

  Widget _errorView(ThemeData theme, AppLocalizations l10n) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.translate('share_load_failed'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _destinations = _load();
                });
              },
              child: Text(l10n.translate('share_try_again')),
            ),
          ],
        ),
      );

  Widget _heading(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Text(text, style: theme.textTheme.labelLarge),
      );

  String _initial(String title) {
    final trimmed = title.trim();
    return trimmed.isEmpty ? '?' : trimmed.substring(0, 1);
  }

  void _sendToChat(ChatDestination chat) {
    Navigator.of(context).pop();
    unawaited(
      widget.rootContext.push<void>(
        '/chat/${chat.chatId}',
        extra: <String, dynamic>{
          'otherUid': chat.otherUid,
          'sharedTourId': chat.sharedTourId,
          'otherEmail': chat.otherEmail,
          'sharedFiles': _sendable,
        },
      ),
    );
  }

  void _sendToChannel(ChannelDestination channel) {
    Navigator.of(context).pop();
    unawaited(_sendToGroupChannel(widget.rootContext, channel, _sendable));
  }
}

/// The name a channel row shows, the same as in the channels screen.
String _channelTitle(AppLocalizations l10n, ChannelDestination channel) {
  return channelTitleText(
    channel: channel.channel,
    group: channel.group,
    translate: (key) => l10n.translate(key),
  );
}

/// Sends [files] to [channel] once the sheet has closed. Progress and the outcome show
/// as snack bars on the root messenger, so they stay visible wherever the user is.
Future<void> _sendToGroupChannel(
  BuildContext rootContext,
  ChannelDestination channel,
  List<SharedFile> files,
) async {
  final l10n = rootContext.l10n;
  final messenger = ScaffoldMessenger.maybeOf(rootContext);
  final name = _channelTitle(l10n, channel);
  const sending = Duration(minutes: 5);
  const outcome = Duration(seconds: 4);

  void show(String text, Duration duration) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: duration));
  }

  show(l10n.translate('share_sending', args: {'channel': name}), sending);
  try {
    await ChannelShareSender(
      repository: TourChannelRepository(groups: TourGroupRepository()),
    ).send(
      tourId: channel.tourId,
      channelId: channel.channelId,
      files: files,
      onProgress: (sent, total) => show(
        l10n.translate(
          'share_sending_progress',
          args: {
            'sent': l10n.number(sent),
            'total': l10n.number(total),
            'channel': name,
          },
        ),
        sending,
      ),
    );
    show(l10n.translate('share_sent_done', args: {'channel': name}), outcome);
  } catch (error, stack) {
    logWarning(
      '[ShareIntake] could not send the files to ${channel.channelId}',
      error,
      stack,
    );
    show(l10n.translate('share_send_failed', args: {'channel': name}), outcome);
  }
}
