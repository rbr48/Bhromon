import '../models/study_thread_models.dart';

/// The most threads an admin can pin in one book.
const int kPinnedThreadMax = 3;

/// The most threads a member can start in one day. The limit is set after the first book,
/// so it lives here and not in the rules.
const int kThreadsPerDayMax = 10;

/// Threads in reading order: pinned first, then the newest. A thread whose time is not yet
/// known comes first, since it was just started.
List<StudyThread> sortStudyThreads(Iterable<StudyThread> threads) {
  final sorted = threads.toList();
  sorted.sort((a, b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    final ta = a.createdAt;
    final tb = b.createdAt;
    if (ta == null && tb == null) return 0;
    if (ta == null) return -1;
    if (tb == null) return 1;
    return tb.compareTo(ta);
  });
  return sorted;
}

/// The threads in the order a conversation reads: pinned ones first, as [sortStudyThreads] has
/// them, then the rest oldest first, so the newest is last and a chat opens at it.
List<StudyThread> chatOrderStudyThreads(Iterable<StudyThread> threads) {
  final sorted = sortStudyThreads(threads);
  return [
    for (final thread in sorted)
      if (thread.pinned) thread,
    for (final thread in sorted.reversed)
      if (!thread.pinned) thread,
  ];
}

/// The longest first line a thread takes as its title. A longer line is cut at a word and ends
/// with an ellipsis; the whole text is still the question.
const int kThreadTitleMax = 80;

/// The title and question of a thread started from the chat box. The first line of the text is
/// the title, and the whole text, trimmed, is the question. A blank text gives a blank title and
/// question, which the caller refuses.
({String title, String body}) threadTitleAndBody(String text) {
  final body = text.trim();
  final firstLine = body.split('\n').first.trim();
  return (title: _cutAtWord(firstLine, kThreadTitleMax), body: body);
}

String _cutAtWord(String line, int max) {
  if (line.length <= max) return line;
  final space = line.lastIndexOf(' ', max);
  final end = space > 0 ? space : max;
  return '${line.substring(0, end).trimRight()}…';
}

/// The threads whose title or body contains the query, ignoring case. An empty query keeps
/// every thread. The search runs only over the threads already loaded.
List<StudyThread> searchStudyThreads(
  Iterable<StudyThread> threads,
  String query,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return threads.toList();
  return [
    for (final thread in threads)
      if (thread.title.toLowerCase().contains(needle) ||
          thread.body.toLowerCase().contains(needle))
        thread,
  ];
}

/// Whether a thread is past the member's place in the book, so it waits behind the fence. A
/// thread on a chapter later than the place is behind it. Without a place, nothing is behind
/// the fence, and neither is a thread about the whole book.
bool isBehindFence(
  StudyThread thread, {
  required Map<String, int> chapterNumberById,
  required int? place,
}) {
  final chapterId = thread.chapterId;
  if (place == null || chapterId == null) return false;
  final number = chapterNumberById[chapterId];
  return number != null && number > place;
}

/// The day a member's threads are counted on, as a number: the calendar day in Dhaka (UTC+6, with no daylight saving),
/// so 20261111. The server counts on the same day from its own clock (studyDayKey in firestore.rules).
int threadDayKey(DateTime now) {
  final dhaka = now.toUtc().add(const Duration(hours: 6));
  return dhaka.year * 10000 + dhaka.month * 100 + dhaka.day;
}

/// How many threads a member started on the Dhaka day of [now].
int threadsStartedToday(
  Iterable<StudyThread> threads, {
  required String email,
  required DateTime now,
}) {
  final today = threadDayKey(now);
  var count = 0;
  for (final thread in threads) {
    final at = thread.createdAt;
    if (thread.createdByEmail != email || at == null) continue;
    if (threadDayKey(at) == today) count++;
  }
  return count;
}

/// Whether a member may start another thread today.
bool canStartThreadToday(
  Iterable<StudyThread> threads, {
  required String email,
  required DateTime now,
}) =>
    threadsStartedToday(threads, email: email, now: now) < kThreadsPerDayMax;

/// Whether an admin may pin one more thread in the book.
bool canPinMoreThreads(Iterable<StudyThread> threads) =>
    threads.where((t) => t.pinned).length < kPinnedThreadMax;

/// Replies in the order they were written, oldest first. A reply whose time is not yet known
/// comes last, since it was just written.
List<StudyReply> sortStudyReplies(Iterable<StudyReply> replies) {
  final sorted = replies.toList();
  sorted.sort((a, b) {
    final ta = a.createdAt;
    final tb = b.createdAt;
    if (ta == null && tb == null) return 0;
    if (ta == null) return 1;
    if (tb == null) return -1;
    return ta.compareTo(tb);
  });
  return sorted;
}

/// Whether a viewer sees a reply. A reported reply is hidden from members other than its
/// author; an admin sees every reply.
bool isReplyVisibleTo(
  StudyReply reply, {
  required String viewerEmail,
  required bool isAdmin,
}) =>
    !reply.isReported || isAdmin || reply.createdByEmail == viewerEmail;

/// Whether a viewer may accept a reply: the member who asked, or an admin on their behalf.
bool canAcceptAnswer(
  StudyThread thread, {
  required String viewerEmail,
  required bool isAdmin,
}) =>
    isAdmin || thread.createdByEmail == viewerEmail;

/// Whether a member may reply to a thread. A locked thread takes no more replies.
bool canReplyTo(StudyThread thread) => !thread.locked;

/// Whether a viewer may mark a reply helpful or report it. Nobody votes on their own reply.
bool canVoteOnReply(StudyReply reply, {required String viewerEmail}) =>
    reply.createdByEmail != viewerEmail;
