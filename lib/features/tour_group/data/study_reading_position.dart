import 'package:hive/hive.dart';

/// Where a member is in a book, kept on this device only. It is the number of the chapter
/// the member is on, and it is never sent to the group or stored in the database, so nobody
/// else can see it. A failure to read or write it leaves the list as it was.
///
/// The same box keeps the member's choice of whether to hide threads from later chapters (the
/// fence). That choice is on by default, and it stays on this device too.
class StudyReadingPosition {
  static const _boxName = 'study_positions';
  static const _fenceKey = 'fence_hide_later_chapters';

  /// The chapter number the member is on in [bookId], or null when they have not said.
  Future<int?> load({required String tourId, required String bookId}) async {
    try {
      final box = await _box();
      final saved = box.get(_key(tourId, bookId));
      return saved is int ? saved : null;
    } catch (_) {
      return null;
    }
  }

  /// Saves the chapter the member is on. Null clears it.
  Future<void> save({
    required String tourId,
    required String bookId,
    required int? chapterNumber,
  }) async {
    try {
      final box = await _box();
      final key = _key(tourId, bookId);
      if (chapterNumber == null) {
        await box.delete(key);
      } else {
        await box.put(key, chapterNumber);
      }
    } catch (_) {
      // Best effort: the member can mark their place again.
    }
  }

  /// Whether threads from later chapters are hidden. True unless the member has turned it off.
  Future<bool> loadFence() async {
    try {
      final box = await _box();
      final saved = box.get(_fenceKey);
      return saved is bool ? saved : true;
    } catch (_) {
      return true;
    }
  }

  /// Saves whether threads from later chapters are hidden.
  Future<void> saveFence(bool hide) async {
    try {
      final box = await _box();
      await box.put(_fenceKey, hide);
    } catch (_) {
      // Best effort: the fence comes back on next time.
    }
  }

  Future<Box<dynamic>> _box() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box<dynamic>(_boxName);
    return Hive.openBox<dynamic>(_boxName);
  }

  String _key(String tourId, String bookId) => '$tourId|$bookId';
}
