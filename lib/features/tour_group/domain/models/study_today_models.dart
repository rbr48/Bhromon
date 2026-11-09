/// A chapter that is due, with the title of its book, for the Today card. Only chapters the
/// member has not marked read are listed.
class StudyDeadline {
  const StudyDeadline({
    required this.chapterId,
    required this.bookTitle,
    required this.chapterTitle,
    required this.dueOn,
  });

  final String chapterId;
  final String bookTitle;
  final String chapterTitle;

  /// The day the chapter is due.
  final DateTime dueOn;
}
