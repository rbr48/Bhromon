import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:bhromon/core/entities/cost_item.dart';
import 'package:bhromon/core/entities/explorer_profile.dart';
import 'package:bhromon/core/entities/trip_block.dart';
import 'package:bhromon/core/entities/trip_log.dart';
import 'package:bhromon/core/errors/failures.dart';
import 'package:bhromon/core/value_objects/explorer_score.dart';
import 'package:bhromon/core/value_objects/geo_coordinate.dart';
import 'package:bhromon/core/value_objects/trust_tier.dart';
import 'package:bhromon/core/value_objects/diary_visibility.dart';
import 'package:bhromon/features/explorer/domain/repositories/i_explorer_repository.dart';
import 'package:bhromon/features/trip_log/domain/repositories/i_trip_log_repository.dart';
import 'package:bhromon/features/trip_log/domain/usecases/publish_trip_log_usecase.dart';

import 'publish_trip_log_usecase_test.mocks.dart';

@GenerateMocks([ITripLogRepository, IExplorerRepository])
void main() {
  late MockITripLogRepository mockTripLogRepo;
  late MockIExplorerRepository mockExplorerRepo;
  late PublishTripLogUseCase useCase;

  // ────────────────────────────────────────────────────
  // Fixture builders
  // ────────────────────────────────────────────────────

  final tProfile = ExplorerProfile(
    uid: 'author-uid',
    displayName: 'Trip Author',
    explorerScore: const ExplorerScore(value: 80, tier: TrustTier.community),
    tier: TrustTier.community,
    badges: const [],
    division: 'Sylhet',
    createdAt: DateTime(2023, 6, 1),
  );

  /// A fully valid TripLog for public visibility (passes all validation gates).
  final validPublicTripLog = TripLog(
    tripId: 'trip-001',
    authorId: 'author-uid',
    title: 'Sundarban Adventure',
    blocks: [
      const TripBlock.text(id: 'blk-1', content: 'Day 1 journey'),
      const TripBlock.image(
          id: 'blk-2',
          storageUrl: 'https://storage/img.jpg',
          caption: 'River view'),
      const TripBlock.safetyNote(id: 'blk-3', text: 'Watch out for tigers', level: 'warning'),
      const TripBlock.costEntry(id: 'blk-4', items: [], currency: 'BDT'),
      const TripBlock.route(id: 'blk-5', points: []),
    ],
    routePoints: [
      const GeoCoordinate(latitude: 22.0, longitude: 89.5),
      const GeoCoordinate(latitude: 22.1, longitude: 89.6),
    ],
    costItems: [
      const CostItem(label: 'Boat', amountBDT: 500, category: 'transport'),
    ],
    locationPinId: 'pin-sundarban',
    trustScore: 0,
    helpfulVotes: 0,
    lastConfirmed: DateTime(2024, 5, 10),
    division: 'Khulna',
    district: 'Satkhira',
    visibility: DiaryVisibility.community,
  );

  /// A private TripLog (no requirements).
  final privateTripLog = TripLog(
    tripId: 'trip-001',
    authorId: 'author-uid',
    title: '',
    blocks: const [],
    routePoints: const [],
    costItems: const [],
    locationPinId: 'pin-sundarban',
    trustScore: 0,
    helpfulVotes: 0,
    lastConfirmed: DateTime(2024, 5, 10),
    division: 'Khulna',
    district: 'Satkhira',
    visibility: DiaryVisibility.private,
  );

  setUp(() {
    mockTripLogRepo = MockITripLogRepository();
    mockExplorerRepo = MockIExplorerRepository();
    useCase = PublishTripLogUseCase(mockTripLogRepo, mockExplorerRepo);
  });

  // ────────────────────────────────────────────────────
  // Validation gate: title for public posts
  // ────────────────────────────────────────────────────
  group('Validation — Public Visibility', () {
    test('returns ValidationFailure when title is empty', () async {
      final params = PublishTripLogParams(
        tripLog: validPublicTripLog.copyWith(title: ''),
        authorId: 'author-uid',
      );

      final result = await useCase(params);

      expect(result.isLeft(), true);
      result.fold(
        (f) {
          expect(f, isA<ValidationFailure>());
          expect(f.message, 'Title is required for public posts');
        },
        (_) => fail('Expected Left'),
      );
    });

    test('returns ValidationFailure when title is only whitespace', () async {
      final params = PublishTripLogParams(
        tripLog: validPublicTripLog.copyWith(title: '   '),
        authorId: 'author-uid',
      );

      final result = await useCase(params);

      expect(result.isLeft(), true);
      result.fold(
        (f) {
          expect(f, isA<ValidationFailure>());
          expect(f.message, 'Title is required for public posts');
        },
        (_) => fail('Expected Left'),
      );
    });

    test('returns ValidationFailure when blocks have no images/videos', () async {
      final params = PublishTripLogParams(
        tripLog: validPublicTripLog.copyWith(
          blocks: validPublicTripLog.blocks.where((b) => b is! ImageBlock && b is! VideoBlock).toList(),
        ),
        authorId: 'author-uid',
      );

      final result = await useCase(params);

      expect(result.isLeft(), true);
      result.fold(
        (f) {
          expect(f, isA<ValidationFailure>());
          expect(f.message, 'At least one image or video is required for public posts');
        },
        (_) => fail('Expected Left'),
      );
    });

    test('returns ValidationFailure when blocks have no safety note', () async {
      final params = PublishTripLogParams(
        tripLog: validPublicTripLog.copyWith(
          blocks: validPublicTripLog.blocks.where((b) => b is! SafetyNoteBlock).toList(),
        ),
        authorId: 'author-uid',
      );

      final result = await useCase(params);

      expect(result.isLeft(), true);
      result.fold(
        (f) {
          expect(f, isA<ValidationFailure>());
          expect(f.message, 'A safety note is required for public posts');
        },
        (_) => fail('Expected Left'),
      );
    });

    test('returns ValidationFailure when blocks have no cost entry', () async {
      final params = PublishTripLogParams(
        tripLog: validPublicTripLog.copyWith(
          blocks: validPublicTripLog.blocks.where((b) => b is! CostEntryBlock).toList(),
        ),
        authorId: 'author-uid',
      );

      final result = await useCase(params);

      expect(result.isLeft(), true);
      result.fold(
        (f) {
          expect(f, isA<ValidationFailure>());
          expect(f.message, 'An expense breakdown is required for public posts');
        },
        (_) => fail('Expected Left'),
      );
    });

    test('returns ValidationFailure when blocks have no route map', () async {
      final params = PublishTripLogParams(
        tripLog: validPublicTripLog.copyWith(
          blocks: validPublicTripLog.blocks.where((b) => b is! RouteBlock).toList(),
        ),
        authorId: 'author-uid',
      );

      final result = await useCase(params);

      expect(result.isLeft(), true);
      result.fold(
        (f) {
          expect(f, isA<ValidationFailure>());
          expect(f.message, 'A route map is required for public posts');
        },
        (_) => fail('Expected Left'),
      );
    });
  });

  group('Validation — Private Visibility (Self-Posting)', () {
    test('succeeds even with empty title and empty blocks', () async {
      final params = PublishTripLogParams(
        tripLog: privateTripLog,
        authorId: 'author-uid',
      );

      final expectedSavedLog = privateTripLog.copyWith(title: 'Untitled Log');

      when(mockExplorerRepo.getProfile('author-uid'))
          .thenAnswer((_) async => Right(tProfile));
      when(mockTripLogRepo.publishTripLog(any)).thenAnswer((_) async => Right(expectedSavedLog));

      final result = await useCase(params);

      expect(result.isRight(), true);
      result.fold(
        (_) => fail('Expected Right'),
        (r) {
          expect(r.title, 'Untitled Log');
        },
      );
    });
  });

  group('Happy path', () {
    test('returns Right(TripLog) when all validations pass and publish succeeds',
        () async {
      final tPublishedLog = validPublicTripLog.copyWith(
        publishedAt: DateTime(2024, 5, 10, 10, 30),
      );
      final tParams = PublishTripLogParams(
        tripLog: validPublicTripLog,
        authorId: 'author-uid',
      );

      when(mockExplorerRepo.getProfile('author-uid'))
          .thenAnswer((_) async => Right(tProfile));
      when(mockTripLogRepo.publishTripLog(validPublicTripLog))
          .thenAnswer((_) async => Right(tPublishedLog));

      final result = await useCase(tParams);

      expect(result, Right<Failure, TripLog>(tPublishedLog));
      verify(mockTripLogRepo.publishTripLog(validPublicTripLog)).called(1);
    });
  });
}
