import 'package:bhromon/features/tour_group/domain/models/study_subject_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_subject_rules.dart';
import 'package:flutter_test/flutter_test.dart';

// A study group's subjects: which modules a viewer sees, who may post in each, which posts a
// viewer sees and in what order, and how the stored fields are read. The rules here mirror the
// ones in firestore.rules, so a change to one needs the other.

StudyModuleSettings _module(
  StudyModuleKey key, {
  bool enabled = true,
  StudyPostPolicy policy = StudyPostPolicy.members,
}) =>
    StudyModuleSettings(
      key: key,
      enabled: enabled,
      name: key.name,
      postPolicy: policy,
    );

StudyPost _post(
  String id, {
  String by = 'someone@x.com',
  DateTime? at,
  int helpful = 0,
  bool shown = true,
  bool pinned = false,
}) =>
    StudyPost(
      id: id,
      text: 'Text $id',
      createdByEmail: by,
      createdAt: at,
      helpfulCount: helpful,
      shown: shown,
      pinned: pinned,
    );

StudySubject _subject(String id, String title) =>
    StudySubject(id: id, title: title);

void main() {
  group('modules a viewer sees', () {
    test('an admin sees every module, in catalogue order', () {
      final visible = visibleStudyModules(settings: const {}, isAdmin: true);
      expect(visible, StudyModuleKey.values);
    });

    test('a member sees only the live modules that are on', () {
      final visible = visibleStudyModules(
        settings: {
          StudyModuleKey.tips: _module(StudyModuleKey.tips),
          StudyModuleKey.suggestions:
              _module(StudyModuleKey.suggestions, enabled: false),
          StudyModuleKey.discussion: _module(StudyModuleKey.discussion),
        },
        isAdmin: false,
      );
      expect(visible, [StudyModuleKey.tips]);
    });

    test('a member sees nothing when no module is on', () {
      expect(
        visibleStudyModules(settings: const {}, isAdmin: false),
        isEmpty,
      );
    });
  });

  group('who may post', () {
    test('no post in a module with no settings', () {
      expect(canPostInStudyModule(settings: null, isAdmin: true), isFalse);
    });

    test('no post in a module that is off, even for an admin', () {
      final off = _module(StudyModuleKey.tips, enabled: false);
      expect(canPostInStudyModule(settings: off, isAdmin: true), isFalse);
      expect(canPostInStudyModule(settings: off, isAdmin: false), isFalse);
    });

    test(
        'members post where the module lets them, and admins post in any module that is on',
        () {
      final members = _module(StudyModuleKey.tips);
      final approval = _module(
        StudyModuleKey.suggestions,
        policy: StudyPostPolicy.approval,
      );
      final adminsOnly = _module(
        StudyModuleKey.tips,
        policy: StudyPostPolicy.admins,
      );
      expect(canPostInStudyModule(settings: members, isAdmin: false), isTrue);
      expect(canPostInStudyModule(settings: approval, isAdmin: false), isTrue);
      expect(
          canPostInStudyModule(settings: adminsOnly, isAdmin: false), isFalse);
      expect(canPostInStudyModule(settings: adminsOnly, isAdmin: true), isTrue);
    });
  });

  group('whether a post is shown at once', () {
    test('an admin\'s post is always shown', () {
      for (final policy in StudyPostPolicy.values) {
        expect(
          postShownAtOnce(
            settings: _module(StudyModuleKey.tips, policy: policy),
            isAdmin: true,
          ),
          isTrue,
        );
      }
    });

    test(
        'a member\'s post is shown only where the module lets members post directly',
        () {
      expect(
        postShownAtOnce(settings: _module(StudyModuleKey.tips), isAdmin: false),
        isTrue,
      );
      expect(
        postShownAtOnce(
          settings:
              _module(StudyModuleKey.tips, policy: StudyPostPolicy.approval),
          isAdmin: false,
        ),
        isFalse,
      );
    });
  });

  group('which posts a viewer sees', () {
    final posts = [
      _post('shown', by: 'b@x.com'),
      _post('waiting', by: 'b@x.com', shown: false),
      _post('mine', by: 'me@x.com', shown: false),
    ];

    test('a member sees shown posts and their own waiting post', () {
      final ids = visibleStudyPosts(
        posts: posts,
        viewerEmail: 'me@x.com',
        isAdmin: false,
      ).map((p) => p.id);
      expect(ids, ['shown', 'mine']);
    });

    test('an admin sees every post, waiting ones too', () {
      final ids = visibleStudyPosts(
        posts: posts,
        viewerEmail: 'admin@x.com',
        isAdmin: true,
      ).map((p) => p.id);
      expect(ids, ['shown', 'waiting', 'mine']);
    });
  });

  group('the order of posts', () {
    test('pinned first, then the most helpful, then the newest', () {
      final sorted = sortStudyPosts([
        _post('old', at: DateTime(2026, 11, 1)),
        _post('new', at: DateTime(2026, 11, 5)),
        _post('helpful', at: DateTime(2026, 10, 1), helpful: 4),
        _post('pinned', at: DateTime(2026, 9, 1), pinned: true),
      ]);
      expect(sorted.map((p) => p.id), ['pinned', 'helpful', 'new', 'old']);
    });

    test(
        'a post whose time is not yet known comes first, since it was just written',
        () {
      final sorted = sortStudyPosts([
        _post('written', at: DateTime(2026, 11, 5)),
        _post('pending'),
      ]);
      expect(sorted.map((p) => p.id), ['pending', 'written']);
    });

    test('sorting leaves the list it was given as it was', () {
      final input = [
        _post('a', at: DateTime(2026, 11, 1)),
        _post('b', at: DateTime(2026, 11, 2)),
      ];
      sortStudyPosts(input);
      expect(input.map((p) => p.id), ['a', 'b']);
    });
  });

  group('subjects', () {
    test('sorted by title, ignoring case', () {
      final sorted = studySubjectsByTitle([
        _subject('1', 'physics'),
        _subject('2', 'Biology'),
        _subject('3', 'Chemistry'),
      ]);
      expect(sorted.map((s) => s.id), ['2', '3', '1']);
    });

    test('a subject with no title is not read', () {
      expect(StudySubject.fromMap('x', {'title': '   '}), isNull);
      expect(StudySubject.fromMap('x', {}), isNull);
    });

    test(
        'a subject with no approval was listed before approvals, and reads as listed',
        () {
      final subject = StudySubject.fromMap('x', {'title': 'Physics'});
      expect(subject?.isListed, isTrue);
    });

    test('a proposal and a declined subject read with their approval and note',
        () {
      final proposed = StudySubject.fromMap(
          'p', {'title': 'Chemistry', 'approval': 'proposed'});
      final declined = StudySubject.fromMap('d', {
        'title': 'Music',
        'approval': 'declined',
        'declineNote': '  Not this course  ',
      });
      expect(proposed?.isProposed, isTrue);
      expect(declined?.isDeclined, isTrue);
      expect(declined?.declineNote, 'Not this course');
    });

    test('an exam date is read only when it is a date', () {
      final exam = DateTime(2026, 12, 1);
      expect(
        StudySubject.fromMap('x', {'title': 'Physics', 'examDate': exam})
            ?.examDate,
        exam,
      );
      expect(
        StudySubject.fromMap('x', {'title': 'Physics', 'examDate': 'soon'})
            ?.examDate,
        isNull,
      );
    });
  });

  group('the exam countdown', () {
    test('counts whole days on dates, ignoring the time of day', () {
      final today = DateTime(2026, 11, 9, 0, 5);
      expect(daysUntilExam(DateTime(2026, 11, 9, 23, 59), today), 0);
      expect(daysUntilExam(DateTime(2026, 11, 10), today), 1);
      expect(daysUntilExam(DateTime(2026, 11, 8, 9), today), -1);
      expect(daysUntilExam(DateTime(2026, 11, 20), today), 11);
    });
  });

  group('modules and posts as stored', () {
    test('tips, suggestions and shared findings are live', () {
      final live = StudyModuleKey.values.where((k) => k.isLive).toList();
      expect(live, [
        StudyModuleKey.tips,
        StudyModuleKey.suggestions,
        StudyModuleKey.findings,
      ]);
    });

    test('a module key is read from its name, and an unknown name is not', () {
      expect(StudyModuleKey.fromName('tips'), StudyModuleKey.tips);
      expect(StudyModuleKey.fromName('bogus'), isNull);
      expect(StudyModuleKey.fromName(null), isNull);
    });

    test(
        'a module with no name is not read, and an unknown post policy reads as members',
        () {
      expect(
        StudyModuleSettings.fromMap(
          StudyModuleKey.tips,
          {'enabled': true, 'name': ' '},
        ),
        isNull,
      );
      final read = StudyModuleSettings.fromMap(StudyModuleKey.tips, {
        'enabled': true,
        'name': ' Exam tips ',
        'postPolicy': 'everyone',
      });
      expect(read?.name, 'Exam tips');
      expect(read?.postPolicy, StudyPostPolicy.members);
    });

    test('a module is on only when its enabled flag is true', () {
      final read = StudyModuleSettings.fromMap(
        StudyModuleKey.tips,
        {'enabled': 'yes', 'name': 'Tips'},
      );
      expect(read?.enabled, isFalse);
    });

    test(
        'a post with no text is not read; a post reads its helpful count and flags',
        () {
      expect(StudyPost.fromMap('x', {'text': '  '}), isNull);
      final post = StudyPost.fromMap('x', {
        'text': 'Revise chapter 3',
        'helpfulCount': 2.0,
        'shown': false,
        'pinned': true,
      });
      expect(post?.helpfulCount, 2);
      expect(post?.shown, isFalse);
      expect(post?.pinned, isTrue);
    });

    test('a post is shown unless it says otherwise', () {
      expect(StudyPost.fromMap('x', {'text': 'Revise'})?.shown, isTrue);
    });
  });

  group('the fields a write carries', () {
    test(
        'empty optional text is stored as null, so the rules see no empty strings',
        () {
      final fields = const StudySubject(
        id: '',
        title: 'Physics',
        code: '',
        description: '',
      ).toFields();
      expect(fields['code'], isNull);
      expect(fields['description'], isNull);
      expect(fields['declineNote'], isNull);
    });

    test('a module writes its three fields', () {
      expect(_module(StudyModuleKey.tips).toFields(), {
        'enabled': true,
        'name': 'tips',
        'postPolicy': 'members',
      });
    });
  });
}
