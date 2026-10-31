/// The largest family size a member can set. The family size picker, the
/// ledger weights and the seat planner all use the same 1 to 20.
const int kMaxFamilySize = 20;

/// The family size after a dependent is added. It goes up by one, unless the
/// member is already at the largest size, and then [counted] is false, so
/// removing the person later will not lower it.
({int size, bool counted}) familySizeWithDependent(int current) {
  final size = current.clamp(1, kMaxFamilySize);
  return size < kMaxFamilySize
      ? (size: size + 1, counted: true)
      : (size: size, counted: false);
}

/// The family size after a dependent is removed. A person who was counted lowers
/// it by one, and it never falls below one. A person who was not counted changes
/// nothing.
int familySizeWithoutDependent(int current, {required bool counted}) {
  final size = current.clamp(1, kMaxFamilySize);
  return counted && size > 1 ? size - 1 : size;
}
