import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

import 'package:bhromon/core/entities/trip_block.dart';
import 'package:bhromon/core/entities/trip_log.dart';
import 'package:bhromon/core/errors/failures.dart';
import 'package:bhromon/core/value_objects/diary_visibility.dart';
import 'package:bhromon/core/value_objects/trip_mood.dart';
import 'package:bhromon/core/value_objects/weather_snapshot.dart';
import 'package:bhromon/features/trip_log/domain/usecases/publish_trip_log_usecase.dart';
import 'package:bhromon/features/trip_log/domain/usecases/get_trip_logs_for_pin_usecase.dart';
import 'package:bhromon/features/trip_log/domain/usecases/save_draft_usecase.dart';
import 'package:bhromon/features/trip_log/domain/usecases/load_draft_usecase.dart';
import 'package:bhromon/features/trip_log/presentation/bloc/trip_log_bloc.dart';
import 'package:bhromon/features/trip_log/presentation/bloc/trip_log_event.dart';
import 'package:bhromon/features/trip_log/presentation/bloc/trip_log_state.dart';

import 'trip_log_bloc_test.mocks.dart';

@GenerateMocks([
  PublishTripLogUseCase,
  GetTripLogsForPinUseCase,
  SaveDraftUseCase,
  LoadDraftUseCase,
  FirebaseAuth,
  User,
])
void main() {
  late MockPublishTripLogUseCase mockPublishTripLog;
  late MockGetTripLogsForPinUseCase mockGetTripLogsForPin;
  late MockSaveDraftUseCase mockSaveDraft;
  late MockLoadDraftUseCase mockLoadDraft;
  late MockFirebaseAuth mockFirebaseAuth;
  late MockUser mockUser;
  late TripLogBloc bloc;

  final tTripLog = TripLog(
    tripId: 'trip-123',
    authorId: 'user-123',
    title: 'Test Journey',
    locationPinId: 'pin-123',
    division: 'Dhaka',
    district: 'Dhaka',
    lastConfirmed: DateTime.now(),
    blocks: const [
      TripBlock.text(id: 'txt-1', content: 'Beautiful Dhaka heritage visit'),
      TripBlock.image(id: 'img-1', storageUrl: 'http://img.jpg', caption: 'Lalbagh'),
      TripBlock.safetyNote(id: 'safe-1', text: 'Safe for night walks', level: 'info'),
      TripBlock.costEntry(id: 'cost-1', items: [], currency: 'BDT'),
      TripBlock.route(id: 'route-1', points: [], description: 'Main highway'),
    ],
    costItems: const [],
    routePoints: const [],
    trustScore: 50,
    helpfulVotes: 0,
  );

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    HydratedBloc.storage = MockStorage();

    mockPublishTripLog = MockPublishTripLogUseCase();
    mockGetTripLogsForPin = MockGetTripLogsForPinUseCase();
    mockSaveDraft = MockSaveDraftUseCase();
    mockLoadDraft = MockLoadDraftUseCase();
    mockFirebaseAuth = MockFirebaseAuth();
    mockUser = MockUser();

    when(mockFirebaseAuth.currentUser).thenReturn(mockUser);
    when(mockUser.uid).thenReturn('user-123');
    
    bloc = TripLogBloc(
      mockPublishTripLog,
      mockGetTripLogsForPin,
      mockSaveDraft,
      mockLoadDraft,
      mockFirebaseAuth,
    );
  });

  tearDown(() {
    bloc.close();
  });

  test('initial state has correct defaults', () {
    expect(bloc.state, const TripLogState(pinId: ''));
  });

  group('LoadDraftEvent', () {
    blocTest<TripLogBloc, TripLogState>(
      'emits [loading, idle] with loaded draft data when draft is found',
      build: () {
        when(mockLoadDraft(any)).thenAnswer((_) async => Right(tTripLog));
        return bloc;
      },
      act: (b) => b.add(const LoadDraftEvent('pin-123')),
      expect: () => [
        const TripLogState(pinId: 'pin-123', status: EditorStatus.loading),
        TripLogState(
          pinId: 'pin-123',
          title: 'Test Journey',
          blocks: tTripLog.blocks,
          visibility: DiaryVisibility.community,
          mood: null,
          tags: const [],
          status: EditorStatus.idle,
        ),
      ],
    );

    blocTest<TripLogBloc, TripLogState>(
      'emits [loading, error] when draft loading fails',
      build: () {
        when(mockLoadDraft(any)).thenAnswer((_) async => const Left(CacheFailure('Failed to load')));
        return bloc;
      },
      act: (b) => b.add(const LoadDraftEvent('pin-123')),
      expect: () => [
        const TripLogState(pinId: 'pin-123', status: EditorStatus.loading),
        const TripLogState(
          pinId: 'pin-123',
          status: EditorStatus.error,
          errorMessage: 'Failed to load',
        ),
      ],
    );
  });

  group('LoadExistingTripLogEvent', () {
    blocTest<TripLogBloc, TripLogState>(
      'emits state with trip details from existing log',
      build: () => bloc,
      act: (b) => b.add(LoadExistingTripLogEvent(tTripLog)),
      expect: () => [
        TripLogState(
          tripId: 'trip-123',
          pinId: 'pin-123',
          title: 'Test Journey',
          blocks: tTripLog.blocks,
          visibility: DiaryVisibility.community,
          mood: null,
          tags: const [],
          status: EditorStatus.idle,
        ),
      ],
    );
  });

  group('Visibility, Mood, Tags, Dates, Weather Events', () {
    blocTest<TripLogBloc, TripLogState>(
      'emits state with updated visibility when UpdateVisibilityEvent is added',
      build: () => bloc,
      act: (b) => b.add(const UpdateVisibilityEvent(DiaryVisibility.friends)),
      expect: () => [
        const TripLogState(pinId: '', visibility: DiaryVisibility.friends),
      ],
    );

    blocTest<TripLogBloc, TripLogState>(
      'emits state with updated mood when UpdateMoodEvent is added',
      build: () => bloc,
      act: (b) => b.add(const UpdateMoodEvent(TripMood.adventure)),
      expect: () => [
        const TripLogState(pinId: '', mood: TripMood.adventure),
      ],
    );

    blocTest<TripLogBloc, TripLogState>(
      'emits state with updated tags when UpdateTagsEvent is added',
      build: () => bloc,
      act: (b) => b.add(const UpdateTagsEvent(['solo', 'budget'])),
      expect: () => [
        const TripLogState(pinId: '', tags: ['solo', 'budget']),
      ],
    );

    final tStartDate = DateTime(2026, 6, 20);
    final tEndDate = DateTime(2026, 6, 25);

    blocTest<TripLogBloc, TripLogState>(
      'emits state with updated dates when UpdateTripDatesEvent is added',
      build: () => bloc,
      act: (b) => b.add(UpdateTripDatesEvent(startDate: tStartDate, endDate: tEndDate)),
      expect: () => [
        TripLogState(pinId: '', tripStartDate: tStartDate, tripEndDate: tEndDate),
      ],
    );

    const tWeather = WeatherSnapshot(
      tempC: 27.5,
      emoji: '☀️',
      description: 'Sunny day',
      precipMm: 0.0,
      windKph: 12.0,
      weatherCode: 1000,
      isSafeToVisit: true,
    );

    blocTest<TripLogBloc, TripLogState>(
      'emits state with updated weather when StampWeatherEvent is added',
      build: () => bloc,
      act: (b) => b.add(const StampWeatherEvent(tWeather)),
      expect: () => [
        const TripLogState(pinId: '', weatherSnapshot: tWeather),
      ],
    );
  });

  group('PublishTripLogEvent', () {
    blocTest<TripLogBloc, TripLogState>(
      'emits [publishing, error] with validation errors when state is incomplete',
      build: () => bloc,
      act: (b) => b.add(const PublishTripLogEvent('Incomplete Trip')),
      expect: () => [
        const TripLogState(
          pinId: '',
          title: 'Incomplete Trip',
          status: EditorStatus.publishing,
        ),
        const TripLogState(
          pinId: '',
          title: 'Incomplete Trip',
          status: EditorStatus.error,
          errorMessage: 'ডায়েরি অসম্পূর্ণ। সব তথ্য পূরণ করুন।',
          validationErrors: [
            'কমপক্ষে একটি ছবি বা ভিডিও যোগ করুন',
            'একটি সেফটি নোট যোগ করুন',
            'খরচের বিবরণ যোগ করুন',
            'রুট ম্যাপ আঁকুন',
          ],
        ),
      ],
    );

    blocTest<TripLogBloc, TripLogState>(
      'emits [publishing, success] when publishing passes validation and succeeds',
      build: () {
        when(mockPublishTripLog(any)).thenAnswer((_) async => Right(tTripLog));
        // Prepare bloc state with complete blocks so validation passes
        return bloc;
      },
      seed: () => TripLogState(
        pinId: 'pin-123',
        title: 'Test Journey',
        blocks: tTripLog.blocks,
      ),
      act: (b) => b.add(const PublishTripLogEvent('Test Journey')),
      expect: () => [
        TripLogState(
          pinId: 'pin-123',
          title: 'Test Journey',
          blocks: tTripLog.blocks,
          status: EditorStatus.publishing,
        ),
        const TripLogState(
          pinId: 'pin-123',
          title: '',
          blocks: [],
          status: EditorStatus.success,
          tags: [],
          visibility: DiaryVisibility.community,
        ),
      ],
    );

    blocTest<TripLogBloc, TripLogState>(
      'emits [publishing, error] when publishing fails on repository layer',
      build: () {
        when(mockPublishTripLog(any)).thenAnswer((_) async => const Left(ServerFailure('Publish error')));
        return bloc;
      },
      seed: () => TripLogState(
        pinId: 'pin-123',
        title: 'Test Journey',
        blocks: tTripLog.blocks,
      ),
      act: (b) => b.add(const PublishTripLogEvent('Test Journey')),
      expect: () => [
        TripLogState(
          pinId: 'pin-123',
          title: 'Test Journey',
          blocks: tTripLog.blocks,
          status: EditorStatus.publishing,
        ),
        TripLogState(
          pinId: 'pin-123',
          title: 'Test Journey',
          blocks: tTripLog.blocks,
          status: EditorStatus.error,
          errorMessage: 'Publish error',
        ),
      ],
    );
  });
}

class MockStorage implements Storage {
  @override
  dynamic read(String key) => null;

  @override
  Future<void> write(String key, dynamic value) async {}

  @override
  Future<void> delete(String key) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<void> close() async {}
}
