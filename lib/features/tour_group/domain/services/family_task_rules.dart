import '../models/family_task_models.dart';

/// The sections of a kind's page, in the order they show.
enum FamilyTaskSection { shopping, todo, done }

/// The page for [kind]: its open items, then the items of that kind already ticked off.
/// Empty sections are left out.
List<({FamilyTaskSection section, List<FamilyTask> items})> familyTaskPage(
  List<FamilyTask> tasks,
  FamilyTaskKind kind,
) {
  final open = [
    for (final t in tasks)
      if (!t.done && t.kind == kind) t,
  ]..sort(_addedOrder);
  final done = [
    for (final t in tasks)
      if (t.done && t.kind == kind) t,
  ]..sort(_tickedOrder);
  final section = kind == FamilyTaskKind.shopping
      ? FamilyTaskSection.shopping
      : FamilyTaskSection.todo;

  return [
    if (open.isNotEmpty) (section: section, items: open),
    if (done.isNotEmpty) (section: FamilyTaskSection.done, items: done),
  ];
}

/// The Dhaka day of [now] (UTC+6, with no daylight saving) as a number, such as 20261111.
/// The rules count the same day from the server's clock (familyTaskDayKey in firestore.rules).
int familyTaskDayKey(DateTime now) {
  final dhaka = now.toUtc().add(const Duration(hours: 6));
  return dhaka.year * 10000 + dhaka.month * 100 + dhaka.day;
}

/// The id of a member's counter for the Dhaka day of [now]: `email__20261111`.
String familyTaskCounterId(String email, DateTime now) =>
    '${email}__${familyTaskDayKey(now)}';

/// Whether a member who has already added [count] items today may add another.
bool familyTaskDayFull(int count) => count >= familyTaskDailyLimit;

/// Whether a list of [count] items is long enough for the screen to say so.
bool familyTaskListIsLong(int count) => count > familyTaskLongListAt;

/// Open items, oldest first, so a new item joins the bottom. Items saved before the time was
/// recorded come first, in text order.
int _addedOrder(FamilyTask a, FamilyTask b) {
  final ta = a.createdAt;
  final tb = b.createdAt;
  if (ta == null || tb == null) {
    if (ta == null && tb == null) return _byText(a, b);
    return ta == null ? -1 : 1;
  }
  final byTime = ta.compareTo(tb);
  return byTime != 0 ? byTime : _byText(a, b);
}

/// Ticked items, the latest tick first. Items ticked before the time was recorded come last,
/// in text order.
int _tickedOrder(FamilyTask a, FamilyTask b) {
  final ta = a.doneAt;
  final tb = b.doneAt;
  if (ta == null || tb == null) {
    if (ta == null && tb == null) return _byText(a, b);
    return ta == null ? 1 : -1;
  }
  final byTime = tb.compareTo(ta);
  return byTime != 0 ? byTime : _byText(a, b);
}

/// Text order, ignoring case, then the id, so two items never trade places between builds.
int _byText(FamilyTask a, FamilyTask b) {
  final byText = a.title.toLowerCase().compareTo(b.title.toLowerCase());
  return byText != 0 ? byText : a.id.compareTo(b.id);
}
