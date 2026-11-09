import '../models/study_glossary_models.dart';

// The rules of the glossary: what a term must hold, which terms count as approved, and who may remove one.

/// What is wrong with a term, or null when it is fine.
enum StudyTermProblem {
  emptyTerm,
  termTooLong,
  emptyDefinition,
  definitionTooLong
}

/// Checks a term before it is saved: its word and its definition.
StudyTermProblem? termProblem({
  required String term,
  required String definition,
}) {
  final word = term.trim();
  if (word.isEmpty) return StudyTermProblem.emptyTerm;
  final meaning = definition.trim();
  if (meaning.isEmpty) return StudyTermProblem.emptyDefinition;
  return null;
}

/// The approved terms, sorted A to Z ignoring case. Proposals are left out.
List<StudyGlossaryTerm> approvedTerms(Iterable<StudyGlossaryTerm> terms) {
  final approved = [
    for (final term in terms)
      if (term.approved) term,
  ];
  approved.sort((a, b) => a.term.toLowerCase().compareTo(b.term.toLowerCase()));
  return approved;
}

/// Whether a member may approve a proposed term. Only an admin does.
bool canApproveTerm({required bool isAdmin}) => isAdmin;

/// Whether a member may remove a term: an admin, or the member who proposed it while it is still a proposal.
bool canRemoveTerm(
  StudyGlossaryTerm term, {
  required String viewerEmail,
  required bool isAdmin,
}) {
  if (isAdmin) return true;
  return !term.approved && term.createdByEmail == viewerEmail;
}
