import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/itinerary_models.dart';
import '../../domain/models/tour_activity_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/destination_catalog.dart';
import '../../domain/services/route_engine.dart';
import '../../domain/services/route_suggestions.dart';
import '../../domain/services/prayer_calculator.dart';
import '../../domain/services/journey_audio_guide_service.dart';
import '../widgets/itinerary/itinerary_editor.dart';
import '../../../../core/localization/localized_date.dart';

String transportModeKey(TransportMode m) => 'route_mode_${m.name}';

IconData transportModeIcon(TransportMode m) => switch (m) {
      TransportMode.road => Icons.directions_bus_filled_rounded,
      TransportMode.rail => Icons.train_rounded,
      TransportMode.air => Icons.flight_rounded,
      TransportMode.river => Icons.directions_boat_filled_rounded,
      TransportMode.sea => Icons.sailing_rounded,
      TransportMode.jeep => Icons.airport_shuttle_rounded,
      TransportMode.boat => Icons.rowing_rounded,
      TransportMode.trek => Icons.hiking_rounded,
    };

String checkpointKindKey(CheckpointKind k) => 'route_cp_${k.name}';

/// The tour's route: every stop on the itinerary, how the group travels
/// between them, the stops along each leg and where the group is now.
class JourneyTrackerScreen extends StatefulWidget {
  final String tourId;

  const JourneyTrackerScreen({super.key, required this.tourId});

  @override
  State<JourneyTrackerScreen> createState() => _JourneyTrackerScreenState();
}

class _JourneyTrackerScreenState extends State<JourneyTrackerScreen> {
  final TourGroupRepository _repository = TourGroupRepository();
  final List<StreamSubscription<Object?>> _subs = [];
  TourGroup? _group;
  TourRole? _myRole;
  Position? _position;
  List<RouteCheckpoint> _checkpoints = const [];
  CheckpointKind? _filter;
  Timer? _clock;

  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;

  @override
  void initState() {
    super.initState();
    _subs.addAll([
      _repository.watchGroup(widget.tourId).listen((g) {
        if (mounted) setState(() => _group = g);
      }, onError: (Object _) {}),
      _repository.watchCheckpoints(widget.tourId).listen((c) {
        if (mounted) setState(() => _checkpoints = c);
      }, onError: (Object _) {}),
    ]);
    _repository.myRole(widget.tourId).then((r) {
      if (mounted) setState(() => _myRole = r);
    });
    unawaited(_fetchGps());
    // ETAs and countdowns move on their own.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    JourneyAudioGuideService().stop();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    super.dispose();
  }

