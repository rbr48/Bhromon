import 'package:bhromon/features/tour_group/domain/models/expense_models.dart';
import 'package:bhromon/features/tour_group/domain/models/family_task_models.dart';
import 'package:bhromon/features/tour_group/domain/models/safety_alert_models.dart';
import 'package:bhromon/features/tour_group/domain/models/samity_models.dart';
import 'package:bhromon/features/tour_group/domain/models/service_request_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';
import 'package:bhromon/features/tour_group/domain/services/fund_analytics.dart';
import 'package:bhromon/features/tour_group/domain/services/tour_record_plan.dart';
import 'package:flutter_test/flutter_test.dart';

TourGroup _group({
  GroupKind kind = GroupKind.tour,
  String? preset,
  bool momentsEnabled = true,
  TourModules modules = const TourModules(),
  SamityConfig samity = const SamityConfig(),
}) {
  return TourGroup(
    id: 'g1',
    name: 'Test group',
    ownerEmail: 'owner@example.com',
    inviteCode: 'CODE1234',
    startDate: DateTime(2026, 11, 1),
    endDate: DateTime(2026, 11, 3),
    createdAt: DateTime(2026, 10, 1),
    kind: kind,
    preset: preset,
    momentsEnabled: momentsEnabled,
    modules: modules,
    samity: samity,
  );
}

TourPostItem _post(String id, {bool archived = false}) {
  return TourPostItem(
    id: id,
    tourId: 'g1',
    authorEmail: 'a@example.com',
    authorName: 'A',
    caption: 'caption',
    images: const [],
    createdAt: DateTime(2026, 10, 25),
    isArchived: archived,
  );
}

TourStoryItem _story(String id, DateTime createdAt) {
  return TourStoryItem(
    id: id,
    authorEmail: 'a@example.com',
    authorName: 'A',
    mediaUrl: 'https://bhromon.fun/media/$id.jpg',
    createdAt: createdAt,
  );
}

SafetyAlert _alert(String id, {required bool resolved}) {
  return SafetyAlert(
    id: id,
    senderEmail: 'a@example.com',
    senderName: 'A',
    resolved: resolved,
  );
}

SettlementRecord _settlement(
  String id, {
  required MfsProvider provider,
  required MfsVerificationStatus status,
  int amountPaisa = 10000,
}) {
  return SettlementRecord(
    id: id,
    tourId: 'g1',
    fromMemberId: 'a@example.com',
    fromMemberName: 'A',
    toMemberId: 'b@example.com',
    toMemberName: 'B',
    amountPaisa: amountPaisa,
    date: DateTime(2026, 11, 2),
    mfsInfo:
        MfsPaymentInfo(provider: provider, trxId: 'TRX$id', status: status),
    addedByEmail: 'a@example.com',
  );
}

