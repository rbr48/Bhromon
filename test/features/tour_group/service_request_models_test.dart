import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/tour_group/domain/models/service_request_models.dart';

void main() {
  group('ServiceRequest Model & Timeline Attributes', () {
    test('creates ServiceRequest with photos and timeline timestamps', () {
      final now = DateTime(2026, 11, 4, 10, 0);
      final inProg = DateTime(2026, 11, 4, 14, 0);
      final resolved = DateTime(2026, 11, 4, 18, 0);

      final req = ServiceRequest(
        id: 'req_1',
        title: 'Elevator 2 stuck',
        details: 'Motor vibrating heavily',
        category: ServiceRequestCategory.lift,
        status: ServiceRequestStatus.resolved,
        createdByEmail: 'resident@example.com',
        createdByName: 'Karim',
        createdAt: now,
        inProgressAt: inProg,
        resolvedAt: resolved,
        resolvedByName: 'Admin Rafiq',
        photoUrls: ['https://media.bhromon.fun/lift_defect.jpg'],
      );

      expect(req.id, 'req_1');
      expect(req.title, 'Elevator 2 stuck');
      expect(req.isResolved, isTrue);
      expect(req.isOpen, isFalse);
      expect(req.photoUrls, ['https://media.bhromon.fun/lift_defect.jpg']);
      expect(req.resolvedByName, 'Admin Rafiq');
      expect(req.inProgressAt, inProg);
      expect(req.resolvedAt, resolved);
    });

    test('serializes toTextFields and deserializes fromMap accurately', () {
      final map = <String, dynamic>{
        'title': 'Water leakage on 4th floor',
        'details': 'Main valve leaking near flat 4B',
        'category': 'water',
        'status': 'in_progress',
        'createdByEmail': 'resident@example.com',
        'createdByName': 'Fatima',
        'createdAt': '2026-11-04T10:00:00.000Z',
        'updatedAt': '2026-11-04T12:00:00.000Z',
        'inProgressAt': '2026-11-04T11:00:00.000Z',
        'adminNote': 'Plumber assigned',
        'photoUrl': 'https://media.bhromon.fun/leak.jpg',
      };

      final req = ServiceRequest.fromMap('req_water', map);
      expect(req, isNotNull);
      expect(req!.id, 'req_water');
      expect(req.category, ServiceRequestCategory.water);
      expect(req.status, ServiceRequestStatus.inProgress);
      expect(req.isInProgress, isTrue);
      expect(req.photoUrls, ['https://media.bhromon.fun/leak.jpg']);
      expect(req.inProgressAt, isNotNull);

      final fields = req.toTextFields();
      expect(fields['title'], 'Water leakage on 4th floor');
      expect(fields['category'], 'water');
      expect(fields['photoUrls'], ['https://media.bhromon.fun/leak.jpg']);
    });

    test('copyWith updates status and timestamps immutably', () {
      const original = ServiceRequest(
        id: 'req_2',
        title: 'Broken Lobby Light',
        status: ServiceRequestStatus.open,
      );
      expect(original.isOpen, isTrue);

      final inProgress = original.copyWith(
        status: ServiceRequestStatus.inProgress,
        inProgressAt: DateTime(2026, 11, 4, 11, 30),
      );
      expect(inProgress.isOpen, isFalse);
      expect(inProgress.isInProgress, isTrue);
      expect(inProgress.inProgressAt, isNotNull);

      final resolved = inProgress.copyWith(
        status: ServiceRequestStatus.resolved,
        resolvedAt: DateTime(2026, 11, 4, 14, 0),
        resolvedByName: 'Caretaker',
      );
      expect(resolved.isResolved, isTrue);
      expect(resolved.resolvedByName, 'Caretaker');
    });

    test(
        'reads photos in order, drops blanks and repeats, and keeps at most three',
        () {
      final req = ServiceRequest.fromMap('req_photos', {
        'title': 'Lobby light flickering',
        'photoUrls': [
          'https://media.bhromon.fun/a.jpg',
          '   ',
          'https://media.bhromon.fun/b.jpg',
          'https://media.bhromon.fun/a.jpg',
          'https://media.bhromon.fun/c.jpg',
          'https://media.bhromon.fun/d.jpg',
        ],
      });
      expect(req, isNotNull);
      expect(req!.photoUrls, [
        'https://media.bhromon.fun/a.jpg',
        'https://media.bhromon.fun/b.jpg',
        'https://media.bhromon.fun/c.jpg',
      ]);
    });

    test('a request without photos has none and writes no photo field', () {
      final req =
          ServiceRequest.fromMap('req_none', {'title': 'Water pressure low'});
      expect(req, isNotNull);
      expect(req!.photoUrls, isEmpty);
      expect(req.toTextFields().containsKey('photoUrls'), isFalse);
    });

    test(
        'a request saved with the single photo field reads that photo as its list',
        () {
      final req = ServiceRequest.fromMap('req_legacy', {
        'title': 'Water pressure low',
        'photoUrl': 'https://media.bhromon.fun/old.jpg',
      });
      expect(req, isNotNull);
      expect(req!.photoUrls, ['https://media.bhromon.fun/old.jpg']);
    });

    test('copyWith replaces the photos and keeps the rest', () {
      const original = ServiceRequest(
        id: 'req_3',
        title: 'Gate lock broken',
        photoUrls: ['https://media.bhromon.fun/a.jpg'],
      );
      final more = original.copyWith(photoUrls: [
        'https://media.bhromon.fun/a.jpg',
        'https://media.bhromon.fun/b.jpg',
      ]);
      expect(more.photoUrls, hasLength(2));
      expect(more.title, 'Gate lock broken');
      expect(more.id, 'req_3');
      expect(original.photoUrls, hasLength(1));
    });
  });
}
