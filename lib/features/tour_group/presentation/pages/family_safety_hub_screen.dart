import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../domain/models/safety_alert_models.dart';
import '../../domain/models/tour_group.dart';
import '../../data/tour_group_repository.dart';
import '../../data/device_battery_reader.dart';
import '../../domain/models/date_codec.dart';
import '../../domain/services/family_telemetry_publisher.dart';
import '../../../../core/utils/app_logger.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/localization/localized_date.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';

class TourLandmark {
  final String id;
  final String name;
  final String subtitle;
  final double lat;
  final double lng;
  final IconData icon;
  final Color color;

  const TourLandmark({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.lat,
    required this.lng,
    required this.icon,
    required this.color,
  });
}

class FamilySafetyHubScreen extends StatefulWidget {
  final String tourId;

  const FamilySafetyHubScreen({super.key, required this.tourId});

  @override
  State<FamilySafetyHubScreen> createState() => _FamilySafetyHubScreenState();
}

class _FamilySafetyHubScreenState extends State<FamilySafetyHubScreen>
    with SingleTickerProviderStateMixin {
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  bool _isSirenActive = false;
  late AnimationController _sirenAnimController;
  Timer? _alertTimer;

  final TourGroupRepository _repository = TourGroupRepository();
  TourGroup? _tourGroup;
  StreamSubscription<TourGroup?>? _groupSub;
  TourRole? _myRole;
  // The alert this device raised and has not resolved yet.
  String? _activeAlertId;
  late final Stream<List<SafetyAlert>> _alerts =
      _repository.watchSafetyAlerts(widget.tourId);
  late final Stream<List<BatteryTelemetry>> _telemetry =
      _repository.watchBatteryTelemetry(widget.tourId);
  late final Stream<List<TourMember>> _roster =
      _repository.watchMembers(widget.tourId);
  final DeviceBatteryReader _batteryReader = DeviceBatteryReader();
  late final FamilyTelemetryPublisher _publisher = FamilyTelemetryPublisher(
    sink: (write) => _repository.publishFamilyTelemetry(widget.tourId, write),
    onError: (error, stack) =>
        logWarning('Safety hub: family telemetry write failed', error, stack),
  );
  StreamSubscription<void>? _batterySub;
  Timer? _telemetryTimer;
  // Whether this member shares their place with the family right now.
  bool _locationShareOn = false;

  List<TourLandmark> get _landmarks {
    final dest = _tourGroup?.destination.toLowerCase() ?? '';
    if (dest.contains('sajek') || dest.contains('সাজেক')) {
      return [
        TourLandmark(
          id: 'sajek_resort',
          name: context.l10n.translate('fsh_sajek_cottage_name'),
          subtitle: context.l10n.translate('fsh_main_cottage_sub'),
          lat: 23.3828,
          lng: 92.2938,
          icon: Icons.hotel,
          color: Colors.amber,
        ),
        TourLandmark(
          id: 'sajek_vehicle',
          name: context.l10n.translate('fsh_sajek_parking_name'),
          subtitle: context.l10n.translate('fsh_tour_transport_sub'),
          lat: 23.3840,
          lng: 92.2945,
          icon: Icons.directions_bus,
          color: Colors.teal,
        ),
        TourLandmark(
          id: 'sajek_helipad',
          name: context.l10n.translate('fsh_sajek_helipad_name'),
          subtitle: context.l10n.translate('fsh_family_meetup_sub'),
          lat: 23.3815,
          lng: 92.2930,
          icon: Icons.wb_cloudy_rounded,
          color: Colors.blueAccent,
        ),
        TourLandmark(
          id: 'konglak_peak',
          name: context.l10n.translate('fsh_konglak_name'),
          subtitle: context.l10n.translate('fsh_konglak_sub'),
          lat: 23.3980,
          lng: 92.3010,
          icon: Icons.landscape_rounded,
          color: Colors.orangeAccent,
        ),
      ];
    } else if (dest.contains('sylhet') || dest.contains('সিলেট')) {
      return [
        TourLandmark(
          id: 'syl_hotel',
          name: context.l10n.translate('fsh_sylhet_hotel_name'),
          subtitle: context.l10n.translate('fsh_main_hotel_sub'),
          lat: 24.8949,
          lng: 91.8687,
          icon: Icons.hotel,
          color: Colors.amber,
        ),
        TourLandmark(
          id: 'syl_bus',
          name: context.l10n.translate('fsh_sylhet_bus_name'),
          subtitle: context.l10n.translate('fsh_main_transport_sub'),
          lat: 24.8960,
          lng: 91.8700,
          icon: Icons.directions_bus,
          color: Colors.teal,
        ),
        TourLandmark(
          id: 'syl_ratargul',
          name: context.l10n.translate('fsh_ratargul_name'),
          subtitle: context.l10n.translate('fsh_ratargul_sub'),
          lat: 25.0050,
          lng: 91.9300,
          icon: Icons.water_rounded,
          color: Colors.blueAccent,
        ),
        TourLandmark(
          id: 'syl_sada',
          name: context.l10n.translate('fsh_bholaganj_name'),
          subtitle: context.l10n.translate('fsh_bholaganj_sub'),
          lat: 25.1634,
          lng: 92.0189,
          icon: Icons.diamond_rounded,
          color: Colors.orangeAccent,
        ),
      ];
    } else if (dest.contains('bandarban') || dest.contains('বান্দরবান')) {
      return [
        TourLandmark(
          id: 'ban_hotel',
          name: context.l10n.translate('fsh_bandarban_hotel_name'),
          subtitle: context.l10n.translate('fsh_main_hotel_sub'),
          lat: 22.1953,
          lng: 92.2184,
          icon: Icons.hotel,
          color: Colors.amber,
        ),
        TourLandmark(
          id: 'ban_bus',
          name: context.l10n.translate('fsh_bandarban_bus_name'),
          subtitle: context.l10n.translate('fsh_hill_transport_sub'),
          lat: 22.1970,
          lng: 92.2190,
          icon: Icons.directions_bus,
          color: Colors.teal,
        ),
        TourLandmark(
          id: 'ban_nilachal',
          name: context.l10n.translate('fsh_nilachal_name'),
          subtitle: context.l10n.translate('fsh_nilachal_sub'),
          lat: 22.1800,
          lng: 92.2050,
          icon: Icons.wb_sunny_rounded,
          color: Colors.blueAccent,
        ),
        TourLandmark(
          id: 'ban_nilgiri',
          name: context.l10n.translate('fsh_nilgiri_name'),
          subtitle: context.l10n.translate('fsh_nilgiri_sub'),
          lat: 21.9189,
          lng: 92.3364,
          icon: Icons.landscape_rounded,
          color: Colors.orangeAccent,
        ),
      ];
    } else if (dest.contains('cox')) {
      return [
        TourLandmark(
          id: 'hotel_sea_moon',
          name: context.l10n.translate('fsh_cox_hotel_name', args: {
            'destination': _tourGroup?.destination ??
                context.l10n.translate('fsh_default_destination')
          }),
          subtitle: context.l10n.translate('fsh_main_hotel_sub'),
          lat: 21.4326,
          lng: 91.9774,
          icon: Icons.hotel,
          color: Colors.amber,
        ),
        TourLandmark(
          id: 'evergreen_bus',
          name: context.l10n.translate('fsh_cox_bus_name', args: {
            'origin': _tourGroup?.originCity ??
                context.l10n.translate('fsh_default_origin'),
            'destination': _tourGroup?.destination ??
                context.l10n.translate('fsh_default_destination')
          }),
          subtitle: context.l10n.translate('fsh_main_bus_sub'),
          lat: 21.4385,
          lng: 91.9740,
          icon: Icons.directions_bus,
          color: Colors.teal,
        ),
        TourLandmark(
          id: 'sugandha_beach',
          name: context.l10n.translate('fsh_cox_meetup_name', args: {
            'destination': _tourGroup?.destination ??
                context.l10n.translate('fsh_default_destination')
          }),
          subtitle: context.l10n.translate('fsh_family_meetup_sub'),
          lat: 21.4298,
          lng: 91.9752,
          icon: Icons.place_rounded,
          color: Colors.blueAccent,
        ),
        TourLandmark(
          id: 'laboni_beach',
          name: context.l10n.translate('fsh_cox_spot_name', args: {
            'destination': _tourGroup?.destination ??
                context.l10n.translate('fsh_default_destination')
          }),
          subtitle: context.l10n.translate('fsh_sightseeing_sub'),
          lat: 21.4390,
          lng: 91.9712,
          icon: Icons.camera_alt_rounded,
          color: Colors.orangeAccent,
        ),
      ];
    }
    // Other destinations have no surveyed points yet; showing Cox's Bazar
    // coordinates for them would send people to the wrong place.
    return const [];
  }

  /// The national health helpline. Local hospital numbers are not listed
  /// because none could be verified; the tour admin can add them on the notice board.
  ({String title, String number, String display}) _getLocalHospitalContact() {
    return (
      title: context.l10n.translate('fsh_national_health_helpline'),
      number: '16263',
      display: '16263',
    );
  }

  @override
  void initState() {
    super.initState();
    _watchGroup();
    _loadRole();
    _sirenAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _initGps();
    _startFamilySharing();
  }

  void _watchGroup() {
    _groupSub?.cancel();
    _groupSub = _repository.watchGroup(widget.tourId).listen((g) {
      if (mounted) setState(() => _tourGroup = g);
    });
  }

  Future<void> _loadRole() async {
    final role = await _repository.myRole(widget.tourId);
    if (mounted) setState(() => _myRole = role);
  }

  @override
  void dispose() {
    _groupSub?.cancel();
    _positionStream?.cancel();
    _batterySub?.cancel();
    _telemetryTimer?.cancel();
    _alertTimer?.cancel();
    _sirenAnimController.dispose();
    // Stops sharing the place when the member leaves this screen.
    unawaited(_publisher.stop(DateTime.now()));
    super.dispose();
  }

  /// Keeps one local position for the direction cards and the SOS message. It is
  /// not published: only a member who turns on the location switch shares it.
  Future<void> _initGps() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _currentPosition = pos);
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen(
        (pos) {
          if (mounted) setState(() => _currentPosition = pos);
          if (_locationShareOn) {
            unawaited(_publisher.onFix(
              PositionFix(pos.latitude, pos.longitude),
              DateTime.now(),
            ));
          }
        },
        onError: (Object error, StackTrace stack) =>
            logWarning('Safety hub: position stream failed', error, stack),
      );
    } catch (error, stack) {
      logWarning('Safety hub: location unavailable', error, stack);
    }
  }

  /// Publishes this phone's battery while the hub is open. Place sharing is
  /// separate, and starts only when the member turns the switch on.
  void _startFamilySharing() {
    unawaited(_resetFamilyTelemetry());
    _batterySub = _batteryReader.changes.listen(
      (_) => unawaited(_publishBattery()),
      onError: (Object error, StackTrace stack) =>
          logWarning('Safety hub: battery changes unavailable', error, stack),
    );
    _telemetryTimer = Timer.periodic(
      _publisher.heartbeat,
      (_) => unawaited(_heartbeat()),
    );
  }

  Future<void> _resetFamilyTelemetry() async {
    final battery = await _batteryReader.read();
    await _publisher.reset(battery, DateTime.now());
  }

  Future<void> _publishBattery() async {
    final battery = await _batteryReader.read();
    await _publisher.onBattery(battery, DateTime.now());
  }

  Future<void> _heartbeat() async {
    await _publishBattery();
    await _publisher.tick(DateTime.now());
  }

  /// Turns place sharing on or off. Turning it on needs location permission;
  /// without it the switch stays off and the member is told why.
  Future<void> _setLocationSharing(bool on) async {
    if (on && !await _hasLocationPermission()) {
      if (mounted) {
        _showMessage(context.l10n.translate('fsh_location_permission_needed'));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _locationShareOn = on);
    final now = DateTime.now();
    await _publisher.setSharingLocation(on, now);
    final pos = _currentPosition;
    if (on && pos != null) {
      await _publisher.onFix(PositionFix(pos.latitude, pos.longitude), now);
    }
  }

  Future<bool> _hasLocationPermission() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (error, stack) {
      logWarning('Safety hub: location permission check failed', error, stack);
      return false;
    }
  }

  Future<void> _callNumber(String number) async {
    final uri = Uri.parse('tel:$number');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openMapNavigation(double lat, double lng) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Phone heading in degrees, or 0 (north) when the device does not report one.
  double get _headingDegrees {
    final heading = _currentPosition?.heading ?? -1;
    return heading >= 0 ? heading : 0;
  }

  /// Starts or stops the alert: a repeating vibration, the pulsing banner, and
  /// a safety alert that every member of the tour can see.
  void _toggleAlert() {
    setState(() => _isSirenActive = !_isSirenActive);
    _alertTimer?.cancel();
    if (_isSirenActive) {
      _sirenAnimController.repeat(reverse: true);
      HapticFeedback.heavyImpact();
      _alertTimer = Timer.periodic(const Duration(milliseconds: 900),
          (_) => HapticFeedback.heavyImpact());
      _raiseAlert();
    } else {
      _sirenAnimController.stop();
      _sirenAnimController.value = 0;
      _resolveAlert();
    }
  }

  void _raiseAlert() {
    final l10n = context.l10n;
    final alertId = _repository.newSafetyAlertId();
    _activeAlertId = alertId;
    final pos = _currentPosition;
    unawaited(_repository
        .raiseSafetyAlert(
      tourId: widget.tourId,
      alertId: alertId,
      latitude: pos?.latitude,
      longitude: pos?.longitude,
    )
        .then(
      (synced) {
        if (!synced) {
          _showMessage(l10n.translate('fsh_alert_not_synced'));
        }
      },
      onError: (Object e) => _showMessage(
          l10n.translate('fsh_alert_send_failed', args: {'error': e})),
    ));
  }

  /// Resolves the alert this device raised, if any. Used when the siren stops.
  void _resolveAlert() {
    final alertId = _activeAlertId;
    _activeAlertId = null;
    if (alertId == null) return;
    _resolveById(alertId);
  }

  void _resolveById(String alertId) {
    final l10n = context.l10n;
    unawaited(_repository.resolveSafetyAlert(widget.tourId, alertId).then(
          (_) {},
          onError: (Object e) => _showMessage(
              l10n.translate('fsh_alert_close_failed', args: {'error': e})),
        ));
  }

  /// Closes an alert from its card. Closing this device's own live alert also
  /// stops the siren, so the two never disagree.
  void _resolveFromCard(SafetyAlert alert) {
    if (alert.id == _activeAlertId && _isSirenActive) {
      _toggleAlert();
      return;
    }
    _resolveById(alert.id);
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Shares the current position as a map link, for the family to find you.
  Future<void> _shareLocation() async {
    final pos = _currentPosition;
    if (pos == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.l10n.translate('fsh_location_unavailable')),
          backgroundColor: Colors.redAccent,
        ));
      }
      return;
    }
    final link =
        'https://maps.google.com/?q=${pos.latitude.toStringAsFixed(6)},${pos.longitude.toStringAsFixed(6)}';
    // ignore: deprecated_member_use
    await Share.share(context.l10n
        .translate('fsh_share_location_text', args: {'link': link}));
  }

  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final phi1 = lat1 * math.pi / 180;
    final phi2 = lat2 * math.pi / 180;
    final deltaLambda = (lon2 - lon1) * math.pi / 180;

    final y = math.sin(deltaLambda) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(deltaLambda);
    final theta = math.atan2(y, x);
    return (theta * 180 / math.pi + 360) % 360;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B1E),
      appBar: AppBar(
        title: Text(context.l10n.translate('fsh_title'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF142428),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // SOS Emergency Beacon
            _buildSosBeacon(),

            const SizedBox(height: 16),

            // Alerts raised by the group, until someone resolves them.
            _buildGroupAlerts(),

            // Place sharing is the member's choice; the family list follows.
            _buildLocationSharingCard(),
            _buildFamilyStatus(),

            // Emergency Contacts
            _buildEmergencyContactsSection(),

            const SizedBox(height: 20),

            // Live Landmark Direction Cards
            Text(
              context.l10n.translate('fsh_important_points'),
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
            ),
            const SizedBox(height: 10),

            ..._landmarks.map((l) => _buildLandmarkCard(l)),

            const SizedBox(height: 20),

            // Safety Guidelines
            _buildSafetyGuidelines(),
          ],
        ),
      ),
    );
  }

  Widget _buildSosBeacon() {
    return AnimatedBuilder(
      animation: _sirenAnimController,
      builder: (context, child) {
        final alertColor = _isSirenActive
            ? Color.lerp(Colors.red.shade900, Colors.redAccent,
                _sirenAnimController.value)!
            : const Color(0xFF1F2E33);

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: alertColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isSirenActive ? Colors.redAccent : Colors.white12,
              width: _isSirenActive ? 2 : 1,
            ),
            boxShadow: _isSirenActive
                ? [
                    BoxShadow(
                      color: Colors.redAccent.withValues(alpha: 0.5),
                      blurRadius: 16,
                      spreadRadius: 4,
                    )
                  ]
                : [],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          _isSirenActive ? Colors.white : Colors.red.shade700,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isSirenActive
                          ? Icons.notifications_active
                          : Icons.shield,
                      color: _isSirenActive ? Colors.red : Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isSirenActive
                              ? context.l10n.translate('fsh_alert_on')
                              : context.l10n.translate('fsh_family_sos'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isSirenActive
                              ? context.l10n.translate('fsh_alert_on_hint')
                              : context.l10n.translate('fsh_alert_off_hint'),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon:
                      Icon(_isSirenActive ? Icons.volume_off : Icons.volume_up),
                  label: Text(
                    _isSirenActive
                        ? context.l10n.translate('fsh_alert_turn_off')
                        : context.l10n.translate('fsh_alert_turn_on'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isSirenActive
                        ? Colors.white
                        : Colors.redAccent.shade700,
                    foregroundColor:
                        _isSirenActive ? Colors.red.shade900 : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _toggleAlert,
                  onLongPress: _shareLocation,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Open alerts from everyone in the tour. Empty when nothing is open.
  Widget _buildGroupAlerts() {
    return StreamBuilder<List<SafetyAlert>>(
      stream: _alerts,
      builder: (context, snapshot) {
        final now = DateTime.now();
        final open = (snapshot.data ?? const <SafetyAlert>[])
            .where((alert) => alert.isOpenAt(now))
            .toList();
        if (open.isEmpty) return const SizedBox.shrink();

        final me = _repository.currentEmail;
        final isAdmin = _myRole?.isAdminOrOwner ?? false;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.translate('fsh_group_alerts'),
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
            ),
            const SizedBox(height: 10),
            for (final alert in open)
              _buildAlertCard(
                alert,
                canResolve: alert.senderEmail == me || isAdmin,
              ),
            const SizedBox(height: 10),
          ],
        );
      },
    );
  }

  Widget _buildAlertCard(SafetyAlert alert, {required bool canResolve}) {
    final raised = alert.createdAt;
    final when = raised == null
        ? context.l10n.translate('fsh_just_now')
        : localizedDateFormat('dd MMM, HH:mm').format(raised);
    final lat = alert.latitude;
    final lng = alert.longitude;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF3B1F1F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.redAccent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.l10n.translate('fsh_sender_sent_alert',
                      args: {'name': alert.senderName}),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              Text(when,
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (lat != null && lng != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.map_rounded, size: 16),
                  label: Text(context.l10n.translate('fsh_view_location')),
                  onPressed: () => _openMapNavigation(lat, lng),
                ),
              if (canResolve)
                OutlinedButton.icon(
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: Text(context.l10n.translate('fsh_mark_safe')),
                  onPressed: () => _resolveFromCard(alert),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// The member's own switch for sharing their place with the family.
  Widget _buildLocationSharingCard() {
    final l10n = context.l10n;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF142428),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _locationShareOn
              ? AppColors.mintGreen.withValues(alpha: 0.5)
              : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _locationShareOn
                    ? Icons.my_location_rounded
                    : Icons.location_off_rounded,
                color: _locationShareOn ? AppColors.mintGreen : Colors.white54,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.translate('fsh_share_my_location'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      l10n.translate('fsh_share_my_location_sub'),
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _locationShareOn,
                activeThumbColor: AppColors.mintGreen,
                onChanged: (on) => unawaited(_setLocationSharing(on)),
              ),
            ],
          ),
          if (_locationShareOn) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.mintGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                l10n.translate('fsh_sharing_now_banner'),
                style: const TextStyle(
                  color: AppColors.mintGreen,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Every active member with their battery and place, as the family can see them.
  Widget _buildFamilyStatus() {
    final l10n = context.l10n;
    return StreamBuilder<List<TourMember>>(
      stream: _roster,
      builder: (context, rosterSnap) {
        return StreamBuilder<List<BatteryTelemetry>>(
          stream: _telemetry,
          builder: (context, telemetrySnap) {
            final members = (rosterSnap.data ?? const <TourMember>[])
                .where((m) => m.status == TourMemberStatus.active)
                .toList();
            if (members.isEmpty) return const SizedBox.shrink();
            final records = {
              for (final t in telemetrySnap.data ?? const <BatteryTelemetry>[])
                t.email: t,
            };
            final now = DateTime.now();
            final me = normalizeEmail(_repository.currentEmail);
            final hasLowBattery = members.any(
                (m) => records[normalizeEmail(m.email)]?.isLowBattery ?? false);

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF142428),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasLowBattery
                      ? Colors.redAccent.withValues(alpha: 0.4)
                      : Colors.white12,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.radar_rounded,
                        color: hasLowBattery
                            ? Colors.redAccent
                            : AppColors.mintGreen,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.translate('fsh_battery_radar_title'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              l10n.translate('fsh_family_status_sub'),
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (hasLowBattery) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.redAccent.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              size: 16, color: Colors.redAccent),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              l10n.translate('fsh_battery_low_warning'),
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  for (final member in members)
                    _buildMemberStatusRow(
                      member,
                      records[normalizeEmail(member.email)],
                      now,
                      isMe: normalizeEmail(member.email) == me,
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMemberStatusRow(
    TourMember member,
    BatteryTelemetry? record,
    DateTime now, {
    required bool isMe,
  }) {
    final l10n = context.l10n;
    final status = record == null ? null : locationStatusAt(record, now);
    final battery = record?.batteryLevel;
    final low = record?.isLowBattery ?? false;
    final critical = record?.isCriticalBattery ?? false;
    final updated = record?.updatedAt;
    final name = isMe
        ? '${member.displayName} (${l10n.translate('fsh_you')})'
        : member.displayName;

    final String placeText;
    if (record == null) {
      placeText = l10n.translate('fsh_no_update');
    } else if (status == LocationStatus.live) {
      placeText = l10n.translate('fsh_location_live');
    } else if (status == LocationStatus.lastKnown) {
      placeText = l10n.translate('fsh_location_last_known', args: {
        'time': localizedDateFormat('h:mm a').format(updated!),
      });
    } else if (record.sharing && record.latitude == null) {
      placeText = l10n.translate('fsh_location_waiting');
    } else {
      placeText = l10n.translate('fsh_location_off');
    }

    final showMap = record != null &&
        status != null &&
        status != LocationStatus.off &&
        record.latitude != null &&
        record.longitude != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: low
            ? Colors.redAccent.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: low ? Colors.redAccent.withValues(alpha: 0.3) : Colors.white10,
        ),
      ),
      child: Row(
        children: [
          Icon(
            battery == null
                ? Icons.battery_unknown_rounded
                : critical
                    ? Icons.battery_alert_rounded
                    : low
                        ? Icons.battery_2_bar_rounded
                        : Icons.battery_full_rounded,
            color: battery == null
                ? Colors.white54
                : critical
                    ? Colors.redAccent
                    : low
                        ? AppColors.gold
                        : AppColors.mintGreen,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  placeText,
                  style: TextStyle(
                    color: status == LocationStatus.live
                        ? AppColors.mintGreen
                        : Colors.white54,
                    fontSize: 11,
                  ),
                ),
                if (updated != null)
                  Text(
                    l10n.translate('fsh_battery_last_seen', args: {
                      'time': localizedDateFormat('h:mm a').format(updated),
                    }),
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
              ],
            ),
          ),
          if (record?.isCharging ?? false) ...[
            const Icon(Icons.bolt_rounded, size: 16, color: AppColors.gold),
            const SizedBox(width: 4),
          ],
          Text(
            battery == null
                ? l10n.translate('fsh_battery_unknown')
                : '${l10n.number(battery)}%',
            style: TextStyle(
              color: battery == null
                  ? Colors.white54
                  : critical
                      ? Colors.redAccent
                      : low
                          ? AppColors.gold
                          : AppColors.mintGreen,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          if (showMap) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: l10n.translate('fsh_battery_map_view'),
              icon: const Icon(Icons.map_rounded,
                  size: 18, color: AppColors.mintGreen),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                final uri = Uri.parse(
                    'https://maps.google.com/?q=${record.latitude},${record.longitude}');
                launchUrl(uri, mode: LaunchMode.externalApplication);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmergencyContactsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.translate('fsh_hotlines_title'),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildDialCard(
                title: context.l10n.translate('fsh_national_emergency'),
                number: '999',
                displayNumber: context.l10n.translate('fsh_999_free'),
                icon: Icons.emergency,
                color: Colors.redAccent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Builder(
          builder: (context) {
            final h = _getLocalHospitalContact();
            return _buildFullWidthDialCard(
              title: h.title,
              number: h.number,
              displayNumber: h.display,
              icon: Icons.local_hospital,
              color: Colors.teal,
            );
          },
        ),
      ],
    );
  }

  Widget _buildDialCard({
    required String title,
    required String number,
    required String displayNumber,
    required IconData icon,
    required Color color,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _callNumber(number),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF142428),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(displayNumber,
                  style: TextStyle(
                      color: color, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullWidthDialCard({
    required String title,
    required String number,
    required String displayNumber,
    required IconData icon,
    required Color color,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _callNumber(number),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF142428),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                  Text(displayNumber,
                      style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const Icon(Icons.phone_in_talk,
                color: Colors.greenAccent, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLandmarkCard(TourLandmark landmark) {
    int? distanceMeters;
    double? bearing;

    if (_currentPosition != null) {
      distanceMeters = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        landmark.lat,
        landmark.lng,
      ).round();

      bearing = _calculateBearing(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        landmark.lat,
        landmark.lng,
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF142428),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: landmark.color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: landmark.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(landmark.icon, color: landmark.color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  landmark.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  landmark.subtitle,
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
                if (distanceMeters != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.near_me,
                          size: 12, color: Colors.greenAccent),
                      const SizedBox(width: 4),
                      Text(
                        distanceMeters > 1000
                            ? context.l10n.translate('fsh_km_away', args: {
                                'km': (distanceMeters / 1000).toStringAsFixed(1)
                              })
                            : context.l10n.translate('fsh_meters_away',
                                args: {'meters': distanceMeters}),
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                      if (bearing != null) ...[
                        const SizedBox(width: 8),
                        Transform.rotate(
                          angle: ((bearing - _headingDegrees) * math.pi / 180),
                          child: const Icon(Icons.arrow_upward,
                              size: 12, color: Colors.amberAccent),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.directions, color: Colors.tealAccent),
            tooltip: context.l10n.translate('fsh_google_directions'),
            onPressed: () => _openMapNavigation(landmark.lat, landmark.lng),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyGuidelines() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF102024),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.amber, size: 18),
              const SizedBox(width: 8),
              Text(
                context.l10n.translate('fsh_sea_guide_title'),
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.translate('fsh_sea_guide_body'),
            style: const TextStyle(
                color: Colors.white70, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }
}
