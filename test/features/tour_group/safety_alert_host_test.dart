import 'dart:async';

import 'package:bhromon/core/entities/explorer_profile.dart';
import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/value_objects/explorer_score.dart';
import 'package:bhromon/core/value_objects/trust_tier.dart';
import 'package:bhromon/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:bhromon/features/auth/presentation/cubit/auth_state.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/safety_alert_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/safety_alert_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// The banner that shows another member's safety alert over every screen, with a repository
// whose alerts the test sends by hand.

class _TestAuthCubit extends Cubit<AuthState> implements AuthCubit {
  _TestAuthCubit(super.initialState);

  void emitState(AuthState state) => emit(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TourGroup _group(String id, String name, {String? preset}) => TourGroup(
      id: id,
      name: name,
      ownerEmail: 'owner@x.com',
      inviteCode: 'ABCDEFGH',
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 4),
      createdAt: DateTime(2026, 10, 1),
      kind: GroupKind.family,
      preset: preset,
    );

class _FakeRepo extends TourGroupRepository {
  _FakeRepo(this.groups);

  final List<TourGroup> groups;
  final Map<String, StreamController<List<SafetyAlert>>> alerts = {};
  final List<String> watched = [];

  @override
  String get currentEmail => 'me@x.com';

  @override
  Stream<List<TourGroup>> watchMyGroups() => Stream.value(groups);

  @override
  Stream<List<SafetyAlert>> watchSafetyAlerts(String tourId, {int limit = 30}) {
    watched.add(tourId);
    return (alerts[tourId] ??= StreamController<List<SafetyAlert>>.broadcast())
        .stream;
  }

  void send(String tourId, List<SafetyAlert> list) => alerts[tourId]!.add(list);
}

/// Lets a stream event reach its listener, then draws the frame it asked for.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

SafetyAlert _alert(String id,
        {String sender = 'rana@x.com', bool resolved = false}) =>
    SafetyAlert(
      id: id,
      senderEmail: sender,
      senderName: 'M S Rana',
      createdAt: DateTime.now().subtract(const Duration(seconds: 5)),
      resolved: resolved,
    );

final _profile = ExplorerProfile(
  uid: 'u1',
  displayName: 'Me',
  explorerScore: const ExplorerScore(value: 250, tier: TrustTier.verified),
  tier: TrustTier.verified,
  badges: const [],
  division: 'Dhaka',
  createdAt: DateTime(2026, 1, 1),
);

Future<({_FakeRepo repo, _TestAuthCubit auth, List<String> opened})> _pump(
  WidgetTester tester, {
  bool signedIn = true,
}) async {
  final repo = _FakeRepo([
    _group('soc', 'Khaurun Complex', preset: TourGroup.societyPreset),
    _group('study', 'JAIBB', preset: TourGroup.studyPreset),
  ]);
  final auth = _TestAuthCubit(
      signedIn ? Authenticated(_profile) : const Unauthenticated());
  final opened = <String>[];
  addTearDown(auth.close);
  await tester.pumpWidget(BlocProvider<AuthCubit>.value(
    value: auth,
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', ''), Locale('bn', '')],
      builder: (context, child) => SafetyAlertHost(
        repository: repo,
        sound: false,
        onOpen: opened.add,
        child: child!,
      ),
      home: const Scaffold(body: Text('any screen')),
    ),
  ));
  await tester.pump();
  await tester.pump();
  return (repo: repo, auth: auth, opened: opened);
}

void main() {
  testWidgets('only groups that have SOS are listened to', (tester) async {
    final h = await _pump(tester);
    expect(h.repo.watched, ['soc']);
  });

  testWidgets('another member\'s alert shows at once, on any screen',
      (tester) async {
    final h = await _pump(tester);
    expect(find.text('M S Rana needs help now'), findsNothing);

    h.repo.send('soc', [_alert('a')]);
    await _settle(tester);

    expect(find.text('any screen'), findsOneWidget);
    expect(find.text('M S Rana needs help now'), findsOneWidget);
    expect(find.text('SOS alert in Khaurun Complex'), findsOneWidget);
  });

  testWidgets('my own alert shows no banner', (tester) async {
    final h = await _pump(tester);
    h.repo.send('soc', [_alert('a', sender: 'me@x.com')]);
    await _settle(tester);

    expect(find.byIcon(Icons.sos_rounded), findsNothing);
  });

  testWidgets('the banner goes when the alert is closed', (tester) async {
    final h = await _pump(tester);
    h.repo.send('soc', [_alert('a')]);
    await _settle(tester);
    expect(find.byIcon(Icons.sos_rounded), findsOneWidget);

    h.repo.send('soc', [_alert('a', resolved: true)]);
    await _settle(tester);
    expect(find.byIcon(Icons.sos_rounded), findsNothing);
  });

  testWidgets('Open goes to that group\'s safety screen', (tester) async {
    final h = await _pump(tester);
    h.repo.send('soc', [_alert('a')]);
    await _settle(tester);

    await tester.tap(find.text('Open'));
    await _settle(tester);

    expect(h.opened, ['soc']);
    expect(find.byIcon(Icons.sos_rounded), findsNothing);
  });

  testWidgets('a hidden alert stays hidden, and a new one still shows',
      (tester) async {
    final h = await _pump(tester);
    h.repo.send('soc', [_alert('a')]);
    await _settle(tester);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await _settle(tester);
    expect(find.byIcon(Icons.sos_rounded), findsNothing);

    // The same alert arriving again does not bring the banner back.
    h.repo.send('soc', [_alert('a')]);
    await _settle(tester);
    expect(find.byIcon(Icons.sos_rounded), findsNothing);

    h.repo.send('soc', [_alert('b'), _alert('a')]);
    await _settle(tester);
    expect(find.byIcon(Icons.sos_rounded), findsOneWidget);
  });

  testWidgets('nothing is listened to until someone signs in', (tester) async {
    final h = await _pump(tester, signedIn: false);
    expect(h.repo.watched, isEmpty);

    h.auth.emitState(Authenticated(_profile));
    await _settle(tester);
    expect(h.repo.watched, ['soc']);
  });

  testWidgets('signing out takes the banner away', (tester) async {
    final h = await _pump(tester);
    h.repo.send('soc', [_alert('a')]);
    await _settle(tester);
    expect(find.byIcon(Icons.sos_rounded), findsOneWidget);

    h.auth.emitState(const Unauthenticated());
    await _settle(tester);
    expect(find.byIcon(Icons.sos_rounded), findsNothing);
  });

  testWidgets('the banner\'s buttons are at least 48 high', (tester) async {
    final h = await _pump(tester);
    h.repo.send('soc', [_alert('a')]);
    await _settle(tester);

    expect(tester.getSize(find.widgetWithText(TextButton, 'Open')).height,
        greaterThanOrEqualTo(48));
  });
}