void main() {
  group('recordSectionsFor', () {
    test('a trip keeps the trip parts, the SOS and the Moments parts', () {
      final sections = recordSectionsFor(_group());

      expect(
        sections,
        containsAll(<TourRecordSection>[
          TourRecordSection.overview,
          TourRecordSection.members,
          TourRecordSection.journey,
          TourRecordSection.notices,
          TourRecordSection.money,
          TourRecordSection.checklist,
          TourRecordSection.transport,
          TourRecordSection.rooms,
          TourRecordSection.safety,
          TourRecordSection.feed,
          TourRecordSection.stories,
          TourRecordSection.highlights,
        ]),
      );
      expect(sections, isNot(contains(TourRecordSection.familyDates)));
      expect(sections, isNot(contains(TourRecordSection.requests)));
    });

    test('a trip with its seats tool off has no transport or rooms', () {
      final sections = recordSectionsFor(
        _group(modules: const TourModules(seatsRooms: false)),
      );

      expect(sections, isNot(contains(TourRecordSection.transport)));
      expect(sections, isNot(contains(TourRecordSection.rooms)));
    });

    test('a household keeps its family parts and not the trip parts', () {
      final sections = recordSectionsFor(
        _group(kind: GroupKind.family),
      );

      expect(
        sections,
        containsAll(<TourRecordSection>[
          TourRecordSection.familyDates,
          TourRecordSection.dependents,
          TourRecordSection.sharedList,
          TourRecordSection.safety,
        ]),
      );
      for (final tripOnly in [
        TourRecordSection.journey,
        TourRecordSection.checklist,
        TourRecordSection.transport,
        TourRecordSection.rooms,
        TourRecordSection.requests,
      ]) {
        expect(sections, isNot(contains(tripOnly)), reason: tripOnly.name);
      }
    });

    test('an office has no money, shared list, SOS or household parts', () {
      final sections = recordSectionsFor(
        _group(kind: GroupKind.family, preset: TourGroup.officePreset),
      );

      expect(sections, contains(TourRecordSection.notices));
      expect(sections, isNot(contains(TourRecordSection.money)));
      expect(sections, isNot(contains(TourRecordSection.sharedList)));
      expect(sections, isNot(contains(TourRecordSection.safety)));
      expect(sections, isNot(contains(TourRecordSection.familyDates)));
      expect(sections, isNot(contains(TourRecordSection.dependents)));
    });

    test('a campus keeps the shared fund, and a samity keeps none', () {
      expect(
        recordSectionsFor(
          _group(kind: GroupKind.family, preset: TourGroup.campusPreset),
        ),
        contains(TourRecordSection.money),
      );
      expect(
        recordSectionsFor(
          _group(kind: GroupKind.family, preset: TourGroup.samityPreset),
        ),
        isNot(contains(TourRecordSection.money)),
      );
    });

    test('a society keeps its requests, its shared list and its SOS', () {
      final sections = recordSectionsFor(
        _group(kind: GroupKind.family, preset: TourGroup.societyPreset),
      );

      expect(
        sections,
        containsAll(<TourRecordSection>[
          TourRecordSection.requests,
          TourRecordSection.sharedList,
          TourRecordSection.safety,
        ]),
      );
    });

    test('a mess keeps its shared list and SOS, and no requests', () {
      final sections = recordSectionsFor(
        _group(kind: GroupKind.family, preset: TourGroup.messPreset),
      );

      expect(sections, contains(TourRecordSection.sharedList));
      expect(sections, contains(TourRecordSection.safety));
      expect(sections, isNot(contains(TourRecordSection.requests)));
    });

    test('a samity keeps its shared list and no SOS', () {
      final sections = recordSectionsFor(
        _group(kind: GroupKind.family, preset: TourGroup.samityPreset),
      );

      expect(sections, contains(TourRecordSection.sharedList));
      expect(sections, isNot(contains(TourRecordSection.safety)));
    });

    test('a study circle has no shared list', () {
      final sections = recordSectionsFor(
        _group(kind: GroupKind.family, preset: TourGroup.studyPreset),
      );

      expect(sections, isNot(contains(TourRecordSection.sharedList)));
      expect(sections, contains(TourRecordSection.feed));
    });

    test('Moments off drops the feed, stories and highlights', () {
      final sections = recordSectionsFor(
        _group(
          kind: GroupKind.family,
          preset: TourGroup.officePreset,
          momentsEnabled: false,
        ),
      );

      expect(sections, isNot(contains(TourRecordSection.feed)));
      expect(sections, isNot(contains(TourRecordSection.stories)));
      expect(sections, isNot(contains(TourRecordSection.highlights)));
    });
  });

  group('content the record keeps', () {
    test('archived posts are left out', () {
      final kept = recordPosts([_post('a'), _post('b', archived: true)]);

      expect(kept.map((p) => p.id), ['a']);
    });

    test('only stories from the last 24 hours are kept', () {
      final now = DateTime(2026, 11, 5, 12);
      final kept = recordStories(
        [
          _story('fresh', now.subtract(const Duration(hours: 23))),
          _story('old', now.subtract(const Duration(hours: 25))),
        ],
        now,
      );

      expect(kept.map((s) => s.id), ['fresh']);
    });

    test('SOS alerts are counted, raised and resolved, with no names', () {
      final counts = recordSafetyCounts([
        _alert('1', resolved: false),
        _alert('2', resolved: true),
        _alert('3', resolved: true),
      ]);

      expect(counts.raised, 3);
      expect(counts.resolved, 2);
    });
  });

  group('file name', () {
    test('a name with letters in any script keeps them', () {
      expect(
        recordFileName('TWA সমিতি'),
        'bhromon_TWA_সমিতি_record.pdf',
      );
    });

    test('punctuation becomes an underscore', () {
      expect(
        recordFileName("Cox's Bazar 2026"),
        'bhromon_Cox_s_Bazar_2026_record.pdf',
      );
    });

    test('a name with no letters falls back to group', () {
      expect(recordFileName('  !!  '), 'bhromon_group_record.pdf');
      expect(recordFileName(''), 'bhromon_group_record.pdf');
    });

    test('a long name is shortened to sixty characters', () {
      final name = 'a' * 80;

      expect(recordSafeName(name), 'a' * 60);
    });
  });

  group('menu options', () {
    test('a member sees no group record on a trip', () {
      expect(recordExportOptions(_group(), isAdmin: false), isEmpty);
    });

    test('an admin sees the group record on a trip', () {
      expect(
        recordExportOptions(_group(), isAdmin: true),
        [RecordExportOption.groupRecord],
      );
    });

    test('a samity that is set up offers its statement first', () {
      final group = _group(
        kind: GroupKind.family,
        preset: TourGroup.samityPreset,
        samity: const SamityConfig(
          contributionTaka: 500,
          startMonth: '2026-11',
          payoutOrder: ['a@example.com'],
        ),
      );

      expect(
        recordExportOptions(group, isAdmin: false),
        [RecordExportOption.samityStatement],
      );
      expect(
        recordExportOptions(group, isAdmin: true),
        [
          RecordExportOption.samityStatement,
          RecordExportOption.groupRecord,
        ],
      );
    });

    test('a samity that is not set up offers no statement', () {
      final group =
          _group(kind: GroupKind.family, preset: TourGroup.samityPreset);

      expect(recordExportOptions(group, isAdmin: false), isEmpty);
    });

    test('a mess offers its meal sheet to every member', () {
      final group =
          _group(kind: GroupKind.family, preset: TourGroup.messPreset);

      expect(
        recordExportOptions(group, isAdmin: false),
        [RecordExportOption.mealSheet],
      );
    });

    test('a study circle offers its study pack to every member', () {
      final group =
          _group(kind: GroupKind.family, preset: TourGroup.studyPreset);

      expect(
        recordExportOptions(group, isAdmin: false),
        [RecordExportOption.studyPack],
      );
    });
  });

  group('labels', () {
    test('every preset expense category has a translation key', () {
      final lists = [
        kFamilyExpenseCategories,
        kExpenseCategories,
        kOfficeExpenseCategories,
        kCampusExpenseCategories,
        kMessExpenseCategories,
        kSocietyExpenseCategories,
        kSamityExpenseCategories,
        kSchoolExpenseCategories,
        kSportsExpenseCategories,
        kStudyExpenseCategories,
        kCommitteeExpenseCategories,
        kFriendsExpenseCategories,
      ];
      for (final category in lists.expand((list) => list)) {
        expect(recordCategoryKey(category), isNotNull, reason: category);
      }
    });

    test('a custom category has no key and prints as typed', () {
      expect(recordCategoryKey('Pocket money'), isNull);
    });

    test('a trip has no kind label, and each other kind has one', () {
      expect(recordKindKey(_group()), isNull);
      expect(
        recordKindKey(
            _group(kind: GroupKind.family, preset: TourGroup.officePreset)),
        'hub_office_badge',
      );
      expect(
        recordKindKey(_group(kind: GroupKind.family)),
        'hub_family_badge',
      );
    });

    test('request and task kinds have keys', () {
      expect(
        recordRequestCategoryKey(ServiceRequestCategory.lift),
        'society_cat_lift',
      );
      expect(
        recordRequestStatusKey(ServiceRequestStatus.inProgress),
        'society_request_status_in_progress',
      );
      expect(
        recordFamilyTaskKindKey(FamilyTaskKind.todo),
        'ft_kind_todo',
      );
    });
  });

  group('ledger transfers', () {
    test('a verified settlement counts at the credited amount', () {
      final transfers = ledgerTransfers(
        const [],
        [
          _settlement(
            'v',
            provider: MfsProvider.bkash,
            status: MfsVerificationStatus.verified,
          ),
        ],
      );

      expect(transfers, hasLength(1));
      expect(transfers.single.amountPaisa, 10000);
      expect(transfers.single.fromId, 'a@example.com');
    });

    test('an unverified or disputed settlement does not move the books', () {
      final transfers = ledgerTransfers(
        const [],
        [
          _settlement(
            'u',
            provider: MfsProvider.nagad,
            status: MfsVerificationStatus.unverified,
          ),
          _settlement(
            'd',
            provider: MfsProvider.nagad,
            status: MfsVerificationStatus.disputed,
          ),
        ],
      );

      expect(transfers, isEmpty);
    });

    test('cash counts as verified and keeps the recorded transfers', () {
      final recorded = [
        TransferItem(
          id: 't1',
          tourId: 'g1',
          fromName: 'A',
          toName: 'B',
          amountPaisa: 500,
          date: DateTime(2026, 11, 2),
        ),
      ];
      final transfers = ledgerTransfers(
        recorded,
        [
          _settlement(
            'c',
            provider: MfsProvider.cash,
            status: MfsVerificationStatus.unverified,
          ),
        ],
      );

      expect(transfers.map((t) => t.id), ['t1', 'c']);
    });
  });
}
