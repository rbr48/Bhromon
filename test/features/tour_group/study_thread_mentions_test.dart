import 'package:bhromon/features/tour_group/domain/models/study_thread_models.dart';
import 'package:flutter_test/flutter_test.dart';

// The members a discussion names with @ are stored with it, as a list of emails. A stored list keeps only the texts
// in it, and a thread or reply written before mentions existed names no one.

void main() {
  test(
      'a thread reads the emails it names, and drops anything that is not a text',
      () {
    final thread = StudyThread.fromMap('t1', {
      'title': 'Why is the sum zero?',
      'body': 'Ask @Ben about it.',
      'mentions': ['ben@x.com', 5, '', 'dee@x.com'],
    });
    expect(thread?.mentions, ['ben@x.com', 'dee@x.com']);
  });

  test('a thread written before mentions existed names no one', () {
    final thread = StudyThread.fromMap('t2', {
      'title': 'Old question',
      'body': 'No mentions here.',
    });
    expect(thread?.mentions, isEmpty);
    expect(thread?.toFields()['mentions'], isEmpty);
  });

  test('a reply carries the emails it names when it is written', () {
    const reply = StudyReply(
      id: 'r1',
      text: 'Thanks @dee',
      createdByEmail: 'ben@x.com',
      mentions: ['dee@x.com'],
    );
    expect(reply.toFields()['mentions'], ['dee@x.com']);
    expect(
        StudyReply.fromMap('r1', {'text': 'Thanks', 'mentions': 'nobody'})
            ?.mentions,
        isEmpty);
  });
}
