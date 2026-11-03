import 'package:bhromon/features/tour_group/presentation/widgets/group_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('a group without a photo shows the icon of its type',
      (tester) async {
    await tester.pumpWidget(
        _host(const GroupAvatar(typeIcon: Icons.family_restroom_rounded)));
    expect(find.byIcon(Icons.family_restroom_rounded), findsOneWidget);

    await tester.pumpWidget(_host(const GroupAvatar(
      typeIcon: Icons.apartment_rounded,
      photoUrl: '',
    )));
    expect(find.byIcon(Icons.apartment_rounded), findsOneWidget);
  });

  testWidgets(
      'a group with a photo clips it to a circle and shows the icon until it loads',
      (tester) async {
    await tester.pumpWidget(_host(const GroupAvatar(
      typeIcon: Icons.card_travel_rounded,
      photoUrl:
          'https://bhromon.fun/media/t1/avatars/0123456789abcdef0123456789abcdef.jpg',
      size: 64,
    )));
    expect(find.byType(ClipOval), findsOneWidget);
    expect(find.byIcon(Icons.card_travel_rounded), findsOneWidget);
  });
}
