import 'package:bhromon/features/tour_group/domain/models/study_material_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_material_rules.dart';
import 'package:flutter_test/flutter_test.dart';

StudyMaterial _material(
  String id, {
  StudyMaterialKind kind = StudyMaterialKind.note,
  StudyMaterialStatus status = StudyMaterialStatus.published,
  String by = 'other@x.com',
  String? chapterId,
  DateTime? createdAt,
  DateTime? reportedAt,
  int reportCount = 0,
  String? url,
}) =>
    StudyMaterial(
      id: id,
      title: 'Material $id',
      kind: kind,
      bookId: 'b1',
      chapterId: chapterId,
      url: url,
      body: kind == StudyMaterialKind.note ? 'Text' : null,
      status: status,
      reportCount: reportCount,
      reportedAt: reportedAt,
      createdByEmail: by,
      createdAt: createdAt,
    );

void main() {
  group('upload limits and kinds', () {
    test('each kind has its size limit; a link and a note have none', () {
      expect(studyMaterialMaxBytes(StudyMaterialKind.image), 10 * 1024 * 1024);
      expect(studyMaterialMaxBytes(StudyMaterialKind.audio), 25 * 1024 * 1024);
      expect(studyMaterialMaxBytes(StudyMaterialKind.video), 100 * 1024 * 1024);
      expect(studyMaterialMaxBytes(StudyMaterialKind.file), 50 * 1024 * 1024);
      expect(studyMaterialMaxBytes(StudyMaterialKind.link), isNull);
      expect(studyMaterialMaxBytes(StudyMaterialKind.note), isNull);
    });

    test('a file takes the kind its extension belongs to', () {
      expect(studyKindForFileName('notes.jpg'), StudyMaterialKind.image);
      expect(studyKindForFileName('lecture.mp4'), StudyMaterialKind.video);
      expect(studyKindForFileName('explain.m4a'), StudyMaterialKind.audio);
      expect(studyKindForFileName('summary.pdf'), StudyMaterialKind.file);
      expect(studyKindForFileName('notes.md'), StudyMaterialKind.file);
      expect(studyKindForFileName('config.json'), StudyMaterialKind.file);
      expect(studyKindForFileName('book.epub'), StudyMaterialKind.file);
      expect(studyKindForFileName('archive.7z'), StudyMaterialKind.file);
      expect(studyKindForFileName('program.exe'), isNull);
    });

    test('a file of the wrong kind, an empty file or one too large is refused',
        () {
      expect(
        studyFileProblem(
          kind: StudyMaterialKind.image,
          fileName: 'summary.pdf',
          sizeBytes: 1000,
        ),
        StudyFileProblem.unsupported,
      );
      expect(
        studyFileProblem(
          kind: StudyMaterialKind.file,
          fileName: 'summary.pdf',
          sizeBytes: 0,
        ),
        StudyFileProblem.empty,
      );
      expect(
        studyFileProblem(
          kind: StudyMaterialKind.file,
          fileName: 'summary.pdf',
          sizeBytes: 50 * 1024 * 1024 + 1,
        ),
        StudyFileProblem.tooLarge,
      );
    });

    test('a file exactly at its limit is accepted', () {
      expect(
        studyFileProblem(
          kind: StudyMaterialKind.file,
          fileName: 'summary.pdf',
          sizeBytes: 50 * 1024 * 1024,
        ),
        isNull,
      );
    });

    test('a link or a note is never a file', () {
      expect(
        studyFileProblem(
          kind: StudyMaterialKind.link,
          fileName: 'summary.pdf',
          sizeBytes: 10,
        ),
        StudyFileProblem.unsupported,
      );
    });

    test('the picker offers the extensions of an upload kind only', () {
      expect(studyMaterialExtensions(StudyMaterialKind.file), contains('pdf'));
      expect(studyMaterialExtensions(StudyMaterialKind.file), contains('md'));
      expect(studyMaterialExtensions(StudyMaterialKind.file), contains('epub'));
      expect(studyMaterialExtensions(StudyMaterialKind.file), contains('7z'));
      expect(studyMaterialExtensions(StudyMaterialKind.video), contains('mkv'));
      expect(studyMaterialExtensions(StudyMaterialKind.link), isEmpty);
      expect(studyMaterialExtensions(StudyMaterialKind.note), isEmpty);
    });
  });

  group('links', () {
    test('an http or https address with a host is valid', () {
      expect(isStudyLinkValid('https://example.com/notes'), isTrue);
      expect(isStudyLinkValid('http://example.com'), isTrue);
      expect(isStudyLinkValid('  https://example.com  '), isTrue);
    });

    test('anything else is not a link the app lists', () {
      expect(isStudyLinkValid('ftp://example.com/file'), isFalse);
      expect(isStudyLinkValid('https://'), isFalse);
      expect(isStudyLinkValid('example.com'), isFalse);
      expect(isStudyLinkValid(''), isFalse);
    });

    test('a long link is still a link: study text has no length limit', () {
      expect(isStudyLinkValid('https://example.com/${'x' * 2000}'), isTrue);
    });

    test('the domain is the host without a leading www.', () {
      expect(studyLinkDomain('https://www.example.com/path'), 'example.com');
      expect(studyLinkDomain('https://docs.example.org'), 'docs.example.org');
      expect(studyLinkDomain('not a link'), '');
    });
  });

  group('who sees, reports and manages a material', () {
    test(
        'published material is shown to the group; pending and hidden only to the uploader and admins',
        () {
      final published = _material('a');
      final pending = _material('b', status: StudyMaterialStatus.pending);
      final hidden = _material('c', status: StudyMaterialStatus.hidden);

      expect(
          isStudyMaterialVisibleTo(published,
              viewerEmail: 'me@x.com', isAdmin: false),
          isTrue);
      expect(
          isStudyMaterialVisibleTo(pending,
              viewerEmail: 'me@x.com', isAdmin: false),
          isFalse);
      expect(
          isStudyMaterialVisibleTo(hidden,
              viewerEmail: 'me@x.com', isAdmin: false),
          isFalse);
      expect(
          isStudyMaterialVisibleTo(pending,
              viewerEmail: 'other@x.com', isAdmin: false),
          isTrue);
      expect(
          isStudyMaterialVisibleTo(hidden,
              viewerEmail: 'admin@x.com', isAdmin: true),
          isTrue);
    });

    test(
        'a member reports another member\'s published material, never their own or a waiting one',
        () {
      expect(canReportStudyMaterial(_material('a'), viewerEmail: 'me@x.com'),
          isTrue);
      expect(
          canReportStudyMaterial(_material('a', by: 'me@x.com'),
              viewerEmail: 'me@x.com'),
          isFalse);
      expect(
        canReportStudyMaterial(
            _material('a', status: StudyMaterialStatus.pending),
            viewerEmail: 'me@x.com'),
        isFalse,
      );
      expect(
        canReportStudyMaterial(
            _material('a', status: StudyMaterialStatus.hidden),
            viewerEmail: 'me@x.com'),
        isFalse,
      );
    });

    test('the uploader and an admin edit or remove a material', () {
      final mine = _material('a', by: 'me@x.com');
      expect(
          canManageStudyMaterial(mine, viewerEmail: 'me@x.com', isAdmin: false),
          isTrue);
      expect(
          canManageStudyMaterial(mine,
              viewerEmail: 'other@x.com', isAdmin: false),
          isFalse);
      expect(
          canManageStudyMaterial(mine,
              viewerEmail: 'admin@x.com', isAdmin: true),
          isTrue);
    });

    test(
        'an admin\'s material is published at once; a member\'s waits unless the group publishes directly',
        () {
      expect(
        initialStudyMaterialStatus(isAdmin: true, needsApproval: true),
        StudyMaterialStatus.published,
      );
      expect(
        initialStudyMaterialStatus(isAdmin: false, needsApproval: true),
        StudyMaterialStatus.pending,
      );
      expect(
        initialStudyMaterialStatus(isAdmin: false, needsApproval: false),
        StudyMaterialStatus.published,
      );
    });
  });

  group('order and the queues', () {
    test('materials are newest first, and one with no time comes first', () {
      final sorted = sortStudyMaterials([
        _material('old', createdAt: DateTime(2026, 1, 1)),
        _material('new', createdAt: DateTime(2026, 3, 1)),
        _material('unknown'),
      ]);
      expect(sorted.map((m) => m.id), ['unknown', 'new', 'old']);
    });

    test('a chapter filter keeps one chapter, and null keeps all', () {
      final materials = [
        _material('a', chapterId: 'c1'),
        _material('b', chapterId: 'c2'),
        _material('c'),
      ];
      expect(studyMaterialsInChapter(materials, null), hasLength(3));
      expect(studyMaterialsInChapter(materials, 'c1').map((m) => m.id), ['a']);
    });

    test('the review queue holds the hidden material, oldest report first', () {
      final queue = studyReviewQueue([
        _material('later',
            status: StudyMaterialStatus.hidden,
            reportedAt: DateTime(2026, 3, 2)),
        _material('earlier',
            status: StudyMaterialStatus.hidden,
            reportedAt: DateTime(2026, 3, 1)),
        _material('shown'),
      ]);
      expect(queue.map((m) => m.id), ['earlier', 'later']);
    });

    test('the approval queue holds the waiting material, newest first', () {
      final queue = studyApprovalQueue([
        _material('old',
            status: StudyMaterialStatus.pending,
            createdAt: DateTime(2026, 1, 1)),
        _material('new',
            status: StudyMaterialStatus.pending,
            createdAt: DateTime(2026, 2, 1)),
        _material('shown'),
      ]);
      expect(queue.map((m) => m.id), ['new', 'old']);
    });

    test('a report is overdue after 24 hours with no decision', () {
      final now = DateTime(2026, 3, 2, 12);
      expect(
        isStudyReportOverdue(
          _material('a',
              status: StudyMaterialStatus.hidden,
              reportedAt: DateTime(2026, 3, 1, 11)),
          now: now,
        ),
        isTrue,
      );
      expect(
        isStudyReportOverdue(
          _material('a',
              status: StudyMaterialStatus.hidden,
              reportedAt: DateTime(2026, 3, 1, 13)),
          now: now,
        ),
        isFalse,
      );
      expect(
        isStudyReportOverdue(
          _material('a',
              status: StudyMaterialStatus.published,
              reportedAt: DateTime(2026, 3, 1)),
          now: now,
        ),
        isFalse,
      );
    });
  });

  group('the record', () {
    test('a stored material reads back with its kind, status and report count',
        () {
      final material = StudyMaterial.fromMap('m1', {
        'title': ' Chapter 2 summary ',
        'kind': 'file',
        'bookId': 'b1',
        'chapterId': 'c2',
        'url': 'https://bhromon.fun/media/T/study/aaaa.pdf',
        'sizeBytes': 2048,
        'status': 'hidden',
        'reportCount': 2,
        'createdByEmail': 'other@x.com',
      });
      expect(material, isNotNull);
      expect(material!.title, 'Chapter 2 summary');
      expect(material.kind, StudyMaterialKind.file);
      expect(material.status, StudyMaterialStatus.hidden);
      expect(material.reportCount, 2);
      expect(material.sizeBytes, 2048);
      expect(material.chapterId, 'c2');
    });

    test(
        'a record with no title or book is left out, and unknown names fall back',
        () {
      expect(StudyMaterial.fromMap('x', {'title': '', 'bookId': 'b1'}), isNull);
      expect(
          StudyMaterial.fromMap('x', {'title': 'Notes', 'bookId': ''}), isNull);
      final odd = StudyMaterial.fromMap('x', {
        'title': 'Notes',
        'bookId': 'b1',
        'kind': 'hologram',
        'status': 'archived',
      });
      expect(odd!.kind, StudyMaterialKind.note);
      expect(odd.status, StudyMaterialStatus.pending);
    });

    test('a new material is filed with its rights confirmed and no reports',
        () {
      final fields = _material('a', by: 'me@x.com')
          .toFields(status: StudyMaterialStatus.pending);
      expect(fields['rightsConfirmed'], isTrue);
      expect(fields['reportCount'], 0);
      expect(fields['status'], 'pending');
      expect(fields['createdByEmail'], 'me@x.com');
    });

    test(
        'a report reason is one of the listed reasons; an unknown one is other',
        () {
      expect(StudyMaterialReportReason.fromName('exam'),
          StudyMaterialReportReason.exam);
      expect(StudyMaterialReportReason.fromName('rude'),
          StudyMaterialReportReason.other);
    });
  });
  group('who may add a material', () {
    test('the policy is off by default: members wait for approval, may add',
        () {
      const policy = StudyMaterialPolicy();
      expect(policy.needsApproval, isTrue);
      expect(policy.onlyAdminsPost, isFalse);
    });

    test('an admin may always add, with or without the rule', () {
      expect(canFileStudyMaterial(isAdmin: true, onlyAdminsPost: true), isTrue);
      expect(
          canFileStudyMaterial(isAdmin: true, onlyAdminsPost: false), isTrue);
    });

    test('a member may add unless only admins may add', () {
      expect(
          canFileStudyMaterial(isAdmin: false, onlyAdminsPost: false), isTrue);
      expect(
          canFileStudyMaterial(isAdmin: false, onlyAdminsPost: true), isFalse);
    });
  });

  group('the library groups materials by chapter', () {
    test('whole-book materials first, then chapters in order, newest first',
        () {
      final groups = groupStudyMaterialsByChapter([
        _material('c2', chapterId: 'ch2'),
        _material('old', chapterId: 'ch1', createdAt: DateTime(2030, 1, 1)),
        _material('new', chapterId: 'ch1', createdAt: DateTime(2030, 1, 2)),
        _material('book'),
      ], [
        'ch1',
        'ch2',
        'ch3'
      ]);
      expect([for (final g in groups) g.chapterId], [null, 'ch1', 'ch2']);
      expect([for (final m in groups[1].materials) m.id], ['new', 'old']);
    });

    test('a material of a chapter that is gone sits with the whole book', () {
      final groups = groupStudyMaterialsByChapter(
          [_material('lost', chapterId: 'removed')], ['ch1']);
      expect(groups.single.chapterId, isNull);
      expect(groups.single.materials.single.id, 'lost');
    });
  });
}
