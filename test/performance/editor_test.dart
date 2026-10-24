import 'package:dartz/dartz.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:mockito/mockito.dart';

import 'package:bhromon/core/entities/trip_block.dart';
import 'package:bhromon/core/entities/trip_log.dart';
import 'package:bhromon/core/services/trip_log_quality_scorer.dart';
import 'package:bhromon/core/entities/cost_item.dart';
import 'package:bhromon/features/trip_log/presentation/bloc/trip_log_bloc.dart';
import 'package:bhromon/features/trip_log/presentation/bloc/trip_log_event.dart';
import 'package:bhromon/features/trip_log/presentation/bloc/trip_log_state.dart';

import '../features/trip_log/presentation/bloc/trip_log_bloc_test.mocks.dart';

/// Hydrated storage that counts writes (each is a disk write on device).
class CountingStorage implements Storage {
  int writes = 0;
  final Map<String, dynamic> data = {};

  @override
  dynamic read(String key) => data[key];

  @override
  Future<void> write(String key, dynamic value) async {
    writes++;
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async => data.remove(key);

  @override
  Future<void> clear() async => data.clear();

  @override
  Future<void> close() async {}
}

void main() {
  group('TripLogState.onlyTypedTextChanged', () {
    const quality = QualityResult(
        score: 40, tips: ['add photos'], strengths: [], trustBonus: 0);
    const base = TripLogState(
      pinId: 'p',
      title: 'Sajek',
      blocks: [
        TripBlock.text(id: 't', content: 'Day one'),
        TripBlock.image(id: 'i', storageUrl: 'u', caption: 'view'),
        TripBlock.costEntry(id: 'c', items: [], currency: 'BDT'),
      ],
      qualityResult: quality,
    );

    test('true when only typed text changed', () {
      final typed = base.copyWith(
        title: 'Sajek Valley',
        blocks: const [
          TripBlock.text(id: 't', content: 'Day one, we hiked'),
          TripBlock.image(id: 'i', storageUrl: 'u', caption: 'the view'),
          TripBlock.costEntry(id: 'c', items: [], currency: 'BDT'),
        ],
        qualityResult: const QualityResult(
            score: 40, tips: ['add photos'], strengths: [], trustBonus: 0),
      );
      expect(TripLogState.onlyTypedTextChanged(base, typed), isTrue);
    });

    test('false when something the editor renders from state changed', () {
      // A cost item is drawn from state, not from a text controller.
      final costAdded = base.copyWith(blocks: [
        base.blocks[0],
        base.blocks[1],
        const TripBlock.costEntry(
            id: 'c',
            items: [
              CostItem(label: 'Bus', amountBDT: 500, category: 'transport')
            ],
            currency: 'BDT'),
      ]);
      expect(TripLogState.onlyTypedTextChanged(base, costAdded), isFalse);

      final blockAdded = base.copyWith(blocks: [
        ...base.blocks,
        const TripBlock.text(id: 't2', content: ''),
      ]);
      expect(TripLogState.onlyTypedTextChanged(base, blockAdded), isFalse);

      final scoreChanged = base.copyWith(
          qualityResult: const QualityResult(
              score: 55, tips: [], strengths: [], trustBonus: 0));
      expect(TripLogState.onlyTypedTextChanged(base, scoreChanged), isFalse);

      final cleared = base.copyWith(title: '');
      expect(TripLogState.onlyTypedTextChanged(base, cleared), isFalse,
          reason: 'title emptiness drives the publish checklist');

      final status = base.copyWith(status: EditorStatus.saving);
      expect(TripLogState.onlyTypedTextChanged(base, status), isFalse);
    });
  });

  group('TripLogBloc keystroke work', () {
    late MockPublishTripLogUseCase publish;
    late MockGetTripLogsForPinUseCase getForPin;
    late MockSaveDraftUseCase saveDraft;
    late MockLoadDraftUseCase loadDraft;
    late MockFirebaseAuth auth;
    late CountingStorage storage;

    final draft = TripLog(
      tripId: 'draft_pin',
      authorId: 'me',
      title: 'Draft',
      blocks: const [TripBlock.text(id: 't', content: 'hello')],
      routePoints: const [],
      costItems: const [],
      locationPinId: 'pin',
      trustScore: 0,
      helpfulVotes: 0,
      lastConfirmed: DateTime(2026),
      division: 'Dhaka',
      district: 'Dhaka',
    );

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      storage = CountingStorage();
      HydratedBloc.storage = storage;
      publish = MockPublishTripLogUseCase();
      getForPin = MockGetTripLogsForPinUseCase();
      saveDraft = MockSaveDraftUseCase();
      loadDraft = MockLoadDraftUseCase();
      auth = MockFirebaseAuth();
      when(loadDraft.call(any)).thenAnswer((_) async => Right(draft));
      when(saveDraft.call(any)).thenAnswer((_) async => const Right(unit));
    });

    TripLogBloc build() =>
        TripLogBloc(publish, getForPin, saveDraft, loadDraft, auth);

    test('a burst of typing saves the draft once, after typing pauses', () {
      fakeAsync((async) {
        final bloc = build();
        bloc.add(const LoadDraftEvent('pin'));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        storage.writes = 0;

        // 40 keystrokes over 2 seconds (one every 50 ms).
        const text = 'Sajek Valley sunrise trip with friends!';
        for (var i = 1; i <= text.length; i++) {
          bloc.add(UpdateTitleEvent(text.substring(0, i)));
          async.elapse(const Duration(milliseconds: 50));
        }
        verifyNever(saveDraft.call(any));
        expect(storage.writes, 0,
            reason: 'hydrated state used to be written on every keystroke');

        async.elapse(TripLogBloc.draftSaveDelay);
        async.flushMicrotasks();

        final saved = verify(saveDraft.call(captureAny)).captured;
        expect(saved, hasLength(1), reason: 'was one draft save per keystroke');
        expect((saved.single as TripLog).title, text);
        expect(storage.writes, 1);
        expect(bloc.state.title, text);

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('text block edits are coalesced the same way', () {
      fakeAsync((async) {
        final bloc = build();
        bloc.add(const LoadDraftEvent('pin'));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        clearInteractions(saveDraft);

        for (var i = 0; i < 25; i++) {
          bloc.add(UpdateBlockEvent(
              0, TripBlock.text(id: 't', content: 'hello ${'x' * i}')));
          async.elapse(const Duration(milliseconds: 80));
        }
        async.elapse(TripLogBloc.draftSaveDelay);
        async.flushMicrotasks();

        verify(saveDraft.call(any)).called(1);
        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('closing the editor saves edits made inside the debounce window',
        () async {
      final bloc = build();
      bloc.add(const LoadDraftEvent('pin'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      clearInteractions(saveDraft);

      bloc.add(const UpdateTitleEvent('Last-second edit'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await bloc.close();

      final saved = verify(saveDraft.call(captureAny)).captured;
      expect((saved.single as TripLog).title, 'Last-second edit');
      expect(storage.data.values.single['title'], 'Last-second edit');
    });

    test('the periodic timer does not resave an unchanged draft', () {
      fakeAsync((async) {
        final bloc = build();
        bloc.add(const LoadDraftEvent('pin'));
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 5));
        verifyNever(saveDraft.call(any));
        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('rapid edits keep the newest text (no out-of-order overwrite)',
        () async {
      final bloc = build();
      bloc.add(const LoadDraftEvent('pin'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      const text = 'Cox Bazar';
      for (var i = 1; i <= text.length; i++) {
        bloc.add(UpdateTitleEvent(text.substring(0, i)));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.title, text);
      final expected = TripLogQualityScorer.scoreSync(
        title: text,
        bodyText: 'hello',
        imageCount: 0,
        videoCount: 0,
        routePointCount: 0,
        costItemCount: 0,
        safetyNoteCount: 0,
      );
      expect(bloc.state.qualityResult?.score, expected.score,
          reason: 'quality must match the latest content, not a stale edit');
      await bloc.close();
    });
  });

  group('quality scoring cost', () {
    test('normal diaries score inline; an isolate per edit costs far more',
        () async {
      final body = List.filled(800, 'word').join(' '); // ~4,000 chars
      const runs = 30;

      final sw = Stopwatch()..start();
      for (var i = 0; i < runs; i++) {
        await TripLogQualityScorer.score(
          title: 'Title $i',
          bodyText: body,
          imageCount: 1,
          videoCount: 0,
          routePointCount: 2,
          costItemCount: 1,
          safetyNoteCount: 1,
        );
      }
      final inline = sw.elapsedMicroseconds;

      sw.reset();
      for (var i = 0; i < runs; i++) {
        await TripLogQualityScorer.scoreInIsolate(
            title: 'Title $i', bodyText: body);
      }
      final isolates = sw.elapsedMicroseconds;
      // ignore: avoid_print
      print('$runs scores: inline ${inline ~/ 1000} ms, '
          'isolate per call ${isolates ~/ 1000} ms');
      expect(inline, lessThan(isolates));
    });

    test('inline and isolate scoring agree', () async {
      final inline = await TripLogQualityScorer.score(
        title: 'Sajek trip',
        bodyText: 'We took the night bus and hiked at dawn.',
        imageCount: 0,
        videoCount: 0,
        routePointCount: 0,
        costItemCount: 0,
        safetyNoteCount: 0,
      );
      final isolate = await TripLogQualityScorer.scoreInIsolate(
          title: 'Sajek trip',
          bodyText: 'We took the night bus and hiked at dawn.');
      expect(inline.score, isolate.score);
      expect(inline.tips, isolate.tips);
    });
  });
}
