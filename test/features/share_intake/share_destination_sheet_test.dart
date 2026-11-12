import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/share_intake/data/share_destinations_loader.dart';
import 'package:bhromon/features/share_intake/domain/share_plan.dart';
import 'package:bhromon/features/share_intake/domain/shared_file.dart';
import 'package:bhromon/features/share_intake/presentation/share_destination_sheet.dart';
import 'package:bhromon/features/tour_group/domain/models/channel_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// The sheet is driven by fixed destinations, so no Firestore is needed. The chat route is a
// stand-in page that records where a tap went.

SharedFile _file() => const SharedFile(
    name: 'notes.pdf', sizeBytes: 1000, path: '/cache/notes.pdf');

TourGroup _group(String id, String name) => TourGroup(
      id: id,
      name: name,
      ownerEmail: 'owner@example.com',
      inviteCode: 'ABCDEFGH',
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 2),
      createdAt: DateTime(2026, 1, 1),
    );

ChatDestination _chat({
  required String id,
  required String otherUid,
  String? title,
  String? tourName,
}) =>
    ChatDestination(
      chatId: id,
      otherUid: otherUid,
      title: title,
      tourName: tourName,
      sharedTourId: 't1',
    );

/// Where the last tap on a chat row went: the chat id and the route's extra data.
({String chatId, Map<String, dynamic>? extra})? _opened;

GoRouter _router(Future<ShareDestinations> Function() load) {
  return GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showShareDestinationSheet(
                context,
                files: [_file()],
                currentUid: 'me',
                loadDestinations: load,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/chat/:chatId',
        builder: (context, state) {
          _opened = (
            chatId: state.pathParameters['chatId']!,
            extra: state.extra as Map<String, dynamic>?,
          );
          return const Text('chat page');
        },
      ),
    ],
  );
}

Future<void> _pump(WidgetTester tester, GoRouter router) async {
  _opened = null;
  await tester.pumpWidget(MaterialApp.router(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    routerConfig: router,
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a chat row shows the other person\'s name and its group',
      (tester) async {
    await _pump(
      tester,
      _router(() async => ShareDestinations(
            chats: [
              _chat(
                  id: 'c1',
                  otherUid: 'rahim',
                  title: 'Rahim',
                  tourName: 'Cox Trip'),
              _chat(id: 'c2', otherUid: 'karim', tourName: 'Office'),
            ],
            channels: const [],
          )),
    );

    expect(find.text('Rahim'), findsOneWidget);
    expect(find.text('Cox Trip'), findsOneWidget);
    // A chat with no name shows the neutral label, never the sender's own name.
    expect(find.text('Member'), findsOneWidget);
    expect(find.text('Office'), findsOneWidget);
  });

  testWidgets('tapping a chat row opens that chat with its files',
      (tester) async {
    await _pump(
      tester,
      _router(() async => ShareDestinations(
            chats: [
              _chat(
                  id: 'c1',
                  otherUid: 'rahim',
                  title: 'Rahim',
                  tourName: 'Cox Trip'),
              _chat(
                  id: 'c2',
                  otherUid: 'karim',
                  title: 'Karim',
                  tourName: 'Office'),
            ],
            channels: const [],
          )),
    );

    await tester.tap(find.text('Karim'));
    await tester.pumpAndSettle();

    expect(_opened?.chatId, 'c2');
    expect(_opened?.extra?['otherUid'], 'karim');
    expect(_opened?.extra?['sharedTourId'], 't1');
    expect((_opened?.extra?['sharedFiles'] as List?)?.length, 1);
  });

  testWidgets('channels are listed under a heading for each group',
      (tester) async {
    final cox = _group('t1', 'Cox Trip');
    final office = _group('t2', 'Office');
    await _pump(
      tester,
      _router(() async => ShareDestinations(
            chats: const [],
            channels: [
              ChannelDestination(
                  group: cox,
                  channel: const TourChannel(id: 'rules', name: 'Rules')),
              ChannelDestination(
                  group: office,
                  channel: const TourChannel(id: 'news', name: 'News')),
            ],
          )),
    );

    expect(find.text('Cox Trip'), findsOneWidget);
    expect(find.text('Office'), findsOneWidget);
    expect(find.text('# Rules'), findsOneWidget);
    expect(find.text('# News'), findsOneWidget);
  });

  testWidgets('a list with groups missing says so and offers a retry',
      (tester) async {
    await _pump(
      tester,
      _router(() async => const ShareDestinations(
            chats: [],
            channels: [],
            incomplete: true,
          )),
    );

    expect(
      find.text(
        'Some groups could not be loaded, so they are not listed. Try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('a load that fails shows the error, not an empty list',
      (tester) async {
    await _pump(
      tester,
      _router(() => Future<ShareDestinations>.error(StateError('no network'))),
    );

    expect(
        find.text('Could not load your chats and channels.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
