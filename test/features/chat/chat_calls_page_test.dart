import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/widgets/swipe_pager.dart';
import 'package:bhromon/features/chat/domain/call_log_entry.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_calls_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The calls page of a one-to-one chat (the swipe from messages). Me is 'me'.

CallLogEntry _call({
  required String caller,
  required String callee,
  bool isVideo = false,
  String status = 'ended',
  int? seconds,
}) {
  return CallLogEntry(
    callerId: caller,
    calleeId: callee,
    isVideo: isVideo,
    status: status,
    durationSeconds: seconds,
  );
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      DefaultMaterialLocalizations.delegate,
      DefaultWidgetsLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  ));
  await tester.pumpAndSettle();
}

ChatCallsPage _page({
  required List<ChatCallRow> rows,
  required VoidCallback onVoice,
  required VoidCallback onVideo,
  void Function(bool)? onBack,
}) {
  return ChatCallsPage(
    otherName: 'Rahim',
    currentUid: 'me',
    rows: rows,
    onVoiceCall: onVoice,
    onVideoCall: onVideo,
    onCallBack: onBack ?? (_) {},
  );
}

/// The chat's pager in a host that keeps the page, as the chat screen does.
class _SwipeHost extends StatefulWidget {
  const _SwipeHost({required this.onVoice, required this.onVideo});

  final VoidCallback onVoice;
  final VoidCallback onVideo;

  @override
  State<_SwipeHost> createState() => _SwipeHostState();
}

class _SwipeHostState extends State<_SwipeHost> {
  final PageController _controller = PageController();
  int _current = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 600,
      child: SwipePager(
        controller: _controller,
        count: 2,
        selectedIndex: _current,
        onSettled: (page) => setState(() => _current = page),
        itemBuilder: (context, index) => index == 1
            ? _page(
                rows: const [],
                onVoice: widget.onVoice,
                onVideo: widget.onVideo,
              )
            : const Center(child: Text('messages')),
      ),
    );
  }
}

void main() {
  testWidgets('the calls page names the person and offers both ways to call',
      (tester) async {
    var voice = 0;
    var video = 0;
    await _pump(
      tester,
      _page(rows: const [], onVoice: () => voice++, onVideo: () => video++),
    );
    expect(find.text('Calls with Rahim'), findsOneWidget);
    await tester.tap(find.text('Audio call'));
    await tester.tap(find.text('Video call'));
    await tester.pump();
    expect(voice, 1);
    expect(video, 1);
  });

  testWidgets('with no calls the history says so', (tester) async {
    await _pump(tester, _page(rows: const [], onVoice: () {}, onVideo: () {}));
    expect(find.text('No calls with Rahim yet.'), findsOneWidget);
  });

  testWidgets('each call shows how it went, and calls back the way it was made',
      (tester) async {
    final calls = <bool>[];
    final rows = [
      ChatCallRow(
        entry: _call(caller: 'me', callee: 'rahim', isVideo: true, seconds: 65),
        at: DateTime(2026, 11, 2, 18, 30),
      ),
      ChatCallRow(
        entry: _call(caller: 'rahim', callee: 'me', status: 'missed'),
        at: null,
      ),
    ];
    await _pump(
      tester,
      _page(
        rows: rows,
        onVoice: () {},
        onVideo: () {},
        onBack: calls.add,
      ),
    );
    expect(find.text('Outgoing video call'), findsOneWidget);
    expect(find.text('Missed call'), findsOneWidget);
    expect(find.textContaining('1:05'), findsOneWidget,
        reason: 'a connected call shows its length');

    // The call-back icons: the first call was video, the second was not connected.
    final tiles = find.byType(IconButton);
    await tester.tap(tiles.at(0));
    await tester.pump();
    expect(calls, [true]);
  });

  testWidgets(
      'a swipe between pages only shows the page: it never starts a call',
      (tester) async {
    var voice = 0;
    var video = 0;
    await _pump(
      tester,
      _SwipeHost(
        onVoice: () => voice++,
        onVideo: () => video++,
      ),
    );
    // Swipe left to the calls page, then back to the messages.
    await tester.drag(find.text('messages'), const Offset(-550, 0));
    await tester.pumpAndSettle();
    expect(find.text('Calls with Rahim'), findsOneWidget);
    await tester.drag(find.text('Calls with Rahim'), const Offset(550, 0));
    await tester.pumpAndSettle();
    expect(find.text('messages'), findsOneWidget);
    expect(voice, 0);
    expect(video, 0);
  });

  testWidgets('the page switch names both pages and reports the one tapped',
      (tester) async {
    final chosen = <int>[];
    await _pump(
      tester,
      ChatPageSwitch(selected: 0, onSelected: chosen.add),
    );
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Calls'), findsOneWidget);
    await tester.tap(find.text('Calls'));
    await tester.pump();
    expect(chosen, [1]);
  });
}
