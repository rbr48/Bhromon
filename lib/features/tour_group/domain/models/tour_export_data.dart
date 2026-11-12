import '../services/tour_record_plan.dart';
import '../services/trip_ledger_engine.dart';
import 'dependent_models.dart';
import 'expense_models.dart';
import 'family_date_models.dart';
import 'family_task_models.dart';
import 'logistics_models.dart';
import 'safety_alert_models.dart';
import 'service_request_models.dart';
import 'tour_activity_models.dart';
import 'tour_group.dart';
import 'tour_post_models.dart';
import 'vehicle_models.dart';

/// Everything the PDF export reads from one group, gathered in one pass. Only the parts
/// the group's record holds are read; [incomplete] names the parts that could not be read.
/// Member emails stay in these models; the PDF prints names only.
class TourExportData {
  const TourExportData({
    required this.group,
    required this.exportedAt,
    required this.members,
    required this.notices,
    this.checkpoints = const [],
    this.checklist = const [],
    this.expenses = const [],
    this.deposits = const [],
    this.transfers = const [],
    this.settlements = const [],
    this.ledger,
    this.vehicles = const [],
    this.vehicleSeats = const {},
    this.coachSeats = const [],
    this.hotelRooms = const [],
    this.safetyAlerts = const [],
    this.posts = const [],
    this.comments = const {},
    this.stories = const [],
    this.highlights = const [],
    this.familyDates = const [],
    this.dependents = const [],
    this.familyTasks = const [],
    this.serviceRequests = const [],
    this.incomplete = const {},
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

  /// Settle-up payments recorded in the fund, newest first.
  final List<TransferItem> transfers;

  /// MFS and peer settlements, newest first. Only verified ones move the balances.
  final List<SettlementRecord> settlements;

  /// The balances of the members and the settlements that would clear them. Null when the
  /// money could not be read.
  final LedgerSummary? ledger;
  final List<TourVehicle> vehicles;

  /// Seats of each vehicle, by vehicle id.
  final Map<String, List<BusSeat>> vehicleSeats;

  /// Seats of the original coach the tour starts with.
  final List<BusSeat> coachSeats;
  final List<HotelRoom> hotelRooms;

  /// The SOS alerts of the group, read only for a group that has SOS. The record prints
  /// their counts, never who raised them or when.
  final List<SafetyAlert> safetyAlerts;

  /// The posts the record keeps, oldest first.
  final List<TourPostItem> posts;

  /// Comments by post id, oldest first.
  final Map<String, List<TourCommentItem>> comments;

  /// The stories of the last 24 hours, newest first.
  final List<TourStoryItem> stories;
  final List<TourStoryHighlight> highlights;
  final List<FamilyDate> familyDates;
  final List<Dependent> dependents;
  final List<FamilyTask> familyTasks;
  final List<ServiceRequest> serviceRequests;

  /// The parts of the record that could not be read, so the file says so.
  final Set<TourRecordSection> incomplete;

  /// The parts this record holds for the group (see [recordSectionsFor]).
  Set<TourRecordSection> get sections => {...recordSectionsFor(group)};
}

/// Set by the export's Cancel button. The export checks it between its steps.
class TourExportCancel {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// Thrown when the user cancels an export part way through. It is not a failure.
class TourExportCancelled implements Exception {
  const TourExportCancelled();
}
