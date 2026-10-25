// Slash commands typed into a channel: "/split" records an expense and "/poll"
// starts a vote. Anything else is an ordinary message.

import '../models/channel_models.dart';
import 'trip_ledger_engine.dart';

sealed class ChatCommand {
  const ChatCommand();
}

/// "/split 2400 Dinner at Laboni": an expense shared by the whole tour.
class SplitCommand extends ChatCommand {
  final int amountPaisa;
  final String title;

  const SplitCommand({required this.amountPaisa, required this.title});
}

/// "/poll Where to eat? | Hilsa | Chicken": a question with up to six options.
class PollCommand extends ChatCommand {
  final String question;
  final List<String> options;

  const PollCommand({required this.question, required this.options});
}

/// A command that could not be used. [messageKey] is a translation key that
/// says why.
class ChatCommandError extends ChatCommand {
  final String messageKey;

  const ChatCommandError(this.messageKey);
}

const int _maxTitleLength = 80;
const int _maxQuestionLength = 200;
const int _maxOptionLength = 60;

/// The command [text] holds, or null when it is an ordinary message.
ChatCommand? parseChatCommand(String text) {
  final trimmed = text.trim();
  if (!trimmed.startsWith('/')) return null;

  final space = trimmed.indexOf(RegExp(r'\s'));
  final name =
      (space < 0 ? trimmed : trimmed.substring(0, space)).toLowerCase();
  final args = space < 0 ? '' : trimmed.substring(space).trim();

  switch (name) {
    case '/split':
      return _split(args);
    case '/poll':
      return _poll(args);
    default:
      return const ChatCommandError('chat_command_unknown');
  }
}

ChatCommand _split(String args) {
  if (args.isEmpty) return const ChatCommandError('chat_split_usage');
  final amountText = args.split(RegExp(r'\s+')).first;
  final title = args.substring(amountText.length).trim();

  final paisa = TripLedgerEngine.parseTakaInput(amountText);
  if (paisa == null) return const ChatCommandError('chat_split_bad_amount');
  if (title.isEmpty) return const ChatCommandError('chat_split_no_title');
  if (title.length > _maxTitleLength) {
    return const ChatCommandError('chat_split_title_long');
  }
  return SplitCommand(amountPaisa: paisa, title: title);
}

ChatCommand _poll(String args) {
  final pieces = args.split('|').map((p) => p.trim()).toList();
  final question = pieces.first;
  if (question.isEmpty) return const ChatCommandError('chat_poll_usage');
  if (question.length > _maxQuestionLength) {
    return const ChatCommandError('chat_poll_question_long');
  }

  final options = pieces.skip(1).where((o) => o.isNotEmpty).toList();
  if (options.length < 2) return const ChatCommandError('chat_poll_usage');
  if (options.length > kChannelMaxPollOptions) {
    return const ChatCommandError('chat_poll_too_many');
  }
  if (options.any((o) => o.length > _maxOptionLength)) {
    return const ChatCommandError('chat_poll_option_long');
  }
  return PollCommand(question: question, options: options);
}
