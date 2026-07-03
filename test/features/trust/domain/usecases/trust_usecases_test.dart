import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:bhromon/core/errors/failures.dart';
import 'package:bhromon/features/trust/domain/repositories/i_trust_repository.dart';
import 'package:bhromon/features/trust/domain/usecases/flag_content_usecase.dart';
import 'package:bhromon/features/trust/domain/usecases/appeal_flag_usecase.dart';
import 'package:bhromon/features/trust/domain/usecases/get_explorer_score_usecase.dart';

import 'trust_usecases_test.mocks.dart';

@GenerateMocks([ITrustRepository])
void main() {
  late MockITrustRepository mockRepo;

  const tServerFailure = ServerFailure('Trust service unavailable');

  setUp(() {
    mockRepo = MockITrustRepository();
  });

  // ────────────────────────────────────────────────────
  // FlagContentUseCase
  // ────────────────────────────────────────────────────
  group('FlagContentUseCase', () {
    late FlagContentUseCase useCase;

    setUp(() => useCase = FlagContentUseCase(mockRepo));

    test(
        'delegates all params to ITrustRepository.submitFlag '
        'and returns Right(unit) on success', () async {
      when(mockRepo.submitFlag(
        targetId: 'content-123',
        targetType: 'trip_log',
        flagType: 'spam_flag',
        reason: 'Misleading content',
      )).thenAnswer((_) async => const Right(unit));

      final result = await useCase(FlagContentParams(
        targetId: 'content-123',
        targetType: 'trip_log',
        flagType: 'spam_flag',
        reason: 'Misleading content',
      ));

      expect(result, const Right<Failure, Unit>(unit));
      verify(mockRepo.submitFlag(
        targetId: 'content-123',
        targetType: 'trip_log',
        flagType: 'spam_flag',
        reason: 'Misleading content',
      )).called(1);
      verifyNoMoreInteractions(mockRepo);
    });

    test('passes safety_flag type correctly', () async {
      when(mockRepo.submitFlag(
        targetId: 'pro-tip-456',
        targetType: 'pro_tip',
        flagType: 'safety_flag',
        reason: 'Dangerous advice',
      )).thenAnswer((_) async => const Right(unit));

      final result = await useCase(FlagContentParams(
        targetId: 'pro-tip-456',
        targetType: 'pro_tip',
        flagType: 'safety_flag',
        reason: 'Dangerous advice',
      ));

      expect(result, const Right<Failure, Unit>(unit));
    });

    test('returns Left(ServerFailure) when repository fails', () async {
      when(mockRepo.submitFlag(
        targetId: anyNamed('targetId'),
        targetType: anyNamed('targetType'),
        flagType: anyNamed('flagType'),
        reason: anyNamed('reason'),
      )).thenAnswer((_) async => const Left(tServerFailure));

      final result = await useCase(FlagContentParams(
        targetId: 'content-999',
        targetType: 'trip_log',
        flagType: 'spam_flag',
        reason: 'Reason',
      ));

      expect(result, const Left<Failure, Unit>(tServerFailure));
    });
  });

  // ────────────────────────────────────────────────────
  // AppealFlagUseCase
  // ────────────────────────────────────────────────────
  group('AppealFlagUseCase', () {
    late AppealFlagUseCase useCase;

    setUp(() => useCase = AppealFlagUseCase(mockRepo));

    test(
        'delegates all params to ITrustRepository.submitAppeal '
        'and returns Right(unit) on success', () async {
      when(mockRepo.submitAppeal(
        targetId: 'content-123',
        justification: 'This was incorrectly flagged',
      )).thenAnswer((_) async => const Right(unit));

      final result = await useCase(AppealFlagParams(
        targetId: 'content-123',
        justification: 'This was incorrectly flagged',
      ));

      expect(result, const Right<Failure, Unit>(unit));
      verify(mockRepo.submitAppeal(
        targetId: 'content-123',
        justification: 'This was incorrectly flagged',
      )).called(1);
      verifyNoMoreInteractions(mockRepo);
    });

    test('returns Left(ServerFailure) when repository fails', () async {
      when(mockRepo.submitAppeal(
        targetId: anyNamed('targetId'),
        justification: anyNamed('justification'),
      )).thenAnswer((_) async => const Left(tServerFailure));

      final result = await useCase(AppealFlagParams(
        targetId: 'content-xyz',
        justification: 'My justification',
      ));

      expect(result, const Left<Failure, Unit>(tServerFailure));
    });
  });

  // ────────────────────────────────────────────────────
  // GetExplorerScoreUseCase
  // ────────────────────────────────────────────────────
  group('GetExplorerScoreUseCase', () {
    late GetExplorerScoreUseCase useCase;

    setUp(() => useCase = GetExplorerScoreUseCase(mockRepo));

    test('streams Right(score) from the repository', () async {
      const tUid = 'uid-stream-test';
      final scoreStream = Stream.fromIterable([
        const Right<Failure, int>(100),
        const Right<Failure, int>(150),
        const Right<Failure, int>(200),
      ]);

      when(mockRepo.getScoreStream(tUid)).thenAnswer((_) => scoreStream);

      final stream = useCase.watch(tUid);

      await expectLater(
        stream,
        emitsInOrder([
          const Right<Failure, int>(100),
          const Right<Failure, int>(150),
          const Right<Failure, int>(200),
          emitsDone,
        ]),
      );
      verify(mockRepo.getScoreStream(tUid)).called(1);
    });

    test('streams Left(ServerFailure) when repository emits an error',
        () async {
      const tUid = 'uid-stream-error';
      final errorStream = Stream.fromIterable([
        const Left<Failure, int>(tServerFailure),
      ]);

      when(mockRepo.getScoreStream(tUid)).thenAnswer((_) => errorStream);

      final stream = useCase.watch(tUid);

      await expectLater(
        stream,
        emitsInOrder([
          const Left<Failure, int>(tServerFailure),
          emitsDone,
        ]),
      );
    });

    test('uses the uid argument to look up the correct stream', () {
      const tUid = 'uid-lookup-check';
      when(mockRepo.getScoreStream(tUid))
          .thenAnswer((_) => const Stream<Either<Failure, int>>.empty());

      useCase.watch(tUid);

      verify(mockRepo.getScoreStream(tUid)).called(1);
      verifyNoMoreInteractions(mockRepo);
    });
  });
}
