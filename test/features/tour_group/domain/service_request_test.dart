import 'package:bhromon/features/tour_group/domain/models/service_request_models.dart';
import 'package:bhromon/features/tour_group/domain/services/service_request_rules.dart';
import 'package:flutter_test/flutter_test.dart';

ServiceRequest _req({
  String id = 'r1',
  String title = 'Lift stops at floor 4',
  ServiceRequestStatus status = ServiceRequestStatus.open,
  String by = 'a@x.com',
  DateTime? at,
}) =>
    ServiceRequest(
      id: id,
      title: title,
      status: status,
      createdByEmail: by,
      createdAt: at,
    );

void main() {
  group('service request model', () {
    test('a stored request reads its words, category, status and author', () {
      final r = ServiceRequest.fromMap('r1', {
        'title': '  Water pressure low  ',
        'details': 'Since Monday, floors 5 to 7',
        'category': 'water',
        'status': 'in_progress',
        'createdByEmail': 'a@x.com',
        'createdByName': 'Rahim',
        'adminNote': 'Plumber called',
        'createdAt': DateTime(2026, 3, 1),
      });

      expect(r?.title, 'Water pressure low');
      expect(r?.details, 'Since Monday, floors 5 to 7');
      expect(r?.category, ServiceRequestCategory.water);
      expect(r?.status, ServiceRequestStatus.inProgress);
      expect(r?.createdByName, 'Rahim');
      expect(r?.adminNote, 'Plumber called');
      expect(r?.createdAt, DateTime(2026, 3, 1));
      expect(r?.isOpen, isFalse);
    });

    test(
        'a request with no title is skipped, and unknown values read as defaults',
        () {
      expect(ServiceRequest.fromMap('r2', {'title': '   '}), isNull);

      final r = ServiceRequest.fromMap('r3', {
        'title': 'Garbage in',
        'category': 'parking',
        'status': 'done',
      });
      expect(r?.category, ServiceRequestCategory.other);
      expect(r?.status, ServiceRequestStatus.open);
      expect(r?.isOpen, isTrue);
    });

    test('the text an author writes, and the stored status names', () {
      expect(_req(title: 'Lift').toTextFields(), {
        'title': 'Lift',
        'details': '',
        'category': 'other',
      });
      expect(ServiceRequestStatus.inProgress.stored, 'in_progress');
      expect(ServiceRequestStatus.fromStored('resolved'),
          ServiceRequestStatus.resolved);
    });
  });

  group('service request rules', () {
    test(
        'only the author changes the words, and only while the request is open',
        () {
      expect(canEditServiceRequestText(_req(by: 'a@x.com'), 'a@x.com'), isTrue);
      expect(
          canEditServiceRequestText(_req(by: 'a@x.com'), 'b@x.com'), isFalse);
      expect(
        canEditServiceRequestText(
          _req(by: 'a@x.com', status: ServiceRequestStatus.inProgress),
          'a@x.com',
        ),
        isFalse,
      );
      expect(
        canEditServiceRequestText(
          _req(by: 'a@x.com', status: ServiceRequestStatus.resolved),
          'a@x.com',
        ),
        isFalse,
      );
    });

    test('the author or an admin removes a request', () {
      final r = _req(by: 'a@x.com');

      expect(canDeleteServiceRequest(r, 'a@x.com', isAdmin: false), isTrue);
      expect(canDeleteServiceRequest(r, 'b@x.com', isAdmin: false), isFalse);
      expect(canDeleteServiceRequest(r, 'b@x.com', isAdmin: true), isTrue);
    });

    test('a title needs three to 120 characters once trimmed', () {
      expect(isValidServiceRequestTitle('  ab  '), isFalse);
      expect(isValidServiceRequestTitle('abc'), isTrue);
      expect(isValidServiceRequestTitle('x' * kServiceRequestTitleMax), isTrue);
      expect(
        isValidServiceRequestTitle('x' * (kServiceRequestTitleMax + 1)),
        isFalse,
      );
    });

    test('requests are counted by status', () {
      final counts = countServiceRequests([
        _req(id: '1'),
        _req(id: '2', status: ServiceRequestStatus.inProgress),
        _req(id: '3', status: ServiceRequestStatus.resolved),
        _req(id: '4', status: ServiceRequestStatus.resolved),
      ]);

      expect(counts.open, 1);
      expect(counts.inProgress, 1);
      expect(counts.resolved, 2);
      expect(counts.total, 4);
    });

    test(
        'a filter keeps one status; the newest comes first and undated ones last',
        () {
      final list = [
        _req(id: 'old', at: DateTime(2026, 1, 1)),
        _req(id: 'none'),
        _req(id: 'new', at: DateTime(2026, 2, 1)),
        _req(
          id: 'done',
          status: ServiceRequestStatus.resolved,
          at: DateTime(2026, 1, 15),
        ),
      ];

      expect(filterServiceRequests(list).map((r) => r.id),
          ['new', 'done', 'old', 'none']);
      expect(
        filterServiceRequests(list, status: ServiceRequestStatus.resolved)
            .map((r) => r.id),
        ['done'],
      );
      expect(
        filterServiceRequests(list, status: ServiceRequestStatus.inProgress),
        isEmpty,
      );
    });
  });
}
