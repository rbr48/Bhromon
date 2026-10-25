import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/chat_mentions.dart';
import 'package:flutter_test/flutter_test.dart';

TourMember _member(
  String name,
  String email, {
  TourRole role = TourRole.member,
  TourMemberStatus status = TourMemberStatus.active,
}) {
  return TourMember(
    tourId: 't1',
    email: email,
    displayName: name,
    role: role,
    status: status,
    joinedAt: DateTime(2026),
  );
}

final List<TourMember> _members = [
  _member('Tanvir Ahmed', 'tanvir@x.com'),
  _member('Tan', 'tan@x.com'),
  _member('Rahim', 'rahim@x.com', role: TourRole.admin),
  _member('Old Friend', 'old@x.com', status: TourMemberStatus.invited),
];

void main() {
  group('resolveMentions', () {
    test('a full name matches the longest name, not a shorter prefix', () {
      expect(
          resolveMentions('hi @Tanvir Ahmed see', _members), ['tanvir@x.com']);
    });

    test('a short name matches only at a word boundary', () {
      expect(resolveMentions('@Tan ok', _members), ['tan@x.com']);
    });

    test('@everyone and @all mention every active member, not invited ones',
        () {
      final expected = ['tanvir@x.com', 'tan@x.com', 'rahim@x.com'];
      expect(resolveMentions('@everyone', _members), expected);
      expect(resolveMentions('@all', _members), expected);
    });

    test('@admin mentions the organisers only', () {
      expect(resolveMentions('@admin', _members), ['rahim@x.com']);
    });

    test('names ignore case', () {
      expect(resolveMentions('@RAHIM', _members), ['rahim@x.com']);
    });

    test('an email address is not a mention', () {
      expect(resolveMentions('write to mail@rahim.com', _members), isEmpty);
    });

    test('an invited member cannot be mentioned by name', () {
      expect(resolveMentions('@Old Friend', _members), isEmpty);
    });

    test('a member mentioned twice is listed once', () {
      expect(resolveMentions('@everyone @Rahim', _members),
          ['tanvir@x.com', 'tan@x.com', 'rahim@x.com']);
    });
  });

  group('mention autocomplete', () {
    test('the mention being typed is found at the cursor', () {
      final q = activeMentionQuery('hi @Ta', 6);
      expect(q, isNotNull);
      expect(q!.start, 3);
      expect(q.query, 'ta');
    });

    test('a space ends the mention, so nothing is offered after it', () {
      expect(activeMentionQuery('hi @Tan x', 9), isNull);
    });

    test('an "@" inside a word is not a mention', () {
      expect(activeMentionQuery('mail@x', 6), isNull);
    });

    test('suggestions start with the groups, then members by name', () {
      final all = mentionSuggestions(const MentionQuery(0, ''), _members);
      expect(all.take(2).toList(), [kMentionEveryone, kMentionAdmins]);

      final ta = mentionSuggestions(const MentionQuery(0, 'ta'), _members);
      expect(ta, ['Tanvir Ahmed', 'Tan']);
    });

    test('a suggestion replaces the partial mention and adds a space', () {
      const text = 'hi @Ta now';
      final q = activeMentionQuery(text, 6)!;
      expect(applyMention(text, q, 6, 'Tan'), 'hi @Tan now');
    });
  });
}
