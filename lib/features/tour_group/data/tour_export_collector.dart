import '../domain/models/dependent_models.dart';
import '../domain/models/expense_models.dart';
import '../domain/models/family_date_models.dart';
import '../domain/models/family_task_models.dart';
import '../domain/models/logistics_models.dart';
import '../domain/models/safety_alert_models.dart';
import '../domain/models/service_request_models.dart';
import '../domain/models/tour_activity_models.dart';
import '../domain/models/tour_export_data.dart';
import '../domain/models/tour_group.dart';
import '../domain/models/tour_post_models.dart';
import '../domain/models/vehicle_models.dart';
import '../domain/services/tour_record_plan.dart';
import '../domain/services/trip_ledger_engine.dart';
import 'tour_group_repository.dart';

/// Reads everything the PDF record shows, and says which parts could not be read.
///
/// Only the parts the group's record holds are read (see [recordSectionsFor]). The reads
/// start together, so a slow one does not hold up the others. A read that fails or times
/// out leaves its part out and records it in [TourExportData.incomplete]; nothing is
/// shown as empty when it was only unreadable. Posts are read in full, with the comments
/// of each one, and the archived posts and the stories older than 24 hours are dropped.
class TourExportCollector {
  TourExportCollector(this._repository);

  static const Duration _readTimeout = Duration(seconds: 12);
  static const Duration _groupTimeout = Duration(seconds: 8);
  static const Duration _postsTimeout = Duration(seconds: 25);
  static const Duration _commentTimeout = Duration(seconds: 8);
  static const int _parallelComments = 8;
  static const int _safetyReadLimit = 5000;

  final TourGroupRepository _repository;

