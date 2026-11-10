import '../models/study_subject_models.dart';

/// Which modules a viewer sees, in catalogue order. An admin sees every module, so an admin can
/// turn one on. A member sees only the modules that are on.
List<StudyModuleKey> visibleStudyModules({
  required Map<StudyModuleKey, StudyModuleSettings> settings,
  required bool isAdmin,
}) =>
    [
      for (final key in StudyModuleKey.values)
        if (isAdmin || (settings[key]?.enabled ?? false)) key,
    ];

/// Whether a member may post in a module. Anyone may post in a module that is on, unless it
/// is for admins only. An admin may post in any module that is on.
bool canPostInStudyModule({
  required StudyModuleSettings? settings,
  required bool isAdmin,
}) =>
    settings != null &&
    settings.enabled &&
    (isAdmin || settings.postPolicy != StudyPostPolicy.admins);

/// Whether a new post is shown at once. An admin's post always is. A member's post is shown
/// at once only when the module lets members post directly.
bool postShownAtOnce({
  required StudyModuleSettings settings,
  required bool isAdmin,
}) =>
    isAdmin || settings.postPolicy == StudyPostPolicy.members;

/// The posts a viewer can see: every shown post, plus a post still waiting for an admin when
/// the viewer wrote it or is an admin.
List<StudyPost> visibleStudyPosts({
  required List<StudyPost> posts,
  required String viewerEmail,
  required bool isAdmin,
}) =>
    [
      for (final post in posts)
        if (post.shown || isAdmin || post.createdByEmail == viewerEmail) post,
    ];

/// Posts in reading order: pinned first, then the most helpful, then the newest. A post whose
/// time is not yet known comes first, since it was just written.
List<StudyPost> sortStudyPosts(List<StudyPost> posts) {
  final sorted = [...posts];
  sorted.sort((a, b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    if (a.helpfulCount != b.helpfulCount) {
      return b.helpfulCount.compareTo(a.helpfulCount);
    }
    final ta = a.createdAt;
    final tb = b.createdAt;
    if (ta == null && tb == null) return 0;
    if (ta == null) return -1;
    if (tb == null) return 1;
    return tb.compareTo(ta);
  });
  return sorted;
}

/// The subjects sorted by title, ignoring case.
List<StudySubject> studySubjectsByTitle(Iterable<StudySubject> subjects) =>
    subjects.toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

/// The subjects the group studies: listed and not archived. Members see only these, and so
/// does the exam countdown on the Today card. A proposal waits for an admin, and an archived
/// subject is hidden until an admin restores it.
List<StudySubject> activeStudySubjects(Iterable<StudySubject> subjects) =>
    subjects.where((subject) => subject.isListed && !subject.archived).toList();

/// The subjects an admin has archived, by title. Only an admin sees them, to restore them.
List<StudySubject> archivedStudySubjects(Iterable<StudySubject> subjects) =>
    studySubjectsByTitle(subjects.where((subject) => subject.archived));

/// Whole calendar days from [today] to [examDate], counted on dates only. Negative when the
/// exam has already passed, and zero on the day itself.
int daysUntilExam(DateTime examDate, DateTime today) {
  final exam = DateTime(examDate.year, examDate.month, examDate.day);
  final now = DateTime(today.year, today.month, today.day);
  return exam.difference(now).inDays;
}
