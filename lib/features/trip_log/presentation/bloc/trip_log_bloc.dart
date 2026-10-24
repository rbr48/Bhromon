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

  /// Editor content changed since the last draft save.
  bool _dirty = false;
  Timer? _draftSaveDebounce;
  Timer? _persistDebounce;

  /// How long typing must pause before the draft is saved.
  static const Duration draftSaveDelay = Duration(seconds: 2);

  /// How long state must settle before it is written to hydrated storage.
  static const Duration persistDelay = Duration(milliseconds: 600);

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
      _markDirty();
      // Auto-stamp weather on first block addition if not yet done
      if (!_weatherStamped) _tryStampWeather();
    });

    on<UpdateBlockEvent>((event, emit) async {
      final updated = List<TripBlock>.from(state.blocks);
      updated[event.index] = event.block;
      final quality = await _computeQuality(updated, state.title);
      emit(state.copyWith(blocks: updated, qualityResult: quality));
      _markDirty();
    });

    on<DeleteBlockEvent>((event, emit) async {
      final updated = List<TripBlock>.from(state.blocks)..removeAt(event.index);
      final quality = await _computeQuality(updated, state.title);
      emit(state.copyWith(blocks: updated, qualityResult: quality));
      _markDirty();
    });

    on<ReorderBlocksEvent>((event, emit) {
      emit(state.copyWith(blocks: event.blocks));
      _markDirty();
    });

    on<UpdateTitleEvent>((event, emit) async {
      final quality = await _computeQuality(state.blocks, event.title);
      emit(state.copyWith(title: event.title, qualityResult: quality));
      _markDirty();
    });

    on<AutoSaveDraftEvent>((event, emit) => _saveCurrentDraft());

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
          _draftSaveDebounce?.cancel();
          _dirty = false;
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
      _markDirty();
    });

    on<UpdateMoodEvent>((event, emit) {
      if (event.mood == null) {
        emit(state.copyWith(clearMood: true));
      } else {
        emit(state.copyWith(mood: event.mood));
      }
      _markDirty();
    });

    on<UpdateTagsEvent>((event, emit) {
      emit(state.copyWith(tags: event.tags));
      _markDirty();
    });

    on<UpdateTripDatesEvent>((event, emit) {
      emit(state.copyWith(
        tripStartDate: event.startDate,
        tripEndDate: event.endDate,
      ));
      _markDirty();
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

  /// Saves the editor content as the pin's draft.
  Future<void> _saveCurrentDraft() async {
    _draftSaveDebounce?.cancel();
    _dirty = false;
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
      try {
        final result = await _saveDraft(currentDraft);
        // Try again on the next save if this one failed.
        if (result.isLeft()) _dirty = true;
      } catch (_) {
        _dirty = true;
      }
    }
  }

  /// Records an edit: the draft is saved once edits pause for
  /// [draftSaveDelay] (and by the periodic timer if that never happens).
  void _markDirty() {
    _dirty = true;
    _draftSaveDebounce?.cancel();
    _draftSaveDebounce = Timer(draftSaveDelay, () {
      if (!isClosed && _dirty) add(AutoSaveDraftEvent());
    });
  }

  void _startAutoSaveTimer() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      // Nothing changed since the last save: don't rewrite the same draft.
      if (_dirty) add(AutoSaveDraftEvent());
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

  /// HydratedBloc calls this on every state change and writes the result to
  /// disk. While editing that is once per keystroke, so writes are deferred:
  /// returning null skips the immediate write, and [_persistNow] writes the
  /// latest state once changes settle (or when the bloc closes).
  @override
  Map<String, dynamic>? toJson(TripLogState state) {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(persistDelay, _persistNow);
    return null;
  }

  Map<String, dynamic>? _encode(TripLogState state) {
    try {
      return state.toJson();
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistNow() async {
    _persistDebounce?.cancel();
    _persistDebounce = null;
    final json = _encode(state);
    if (json == null) return;
    try {
      await HydratedBloc.storage.write(storageToken, json);
    } catch (error, stackTrace) {
      onError(error, stackTrace);
    }
  }

  @override
  Future<void> close() async {
    _autoSaveTimer?.cancel();
    _draftSaveDebounce?.cancel();
    // Don't lose the last edits made within the debounce windows.
    if (_dirty) await _saveCurrentDraft();
    if (_persistDebounce != null) await _persistNow();
    return super.close();
  }
}
