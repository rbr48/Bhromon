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

/// How many threads a member started on the calendar day of [now].
int threadsStartedToday(
  Iterable<StudyThread> threads, {
  required String email,
  required DateTime now,
}) {
  var count = 0;
  for (final thread in threads) {
    final at = thread.createdAt;
    if (thread.createdByEmail != email || at == null) continue;
    if (at.year == now.year && at.month == now.month && at.day == now.day) {
      count++;
    }
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
