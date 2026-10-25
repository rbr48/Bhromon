import 'dart:async';

import '../domain/models/tour_post_models.dart';
import 'tour_group_repository.dart';

/// The posts of a tour, newest first, in pages of [pageSize].
///
/// Each page is a live query over a range of creation times, and the ranges
/// meet exactly at each boundary. A post added or deleted anywhere in the feed
/// therefore shows at once, pages never overlap or leave a gap, and each page
/// is read once instead of the whole feed being re-read on every "load more".
class PagedPostFeed {
  PagedPostFeed({
    required TourGroupRepository repository,
    required String tourId,
    this.pageSize = 60,
  })  : _repository = repository,
        _tourId = tourId {
    unawaited(_open(upper: null));
  }

  final TourGroupRepository _repository;
  final String _tourId;
  final int pageSize;

  final List<_FeedPage> _pages = [];
  final StreamController<List<TourPostItem>> _out =
      StreamController<List<TourPostItem>>.broadcast();
  bool _busy = false;

  /// The whole feed loaded so far, newest first. Emits after each change.
  Stream<List<TourPostItem>> get stream => _out.stream;

  /// Whether a page older than the loaded ones exists.
  bool get hasMore => _pages.isNotEmpty && _pages.last.lower != null;

  /// Adds the page of posts older than the loaded ones, if there is one.
  Future<void> loadMore() async {
    if (_busy || !hasMore) return;
    _busy = true;
    try {
      await _open(upper: _pages.last.lower);
    } finally {
      _busy = false;
    }
  }

  Future<void> close() async {
    for (final page in _pages) {
      await page.sub?.cancel();
    }
    _pages.clear();
    await _out.close();
  }

  /// Opens the page below [upper] (the newest page when null) and listens to it.
  Future<void> _open({required DateTime? upper}) async {
    try {
      final lower = await _repository.feedPageBoundary(
        _tourId,
        upper: upper,
        limit: pageSize,
      );
      if (_out.isClosed) return;

      final page = _FeedPage(upper: upper, lower: lower);
      _pages.add(page);
      page.sub = _repository
          .watchPostRange(_tourId, upper: upper, lower: lower)
          .listen(
        (posts) {
          page.posts = posts;
          _emit();
        },
        onError: (Object e) {
          if (!_out.isClosed) _out.addError(e);
        },
      );
    } catch (e) {
      if (!_out.isClosed) _out.addError(e);
    }
  }

  void _emit() {
    if (_out.isClosed) return;
    _out.add([for (final page in _pages) ...page.posts]);
  }
}

class _FeedPage {
  _FeedPage({required this.upper, required this.lower});

  /// Posts strictly older than this belong to a newer page. Null for the newest.
  final DateTime? upper;

  /// Posts not older than this belong to this page. Null for the oldest page.
  final DateTime? lower;

  List<TourPostItem> posts = const [];
  StreamSubscription<List<TourPostItem>>? sub;
}
