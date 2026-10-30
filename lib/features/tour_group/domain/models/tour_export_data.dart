import 'tour_activity_models.dart';
import 'expense_models.dart';
import 'logistics_models.dart';
import 'safety_alert_models.dart';
import 'tour_group.dart';
import 'tour_post_models.dart';
import 'vehicle_models.dart';

/// Everything the PDF export reads from one tour, gathered in one pass. Member
/// emails stay in these models; the PDF only ever prints names.
class TourExportData {
  const TourExportData({
    required this.group,
    required this.exportedAt,
    required this.members,
    required this.notices,
    required this.checkpoints,
    required this.checklist,
    required this.expenses,
    required this.deposits,
    required this.transfers,
    required this.vehicles,
    required this.vehicleSeats,
    required this.coachSeats,
    required this.hotelRooms,
    required this.safetyAlerts,
    required this.posts,
    required this.comments,
    required this.stories,
    required this.highlights,
  });

  final TourGroup group;

  /// When the record was made. Printed on the cover.
  final DateTime exportedAt;
  final List<TourMember> members;
  final List<TourNotice> notices;
  final List<RouteCheckpoint> checkpoints;
  final List<ChecklistItem> checklist;
  final List<ExpenseItem> expenses;
  final List<DepositItem> deposits;
  final List<TransferItem> transfers;
  final List<TourVehicle> vehicles;

  /// Seats of each vehicle, by vehicle id.
  final Map<String, List<BusSeat>> vehicleSeats;

  /// Seats of the original coach the tour starts with.
  final List<BusSeat> coachSeats;
  final List<HotelRoom> hotelRooms;
  final List<SafetyAlert> safetyAlerts;

  /// Every post, oldest first.
  final List<TourPostItem> posts;

  /// Comments by post id, oldest first.
  final Map<String, List<TourCommentItem>> comments;
  final List<TourStoryItem> stories;
  final List<TourStoryHighlight> highlights;
}
