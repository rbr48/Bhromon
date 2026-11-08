import '../../../domain/models/study_models.dart';

/// The translation key of a book's status, which is also the title of its section in the
/// book list.
String studyBookStatusKey(StudyBookStatus status) => switch (status) {
      StudyBookStatus.toRead => 'study_book_status_to_read',
      StudyBookStatus.reading => 'study_book_status_reading',
      StudyBookStatus.finished => 'study_book_status_finished',
    };
