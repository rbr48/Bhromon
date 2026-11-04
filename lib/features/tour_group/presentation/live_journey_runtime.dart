import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import '../../../../app/router.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/locale_controller.dart';
import '../../../../core/utils/app_logger.dart';
import '../data/journey_alarm_scheduler.dart';
import '../data/journey_alarm_sound.dart';
import '../data/journey_location_source.dart';
import '../data/journey_notifications.dart';
import '../data/journey_prefs_store.dart';
import '../data/live_journey_session.dart';
import '../data/tour_group_repository.dart';
import '../domain/models/tour_group.dart';
import '../domain/services/journey_alarm_ring.dart';
import '../domain/services/journey_alert_presentation.dart';
import '../domain/services/journey_targets.dart';
import 'pages/journey_alarm_page.dart';

/// The one live journey of the app (roadmap phases 2 and 3). It wires the
/// session to the platform: the location stream, the notifications, the Hive
/// box, the localizer and the navigator. Nothing starts until the user starts a
/// trip, and the whole runtime stays off unless `kLiveJourney` is set.
class LiveJourneyRuntime {
  LiveJourneyRuntime._();

  static final LiveJourneyRuntime instance = LiveJourneyRuntime._();

  Future<LiveJourneySession>? _opening;
  int? _ringingId;

  /// The app's session, created on first use.
  Future<LiveJourneySession> session() => _opening ??= _open();

  Future<LiveJourneySession> _open() async {
    final store = JourneyPrefsStore(await HiveJourneyPrefsBackend.open());
    final plugin = FlutterLocalNotificationsPlugin();
    final location = JourneyLocationSource();
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    return LiveJourneySession(
      store: store,
      fixes: (sampling, title, text) => location.fixes(
        sampling: sampling,
        isAndroid: isAndroid,
        notificationTitle: title,
        notificationText: text,
      ),
      scheduler:
          JourneyAlarmScheduler(port: FlutterJourneyNotificationPort(plugin)),
      notices: FlutterJourneyNoticePort(plugin),
      events: const NoopJourneyEventSink(),
      text: _translate,
      formatNumber: _formatNumber,
      onRing: (ring) => openAlarm(
        id: ring.id,
        title: _translate(ring.title),
        body: _translate(ring.body),
      ),
    );
  }

  /// Starts a trip on [group]. The caller has already settled the location
  /// permission (see `journey_access_flow.dart`).
  Future<void> startJourney(TourGroup group) async {
    final s = await session();
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    await s.start(
      group: group,
      tripId: id,
      plannedFinalEta: plannedArrivalAt(group),
      copy: _serviceCopy(),
    );
  }

  /// Ends the running trip.
  Future<void> stopJourney() async => (await session()).stop();

  /// Resumes a trip stored before the app closed (roadmap LJ-3.5). It needs a
  /// signed-in user, and the group the trip belongs to. Without them the trip
  /// stays stored, and the next open of its journey screen can resume it.
  Future<void> resumeOnLaunch() async {
    final s = await session();
    if (s.isTracking) return;
    final stored = s.store.readTrip();
    if (stored == null || FirebaseAuth.instance.currentUser == null) return;
    final group = await TourGroupRepository()
        .watchGroup(stored.tourId)
        .first
        .timeout(const Duration(seconds: 15));
    if (group == null) return;
    await s.restore(group: group, copy: _serviceCopy());
  }

  /// Opens the full-screen alarm once for [id]. A second call for a ring that is
  /// already showing does nothing.
  void openAlarm({
    required int id,
    required String title,
    required String body,
  }) {
    if (_ringingId == id) return;
    final navigator = AppRouter.navigatorKey.currentState;
    if (navigator == null) return;
    _ringingId = id;
    navigator.push<void>(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => JourneyAlarmPage(
        title: title,
        body: body,
        ring: AlarmRing(),
        sound: AudioPlayersJourneyAlarmSound(),
        onFinished: (_) {
          _ringingId = null;
          unawaited(navigator.maybePop());
        },
      ),
    ));
  }

  JourneyServiceCopy _serviceCopy() => JourneyServiceCopy(
        title: _translate(const JourneyText('journey_fg_title')),
        tracking: _translate(const JourneyText('journey_fg_tracking')),
        sharing: _translate(const JourneyText('journey_fg_sharing')),
      );
}

String _translate(JourneyText text) {
  return AppLocalizations(LocaleController.instance.locale)
      .translate(text.key, args: text.args);
}

String _formatNumber(num value) {
  return AppLocalizations(LocaleController.instance.locale).number(value);
}

/// Records nothing. The Firestore sink replaces it when group events ship
/// (roadmap LJ-4.2).
class NoopJourneyEventSink implements JourneyEventSink {
  const NoopJourneyEventSink();

  @override
  Future<void> record({
    required String tourId,
    required String stopId,
    required JourneyEventType type,
  }) async {}
}

/// Creates the journey's time zones, channels and tap handler. The app calls
/// it at start-up when `kLiveJourney` is on. Sign-in sets the plugin's tap
/// handler again, and that handler calls [handleJourneyNotificationPayload] too.
Future<void> initJourneyNotifications() async {
  tz_data.initializeTimeZones();
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/launcher_icon'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ),
    onDidReceiveNotificationResponse: (response) {
      final payload = response.payload;
      if (payload != null) handleJourneyNotificationPayload(payload);
    },
  );
  final android = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  if (android != null) await createJourneyChannels(android);
}

/// Starts the journey at launch when the feature is on: the channels and the tap
/// handler, a trip stored before the app closed, and a tap that opened the app
/// from a journey notification. Errors are logged, and the app runs without the
/// feature.
Future<void> startLiveJourney() async {
  try {
    await initJourneyNotifications();
    final plugin = FlutterLocalNotificationsPlugin();
    final launch = await plugin.getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload;
    if (launch?.didNotificationLaunchApp == true && payload != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        handleJourneyNotificationPayload(payload);
      });
    }
    await LiveJourneyRuntime.instance.resumeOnLaunch();
  } catch (error, stackTrace) {
    logWarning('Live journey did not start', error, stackTrace);
  }
}

/// Opens what a journey notification points at. Returns false when the payload
/// is not a journey payload, so the caller can route it another way.
///
/// A stop notice opens the tour's journey screen. An alarm opens the full-screen
/// alarm page with the notice's text.
bool handleJourneyNotificationPayload(String payload) {
  final Object? data;
  try {
    data = jsonDecode(payload);
  } catch (_) {
    return false;
  }
  if (data is! Map) return false;
  switch (data['kind']) {
    case 'journey':
      final tourId = data['tourId'];
      if (tourId is! String || tourId.isEmpty) return false;
      unawaited(AppRouter.router.push('/group/$tourId/journey'));
      return true;
    case 'journey_alarm':
      final title = data['title'];
      final body = data['body'];
      LiveJourneyRuntime.instance.openAlarm(
        id: payload.hashCode,
        title: title is String ? title : '',
        body: body is String ? body : '',
      );
      return true;
    default:
      return false;
  }
}
