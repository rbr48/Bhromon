import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/family_task_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/pages/family_tasks_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// The shared shopping and to-do list. A fake repository records each write and answers the
// streams from fixed lists; the rules these writes must pass are tested on the emulator in
// functions/tests/family_tasks_rules.test.js.

const _me = 'asha@x.com';

TourMember _member(String email, String name,
        {TourRole role = TourRole.member}) =>
    TourMember(
      tourId: 't1',
      email: email,
      displayName: name,
      role: role,
      status: TourMemberStatus.active,
      joinedAt: DateTime.utc(2026, 1, 1),
    );

class _FakeFamilyRepo extends TourGroupRepository {
  _FakeFamilyRepo({required this.tasks, required this.members});

  final List<FamilyTask> tasks;
  final List<TourMember> members;
  final List<String> calls = [];
  Stream<List<FamilyTask>>? failFirstLoad;
  Object? addError;
  bool addSynced = true;
  int watchCount = 0;

  @override
  String get currentEmail => _me;

  @override
  Stream<List<TourMember>> watchMembers(String tourId) => Stream.value(members);

  @override
  Stream<List<FamilyTask>> watchFamilyTasks(String tourId) {
    watchCount++;
    final failing = failFirstLoad;
    if (failing != null && watchCount == 1) return failing;
    return Stream.value(tasks);
  }

  @override
  Future<void> forgetFamilyTasks(String tourId) async {
    calls.add('forget');
  }

  @override
  Future<bool> addFamilyTask(
    String tourId, {
    required String title,
    required FamilyTaskKind kind,
    String? assigneeEmail,
  }) async {
    calls.add('add $title ${kind.name} ${assigneeEmail ?? 'anyone'}');
    final error = addError;
    if (error != null) throw error;
    return addSynced;
  }

  @override
  Future<bool> setFamilyTaskDone(
      String tourId, String taskId, bool done) async {
    calls.add('tick $taskId $done');
    return true;
  }

  @override
  Future<bool> renameFamilyTask(
      String tourId, String taskId, String title) async {
    calls.add('rename $taskId $title');
    return true;
  }

  @override
  Future<bool> reassignFamilyTask(
    String tourId,
    String taskId,
    String? assigneeEmail,
  ) async {
    calls.add('assign $taskId ${assigneeEmail ?? 'anyone'}');
    return true;
  }

  @override
  Future<bool> setFamilyTaskKind(
    String tourId,
    String taskId,
    FamilyTaskKind kind,
  ) async {
    calls.add('kind $taskId ${kind.name}');
    return true;
  }

  @override
  Future<bool> deleteFamilyTask(String tourId, String taskId) async {
    calls.add('delete $taskId');
    return true;
  }

  @override
  Future<bool> clearFamilyTasks(String tourId, List<String> taskIds) async {
    calls.add('clear ${taskIds.join(',')}');
    return true;
  }
}

Future<void> _pump(WidgetTester tester, Widget page) async {
  // A new key gives each page its own app, so a second page in one test is not stuck on the first.
  await tester.pumpWidget(MaterialApp(
    key: UniqueKey(),
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: page,
  ));
  await tester.pumpAndSettle();
}

