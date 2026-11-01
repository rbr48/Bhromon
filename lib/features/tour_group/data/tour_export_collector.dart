import '../domain/models/expense_models.dart';
import '../domain/models/logistics_models.dart';
import '../domain/models/safety_alert_models.dart';
import '../domain/models/tour_activity_models.dart';
import '../domain/models/tour_export_data.dart';
import '../domain/models/tour_group.dart';
import '../domain/models/tour_post_models.dart';
import '../domain/models/vehicle_models.dart';
import 'tour_group_repository.dart';

/// Reads everything the PDF export shows, one part of the tour at a time. Posts
/// are read in full (the feed only shows the newest page), and each post's
/// comments come with them.
class TourExportCollector {
  TourExportCollector(this._repository);

  static const int _parallelReads = 8;

  final TourGroupRepository _repository;

  Future<T> _safe<T>(
    Stream<T> stream, {
    required T fallback,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    try {
      return await stream.first.timeout(timeout);
    } catch (_) {
      return fallback;
    }
  }

  /// [onPosts] reports how many posts have had their comments read, out of all.
  Future<TourExportData> collect(
    TourGroup group, {
    void Function(int done, int total)? onPosts,
  }) async {
    final id = group.id;
    final latest = await _repository
            .getGroup(id)
            .timeout(
              const Duration(seconds: 8),
              onTimeout: () => group,
            )
            .catchError((_) => group) ??
        group;
    final members = await _safe(_repository.watchMembers(id),
        fallback: const <TourMember>[]);
    final notices = await _safe(_repository.watchNotices(id),
        fallback: const <TourNotice>[]);
    final checkpoints = await _safe(_repository.watchCheckpoints(id),
        fallback: const <RouteCheckpoint>[]);
    final savedChecklist = await _safe(_repository.watchChecklist(id),
        fallback: const <ChecklistItem>[]);
    final byId = {for (final item in savedChecklist) item.id: item};
    final tourType = latest.tourType;
    final isBeach = tourType == TourType.beach ||
        tourType == TourType.heritage ||
        tourType == TourType.custom;
    final isHill = tourType == TourType.hill || tourType == TourType.custom;
    final isNature = tourType == TourType.nature || tourType == TourType.custom;

    final checklist = <ChecklistItem>[];
    for (var i = 0; i < checklistDefaultItems.length; i++) {
      final def = checklistDefaultItems[i];
      if (!isBeach && def.category == 'check_cat_beach') continue;
      if (!isHill && def.category == 'check_cat_hill') continue;
      if (!isNature && def.category == 'check_cat_nature') continue;
      final defId = 'default_$i';
      final existing = byId[defId];
      checklist.add(ChecklistItem(
        id: defId,
        title: def.title,
        category: def.category,
        checkedBy: existing?.checkedBy ?? const [],
      ));
    }
    for (final item in savedChecklist) {
      if (!item.id.startsWith('default_')) {
        checklist.add(item);
      }
    }
    final expenses = await _safe(_repository.watchExpenses(id),
        fallback: const <ExpenseItem>[]);
    final deposits = await _safe(_repository.watchDeposits(id),
        fallback: const <DepositItem>[]);
    final transfers = await _safe(_repository.watchTransfers(id),
        fallback: const <TransferItem>[]);
    final vehicles = await _safe(_repository.watchVehicles(id),
        fallback: const <TourVehicle>[]);
    final vehicleSeats = <String, List<BusSeat>>{};
    for (final vehicle in vehicles) {
      vehicleSeats[vehicle.id] = await _safe(
        _repository.watchSeatsOf(id, vehicle.id),
        fallback: const <BusSeat>[],
      );
    }
    final coachSeats = await _safe(_repository.watchCoachSeats(id),
        fallback: const <BusSeat>[]);
    final hotelRooms = await _safe(_repository.watchHotelRooms(id),
        fallback: const <HotelRoom>[]);
    final safetyAlerts = await _safe(
      _repository.watchSafetyAlerts(id, limit: 1000),
      fallback: const <SafetyAlert>[],
    );
    final stories = await _safe(_repository.watchStories(id),
        fallback: const <TourStoryItem>[]);
    final highlights = await _safe(_repository.watchHighlights(id),
        fallback: const <TourStoryHighlight>[]);

    List<TourPostItem> posts = const [];
    try {
      posts = await _repository.fetchAllPostsForExport(id).timeout(
            const Duration(seconds: 25),
            onTimeout: () => const [],
          );
    } catch (_) {
      posts = const [];
    }

    final comments = <String, List<TourCommentItem>>{};
    for (var i = 0; i < posts.length; i += _parallelReads) {
      final chunk = posts.skip(i).take(_parallelReads).toList();
      final results = await Future.wait(
        chunk.map((post) async {
          try {
            return await _repository
                .fetchCommentsForExport(id, post.id)
                .timeout(const Duration(seconds: 8), onTimeout: () => const []);
          } catch (_) {
            return const <TourCommentItem>[];
          }
        }),
      );
      for (var j = 0; j < chunk.length; j++) {
        comments[chunk[j].id] = results[j];
      }
      onPosts?.call(i + chunk.length, posts.length);
    }

    return TourExportData(
      group: latest,
      exportedAt: DateTime.now(),
      members: members,
      notices: notices,
      checkpoints: checkpoints,
      checklist: checklist,
      expenses: expenses,
      deposits: deposits,
      transfers: transfers,
      vehicles: vehicles,
      vehicleSeats: vehicleSeats,
      coachSeats: coachSeats,
      hotelRooms: hotelRooms,
      safetyAlerts: safetyAlerts,
      posts: posts,
      comments: comments,
      stories: stories,
      highlights: highlights,
    );
  }
}
