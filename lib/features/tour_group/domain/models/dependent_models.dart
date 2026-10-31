// A person in a family who has no account of their own, such as a child or a
// grandparent. A member lists them under their own email, and they count toward
// that member's family size. Stored under tours/{id}/dependents.

const int kMaxDependentNameLength = 60;
const int kMaxDependentRelationLength = 30;

class Dependent {
  const Dependent({
    required this.id,
    required this.name,
    required this.parentEmail,
    this.relation = '',
    this.countedInFamily = false,
  });

  final String id;
  final String name;

  /// The member who listed this person. Only they change or remove the entry.
  final String parentEmail;

  /// What they are to the member, such as "son" or "mother". Optional.
  final String relation;

  /// Whether adding this person raised the member's family size, so removing
  /// them lowers it again. A member already at the largest size is not raised.
  final bool countedInFamily;

  Map<String, dynamic> toFields() => {
        'name': name,
        'relation': relation,
        'parentEmail': parentEmail,
        'countedInFamily': countedInFamily,
      };

  /// Reads one stored entry. Returns null when it has no name or no parent.
  static Dependent? fromMap(String id, Map<String, dynamic> map) {
    final name = (map['name'] as String?)?.trim() ?? '';
    final parent = (map['parentEmail'] as String?) ?? '';
    if (name.isEmpty || parent.isEmpty) return null;
    return Dependent(
      id: id,
      name: name,
      parentEmail: parent,
      relation: ((map['relation'] as String?) ?? '').trim(),
      countedInFamily: map['countedInFamily'] == true,
    );
  }
}