TextEditingController _draftOf(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!;

void main() {
  testWidgets(
      'lists open items by kind and ticked ones last, with names and never an address',
      (tester) async {
    final repo = _FakeFamilyRepo(
      members: [_member(_me, 'Asha'), _member('babu@x.com', 'Babu')],
      tasks: [
        FamilyTask(
          id: 'a',
          title: 'Rice',
          kind: FamilyTaskKind.shopping,
          createdByEmail: _me,
          assigneeEmail: 'babu@x.com',
          createdAt: DateTime.utc(2026, 11, 1),
        ),
        FamilyTask(
          id: 'b',
          title: 'Milk',
          kind: FamilyTaskKind.shopping,
          done: true,
          createdByEmail: 'babu@x.com',
          doneByEmail: 'babu@x.com',
          doneAt: DateTime.utc(2026, 11, 2),
        ),
        FamilyTask(
          id: 'c',
          title: 'Soap',
          kind: FamilyTaskKind.shopping,
          createdByEmail: 'gone@x.com',
          assigneeEmail: 'gone@x.com',
          createdAt: DateTime.utc(2026, 11, 3),
        ),
      ],
    );

    await _pump(tester, FamilyTasksScreen(tourId: 't1', repository: repo));

    expect(find.text('To buy'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('For Babu'), findsOneWidget);
    expect(find.text('For Former member'), findsOneWidget);
    expect(find.text('Ticked by Babu'), findsOneWidget);
    expect(find.textContaining('@'), findsNothing);

    final rice = tester.getTopLeft(find.text('Rice')).dy;
    final soap = tester.getTopLeft(find.text('Soap')).dy;
    final milk = tester.getTopLeft(find.text('Milk')).dy;
    expect(rice, lessThan(soap));
    expect(soap, lessThan(milk));
  });

  testWidgets(
      'an empty list offers suggestions, and a suggestion adds its item and keeps the draft',
      (tester) async {
    final repo =
        _FakeFamilyRepo(members: [_member(_me, 'Asha')], tasks: const []);
    await _pump(tester, FamilyTasksScreen(tourId: 't1', repository: repo));

    expect(find.text('Shopping list is empty'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Half a draft');
    await tester.tap(find.text('Groceries'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['add Groceries shopping anyone']);
    expect(_draftOf(tester).text, 'Half a draft');
  });

  testWidgets('a typed item is added, and the box is cleared once it is saved',
      (tester) async {
    final repo =
        _FakeFamilyRepo(members: [_member(_me, 'Asha')], tasks: const []);
    await _pump(tester, FamilyTasksScreen(tourId: 't1', repository: repo));

    await tester.enterText(find.byType(TextField), 'Salt');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(repo.calls, ['add Salt shopping anyone']);
    expect(_draftOf(tester).text, isEmpty);
  });

  testWidgets('a member at the day limit is told so, and keeps the draft',
      (tester) async {
    final repo =
        _FakeFamilyRepo(members: [_member(_me, 'Asha')], tasks: const [])
          ..addError = const FamilyTaskDailyLimitException();
    await _pump(tester, FamilyTasksScreen(tourId: 't1', repository: repo));

    await tester.enterText(find.byType(TextField), 'Salt');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(
      find.text('You can add up to 200 items a day. Try again tomorrow.'),
      findsOneWidget,
    );
    expect(_draftOf(tester).text, 'Salt');
  });

  testWidgets(
      'an add the server has not confirmed yet says it is saved on this phone',
      (tester) async {
    final repo =
        _FakeFamilyRepo(members: [_member(_me, 'Asha')], tasks: const [])
          ..addSynced = false;
    await _pump(tester, FamilyTasksScreen(tourId: 't1', repository: repo));

    await tester.enterText(find.byType(TextField), 'Salt');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(
      find.text(
          'Saved on this phone. It reaches the others when you are online.'),
      findsOneWidget,
    );
    expect(_draftOf(tester).text, isEmpty);
  });

  testWidgets('a list that fails to load offers a retry, which listens again',
      (tester) async {
    final repo = _FakeFamilyRepo(
        members: [_member(_me, 'Asha')], tasks: const [])
      ..failFirstLoad = Stream<List<FamilyTask>>.error(StateError('offline'));
    await _pump(tester, FamilyTasksScreen(tourId: 't1', repository: repo));

    expect(find.text('Could not load the list. Check your connection.'),
        findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['forget']);
    expect(repo.watchCount, 2);
    expect(find.text('Shopping list is empty'), findsOneWidget);
  });

  testWidgets(
      'a member changes only the items they added, and an admin changes any item',
      (tester) async {
    final tasks = [
      const FamilyTask(
          id: 'mine',
          title: 'Mine',
          kind: FamilyTaskKind.shopping,
          createdByEmail: _me),
      const FamilyTask(
        id: 'theirs',
        title: 'Theirs',
        kind: FamilyTaskKind.shopping,
        createdByEmail: 'babu@x.com',
      ),
    ];

    final member = _FakeFamilyRepo(
      members: [_member(_me, 'Asha'), _member('babu@x.com', 'Babu')],
      tasks: tasks,
    );
    await _pump(tester, FamilyTasksScreen(tourId: 't1', repository: member));
    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);

    final admin = _FakeFamilyRepo(
      members: [
        _member(_me, 'Asha', role: TourRole.admin),
        _member('babu@x.com', 'Babu')
      ],
      tasks: tasks,
    );
    await _pump(tester, FamilyTasksScreen(tourId: 't1', repository: admin));
    expect(find.byIcon(Icons.more_vert_rounded), findsNWidgets(2));
  });

  testWidgets(
      'the item menu moves an item to the to-do list and gives it to a member',
      (tester) async {
    final repo = _FakeFamilyRepo(
      members: [_member(_me, 'Asha'), _member('babu@x.com', 'Babu')],
      tasks: [
        const FamilyTask(
            id: 'x1',
            title: 'Rice',
            kind: FamilyTaskKind.shopping,
            createdByEmail: _me),
      ],
    );
    await _pump(tester, FamilyTasksScreen(tourId: 't1', repository: repo));

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to to do'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['kind x1 todo']);

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Give to'));
    await tester.pumpAndSettle();
    expect(find.text('Give this item to'), findsOneWidget);
    await tester.tap(find.text('Babu'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['kind x1 todo', 'assign x1 babu@x.com']);
  });

  testWidgets(
      'the item menu renames an item, and removal waits for a confirmation',
      (tester) async {
    final repo = _FakeFamilyRepo(
      members: [_member(_me, 'Asha')],
      tasks: [
        const FamilyTask(
            id: 'x1',
            title: 'Rice',
            kind: FamilyTaskKind.shopping,
            createdByEmail: _me),
      ],
    );
    await _pump(tester, FamilyTasksScreen(tourId: 't1', repository: repo));

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Basmati',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['rename x1 Basmati']);

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove this item?'), findsOneWidget);
    expect(repo.calls, ['rename x1 Basmati']);

    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['rename x1 Basmati', 'delete x1']);
  });

  testWidgets(
      'clear finished removes only the finished items the member may remove',
      (tester) async {
    final repo = _FakeFamilyRepo(
      members: [_member(_me, 'Asha'), _member('babu@x.com', 'Babu')],
      tasks: [
        FamilyTask(
          id: 'a',
          title: 'Milk',
          kind: FamilyTaskKind.shopping,
          done: true,
          createdByEmail: _me,
          doneByEmail: _me,
          doneAt: DateTime.utc(2026, 11, 2),
        ),
        FamilyTask(
          id: 'b',
          title: 'Eggs',
          kind: FamilyTaskKind.shopping,
          done: true,
          createdByEmail: 'babu@x.com',
          doneByEmail: 'babu@x.com',
          doneAt: DateTime.utc(2026, 11, 3),
        ),
      ],
    );
    await _pump(tester, FamilyTasksScreen(tourId: 't1', repository: repo));

    await tester.tap(find.text('Clear finished'));
    await tester.pumpAndSettle();
    expect(
      find.text(
          'Finished items you added will be removed: 1. Items others added stay.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Clear finished'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['clear a']);
  });

  testWidgets('a list above 500 items says it is getting long', (tester) async {
    final repo = _FakeFamilyRepo(
      members: [_member(_me, 'Asha')],
      tasks: [
        for (var i = 0; i <= familyTaskLongListAt; i++)
          FamilyTask(
              id: 'i$i', title: 'Item $i', kind: FamilyTaskKind.shopping),
      ],
    );
    await _pump(tester, FamilyTasksScreen(tourId: 't1', repository: repo));

    expect(find.textContaining('getting long'), findsOneWidget);
  });

  testWidgets(
      'the scope sheet says which circles have the list, and which do not',
      (tester) async {
    final repo =
        _FakeFamilyRepo(members: [_member(_me, 'Asha')], tasks: const []);
    await _pump(tester, FamilyTasksScreen(tourId: 't1', repository: repo));

    await tester.tap(find.byTooltip('Scope & help'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Offices and campuses do not have this list'),
        findsOneWidget);
  });

  test('every key the family list uses is written in English and in Bengali',
      () {
    const keys = [
      'ft_title',
      'ft_add_hint',
      'ft_kind_shopping',
      'ft_kind_todo',
      'ft_for_label',
      'ft_anyone',
      'ft_for',
      'ft_ticked_by',
      'ft_section_shopping',
      'ft_section_todo',
      'ft_section_done',
      'ft_rename_title',
      'ft_edit',
      'ft_remove',
      'ft_delete_title',
      'ft_delete_body',
      'ft_save_failed',
      'ft_load_failed',
      'ft_untitled',
      'ft_former_member',
      'ft_unnamed',
      'ft_saved_offline',
      'ft_limit_reached',
      'ft_try_again',
      'ft_item_options',
      'ft_assign_action',
      'ft_assign_title',
      'ft_move_to_buy',
      'ft_move_to_todo',
      'ft_clear_done',
      'ft_clear_done_title',
      'ft_clear_done_body',
      'ft_long_list',
      'ft_scope_tooltip',
      'ft_scope_subtitle',
      'ft_scope_title',
      'ft_scope_shopping_title',
      'ft_scope_shopping_body',
      'ft_scope_chores_title',
      'ft_scope_chores_body',
      'ft_scope_members_title',
      'ft_scope_members_body',
      'ft_scope_events_title',
      'ft_scope_events_body',
      'ft_scope_excluded',
      'ft_got_it',
      'ft_cancel',
      'ft_save',
      'ft_send',
      'ft_suggest_shopping_1',
      'ft_suggest_shopping_2',
      'ft_suggest_shopping_3',
      'ft_suggest_shopping_4',
      'ft_suggest_shopping_5',
      'ft_suggest_todo_1',
      'ft_suggest_todo_2',
      'ft_suggest_todo_3',
      'ft_suggest_todo_4',
      'ft_suggest_todo_5',
      'ft_empty_shopping_title',
      'ft_empty_shopping_body',
      'ft_empty_todo_title',
      'ft_empty_todo_body',
    ];
    for (final locale in const ['en', 'bn']) {
      final l10n = AppLocalizations(Locale(locale));
      for (final key in keys) {
        expect(l10n.translate(key), isNot(key), reason: '$key in $locale');
        expect(l10n.translate(key), isNotEmpty, reason: '$key in $locale');
      }
    }
  });
}
