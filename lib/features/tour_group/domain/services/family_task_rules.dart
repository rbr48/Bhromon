import '../models/family_task_models.dart';

/// The sections of the shared list, in the order they show.
enum FamilyTaskSection { shopping, todo, done }

/// Splits the items into sections. Open items come first, sorted by their text,
/// and the items already ticked off come last. Empty sections are left out.
List<({FamilyTaskSection section, List<FamilyTask> items})> familyTaskSections(
  List<FamilyTask> tasks,
) {
  int byTitle(FamilyTask a, FamilyTask b) =>
      a.title.toLowerCase().compareTo(b.title.toLowerCase());

  final shopping = [
    for (final t in tasks)
      if (!t.done && t.kind == FamilyTaskKind.shopping) t,
  ]..sort(byTitle);
  final todo = [
    for (final t in tasks)
      if (!t.done && t.kind == FamilyTaskKind.todo) t,
  ]..sort(byTitle);
  final done = [
    for (final t in tasks)
      if (t.done) t,
  ]..sort(byTitle);

  return [
    if (shopping.isNotEmpty)
      (section: FamilyTaskSection.shopping, items: shopping),
    if (todo.isNotEmpty) (section: FamilyTaskSection.todo, items: todo),
    if (done.isNotEmpty) (section: FamilyTaskSection.done, items: done),
  ];
}
