import '../../../domain/models/study_models.dart';
import '../../../domain/models/study_subject_models.dart';

/// The translation key of a book's status, which is also the title of its section in the
/// book list.
String studyBookStatusKey(StudyBookStatus status) => switch (status) {
      StudyBookStatus.toRead => 'study_book_status_to_read',
      StudyBookStatus.reading => 'study_book_status_reading',
      StudyBookStatus.finished => 'study_book_status_finished',
    };

/// The translation key of a module's default name. The group sees it until an admin renames
/// the module.
String studyModuleLabelKey(StudyModuleKey key) => switch (key) {
      StudyModuleKey.tips => 'study_module_tips',
      StudyModuleKey.suggestions => 'study_module_suggestions',
      StudyModuleKey.discussion => 'study_module_discussion',
      StudyModuleKey.findings => 'study_module_findings',
      StudyModuleKey.problems => 'study_module_problems',
      StudyModuleKey.papers => 'study_module_papers',
      StudyModuleKey.plan => 'study_module_plan',
      StudyModuleKey.glossary => 'study_module_glossary',
      StudyModuleKey.assignments => 'study_module_assignments',
      StudyModuleKey.challenges => 'study_module_challenges',
      StudyModuleKey.flashcards => 'study_module_flashcards',
    };

/// The translation key of a posting policy, as the module sheet names it.
String studyPolicyKey(StudyPostPolicy policy) => switch (policy) {
      StudyPostPolicy.members => 'study_policy_members',
      StudyPostPolicy.admins => 'study_policy_admins',
      StudyPostPolicy.approval => 'study_policy_approval',
    };