  /// [onComments] reports how many posts have had their comments read, out of all.
  /// Throws [TourExportCancelled] between steps once [cancel] is set.
  Future<TourExportData> collect(
    TourGroup group, {
    void Function(int done, int total)? onComments,
    TourExportCancel? cancel,
  }) async {
    final id = group.id;
    final now = DateTime.now();
    final sections = {...recordSectionsFor(group)};
    final gaps = <TourRecordSection>{};

    void checkCancel() {
      if (cancel?.isCancelled ?? false) throw const TourExportCancelled();
    }

    checkCancel();
    // Every read starts now; each part is awaited below.
    final latestF = _latest(group);
    final membersF = _read(TourRecordSection.members, gaps,
        () => _repository.watchMembers(id).first, const <TourMember>[]);
    final noticesF = _read(TourRecordSection.notices, gaps,
        () => _repository.watchNotices(id).first, const <TourNotice>[]);
    final expensesF = _read(TourRecordSection.money, gaps,
        () => _repository.watchExpenses(id).first, const <ExpenseItem>[]);
    final depositsF = _read(TourRecordSection.money, gaps,
        () => _repository.watchDeposits(id).first, const <DepositItem>[]);
    final transfersF = _read(TourRecordSection.money, gaps,
        () => _repository.watchTransfers(id).first, const <TransferItem>[]);
    final settlementsF = _read(
        TourRecordSection.money,
        gaps,
        () => _repository.watchSettlements(id).first,
        const <SettlementRecord>[]);

    final checkpointsF = sections.contains(TourRecordSection.journey)
        ? _read(
            TourRecordSection.journey,
            gaps,
            () => _repository.watchCheckpoints(id).first,
            const <RouteCheckpoint>[])
        : Future.value(const <RouteCheckpoint>[]);
    final checklistF = sections.contains(TourRecordSection.checklist)
        ? _read(TourRecordSection.checklist, gaps,
            () => _repository.watchChecklist(id).first, const <ChecklistItem>[])
        : Future.value(const <ChecklistItem>[]);
    final vehiclesF = sections.contains(TourRecordSection.transport)
        ? _read(TourRecordSection.transport, gaps,
            () => _repository.watchVehicles(id).first, const <TourVehicle>[])
        : Future.value(const <TourVehicle>[]);
    final coachSeatsF = sections.contains(TourRecordSection.transport)
        ? _read(TourRecordSection.transport, gaps,
            () => _repository.watchCoachSeats(id).first, const <BusSeat>[])
        : Future.value(const <BusSeat>[]);
    final hotelRoomsF = sections.contains(TourRecordSection.rooms)
        ? _read(TourRecordSection.rooms, gaps,
            () => _repository.watchHotelRooms(id).first, const <HotelRoom>[])
        : Future.value(const <HotelRoom>[]);
    final safetyF = sections.contains(TourRecordSection.safety)
        ? _read(
            TourRecordSection.safety,
            gaps,
            () => _repository
                .watchSafetyAlerts(id, limit: _safetyReadLimit)
                .first,
            const <SafetyAlert>[])
        : Future.value(const <SafetyAlert>[]);
    final storiesF = sections.contains(TourRecordSection.stories)
        ? _read(TourRecordSection.stories, gaps,
            () => _repository.watchStories(id).first, const <TourStoryItem>[])
        : Future.value(const <TourStoryItem>[]);
    final highlightsF = sections.contains(TourRecordSection.highlights)
        ? _read(
            TourRecordSection.highlights,
            gaps,
            () => _repository.watchHighlights(id).first,
            const <TourStoryHighlight>[])
        : Future.value(const <TourStoryHighlight>[]);
    final postsF = sections.contains(TourRecordSection.feed)
        ? _read(
            TourRecordSection.feed,
            gaps,
            () => _repository.fetchAllPostsForExport(id),
            const <TourPostItem>[],
            timeout: _postsTimeout)
        : Future.value(const <TourPostItem>[]);
    final familyDatesF = sections.contains(TourRecordSection.familyDates)
        ? _read(TourRecordSection.familyDates, gaps,
            () => _repository.watchFamilyDates(id).first, const <FamilyDate>[])
        : Future.value(const <FamilyDate>[]);
    final dependentsF = sections.contains(TourRecordSection.dependents)
        ? _read(TourRecordSection.dependents, gaps,
            () => _repository.watchDependents(id).first, const <Dependent>[])
        : Future.value(const <Dependent>[]);
    final familyTasksF = sections.contains(TourRecordSection.sharedList)
        ? _read(TourRecordSection.sharedList, gaps,
            () => _repository.watchFamilyTasks(id).first, const <FamilyTask>[])
        : Future.value(const <FamilyTask>[]);
    final requestsF = sections.contains(TourRecordSection.requests)
        ? _read(
            TourRecordSection.requests,
            gaps,
            () => _repository.watchServiceRequests(id).first,
            const <ServiceRequest>[])
        : Future.value(const <ServiceRequest>[]);

    final latest = await latestF;
    final members = await membersF;
    final notices = await noticesF;
    final expenses = await expensesF;
    final deposits = await depositsF;
    final transfers = await transfersF;
    final settlements = await settlementsF;
    final checkpoints = await checkpointsF;
    final savedChecklist = await checklistF;
    checkCancel();

    final vehicles = await vehiclesF;
    final coachSeats = await coachSeatsF;
    final hotelRooms = await hotelRoomsF;
    final seatLists = await Future.wait([
      for (final vehicle in vehicles)
        _read(
            TourRecordSection.transport,
            gaps,
            () => _repository.watchSeatsOf(id, vehicle.id).first,
            const <BusSeat>[]),
    ]);
    final vehicleSeats = {
      for (var i = 0; i < vehicles.length; i++) vehicles[i].id: seatLists[i],
    };
    final safetyAlerts = await safetyF;
    final stories = recordStories(await storiesF, now);
    final highlights = await highlightsF;
    final familyDates = await familyDatesF;
    final dependents = await dependentsF;
    final familyTasks = await familyTasksF;
    final serviceRequests = await requestsF;

    // The balances need the members and all the money; without either, no balance is shown.
    LedgerSummary? ledger;
    if (!gaps.contains(TourRecordSection.money) &&
        !gaps.contains(TourRecordSection.members)) {
      try {
        ledger = TripLedgerEngine.computeLedger(
          members: [
            for (final member in members)
              LedgerMemberInput(
                id: member.email,
                name: member.displayName,
                familyCount: member.familyCount,
              ),
          ],
          expenses: expenses,
          deposits: deposits,
          transfers: ledgerTransfers(transfers, settlements),
        );
      } catch (_) {
        gaps.add(TourRecordSection.money);
      }
    }

    final posts = recordPosts(await postsF);
    checkCancel();
    final comments = <String, List<TourCommentItem>>{};
    for (var i = 0; i < posts.length; i += _parallelComments) {
      checkCancel();
      final chunk = posts.skip(i).take(_parallelComments).toList();
      final results = await Future.wait([
        for (final post in chunk)
          _read(
              TourRecordSection.feed,
              gaps,
              () => _repository.fetchCommentsForExport(id, post.id),
              const <TourCommentItem>[],
              timeout: _commentTimeout),
      ]);
      for (var j = 0; j < chunk.length; j++) {
        comments[chunk[j].id] = results[j];
      }
      onComments?.call(i + chunk.length, posts.length);
    }

    return TourExportData(
      group: latest,
      exportedAt: now,
      members: members,
      notices: notices,
      checkpoints: checkpoints,
      checklist: sections.contains(TourRecordSection.checklist)
          ? _checklistFor(latest, savedChecklist)
          : const <ChecklistItem>[],
      expenses: expenses,
      deposits: deposits,
      transfers: transfers,
      settlements: settlements,
      ledger: ledger,
      vehicles: vehicles,
      vehicleSeats: vehicleSeats,
      coachSeats: coachSeats,
      hotelRooms: hotelRooms,
      safetyAlerts: safetyAlerts,
      posts: posts,
      comments: comments,
      stories: stories,
      highlights: highlights,
      familyDates: familyDates,
      dependents: dependents,
      familyTasks: familyTasks,
      serviceRequests: serviceRequests,
      incomplete: gaps,
    );
  }

  /// The group as the server has it now. When that read fails, the copy the screen holds is
  /// used: it is the group the user is looking at.
  Future<TourGroup> _latest(TourGroup group) async {
    try {
      final fresh = await _repository.getGroup(group.id).timeout(_groupTimeout);
      return fresh ?? group;
    } catch (_) {
      return group;
    }
  }

  /// One read of [load], bounded by [timeout]. A failure records [section] as unreadable
  /// and gives [fallback].
  Future<T> _read<T>(
    TourRecordSection section,
    Set<TourRecordSection> gaps,
    Future<T> Function() load,
    T fallback, {
    Duration timeout = _readTimeout,
  }) async {
    try {
      return await load().timeout(timeout);
    } catch (_) {
      gaps.add(section);
      return fallback;
    }
  }

  /// The packing list of a trip: the default items for its tour type, each with its saved
  /// ticks, then the items the group added. A non-trip group has no packing list.
  List<ChecklistItem> _checklistFor(
    TourGroup group,
    List<ChecklistItem> saved,
  ) {
    final tourType = group.tourType;
    final isBeach = tourType == TourType.beach ||
        tourType == TourType.heritage ||
        tourType == TourType.custom;
    final isHill = tourType == TourType.hill || tourType == TourType.custom;
    final isNature = tourType == TourType.nature || tourType == TourType.custom;
    final byId = {for (final item in saved) item.id: item};

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
    for (final item in saved) {
      if (!item.id.startsWith('default_')) {
        checklist.add(item);
      }
    }
    return checklist;
  }
}
