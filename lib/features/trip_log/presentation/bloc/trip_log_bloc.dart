import 'dart:async';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/entities/trip_log.dart';
import '../../../../core/entities/trip_block.dart';
import '../../../../core/entities/cost_item.dart';
import '../../../../core/value_objects/trust_tier.dart';
import '../../../../core/value_objects/sync_status.dart';
import '../../../../core/value_objects/geo_coordinate.dart';
import '../../../../core/value_objects/diary_visibility.dart';
import '../../../../core/value_objects/weather_snapshot.dart';
import '../../../../core/services/trip_log_quality_scorer.dart';
import '../../../../core/services/weather_service.dart';
import '../../domain/usecases/publish_trip_log_usecase.dart';
import '../../domain/usecases/get_trip_logs_for_pin_usecase.dart';
import '../../domain/usecases/save_draft_usecase.dart';
import '../../domain/usecases/load_draft_usecase.dart';
import 'trip_log_event.dart';
import 'trip_log_state.dart';

@injectable
class TripLogBloc extends HydratedBloc<TripLogEvent, TripLogState> {
  final PublishTripLogUseCase _publishTripLog;
  // ignore: unused_field
  final GetTripLogsForPinUseCase _getTripLogsForPin;
  final SaveDraftUseCase _saveDraft;
  final LoadDraftUseCase _loadDraft;
  final FirebaseAuth _firebaseAuth;
  Timer? _autoSaveTimer;

  // Track whether weather has been auto-stamped for this session
  bool _weatherStamped = false;

  TripLogBloc(
    this._publishTripLog,
    this._getTripLogsForPin,
    this._saveDraft,
    this._loadDraft,
    this._firebaseAuth,
  ) : super(const TripLogState(pinId: '')) {
    // ── Core events ───────────────────────────────────────────────────────────
    on<LoadDraftEvent>((event, emit) async {
      emit(state.copyWith(pinId: event.pinId, status: EditorStatus.loading));
      final result = await _loadDraft(event.pinId);
      result.fold(
        (failure) => emit(state.copyWith(
            status: EditorStatus.error, errorMessage: failure.message)),
        (draft) {
          if (draft != null) {
            emit(state.copyWith(
              pinId: event.pinId,
              title: draft.title,
              blocks: draft.blocks,
              visibility: draft.visibility,
              mood: draft.mood,
              tags: draft.tags,
              status: EditorStatus.idle,
            ));
          } else {
            emit(state.copyWith(
                pinId: event.pinId,
                blocks: [],
                title: '',
                status: EditorStatus.idle));
          }
        },
      );
      _startAutoSaveTimer();
    });

    on<LoadExistingTripLogEvent>((event, emit) {
      emit(state.copyWith(
        tripId: event.tripLog.tripId,
        pinId: event.tripLog.locationPinId,
        title: event.tripLog.title,
        blocks: event.tripLog.blocks,
        visibility: event.tripLog.visibility,
        mood: event.tripLog.mood,
        tags: event.tripLog.tags,
        status: EditorStatus.idle,
      ));
    });

    on<AddBlockEvent>((event, emit) async {
      final updated = List<TripBlock>.from(state.blocks)..add(event.block);
      final quality = await _computeQuality(updated, state.title);
      emit(state.copyWith(blocks: updated, qualityResult: quality));
      // Auto-stamp weather on first block addition if not yet done
      if (!_weatherStamped) _tryStampWeather();
    });

    on<UpdateBlockEvent>((event, emit) async {
      final updated = List<TripBlock>.from(state.blocks);
      updated[event.index] = event.block;
      final quality = await _computeQuality(updated, state.title);
      emit(state.copyWith(blocks: updated, qualityResult: quality));
    });

    on<DeleteBlockEvent>((event, emit) async {
      final updated = List<TripBlock>.from(state.blocks)..removeAt(event.index);
      final quality = await _computeQuality(updated, state.title);
      emit(state.copyWith(blocks: updated, qualityResult: quality));
    });

    on<ReorderBlocksEvent>((event, emit) {
      emit(state.copyWith(blocks: event.blocks));
    });

    on<UpdateTitleEvent>((event, emit) async {
      final quality = await _computeQuality(state.blocks, event.title);
      emit(state.copyWith(title: event.title, qualityResult: quality));
      add(AutoSaveDraftEvent());
    });

    on<AutoSaveDraftEvent>((event, emit) async {
      if (state.pinId.isNotEmpty &&
          (state.title.isNotEmpty || state.blocks.isNotEmpty)) {
        final costItems = _extractCostItems(state.blocks);
        final currentDraft = TripLog(
          tripId: 'draft_${state.pinId}',
          authorId: 'current_user',
          title: state.title,
          blocks: state.blocks,
          routePoints: const [
            GeoCoordinate(latitude: 23.6850, longitude: 90.3563),
            GeoCoordinate(latitude: 23.9000, longitude: 90.4000),
          ],
          costItems: costItems,
          locationPinId: state.pinId,
          trustScore: 0,
          helpfulVotes: 0,
          lastConfirmed: DateTime.now(),
          division: 'Dhaka',
          district: 'Rangamati',
          tier: TrustTier.unverified,
          syncStatus: SyncStatus.pendingUpload,
          visibility: state.visibility,
          mood: state.mood,
          tags: state.tags,
          tripStartDate: state.tripStartDate,
          tripEndDate: state.tripEndDate,
          weatherAtVisit: state.weatherSnapshot,
        );
        await _saveDraft(currentDraft);
      }
    });

    on<PublishTripLogEvent>((event, emit) async {
      emit(state.copyWith(title: event.title, status: EditorStatus.publishing));

      final missing = state.getMissingRequirements();
      if (missing.isNotEmpty) {
        emit(state.copyWith(
          status: EditorStatus.error,
          errorMessage: 'ডায়েরি অসম্পূর্ণ। সব তথ্য পূরণ করুন।',
          validationErrors: missing,
        ));
        return;
      }

      final costItems = _extractCostItems(state.blocks);
      final String authorId = _firebaseAuth.currentUser?.uid ?? 'explorer_user';

      final tripLog = TripLog(
        tripId: state.tripId ?? 'trip_${DateTime.now().millisecondsSinceEpoch}',
        authorId: authorId,
        title: event.title,
        blocks: state.blocks,
        routePoints: const [
          GeoCoordinate(latitude: 23.6850, longitude: 90.3563),
          GeoCoordinate(latitude: 23.9000, longitude: 90.4000),
        ],
        costItems: costItems,
        locationPinId: state.pinId,
        trustScore: 50,
        helpfulVotes: 0,
        lastConfirmed: DateTime.now(),
        division: 'Dhaka',
        district: 'Rangamati',
        tier: TrustTier.community,
        // Travel Diary fields
        visibility: state.visibility,
        mood: state.mood,
        tags: state.tags,
        tripStartDate: state.tripStartDate,
        tripEndDate: state.tripEndDate,
        weatherAtVisit: state.weatherSnapshot,
      );

      final result = await _publishTripLog(PublishTripLogParams(
        tripLog: tripLog,
        authorId: authorId,
      ));
      result.fold(
        (failure) => emit(state.copyWith(
            status: EditorStatus.error, errorMessage: failure.message)),
        (published) {
          _autoSaveTimer?.cancel();
          _weatherStamped = false;
          emit(state.copyWith(
            status: EditorStatus.success,
            blocks: const [],
            title: '',
            tags: const [],
            visibility: DiaryVisibility.community,
          ));
        },
      );
    });

    // ── Travel Diary events ───────────────────────────────────────────────────
    on<UpdateVisibilityEvent>((event, emit) {
      emit(state.copyWith(visibility: event.visibility));
    });

    on<UpdateMoodEvent>((event, emit) {
      if (event.mood == null) {
        emit(state.copyWith(clearMood: true));
      } else {
        emit(state.copyWith(mood: event.mood));
      }
    });

    on<UpdateTagsEvent>((event, emit) {
      emit(state.copyWith(tags: event.tags));
    });

    on<UpdateTripDatesEvent>((event, emit) {
      emit(state.copyWith(
        tripStartDate: event.startDate,
        tripEndDate: event.endDate,
      ));
    });

    on<StampWeatherEvent>((event, emit) {
      _weatherStamped = true;
      emit(state.copyWith(weatherSnapshot: event.weather));
    });
    // ─────────────────────────────────────────────────────────────────────────
  }

