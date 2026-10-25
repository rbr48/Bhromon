import 'package:bhromon/features/tour_group/domain/services/chat_commands.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chat commands', () {
    test('an ordinary message is not a command', () {
      expect(parseChatCommand('hello everyone'), isNull);
      expect(parseChatCommand('  path/to/file'), isNull);
    });

    test('/split records the amount in paisa and the title', () {
      final c = parseChatCommand('/split 2400 Dinner at Laboni');
      expect(c, isA<SplitCommand>());
      final split = c! as SplitCommand;
      expect(split.amountPaisa, 240000);
      expect(split.title, 'Dinner at Laboni');
    });

    test('/split accepts Bengali digits', () {
      final split = parseChatCommand('/split ২৪০০ চা') as SplitCommand;
      expect(split.amountPaisa, 240000);
    });

    test('/split explains what is missing or wrong', () {
      expect(_key('/split'), 'chat_split_usage');
      expect(_key('/split 0 tea'), 'chat_split_bad_amount');
      expect(_key('/split abc tea'), 'chat_split_bad_amount');
      expect(_key('/split 500'), 'chat_split_no_title');
      expect(_key('/split 500 ${'x' * 81}'), 'chat_split_title_long');
    });

    test('/poll takes a question and two to six options', () {
      final c = parseChatCommand('/poll Where to eat? | Hilsa | Chicken');
      expect(c, isA<PollCommand>());
      final poll = c! as PollCommand;
      expect(poll.question, 'Where to eat?');
      expect(poll.options, ['Hilsa', 'Chicken']);
    });

    test('/poll explains what is missing or wrong', () {
      expect(_key('/poll'), 'chat_poll_usage');
      expect(_key('/poll | a | b'), 'chat_poll_usage');
      expect(_key('/poll Q | only one'), 'chat_poll_usage');
      expect(_key('/poll Q | a | b | c | d | e | f | g'), 'chat_poll_too_many');
      expect(_key('/poll Q | ${'x' * 61} | b'), 'chat_poll_option_long');
      expect(_key('/poll ${'q' * 201} | a | b'), 'chat_poll_question_long');
    });

    test('command names ignore case and need no spaces around "|"', () {
      final poll = parseChatCommand('/POLL Q|a|b') as PollCommand;
      expect(poll.options, ['a', 'b']);
    });

    test('an unknown command is reported', () {
      expect(_key('/bus'), 'chat_command_unknown');
    });
  });
}

String? _key(String text) {
  final c = parseChatCommand(text);
  return c is ChatCommandError ? c.messageKey : null;
}
