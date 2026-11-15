import 'package:bhromon/core/widgets/data_list_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows a header and a row per record, and a row can be tapped',
      (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DataListTable(
          columns: const [
            DataListColumn('Code', width: 80),
            DataListColumn('Subject', flex: 3),
          ],
          rows: [
            for (final (code, name) in const [
              ('101', 'Monetary and Financial System'),
              ('102', 'Basic Accounting'),
            ])
              DataListRow(
                key: ValueKey<String>(code),
                onTap: () => tapped.add(code),
                trailing: const Icon(Icons.chevron_right),
                cells: [Text(code), Text(name)],
              ),
          ],
        ),
      ),
    ));

    expect(find.text('Code'), findsOneWidget);
    expect(find.text('Subject'), findsOneWidget);
    expect(find.text('Basic Accounting'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));

    await tester.tap(find.text('Basic Accounting'));
    expect(tapped, ['102']);

    // The fixed column is as wide in every row, so the next column lines up.
    final first = tester.getTopLeft(find.text('Monetary and Financial System'));
    final second = tester.getTopLeft(find.text('Basic Accounting'));
    expect(first.dx, second.dx);
  });

  testWidgets('a table is offered only where there is room', (tester) async {
    Future<bool> at(double width) async {
      late bool shows;
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: Builder(builder: (context) {
          shows = showsDataTable(context);
          return const SizedBox();
        }),
      ));
      return shows;
    }

    expect(await at(390), isFalse);
    expect(await at(639), isFalse);
    expect(await at(640), isTrue);
    expect(await at(890), isTrue);
  });
}