  Future<void> _fetchGps() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _position = pos);
    } catch (_) {}
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text), backgroundColor: error ? Colors.redAccent : null));
  }

  Future<void> _open(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        _snack(context.l10n.translate('route_open_failed'), error: true);
      }
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    final l10n = context.l10n;
    try {
      await action();
    } catch (e) {
      _snack(l10n.translate('route_save_failed', args: {'error': e}),
          error: true);
    }
  }

  String _when(DateTime t) => localizedDateFormat('d MMM, h:mm a').format(t);

  String _duration(AppLocalizations l10n, Duration d) {
    final h = d.inHours, m = d.inMinutes % 60;
    if (h == 0) {
      return l10n.translate('route_minutes', args: {'m': l10n.number(m)});
    }
    return l10n.translate('route_hours',
        args: {'h': l10n.number(h), 'm': l10n.number(m)});
  }

  String _km(AppLocalizations l10n, RouteLeg leg) {
    final km = leg.km;
    if (km == null) return l10n.translate('route_km_unknown');
    return l10n.translate(leg.isEstimated ? 'route_km_about' : 'route_km',
        args: {'km': l10n.number(km)});
  }

  // ── Actions ────────────────────────────────────────────────────────────

  Future<void> _editItinerary(TourGroup g) async {
    final edit = await showItineraryEditor(context, g);
    if (edit == null) return;
    await _guard(() => _repository.saveItinerary(
          widget.tourId,
          stops: edit.stops,
          returnHome: edit.returnHome,
          startDate: g.startDate,
          endDate: g.endDate,
        ));
  }

  Future<void> _markLeg(RouteLeg leg, {required bool depart}) async {
    final now = DateTime.now();
    final plan = depart
        ? leg.plan.copyWith(departedAt: now, arrivedAt: null)
        : leg.plan
            .copyWith(departedAt: leg.plan.departedAt ?? now, arrivedAt: now);
    await _guard(() => _repository.saveLegPlan(widget.tourId, leg.key, plan));
  }

  Future<void> _resetLeg(RouteLeg leg) => _guard(() => _repository.saveLegPlan(
      widget.tourId,
      leg.key,
      leg.plan.copyWith(departedAt: null, arrivedAt: null)));

  Future<void> _editLeg(RouteLeg leg) async {
    final plan = await showModalBottomSheet<LegPlan>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF142428),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _LegSheet(leg: leg),
    );
    if (plan == null) return;
    await _guard(() => _repository.saveLegPlan(widget.tourId, leg.key, plan));
  }

  Future<void> _addSuggested(RouteLeg leg, List<SuggestedStop> stops) async {
    final l10n = context.l10n;
    final existing = {
      for (final c in _checkpoints)
        if (c.legKey == leg.key) c.name,
    };
    final fresh = stops.where((s) => !existing.contains(s.name)).toList();
    if (fresh.isEmpty) {
      _snack(l10n.translate('route_suggested_none'));
      return;
    }
    await _guard(() async {
      for (final s in fresh) {
        await _repository.addCheckpoint(
          tourId: widget.tourId,
          name: s.name,
          kmFromStart: s.km,
          highlight: s.highlight,
          lat: s.lat,
          lng: s.lng,
          legKey: leg.key,
          kind: s.kind,
        );
      }
    });
    _snack(l10n.translate('route_suggested_added',
        args: {'n': l10n.number(fresh.length)}));
  }

  Future<void> _editCheckpoint(RouteLeg leg,
      {RouteCheckpoint? existing}) async {
    final result = await showModalBottomSheet<RouteCheckpoint>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF142428),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CheckpointSheet(
        legKey: leg.key,
        existing: existing,
        position: _position,
      ),
    );
    if (result == null) return;
    await _guard(() async {
      if (existing == null) {
        await _repository.addCheckpoint(
          tourId: widget.tourId,
          name: result.name,
          kmFromStart: result.kmFromStart,
          highlight: result.highlight,
          lat: result.lat,
          lng: result.lng,
          legKey: leg.key,
          kind: result.kind,
          plannedAt: result.plannedAt,
          notes: result.notes,
        );
      } else {
        await _repository.updateCheckpoint(widget.tourId, result);
      }
    });
  }

  bool _canChange(RouteCheckpoint c) =>
      _isAdmin || c.addedByEmail == _repository.currentEmail;

  void _checkpointActions(RouteLeg leg, RouteCheckpoint c) {
    final l10n = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF142428),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('${c.kind.emoji} ${c.name}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: ValueListenableBuilder<bool>(
                valueListenable: JourneyAudioGuideService().isSpeaking,
                builder: (context, speaking, _) {
                  final active = speaking &&
                      JourneyAudioGuideService().currentCheckpointId.value ==
                          c.id;
                  return Icon(
                    active ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: active ? AppColors.gold : AppColors.mintGreen,
                  );
                },
              ),
              title: Text(l10n.translate('route_cp_listen_guide'),
                  style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                JourneyAudioGuideService().speakCheckpoint(
                  checkpoint: c,
                  kindLabel: l10n.translate(checkpointKindKey(c.kind)),
                  isBengali: l10n.locale.languageCode == 'bn',
                );
              },
            ),
            if (c.hasLocation)
              ListTile(
                leading:
                    const Icon(Icons.map_rounded, color: AppColors.mintGreen),
                title: Text(l10n.translate('route_open_map'),
                    style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _open(Uri.https('www.google.com', '/maps/search/',
                      {'api': '1', 'query': '${c.lat},${c.lng}'}));
                },
              ),
            if (_isAdmin)
              ListTile(
                leading: Icon(
                    c.visitedAt == null
                        ? Icons.check_circle_outline
                        : Icons.undo_rounded,
                    color: AppColors.gold),
                title: Text(
                    l10n.translate(c.visitedAt == null
                        ? 'route_cp_mark_passed'
                        : 'route_cp_unmark'),
                    style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _guard(() => _repository.setCheckpointVisited(
                      widget.tourId, c.id, c.visitedAt == null));
                },
              ),
            if (_canChange(c)) ...[
              ListTile(
                leading: const Icon(Icons.edit_rounded, color: Colors.white70),
                title: Text(l10n.translate('route_cp_edit'),
                    style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _editCheckpoint(leg, existing: c);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: Text(l10n.translate('route_cp_delete'),
                    style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _guard(
                      () => _repository.deleteCheckpoint(widget.tourId, c.id));
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _share(RoutePlan plan, TourGroup g) {
    final l10n = context.l10n;
    final days = localizedDateFormat('d MMM');
    final lines = <String>[
      '${g.name} — ${l10n.translate('route_title')}',
      '',
    ];
    for (var i = 0; i < plan.points.length; i++) {
      final p = plan.points[i];
      final s = p.stop;
      lines.add(s == null
          ? '🏠 ${p.name}'
          : '📍 ${p.name} (${days.format(s.arrive)} – ${days.format(s.leave)})'
              '${s.stay.isNotEmpty ? ' · ${s.stay}' : ''}');
      if (i < plan.legs.length) {
        final leg = plan.legs[i];
        final d = leg.duration;
        lines.add('   ↓ ${l10n.translate(transportModeKey(leg.plan.mode))}'
            ' · ${_km(l10n, leg)}'
            '${d == null ? '' : ' · ${_duration(l10n, d)}'}'
            '${leg.plan.departAt == null ? '' : ' · ${_when(leg.plan.departAt!)}'}');
      }
    }
    final uri = plan.directionsUri;
    if (uri != null) lines.addAll(['', uri.toString()]);
    // ignore: deprecated_member_use
    Share.share(lines.join('\n'), subject: g.name);
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final g = _group;
    return Scaffold(
      backgroundColor: const Color(0xFF0F1A1C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF142428),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(l10n.translate('route_title'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          if (_isAdmin && g != null)
            IconButton(
              tooltip: l10n.translate('route_edit_itinerary'),
              icon: const Icon(Icons.edit_road_rounded),
              onPressed: () => _editItinerary(g),
            ),
          IconButton(
            tooltip: l10n.translate('route_refresh_gps'),
            icon: const Icon(Icons.my_location),
            onPressed: _fetchGps,
          ),
        ],
      ),
      body: g == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.mintGreen))
          : _body(l10n, g),
    );
  }

  Widget _body(AppLocalizations l10n, TourGroup g) {
    final plan = RoutePlan.of(g);
    final pos = _position;
    final live = pos == null
        ? null
        : plan.locate(pos.latitude, pos.longitude, DateTime.now());
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
      children: [
        _header(l10n, g, plan, live),
        _prayerAndQiblaCard(l10n, g, pos),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (plan.directionsUri != null)
              FilledButton.tonalIcon(
                onPressed: () => _open(plan.directionsUri!),
                icon: const Icon(Icons.directions_rounded),
                label: Text(l10n.translate('route_directions_all')),
              ),
            OutlinedButton.icon(
              onPressed: () => _share(plan, g),
              icon: const Icon(Icons.ios_share_rounded),
              label: Text(l10n.translate('route_share')),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(l10n.translate('route_nearby'),
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final n in const [
              ('hospital', Icons.local_hospital_rounded, 'route_near_hospital'),
              (
                'police station',
                Icons.local_police_rounded,
                'route_near_police'
              ),
              ('pharmacy', Icons.medication_rounded, 'route_near_pharmacy'),
              (
                'petrol pump',
                Icons.local_gas_station_rounded,
                'route_near_fuel'
              ),
              ('mosque', Icons.mosque_rounded, 'route_near_mosque'),
              ('ATM', Icons.atm_rounded, 'route_near_atm'),
              ('restaurant', Icons.restaurant_rounded, 'route_near_food'),
              ('public toilet', Icons.wc_rounded, 'route_near_toilet'),
            ])
              ActionChip(
                avatar: Icon(n.$2, size: 16, color: AppColors.mintGreen),
                label: Text(l10n.translate(n.$3)),
                backgroundColor: const Color(0xFF142428),
                labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
                onPressed: () => _open(nearbySearchUri(n.$1,
                    lat: pos?.latitude, lng: pos?.longitude)),
              ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(l10n.translate('route_filter_all')),
                  selected: _filter == null,
                  onSelected: (_) => setState(() => _filter = null),
                ),
              ),
              for (final k in CheckpointKind.values)
                if (_checkpoints.any((c) => c.kind == k))
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(
                          '${k.emoji} ${l10n.translate(checkpointKindKey(k))}'),
                      selected: _filter == k,
                      onSelected: (_) => setState(() => _filter = k),
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < plan.points.length; i++) ...[
          _pointTile(l10n, plan.points[i], i == 0),
          if (i < plan.legs.length) _legTile(l10n, g, plan.legs[i], live),
        ],
      ],
    );
  }

  Widget _prayerAndQiblaCard(
      AppLocalizations l10n, TourGroup g, Position? pos) {
    final stopName = g.effectiveStops.isNotEmpty
        ? g.effectiveStops.first.name
        : g.destination;
    final preset = presetForName(stopName) ?? presetForName(g.destination);
    final lat = pos?.latitude ?? preset?.lat ?? 23.8103;
    final lng = pos?.longitude ?? preset?.lng ?? 90.4125;

    final schedule = PrayerCalculator.calculate(
      latitude: lat,
      longitude: lng,
      date: DateTime.now(),
    );
    final next = schedule.nextPrayer();
    final remainingMins = next.remaining.inMinutes;
    final hours = remainingMins ~/ 60;
    final mins = remainingMins % 60;
    final timeStr = hours > 0
        ? '${l10n.number(hours)}h ${l10n.number(mins)}m'
        : '${l10n.number(mins)}m';

    final prayerItems = [
      (key: 'prayer_fajr', time: schedule.fajr),
      (key: 'prayer_sunrise', time: schedule.sunrise),
      (key: 'prayer_dhuhr', time: schedule.dhuhr),
      (key: 'prayer_asr', time: schedule.asr),
      (key: 'prayer_maghrib', time: schedule.maghrib),
      (key: 'prayer_isha', time: schedule.isha),
    ];

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF142428),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mosque_rounded,
                  size: 18, color: AppColors.mintGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.translate('prayer_card_title'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.mintGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.mintGreen.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.explore_rounded,
                        size: 14, color: AppColors.mintGreen),
                    const SizedBox(width: 4),
                    Text(
                      l10n.translate('prayer_qibla_bearing', args: {
                        'deg': l10n.number(schedule.qiblaBearing.round()),
                      }),
                      style: const TextStyle(
                        color: AppColors.mintGreen,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.alarm_rounded,
                    size: 15, color: AppColors.gold),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.translate('prayer_next', args: {
                      'prayer': l10n.translate(next.key),
                      'time': timeStr,
                    }),
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final p in prayerItems) ...[
                  Builder(builder: (context) {
                    final isNext = p.key == next.key;
                    final timeFmt =
                        localizedDateFormat('h:mm a').format(p.time);
                    return Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isNext
                            ? AppColors.mintGreen.withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isNext ? AppColors.mintGreen : Colors.white10,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.translate(p.key),
                            style: TextStyle(
                              color:
                                  isNext ? AppColors.mintGreen : Colors.white70,
                              fontSize: 11,
                              fontWeight:
                                  isNext ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            timeFmt,
                            style: TextStyle(
                              color: isNext ? Colors.white : Colors.white54,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(
      AppLocalizations l10n, TourGroup g, RoutePlan plan, LivePosition? live) {
    final current = plan.currentLeg;
    final next = plan.nextLeg;
    String status;
    if (plan.isFinished) {
      status = l10n.translate('route_status_done');
    } else if (live != null && current != null) {
      status = l10n.translate('route_status_live', args: {
        'km': l10n.number(live.kmToNext),
        'place': live.leg.to.name,
        'time': localizedDateFormat('h:mm a').format(live.eta),
      });
    } else if (current != null) {
      final eta = current.eta;
      status = eta == null
          ? l10n.translate('route_status_underway',
              args: {'place': current.to.name})
          : l10n.translate('route_status_eta', args: {
              'place': current.to.name,
              'time': _when(eta),
            });
    } else if (next?.plan.departAt != null) {
      final left = next!.plan.departAt!.difference(DateTime.now());
      status = left.isNegative
          ? l10n.translate('route_status_due', args: {'place': next.to.name})
          : l10n.translate('route_status_next', args: {
              'place': next.to.name,
              'in': _duration(l10n, left),
            });
    } else {
      status = l10n.translate('route_status_planned');
    }

    final nights = g.effectiveStops.fold<int>(0, (n, s) => n + s.nights);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF142428),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.mintGreen.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              [
                g.originCity,
                ...g.effectiveStops.map((s) => s.name),
                if (g.returnHome) g.originCity,
              ].join(' → '),
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
          const SizedBox(height: 6),
          Text(
            l10n.translate('route_summary', args: {
              'km': l10n.number(plan.totalKm),
              'legs': l10n.number(plan.legs.length),
              'nights': l10n.number(nights),
            }),
            style: const TextStyle(color: AppColors.gold, fontSize: 12),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: plan.progress,
              minHeight: 8,
              backgroundColor: Colors.white10,
              valueColor: const AlwaysStoppedAnimation(AppColors.mintGreen),
            ),
          ),
          const SizedBox(height: 8),
          Text(status,
              style: const TextStyle(
                  color: AppColors.mintGreen,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
          if (g.stops.isEmpty && _isAdmin)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l10n.translate('route_add_more_hint'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _pointTile(AppLocalizations l10n, RoutePoint p, bool isStart) {
    final s = p.stop;
    final days = localizedDateFormat('EEE d MMM');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: s == null ? AppColors.gold : AppColors.mintGreen,
          child: Icon(s == null ? Icons.home_rounded : tourTypeIcon(s.kind),
              size: 18, color: AppColors.darkGreen),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF142428),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(p.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                    ),
                    if (p.hasLocation)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: l10n.translate('route_open_map'),
                        icon: const Icon(Icons.map_rounded,
                            color: AppColors.mintGreen, size: 20),
                        onPressed: () => _open(Uri.https(
                            'www.google.com',
                            '/maps/search/',
                            {'api': '1', 'query': p.mapsQuery})),
                      ),
                  ],
                ),
                Text(
                  s == null
                      ? l10n.translate(isStart ? 'itin_start' : 'route_home')
                      : [
                          '${days.format(s.arrive)} – ${days.format(s.leave)}',
                          l10n.translate('itin_nights',
                              args: {'n': l10n.number(s.nights)}),
                        ].join(' · '),
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                if (s != null && s.stay.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('🏨 ${s.stay}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ),
                if (s != null && s.notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(s.notes,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _legTile(
      AppLocalizations l10n, TourGroup g, RouteLeg leg, LivePosition? live) {
    final status = leg.status;
    final statusColor = switch (status) {
      LegStatus.done => AppColors.mintGreen,
      LegStatus.underway => AppColors.gold,
      LegStatus.planned => Colors.white38,
    };
    final checkpoints = [
      for (final c in _checkpoints)
        if ((c.legKey == leg.key || (c.legKey == null && leg.index == 0)) &&
            (_filter == null || c.kind == _filter))
          c,
    ]..sort((a, b) => a.kmFromStart.compareTo(b.kmFromStart));
    final toPreset = leg.to.stop == null
        ? null
        : (presetById(leg.to.stop!.presetId) ?? presetForName(leg.to.name));
    final suggestions = leg.plan.mode == TransportMode.road
        ? suggestedStopsFor(leg, toPresetId: toPreset?.id)
        : const <SuggestedStop>[];
    final d = leg.duration;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 36,
            child: Center(
              child: Container(
                  width: 3, color: statusColor.withValues(alpha: 0.6)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF10201A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: statusColor.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(transportModeIcon(leg.plan.mode),
                          color: statusColor, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${l10n.translate(transportModeKey(leg.plan.mode))} · ${_km(l10n, leg)}'
                          '${d == null ? '' : ' · ${_duration(l10n, d)}'}',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(l10n.translate('route_leg_${status.name}'),
                            style: TextStyle(color: statusColor, fontSize: 11)),
                      ),
                    ],
                  ),
                  if (leg.plan.departAt != null || leg.plan.arriveAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        [
                          if (leg.plan.departAt != null)
                            l10n.translate('route_departs',
                                args: {'time': _when(leg.plan.departAt!)}),
                          if (leg.plan.arriveAt != null)
                            l10n.translate('route_arrives',
                                args: {'time': _when(leg.plan.arriveAt!)}),
                        ].join(' · '),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  if (leg.plan.departedAt != null)
                    Text(
                      [
                        l10n.translate('route_left_at',
                            args: {'time': _when(leg.plan.departedAt!)}),
                        if (leg.plan.arrivedAt != null)
                          l10n.translate('route_arrived_at',
                              args: {'time': _when(leg.plan.arrivedAt!)})
                        else if (leg.eta != null)
                          l10n.translate('route_eta',
                              args: {'time': _when(leg.eta!)}),
                      ].join(' · '),
                      style: TextStyle(color: statusColor, fontSize: 12),
                    ),
                  if (live != null &&
                      live.leg.key == leg.key &&
                      status == LegStatus.underway) ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: live.fraction,
                      minHeight: 4,
                      backgroundColor: Colors.white10,
                      valueColor: const AlwaysStoppedAnimation(AppColors.gold),
                    ),
                  ],
                  if (leg.plan.notes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(leg.plan.notes,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                    ),
                  if (checkpoints.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final c in checkpoints) _checkpointRow(l10n, leg, c),
                  ],
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 0,
                    children: [
                      TextButton.icon(
                        onPressed: () => _open(leg.directionsUri),
                        icon: const Icon(Icons.directions_rounded, size: 18),
                        label: Text(l10n.translate('route_directions')),
                      ),
                      TextButton.icon(
                        onPressed: () => _editCheckpoint(leg),
                        icon: const Icon(Icons.add_location_alt_rounded,
                            size: 18),
                        label: Text(l10n.translate('route_add_stop')),
                      ),
                      if (_isAdmin) ...[
                        if (status == LegStatus.planned)
                          TextButton.icon(
                            onPressed: () => _markLeg(leg, depart: true),
                            icon:
                                const Icon(Icons.play_arrow_rounded, size: 18),
                            label: Text(l10n.translate('route_mark_departed')),
                          ),
                        if (status == LegStatus.underway)
                          TextButton.icon(
                            onPressed: () => _markLeg(leg, depart: false),
                            icon: const Icon(Icons.flag_rounded, size: 18),
                            label: Text(l10n.translate('route_mark_arrived')),
                          ),
                        if (status != LegStatus.planned)
                          TextButton.icon(
                            onPressed: () => _resetLeg(leg),
                            icon: const Icon(Icons.undo_rounded, size: 18),
                            label: Text(l10n.translate('route_reset')),
                          ),
                        TextButton.icon(
                          onPressed: () => _editLeg(leg),
                          icon: const Icon(Icons.tune_rounded, size: 18),
                          label: Text(l10n.translate('route_edit_leg')),
                        ),
                        if (suggestions.isNotEmpty)
                          TextButton.icon(
                            onPressed: () => _addSuggested(leg, suggestions),
                            icon: const Icon(Icons.auto_awesome_rounded,
                                size: 18),
                            label: Text(l10n.translate('route_suggested',
                                args: {'n': l10n.number(suggestions.length)})),
                          ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _checkpointRow(
      AppLocalizations l10n, RouteLeg leg, RouteCheckpoint c) {
    final passed = c.visitedAt != null;
    return InkWell(
      onTap: () => _checkpointActions(leg, c),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.kind.emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name,
                      style: TextStyle(
                          color: passed ? Colors.white54 : Colors.white,
                          decoration:
                              passed ? TextDecoration.lineThrough : null,
                          fontSize: 13)),
                  Text(
                    [
                      l10n.translate('route_km',
                          args: {'km': l10n.number(c.kmFromStart)}),
                      l10n.translate(checkpointKindKey(c.kind)),
                      if (c.plannedAt != null)
                        localizedDateFormat('h:mm a').format(c.plannedAt!),
                      if (c.highlight.isNotEmpty) c.highlight,
                    ].join(' · '),
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  if (c.notes.isNotEmpty)
                    Text(c.notes,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: JourneyAudioGuideService().isSpeaking,
              builder: (ctx, speaking, _) {
                final isCurrent = speaking &&
                    JourneyAudioGuideService().currentCheckpointId.value ==
                        c.id;
                return IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  icon: Icon(
                    isCurrent
                        ? Icons.volume_up_rounded
                        : Icons.volume_up_outlined,
                    color: isCurrent ? AppColors.gold : Colors.white38,
                  ),
                  tooltip: l10n.translate('route_cp_audio_guide'),
                  onPressed: () {
                    JourneyAudioGuideService().speakCheckpoint(
                      checkpoint: c,
                      kindLabel: l10n.translate(checkpointKindKey(c.kind)),
                      isBengali: l10n.locale.languageCode == 'bn',
                    );
                  },
                );
              },
            ),
            if (passed) ...[
              const SizedBox(width: 4),
              const Icon(Icons.check_circle,
                  color: AppColors.mintGreen, size: 16),
            ],
          ],
        ),
      ),
    );
  }
}

/// How a leg is travelled: mode, distance, planned times and notes.
class _LegSheet extends StatefulWidget {
  const _LegSheet({required this.leg});

  final RouteLeg leg;

  @override
  State<_LegSheet> createState() => _LegSheetState();
}

class _LegSheetState extends State<_LegSheet> {
  late LegPlan _p = widget.leg.plan;
  late final _km = TextEditingController(text: _p.distanceKm?.toString() ?? '');
  late final _notes = TextEditingController(text: _p.notes);

  @override
  void dispose() {
    _km.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickTime(DateTime? initial) async {
    final start = initial ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime(start.year - 1),
      lastDate: DateTime(start.year + 3),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(start));
    return DateTime(
        date.year, date.month, date.day, time?.hour ?? 0, time?.minute ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final when = localizedDateFormat('d MMM yyyy, h:mm a');
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${widget.leg.from.name} → ${widget.leg.to.name}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in TransportMode.values)
                  ChoiceChip(
                    avatar: Icon(transportModeIcon(m),
                        size: 16,
                        color: m == _p.mode
                            ? AppColors.darkGreen
                            : Colors.white70),
                    label: Text(l10n.translate(transportModeKey(m))),
                    selected: m == _p.mode,
                    selectedColor: AppColors.mintGreen,
                    backgroundColor: const Color(0xFF1E3326),
                    labelStyle: TextStyle(
                        color:
                            m == _p.mode ? AppColors.darkGreen : Colors.white),
                    onSelected: (_) =>
                        setState(() => _p = _p.copyWith(mode: m)),
                  ),
              ],
            ),
            TextField(
              controller: _km,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                  labelText: l10n.translate('route_distance'),
                  helperText: l10n.translate('route_distance_help'),
                  helperStyle: const TextStyle(color: Colors.white38)),
            ),
            for (final (label, value, set) in [
              (
                'route_plan_depart',
                _p.departAt,
                (DateTime? v) => _p = _p.copyWith(departAt: v)
              ),
              (
                'route_plan_arrive',
                _p.arriveAt,
                (DateTime? v) => _p = _p.copyWith(arriveAt: v)
              ),
            ])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading:
                    const Icon(Icons.schedule_rounded, color: AppColors.gold),
                title: Text(
                    value == null
                        ? l10n.translate('route_time_unset')
                        : when.format(value),
                    style: const TextStyle(color: Colors.white)),
                subtitle: Text(l10n.translate(label),
                    style: const TextStyle(color: Colors.white54)),
                trailing: value == null
                    ? null
                    : IconButton(
                        tooltip: l10n.translate('route_time_clear'),
                        icon: const Icon(Icons.close, color: Colors.white54),
                        onPressed: () => setState(() => set(null)),
                      ),
                onTap: () async {
                  final t = await _pickTime(value);
                  if (t != null) setState(() => set(t));
                },
              ),
            TextField(
              controller: _notes,
              maxLines: 2,
              maxLength: 300,
              style: const TextStyle(color: Colors.white),
              decoration:
                  InputDecoration(labelText: l10n.translate('route_leg_notes')),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.mintGreen,
                    foregroundColor: AppColors.darkGreen),
                onPressed: () {
                  final km = int.tryParse(_km.text.trim());
                  Navigator.pop(
                      context,
                      _p.copyWith(
                        distanceKm:
                            km != null && km > 0 && km < 5000 ? km : null,
                        notes: _notes.text.trim(),
                      ));
                },
                child: Text(l10n.translate('tour_save')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Adds or edits a stop along a leg.
class _CheckpointSheet extends StatefulWidget {
  const _CheckpointSheet({
    required this.legKey,
    this.existing,
    this.position,
  });

  final String legKey;
  final RouteCheckpoint? existing;
  final Position? position;

  @override
  State<_CheckpointSheet> createState() => _CheckpointSheetState();
}

class _CheckpointSheetState extends State<_CheckpointSheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _km = TextEditingController(
      text: widget.existing == null ? '' : '${widget.existing!.kmFromStart}');
  late final _highlight =
      TextEditingController(text: widget.existing?.highlight ?? '');
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  late CheckpointKind _kind = widget.existing?.kind ?? CheckpointKind.food;
  late DateTime? _planned = widget.existing?.plannedAt;
  bool _useGps = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _km.dispose();
    _highlight.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                l10n.translate(widget.existing == null
                    ? 'route_add_stop'
                    : 'route_cp_edit'),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            TextField(
              controller: _name,
              style: const TextStyle(color: Colors.white),
              decoration:
                  InputDecoration(labelText: l10n.translate('route_cp_name')),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final k in CheckpointKind.values)
                  ChoiceChip(
                    label: Text(
                        '${k.emoji} ${l10n.translate(checkpointKindKey(k))}'),
                    selected: k == _kind,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
              ],
            ),
            TextField(
              controller: _km,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration:
                  InputDecoration(labelText: l10n.translate('route_cp_km')),
            ),
            TextField(
              controller: _highlight,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                  labelText: l10n.translate('route_cp_highlight')),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading:
                  const Icon(Icons.schedule_rounded, color: AppColors.gold),
              title: Text(
                  _planned == null
                      ? l10n.translate('route_time_unset')
                      : localizedDateFormat('d MMM, h:mm a').format(_planned!),
                  style: const TextStyle(color: Colors.white)),
              subtitle: Text(l10n.translate('route_cp_planned'),
                  style: const TextStyle(color: Colors.white54)),
              onTap: () async {
                final now = _planned ?? DateTime.now();
                final date = await showDatePicker(
                    context: context,
                    initialDate: now,
                    firstDate: DateTime(now.year - 1),
                    lastDate: DateTime(now.year + 3));
                if (date == null || !context.mounted) return;
                final time = await showTimePicker(
                    context: context, initialTime: TimeOfDay.fromDateTime(now));
                setState(() => _planned = DateTime(date.year, date.month,
                    date.day, time?.hour ?? 0, time?.minute ?? 0));
              },
            ),
            if (widget.position != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _useGps,
                activeThumbColor: AppColors.mintGreen,
                title: Text(l10n.translate('route_cp_use_gps'),
                    style: const TextStyle(color: Colors.white)),
                onChanged: (v) => setState(() => _useGps = v),
              ),
            TextField(
              controller: _notes,
              maxLines: 2,
              maxLength: 300,
              style: const TextStyle(color: Colors.white),
              decoration:
                  InputDecoration(labelText: l10n.translate('itin_notes')),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.mintGreen,
                    foregroundColor: AppColors.darkGreen),
                onPressed: () {
                  final name = _name.text.trim();
                  final km = int.tryParse(_km.text.trim()) ?? 0;
                  if (name.isEmpty) {
                    setState(() =>
                        _error = l10n.translate('route_cp_name_required'));
                    return;
                  }
                  final e = widget.existing;
                  final pos = _useGps ? widget.position : null;
                  Navigator.pop(
                    context,
                    RouteCheckpoint(
                      id: e?.id ?? '',
                      name: name,
                      kmFromStart: km < 0 ? 0 : km,
                      highlight: _highlight.text.trim(),
                      lat: pos?.latitude ?? e?.lat,
                      lng: pos?.longitude ?? e?.lng,
                      addedByEmail: e?.addedByEmail ?? '',
                      legKey: e?.legKey ?? widget.legKey,
                      kind: _kind,
                      plannedAt: _planned,
                      notes: _notes.text.trim(),
                      visitedAt: e?.visitedAt,
                    ),
                  );
                },
                child: Text(l10n.translate('tour_save')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
