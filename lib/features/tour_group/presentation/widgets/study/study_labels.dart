import '../../../domain/models/study_challenge_models.dart';
import '../../../domain/models/study_models.dart';
import '../../../domain/models/study_subject_models.dart';

/// The translation key of a challenge's kind, as the editor names it.
String challengeKindKey(ChallengeKind kind) => switch (kind) {
      ChallengeKind.problems => 'study_challenge_kind_problems',
      ChallengeKind.findings => 'study_challenge_kind_findings',
      ChallengeKind.cards => 'study_challenge_kind_cards',
    };

/// The translation key of a challenge's task sentence. The sentence takes the number of tasks.
String challengeTaskKey(ChallengeKind kind) => switch (kind) {
      ChallengeKind.problems => 'study_challenge_task_problems',
      ChallengeKind.findings => 'study_challenge_task_findings',
      ChallengeKind.cards => 'study_challenge_task_cards',
    };

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
      StudyModuleKey.quizzes => 'study_module_quizzes',
    };

/// The translation key of a posting policy, as the module sheet names it.
String studyPolicyKey(StudyPostPolicy policy) => switch (policy) {
      StudyPostPolicy.members => 'study_policy_members',
      StudyPostPolicy.admins => 'study_policy_admins',
      StudyPostPolicy.approval => 'study_policy_approval',
    };
