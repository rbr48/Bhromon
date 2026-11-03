import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/localization/localized_date.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/features/chat/domain/call_log_entry.dart';
import 'package:flutter/material.dart';

/// One call in the history with a person: how it went, and when.
class ChatCallRow {
  const ChatCallRow({required this.entry, required this.at});

  final CallLogEntry entry;

  /// When the call was logged, or null when the log has no time yet.
  final DateTime? at;
}

/// The calls page of a one-to-one chat: the two ways to call the person, and the call
/// history. A swipe between this page and the messages only shows the page. It never
/// starts a call; only the buttons and the call-back icons do.
class ChatCallsPage extends StatelessWidget {
  const ChatCallsPage({
    super.key,
    required this.otherName,
    required this.currentUid,
    required this.rows,
    required this.onVoiceCall,
    required this.onVideoCall,
    required this.onCallBack,
  });

  final String otherName;
  final String currentUid;

  /// The calls, newest first.
  final List<ChatCallRow> rows;

  final VoidCallback onVoiceCall;
  final VoidCallback onVideoCall;

  /// Calls the person back the way the call was made: video or voice.
  final ValueChanged<bool> onCallBack;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        Text(
          l10n.translate('chat_calls_title', args: {'name': otherName}),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.mintGreen,
                  foregroundColor: AppColors.darkGreen,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: onVoiceCall,
                icon: const Icon(Icons.call_rounded),
                label: Text(l10n.translate('chat_call_audio')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.mintGreen,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: onVideoCall,
                icon: const Icon(Icons.videocam_rounded),
                label: Text(l10n.translate('chat_call_video')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          l10n.translate('chat_calls_history'),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              l10n.translate('chat_calls_empty', args: {'name': otherName}),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54),
            ),
          )
        else
          for (final row in rows)
            _CallHistoryTile(
                row: row, currentUid: currentUid, onCallBack: onCallBack),
      ],
    );
  }
}

class _CallHistoryTile extends StatelessWidget {
  const _CallHistoryTile({
    required this.row,
    required this.currentUid,
    required this.onCallBack,
  });

  final ChatCallRow row;
  final String currentUid;
  final ValueChanged<bool> onCallBack;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final kind = row.entry.kindFor(currentUid);
    final isProblem = kind == CallLogKind.missed ||
        kind == CallLogKind.noAnswer ||
        kind == CallLogKind.declined;
    final when = row.at == null
        ? null
        : localizedDateFormat('d MMM, h:mm a').format(row.at!);
    final seconds = row.entry.durationSeconds;
    final length = row.entry.connected && seconds != null
        ? '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}'
        : null;
    final subtitle =
        [if (when != null) when, if (length != null) length].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: 8,
      leading: Icon(
        row.entry.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
        color: isProblem ? const Color(0xFFEF4444) : AppColors.mintGreen,
      ),
      title: Text(
        l10n.translate(_labelKey(kind)),
        style: const TextStyle(color: Colors.white),
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, style: const TextStyle(color: Colors.white54)),
      trailing: IconButton(
        tooltip: l10n.translate(
            row.entry.isVideo ? 'chat_call_video' : 'chat_call_audio'),
        icon: Icon(
          row.entry.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
          color: AppColors.mintGreen,
        ),
        onPressed: () => onCallBack(row.entry.isVideo),
      ),
    );
  }

  static String _labelKey(CallLogKind kind) => switch (kind) {
        CallLogKind.outgoing => 'chat_call_outgoing',
        CallLogKind.incoming => 'chat_call_incoming',
        CallLogKind.outgoingVideo => 'chat_call_outgoing_video',
        CallLogKind.incomingVideo => 'chat_call_incoming_video',
        CallLogKind.missed => 'chat_call_missed',
        CallLogKind.noAnswer => 'chat_call_no_answer',
        CallLogKind.declined => 'chat_call_declined',
      };
}

/// The two-page switch above a chat: messages or calls. Tapping a label moves the pager
/// to that page, for people who do not swipe.
class ChatPageSwitch extends StatelessWidget {
  const ChatPageSwitch({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  /// 0 for messages, 1 for calls.
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget item(int index, String label) {
      final active = selected == index;
      return Expanded(
        child: Semantics(
          button: true,
          selected: active,
          label: label,
          child: InkWell(
            onTap: () => onSelected(index),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: active ? AppColors.mintGreen : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: active ? AppColors.mintGreen : Colors.white70,
                  fontWeight: active ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        item(0, l10n.translate('chat_view_messages')),
        item(1, l10n.translate('chat_view_calls')),
      ],
    );
  }
}
