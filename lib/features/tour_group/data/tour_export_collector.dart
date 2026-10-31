import '../domain/models/logistics_models.dart';
import '../domain/models/tour_activity_models.dart';
import '../domain/models/tour_export_data.dart';
import '../domain/models/tour_group.dart';
import '../domain/models/tour_post_models.dart';
import 'tour_group_repository.dart';

/// Reads everything the PDF export shows, one part of the tour at a time. Posts
/// are read in full (the feed only shows the newest page), and each post's
/// comments come with them.
class TourExportCollector {
  TourExportCollector(this._repository);

  static const int _parallelReads = 8;

  final TourGroupRepository _repository;

  /// [onPosts] reports how many posts have had their comments read, out of all.
  Future<TourExportData> collect(
    TourGroup group, {
    void Function(int done, int total)? onPosts,
  }) async {
    final id = group.id;
    final latest = await _repository.getGroup(id) ?? group;
    final members = await _repository.watchMembers(id).first;
    final notices = await _repository.watchNotices(id).first;
    final checkpoints = await _repository.watchCheckpoints(id).first;
    final savedChecklist = await _repository.watchChecklist(id).first;
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
    final expenses = await _repository.watchExpenses(id).first;
    final deposits = await _repository.watchDeposits(id).first;
    final transfers = await _repository.watchTransfers(id).first;
    final vehicles = await _repository.watchVehicles(id).first;
    final vehicleSeats = <String, List<BusSeat>>{};
    for (final vehicle in vehicles) {
      vehicleSeats[vehicle.id] =
          await _repository.watchSeatsOf(id, vehicle.id).first;
    }
    final coachSeats = await _repository.watchCoachSeats(id).first;
    final hotelRooms = await _repository.watchHotelRooms(id).first;
    final safetyAlerts =
        await _repository.watchSafetyAlerts(id, limit: 1000).first;
    final stories = await _repository.watchStories(id).first;
    final highlights = await _repository.watchHighlights(id).first;

    final posts = await _repository.fetchAllPostsForExport(id);
    final comments = <String, List<TourCommentItem>>{};
    for (var i = 0; i < posts.length; i += _parallelReads) {
      final chunk = posts.skip(i).take(_parallelReads).toList();
      final results = await Future.wait(
        chunk.map((post) => _repository.fetchCommentsForExport(id, post.id)),
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
