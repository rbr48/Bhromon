import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/chat/domain/e2ee/e2ee_service.dart';
import 'package:bhromon/features/chat/domain/e2ee/safety_number.dart';
import 'package:bhromon/features/chat/presentation/pages/e2ee_verification_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_olm_engine.dart';
import 'memory_stores.dart';

// The safety-number screen (E2EE_DESIGN.md, sections 6 and 9), with the service over
// the fake engine and the in-memory stores. The screen never changes a key without a
// tap, and these tests check that each tap does what its label says.

class _Household {
  _Household(this.engine, this.keys, this.clock);

  final FakeOlmEngine engine;
  final MemoryKeyStore keys;
  final DateTime clock;
  var _deviceCounter = 0;

  E2eeService serviceFor(String uid, MemoryLocalStore local) {
    return E2eeService(
      userId: uid,
      engine: engine,
      keys: keys,
      local: local,
      pickleKeys: FixedPickleKeyVault(),
      newDeviceId: () => 'device-${++_deviceCounter}',
      now: () => clock,
    );
  }
}

Future<void> pumpScreen(
  WidgetTester tester, {
  required E2eeService service,
  required String otherUid,
  required String otherName,
}) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: E2eeVerificationScreen(
      otherUid: otherUid,
      otherName: otherName,
      service: service,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  late FakeOlmEngine engine;
  late MemoryKeyStore keys;
  late _Household household;

  setUp(() {
    engine = FakeOlmEngine();
    keys = MemoryKeyStore();
    household = _Household(engine, keys, DateTime.utc(2026, 11, 8));
  });

  testWidgets(
      'shows the safety number both sides compute, and marks it verified',
      (tester) async {
    final aliceLocal = MemoryLocalStore();
    final alice = household.serviceFor('uid-a', aliceLocal);
    final bob = household.serviceFor('uid-b', MemoryLocalStore());
    await alice.setUpThisDevice();
    await bob.setUpThisDevice();
    final envelope = await alice.encryptText(
      chatId: 'chat-1',
      messageId: 'msg-1',
      recipientUid: 'uid-b',
      text: 'hello',
      sentAtMillis: 1,
    );
    await bob.decryptMessage(
      chatId: 'chat-1',
      messageId: 'msg-1',
      senderUid: 'uid-a',
      envelope: envelope,
    );
    final bobSees = await bob.safetyNumber('uid-a');

    await pumpScreen(tester,
        service: alice, otherUid: 'uid-b', otherName: 'Bob');

    final shown = tester.widget<Text>(find.byKey(const Key('safetyNumber')));
    expect(shown.data, SafetyNumber.grouped(bobSees));
    expect(find.text('Not verified yet'), findsOneWidget);

    expect(find.byKey(const Key('copySafetyNumber')), findsOneWidget);
    await tester.tap(find.byKey(const Key('copySafetyNumber')));
    await tester.pump();
    expect(find.text('Safety number copied to clipboard'), findsOneWidget);

    await tester.tap(find.byKey(const Key('markVerified')));
    await tester.pumpAndSettle();

    expect(find.text('Verified'), findsOneWidget);
    expect(find.byKey(const Key('markVerified')), findsNothing);
  });

  testWidgets(
      'a changed identity is a warning, and trusting the new key clears it',
      (tester) async {
    final alice = household.serviceFor('uid-a', MemoryLocalStore());
    final bob = household.serviceFor('uid-b', MemoryLocalStore());
    await alice.setUpThisDevice();
    await bob.setUpThisDevice();
    await alice.encryptText(
      chatId: 'chat-1',
      messageId: 'msg-1',
      recipientUid: 'uid-b',
      text: 'before',
      sentAtMillis: 1,
    );
    // Bob sets up on a new device, so his identity changes.
    final bobNew = household.serviceFor('uid-b', MemoryLocalStore());
    await bobNew.setUpThisDevice();
    await alice.encryptText(
      chatId: 'chat-1',
      messageId: 'msg-2',
      recipientUid: 'uid-b',
      text: 'after',
      sentAtMillis: 2,
    );

    await pumpScreen(tester,
        service: alice, otherUid: 'uid-b', otherName: 'Bob');

    expect(find.text('Security key changed'), findsOneWidget);
    expect(find.byKey(const Key('trustNewKey')), findsOneWidget);

    await tester.tap(find.byKey(const Key('trustNewKey')));
    await tester.pumpAndSettle();

    expect(find.text('Security key changed'), findsNothing);
    expect(find.text('Not verified yet'), findsOneWidget);
  });

  testWidgets('a device without its keys asks before it sets them up here',
      (tester) async {
    // Another device of the same account holds the keys.
    final other = household.serviceFor('uid-a', MemoryLocalStore());
    await other.setUpThisDevice();
    final here = household.serviceFor('uid-a', MemoryLocalStore());

    await pumpScreen(tester,
        service: here, otherUid: 'uid-b', otherName: 'Bob');

    expect(find.byKey(const Key('setUpHere')), findsOneWidget);

    await tester.tap(find.byKey(const Key('setUpHere')));
    await tester.pumpAndSettle();
    expect(find.text('Set up encryption here?'), findsOneWidget);

    // Cancelling changes nothing.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(keys.publishedDeviceIdSync('uid-a'), 'device-1');

    await tester.tap(find.byKey(const Key('setUpHere')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Set up on this device'),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('setUpHere')), findsNothing);
    expect(find.textContaining('appears after you and Bob'), findsOneWidget);
    expect(keys.publishedDeviceIdSync('uid-a'), 'device-2');
  });
}
