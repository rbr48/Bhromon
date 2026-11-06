import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/theme/theme.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_document_bubble.dart';

ChatDocumentBubble _bubble({double? uploadProgress}) => ChatDocumentBubble(
      documentUrl: '',
      fileName: 'notes.pdf',
      fileSizeBytes: 2048,
      isMe: true,
      timeStr: '',
      uploadProgress: uploadProgress,
    );

Future<void> _pump(WidgetTester tester, Widget bubble) {
  return tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: Center(child: bubble)),
  ));
}

void main() {
  testWidgets('a document that is still sending shows its progress',
      (tester) async {
    await _pump(tester, _bubble(uploadProgress: 0.42));

    expect(find.text('42%'), findsOneWidget);
    final ring = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator));
    expect(ring.value, closeTo(0.42, 1e-9));
  });

  testWidgets('a document that is still sending cannot be opened',
      (tester) async {
    await _pump(tester, _bubble(uploadProgress: 0.1));

    final ink = tester.widget<InkWell>(find.byType(InkWell));
    expect(ink.onTap, isNull);
    await tester.tap(find.byType(InkWell));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a document that is not sending shows no progress',
      (tester) async {
    await _pump(tester, _bubble());

    expect(find.textContaining('%'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final ink = tester.widget<InkWell>(find.byType(InkWell));
    expect(ink.onTap, isNotNull);
  });
}