  /// Extracts all CostItems from costEntry blocks.
  List<CostItem> _extractCostItems(List<TripBlock> blocks) {
    final costItems = <CostItem>[];
    for (final block in blocks) {
      block.when(
        text: (_, __, ___) {},
        image: (_, __, ___, ____) {},
        video: (_, __, ___, ____) {},
        costEntry: (_, items, __) => costItems.addAll(items),
        route: (_, __, ___) {},
        safetyNote: (_, __, ___) {},
        voiceNote: (_, __, ___, ____, _____) {},
      );
    }
    return costItems;
  }

  /// Computes quality score in background isolate.
  Future<QualityResult> _computeQuality(List<TripBlock> blocks, String title) {
    final bodyText =
        blocks.whereType<TextBlock>().map((b) => b.content).join(' ');
    final imageCount = blocks.whereType<ImageBlock>().length;
    final videoCount = blocks.whereType<VideoBlock>().length;
    final routePoints = blocks
        .whereType<RouteBlock>()
        .fold<int>(0, (sum, b) => sum + b.points.length);
    final costItems = blocks.whereType<CostEntryBlock>().length;
    final safetyNotes = blocks.whereType<SafetyNoteBlock>().length;

    return TripLogQualityScorer.score(
      title: title,
      bodyText: bodyText,
      imageCount: imageCount,
      videoCount: videoCount,
      routePointCount: routePoints,
      costItemCount: costItems,
      safetyNoteCount: safetyNotes,
    );
  }

  /// Tries to auto-stamp weather using device location.
  /// Gracefully fails if location/internet is unavailable.
  Future<void> _tryStampWeather() async {
    try {
      // Default to Dhaka coordinates — in production, use Geolocator
      const lat = 23.8103;
      const lng = 90.4125;
      final weather = await WeatherService.getCurrentWeather(lat, lng);
      if (weather != null && !isClosed) {
        add(StampWeatherEvent(
          WeatherSnapshot(
            tempC: weather.tempC,
            emoji: weather.emoji,
            description: weather.description,
            precipMm: weather.precipMm,
            windKph: weather.windKph,
            weatherCode: weather.code,
            isSafeToVisit: weather.isSafeToVisit,
          ),
        ));
      }
    } catch (_) {
      // Graceful degradation — weather stamp is non-critical
    }
  }

  void _startAutoSaveTimer() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      add(AutoSaveDraftEvent());
    });
  }

  @override
  TripLogState? fromJson(Map<String, dynamic> json) {
    try {
      return TripLogState.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  @override
  Map<String, dynamic>? toJson(TripLogState state) {
    try {
      return state.toJson();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> close() {
    _autoSaveTimer?.cancel();
    return super.close();
  }
}
