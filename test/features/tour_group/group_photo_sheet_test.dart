import 'dart:io';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/group_photo_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

// The group photo sheet by role (GP.7): owners and admins change or remove it; a member
// sees the photo and the rule, and nothing to press.

class _Repo extends TourGroupRepository {
  _Repo(this.role);

  final TourRole? role;
  final List<String> removed = [];

  @override
  Future<TourRole?> myRole(String tourId) async => role;

  @override
  Future<void> removeGroupPhoto(
      {required String tourId, String? previousUrl}) async {
    removed.add(previousUrl ?? '');
  }
}

TourGroup _group({String? photoUrl}) => TourGroup(
      id: 'g1',
      name: 'Office',
      ownerEmail: 'me@bhromon.fun',
      inviteCode: 'ABCDEFGH',
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 1),
      createdAt: DateTime(2026, 10, 1),
      kind: GroupKind.family,
      photoUrl: photoUrl,
    );

Future<void> _open(WidgetTester tester, _Repo repo, TourGroup group) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      DefaultMaterialLocalizations.delegate,
      DefaultWidgetsLocalizations.delegate,
    ],
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () =>
                showGroupPhotoSheet(context, group: group, repository: repo),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  // Localisation loads before the first frame of text, so settle before tapping.
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('bhromon_photo_sheet').path);
  });

  testWidgets(
      'an owner can choose a photo; with none there is nothing to remove',
      (tester) async {
    await _open(tester, _Repo(TourRole.owner), _group());
    expect(find.text('Choose a new photo'), findsOneWidget);
    expect(find.text('Remove photo'), findsNothing);
    expect(
        find.text(
            'Shown in the group list and at the top of the hub. Up to 10 MB.'),
        findsOneWidget);
  });

  testWidgets('an admin with a photo can also remove it', (tester) async {
    final repo = _Repo(TourRole.admin);
    await _open(
      tester,
      repo,
      _group(
          photoUrl:
              'https://bhromon.fun/media/g1/avatars/0123456789abcdef0123456789abcdef.jpg'),
    );
    expect(find.text('Choose a new photo'), findsOneWidget);
    await tester.tap(find.text('Remove photo'));
    await tester.pumpAndSettle();
    expect(repo.removed, hasLength(1));
    expect(find.text('The group photo has been removed.'), findsOneWidget);
  });

  testWidgets('a member sees the rule and no change control', (tester) async {
    await _open(tester, _Repo(TourRole.member), _group());
    expect(find.text('Only the owner and admins can change the group photo.'),
        findsOneWidget);
    expect(find.text('Choose a new photo'), findsNothing);
    expect(find.text('Remove photo'), findsNothing);
  });
}
