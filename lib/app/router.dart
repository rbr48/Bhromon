import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bhromon/core/theme/app_motion.dart';
import 'di/injection.dart';
import '../core/utils/logger.dart';
import 'route_not_found_screen.dart';
import '../features/auth/presentation/cubit/auth_cubit.dart';
import '../features/auth/presentation/cubit/auth_state.dart';
import '../features/auth/presentation/pages/login_screen.dart';
import '../features/trust/presentation/pages/trust_dashboard_screen.dart'
    deferred as trust_dashboard;
import '../features/explorer/presentation/pages/explorer_profile_screen.dart';

import '../features/notifications/presentation/pages/notification_settings_screen.dart';
import '../features/auth/presentation/pages/account_deletion_page.dart'
    deferred as account_deletion;
import '../features/chat/presentation/pages/chats_list_screen.dart';
import '../features/chat/presentation/pages/chat_screen.dart';
import '../features/chat/presentation/pages/call_screen.dart'
    deferred as call_page;
import '../features/chat/presentation/pages/starred_messages_screen.dart';

import '../features/tour_group/presentation/pages/join_by_qr_screen.dart';
import '../features/tour_group/presentation/pages/join_group_screen.dart';
import '../features/tour_group/presentation/pages/tour_group_hub_screen.dart';
import '../features/tour_group/presentation/pages/expense_ledger_screen.dart';
import '../features/tour_group/presentation/pages/tour_logistics_hub_screen.dart'
    deferred as tour_logistics;
import '../features/tour_group/presentation/pages/holiday_calendar_screen.dart'
    deferred as holiday_calendar;
import '../features/tour_group/presentation/pages/family_dates_screen.dart'
    deferred as family_dates;
import '../features/tour_group/presentation/pages/study_books_screen.dart'
    deferred as study_books;
import '../features/tour_group/presentation/pages/study_reading_screen.dart'
    deferred as study_reading;
import '../features/tour_group/presentation/pages/study_subjects_screen.dart'
    deferred as study_subjects;
import '../features/tour_group/presentation/pages/family_album_screen.dart'
    deferred as family_album;
import '../features/tour_group/presentation/pages/family_dependents_screen.dart'
    deferred as family_dependents;
import '../features/tour_group/presentation/pages/family_tasks_screen.dart';
import '../features/tour_group/presentation/pages/meals_screen.dart'
    deferred as meals_page;
import '../features/tour_group/presentation/pages/samity_screen.dart'
    deferred as samity_page;
import '../features/tour_group/presentation/pages/society_requests_screen.dart'
    deferred as society_requests;
import '../features/tour_group/presentation/pages/tide_beach_guide_screen.dart'
    deferred as tide_guide;
import '../features/tour_group/presentation/pages/group_channels_screen.dart';
import '../features/tour_group/presentation/pages/tour_checklist_screen.dart'
    deferred as tour_checklist;
import '../features/tour_group/presentation/pages/tour_instafeed_screen.dart';
import '../features/tour_group/presentation/pages/family_safety_hub_screen.dart'
    deferred as family_safety;
import '../features/tour_group/presentation/pages/journey_tracker_screen.dart'
    deferred as journey_tracker;
import '../features/tour_group/presentation/pages/offline_map_viewer_screen.dart'
    deferred as offline_map_viewer;
import '../features/tour_group/domain/services/offline_map_regions.dart';
import '../features/tour_group/domain/models/tour_group.dart';
import '../features/tour_group/presentation/pages/notice_board_screen.dart';
import '../features/tour_group/presentation/pages/tour_quiz_screen.dart'
    deferred as tour_quiz;
import '../features/tour_group/presentation/widgets/tour_membership_guard.dart';
import '../features/tour_group/presentation/pages/tour_scrapbook_screen.dart'
    deferred as tour_scrapbook;
import '../features/tour_group/presentation/widgets/trip_shell.dart';
import '../features/tour_group/data/active_group.dart';
import 'tour_page_key.dart';
import '../features/game_zone/teen_patti/teen_patti_screen.dart'
    deferred as game_teen_patti;

import '../features/game_zone/game_zone_hub_screen.dart'
    deferred as game_zone_hub;
import '../features/game_zone/card29/card29_screen.dart'
    deferred as game_card29;
import '../features/game_zone/chess/chess_screen.dart' deferred as game_chess;
import '../features/game_zone/ludo/ludo_screen.dart' deferred as game_ludo;
import '../features/game_zone/carrom/carrom_screen.dart'
    deferred as game_carrom;
import '../features/game_zone/online/online_game_table_screen.dart'
    deferred as game_online_table;
import '../features/notifications/presentation/pages/notification_center_screen.dart';
import '../features/official_feed/presentation/official_feed_screen.dart'
    deferred as official_feed;
import '../features/newspaper/presentation/pages/newspaper_hub_screen.dart'
    deferred as newspaper_hub;
import '../features/newspaper/presentation/pages/adfree_article_reader_screen.dart'
    deferred as newspaper_reader;
import '../features/newspaper/presentation/pages/adblock_browser_screen.dart'
    deferred as newspaper_browser;
import '../features/newspaper/domain/models/newspaper_models.dart';
import '../features/share_intake/domain/shared_file.dart';

class AppRouter {
  static final _rootNavigatorKey = GlobalKey<NavigatorState>();
  static GlobalKey<NavigatorState> get navigatorKey => _rootNavigatorKey;

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/group-hub',
    errorBuilder: (context, state) {
      logWarning('[router] no page for ${state.uri}');
      return const RouteNotFoundScreen();
    },
    redirect: (context, state) {
      final authState = context.read<AuthCubit>().state;
      final bool loggingIn = state.matchedLocation == '/login';

      if (authState is Unauthenticated) {
        if (state.matchedLocation.startsWith('/join')) {
          return null;
        }
        return loggingIn ? null : '/login';
      }

      if (authState is Authenticated && loggingIn) {
        final redirect = state.uri.queryParameters['redirect'];
        if (redirect != null && redirect.isNotEmpty) {
          return redirect;
        }
        return '/group-hub';
      }

      return null;
    },
    refreshListenable: GoRouterRefreshStream(getIt<AuthCubit>().stream),
    routes: [
      GoRoute(
        path: '/',
        redirect: (context, state) => '/group-hub',
      ),
      GoRoute(
        path: '/join',
        redirect: (context, state) {
          final code = state.uri.queryParameters['code'];
          if (code != null && code.isNotEmpty) {
            return '/join/$code';
          }
          return '/group-hub';
        },
      ),
      GoRoute(
        path: '/join/:code',
        pageBuilder: (context, state) {
          final code = state.pathParameters['code'] ?? '';
          final auto = state.uri.queryParameters['auto'] == 'true';
          final name = state.uri.queryParameters['name'];
          return _customPageTransition(
            state,
            JoinGroupScreen(
              inviteCode: code,
              autoJoin: auto,
              initialGroupName: name,
            ),
          );
        },
      ),
      GoRoute(
        path: '/join-by-qr',
        pageBuilder: (context, state) =>
            _customPageTransition(state, const JoinByQrScreen()),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) =>
            _customPageTransition(state, const LoginScreen()),
      ),
      GoRoute(
        path: '/notifications',
        pageBuilder: (context, state) =>
            _desktopShellPage(state, const NotificationCenterScreen()),
      ),
      GoRoute(
        path: '/official-feed',
        pageBuilder: (context, state) => _desktopShellPage(
          state,
          _DeferredRoute(
            moduleKey: 'official_feed',
            loadLibrary: official_feed.loadLibrary,
            builder: (_) => official_feed.OfficialFeedScreen(),
          ),
        ),
      ),
      GoRoute(
        path: '/profile/:uid',
        pageBuilder: (context, state) => _desktopShellPage(
          state,
          ExplorerProfileScreen(
            uid: state.pathParameters['uid']!,
            tourId: state.uri.queryParameters['tourId'],
            emailHint: state.extra is Map
                ? (state.extra as Map)['email'] as String?
                : null,
          ),
          tourId: state.uri.queryParameters['tourId'],
        ),
      ),
      GoRoute(
        path: '/trust',
        pageBuilder: (context, state) => _desktopShellPage(
          state,
          _DeferredRoute(
            moduleKey: 'trust_dashboard',
            loadLibrary: trust_dashboard.loadLibrary,
            builder: (_) => trust_dashboard.TrustDashboardScreen(),
          ),
        ),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) =>
            _desktopShellPage(state, const NotificationSettingsScreen()),
      ),
      GoRoute(
        path: '/delete-account',
        pageBuilder: (context, state) => _customPageTransition(
          state,
          _DeferredRoute(
            moduleKey: 'account_deletion',
            loadLibrary: account_deletion.loadLibrary,
            builder: (_) => account_deletion.AccountDeletionPage(),
          ),
        ),
      ),
      GoRoute(
        path: '/chats',
        pageBuilder: (context, state) =>
            _desktopShellPage(state, const ChatsListScreen()),
      ),
      GoRoute(
        path: '/chat/:chatId',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final otherUid = extra?['otherUid'] as String?;
          final sharedTourId = (extra?['sharedTourId'] as String?) ??
              state.uri.queryParameters['tourId'];
          return _desktopShellPage(
            state,
            ChatScreen(
              chatId: state.pathParameters['chatId']!,
              otherUid: otherUid,
              sharedTourId: sharedTourId,
              otherEmail: extra?['otherEmail'] as String?,
              otherAvatarUrl: extra?['otherAvatarUrl'] as String?,
              sharedFiles: (extra?['sharedFiles'] as List?)?.cast<SharedFile>(),
            ),
            tourId: sharedTourId,
          );
        },
      ),
      GoRoute(
        path: '/call/:callId',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final query = state.uri.queryParameters;
          final sharedTourId =
              (extra['sharedTourId'] as String?) ?? query['tourId'];
          final localUid = (extra['localUid'] as String?) ??
              FirebaseAuth.instance.currentUser?.uid ??
              '';
          final remoteUid =
              (extra['remoteUid'] as String?) ?? query['callerId'] ?? '';
          final remoteUserName = (extra['remoteUserName'] as String?) ??
              query['callerName'] ??
              'Member';
          final isVideoCall = extra['isVideoCall'] as bool? ??
              (query.containsKey('isVideo')
                  ? query['isVideo'] == 'true'
                  : true);
          return _customPageTransition(
            state,
            _DeferredRoute(
              moduleKey: 'call_page',
              loadLibrary: call_page.loadLibrary,
              builder: (_) => call_page.CallScreen(
                callId: state.pathParameters['callId']!,
                localUid: localUid,
                remoteUid: remoteUid,
                remoteEmail: extra['remoteEmail'] as String?,
                sharedTourId: sharedTourId,
                remoteUserName: remoteUserName,
                remoteAvatarUrl: extra['remoteAvatarUrl'] as String?,
                isCaller: extra['isCaller'] as bool? ?? false,
                isVideoCall: isVideoCall,
                localUserName: extra['localUserName'] as String?,
                localAvatarUrl: extra['localAvatarUrl'] as String?,
              ),
            ),
          );
        },
      ),
      GoRoute(
        path: '/starred-messages',
        pageBuilder: (context, state) =>
            _desktopShellPage(state, const StarredMessagesScreen()),
      ),
      GoRoute(
        path: '/group-hub',
        pageBuilder: (context, state) => _desktopShellPage(
          state,
          TourGroupHubScreen(
            initialTourId: state.uri.queryParameters['tourId'],
          ),
          tourId: state.uri.queryParameters['tourId'],
        ),
      ),
      GoRoute(
        path: '/group/:tourId/ledger',
        pageBuilder: (context, state) => _tripPage(
          state,
          ExpenseLedgerScreen(tourId: state.pathParameters['tourId']!),
        ),
      ),
      GoRoute(
        path: '/group/:tourId/logistics',
        pageBuilder: (context, state) => _tripPage(
          state,
          _DeferredRoute(
            moduleKey: 'tour_logistics',
            loadLibrary: tour_logistics.loadLibrary,
            builder: (_) => tour_logistics.TourLogisticsHubScreen(
                tourId: state.pathParameters['tourId']!),
          ),
        ),
      ),
      GoRoute(
        path: '/group/:tourId/calendar',
        redirect: (context, state) =>
            '/group/${state.pathParameters["tourId"]!}/family-dates',
      ),
      GoRoute(
        path: '/group/:tourId/important-dates',
        redirect: (context, state) =>
            '/group/${state.pathParameters["tourId"]!}/family-dates',
      ),
      GoRoute(
        path: '/group/:tourId/family-dates',
        pageBuilder: (context, state) => _tripPage(
          state,
          _DeferredRoute(
            moduleKey: 'family_dates',
            loadLibrary: family_dates.loadLibrary,
            builder: (_) => family_dates.FamilyDatesScreen(
              tourId: state.pathParameters['tourId']!,
              group: state.extra as TourGroup?,
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/group/:tourId/study-books',
        pageBuilder: (context, state) => _tripPage(
          state,
          _DeferredRoute(
            moduleKey: 'study_books',
            loadLibrary: study_books.loadLibrary,
            builder: (_) => study_books.StudyBooksScreen(
                tourId: state.pathParameters['tourId']!),
          ),
        ),
      ),
      GoRoute(
        path: '/group/:tourId/study-subjects',
        pageBuilder: (context, state) => _tripPage(
          state,
          _DeferredRoute(
            moduleKey: 'study_subjects',
            loadLibrary: study_subjects.loadLibrary,
            builder: (_) => study_subjects.StudySubjectsScreen(
                tourId: state.pathParameters['tourId']!),
          ),
        ),
      ),
      GoRoute(
        path: '/group/:tourId/study-reading',
        pageBuilder: (context, state) => _tripPage(
          state,
          _DeferredRoute(
            moduleKey: 'study_reading',
            loadLibrary: study_reading.loadLibrary,
            builder: (_) => study_reading.StudyReadingScreen(
                tourId: state.pathParameters['tourId']!),
          ),
        ),
      ),
      GoRoute(
        path: '/group/:tourId/album',
        pageBuilder: (context, state) => _tripPage(
          state,
          _DeferredRoute(
            moduleKey: 'family_album',
            loadLibrary: family_album.loadLibrary,
            builder: (_) => family_album.FamilyAlbumScreen(
                tourId: state.pathParameters['tourId']!),
          ),
        ),
      ),
      GoRoute(
        path: '/group/:tourId/dependents',
        pageBuilder: (context, state) => _tripPage(
          state,
          _DeferredRoute(
            moduleKey: 'family_dependents',
            loadLibrary: family_dependents.loadLibrary,
            builder: (_) => family_dependents.FamilyDependentsScreen(
                tourId: state.pathParameters['tourId']!),
          ),
        ),
      ),
      GoRoute(
        path: '/group/:tourId/family-tasks',
        pageBuilder: (context, state) => _tripPage(
          state,
          FamilyTasksScreen(tourId: state.pathParameters['tourId']!),
        ),
      ),
      GoRoute(
        path: '/group/:tourId/meals',
        pageBuilder: (context, state) => _tripPage(
          state,
          _DeferredRoute(
            moduleKey: 'meals_page',
            loadLibrary: meals_page.loadLibrary,
            builder: (_) =>
                meals_page.MealsScreen(tourId: state.pathParameters['tourId']!),
          ),
        ),
      ),
      GoRoute(
        path: '/group/:tourId/requests',
        pageBuilder: (context, state) => _tripPage(
          state,
          _DeferredRoute(
            moduleKey: 'society_requests',
            loadLibrary: society_requests.loadLibrary,
            builder: (_) => society_requests.SocietyRequestsScreen(
                tourId: state.pathParameters['tourId']!),
          ),
        ),
      ),
      GoRoute(
        path: '/group/:tourId/samity',
        pageBuilder: (context, state) => _tripPage(
          state,
          _DeferredRoute(
            moduleKey: 'samity_page',
            loadLibrary: samity_page.loadLibrary,
            builder: (_) => samity_page.SamityScreen(
                tourId: state.pathParameters['tourId']!),
          ),
        ),
      ),
      GoRoute(
        path: '/group/:tourId/tide',
        pageBuilder: (context, state) => _tripPage(
          state,
          _DeferredRoute(
            moduleKey: 'tide_guide',
            loadLibrary: tide_guide.loadLibrary,
            builder: (_) => tide_guide.TideBeachGuideScreen(
                tourId: state.pathParameters['tourId']!),
          ),
        ),
      ),
      GoRoute(
        path: '/group/:tourId/channels',
        // The tab bar stays under a group chat on a phone. It leaves while the keyboard is open,
        // so the text box sits on the keyboard (see TripShell.hideNavWhileTyping).
        pageBuilder: (context, state) => _tripPage(
          state,
          GroupChannelsScreen(tourId: state.pathParameters['tourId']!),
          hideNavWhileTyping: true,
        ),
      ),
      GoRoute(
        path: '/group/:tourId/checklist',
        pageBuilder: (context, state) => _tripPage(
          state,
          _DeferredRoute(
            moduleKey: 'tour_checklist',
            loadLibrary: tour_checklist.loadLibrary,
            builder: (_) => tour_checklist.TourChecklistScreen(
                tourId: state.pathParameters['tourId']!),
          ),
        ),
      ),
      GoRoute(
        path: '/group/:tourId/feed',
        pageBuilder: (context, state) => _tripPage(
          state,
          TourInstaFeedScreen(tourId: state.pathParameters['tourId']!),
        ),
      ),
      GoRoute(
        path: '/group/:tourId/safety',
        pageBuilder: (context, state) => _tripPage(
          state,
          _DeferredRoute(
            moduleKey: 'family_safety',
            loadLibrary: family_safety.loadLibrary,
            builder: (_) => family_safety.FamilySafetyHubScreen(
                tourId: state.pathParameters['tourId']!),
          ),
        ),
      ),
      GoRoute(
        path: '/group/:tourId/journey',
        pageBuilder: (context, state) => _tripPage(
          state,
          _DeferredRoute(
            moduleKey: 'journey_tracker',
            loadLibrary: journey_tracker.loadLibrary,
            builder: (_) => journey_tracker.JourneyTrackerScreen(
                tourId: state.pathParameters['tourId']!),
          ),
        ),
      ),
      GoRoute(
        path: '/group/:tourId/notices',
        pageBuilder: (context, state) => _tripPage(
          state,
          NoticeBoardScreen(tourId: state.pathParameters['tourId']!),
        ),
      ),
      GoRoute(
        path: '/group/:tourId/quiz',
        pageBuilder: (context, state) => _tripPage(
          state,
          _DeferredRoute(
            moduleKey: 'tour_quiz',
            loadLibrary: tour_quiz.loadLibrary,
            builder: (_) => tour_quiz.TourQuizScreen(
                tourId: state.pathParameters['tourId']!),
          ),
        ),
      ),
      GoRoute(
        path: '/group/:tourId/scrapbook',
        pageBuilder: (context, state) => _tripPage(
          state,
          _DeferredRoute(
            moduleKey: 'tour_scrapbook',
            loadLibrary: tour_scrapbook.loadLibrary,
            builder: (_) => tour_scrapbook.TourScrapbookScreen(
                tourId: state.pathParameters['tourId']!),
          ),
        ),
      ),
      GoRoute(
        path: '/offline-map/:regionId',
        pageBuilder: (context, state) {
          final id = state.pathParameters['regionId'] ?? 'sajek_valley';
          final region = regionById(id) ??
              kCuratedOfflineRegions.firstWhere(
                (r) => r.id == id,
                orElse: () => kCuratedOfflineRegions.first,
              );
          return _customPageTransition(
            state,
            _DeferredRoute(
              moduleKey: 'offline_map_viewer',
              loadLibrary: offline_map_viewer.loadLibrary,
              builder: (_) =>
                  offline_map_viewer.OfflineMapViewerScreen(region: region),
            ),
            key: pageKeyFor(state),
          );
        },
      ),
      GoRoute(
        path: '/game-zone',
        pageBuilder: (context, state) => _desktopShellPage(
          state,
          _DeferredRoute(
            moduleKey: 'game_zone_hub',
            loadLibrary: game_zone_hub.loadLibrary,
            builder: (_) => game_zone_hub.GameZoneHubScreen(
                initialTourId: state.uri.queryParameters['tourId']),
          ),
          tourId: state.uri.queryParameters['tourId'],
        ),
      ),
      GoRoute(
        path: '/game-zone/card29',
        pageBuilder: (context, state) => _desktopShellPage(
          state,
          _DeferredRoute(
            moduleKey: 'game_card29',
            loadLibrary: game_card29.loadLibrary,
            builder: (_) => game_card29.Card29Screen(),
          ),
        ),
      ),
      GoRoute(
        path: '/game-zone/chess',
        pageBuilder: (context, state) => _desktopShellPage(
          state,
          _DeferredRoute(
            moduleKey: 'game_chess',
            loadLibrary: game_chess.loadLibrary,
            builder: (_) => game_chess.ChessScreen(),
          ),
        ),
      ),
      GoRoute(
        path: '/game-zone/ludo',
        pageBuilder: (context, state) => _desktopShellPage(
          state,
          _DeferredRoute(
            moduleKey: 'game_ludo',
            loadLibrary: game_ludo.loadLibrary,
            builder: (_) => game_ludo.LudoScreen(),
          ),
        ),
      ),
      GoRoute(
        path: '/game-zone/teen-patti',
        pageBuilder: (context, state) => _desktopShellPage(
          state,
          _DeferredRoute(
            moduleKey: 'game_teen_patti',
            loadLibrary: game_teen_patti.loadLibrary,
            builder: (_) => game_teen_patti.TeenPattiScreen(),
          ),
        ),
      ),
      GoRoute(
        path: '/game-zone/carrom',
        pageBuilder: (context, state) => _desktopShellPage(
          state,
          _DeferredRoute(
            moduleKey: 'game_carrom',
            loadLibrary: game_carrom.loadLibrary,
            builder: (_) => game_carrom.CarromScreen(),
          ),
        ),
      ),
      GoRoute(
        path: '/game-zone/table/:tourId/:gameId',
        pageBuilder: (context, state) {
          final tourId = state.pathParameters['tourId']!;
          final gameId = state.pathParameters['gameId']!;
          return _desktopShellPage(
            state,
            TourMembershipGuard(
              tourId: tourId,
              child: _DeferredRoute(
                moduleKey: 'game_online_table',
                loadLibrary: game_online_table.loadLibrary,
                builder: (_) => game_online_table.OnlineGameTableScreen(
                    tourId: tourId, gameId: gameId),
              ),
            ),
            tourId: tourId,
          );
        },
      ),
      GoRoute(
        path: '/newspaper-hub',
        pageBuilder: (context, state) {
          final tourId = state.uri.queryParameters['tourId'];
          return _desktopShellPage(
            state,
            _DeferredRoute(
              moduleKey: 'newspaper_hub',
              loadLibrary: newspaper_hub.loadLibrary,
              builder: (_) => newspaper_hub.NewspaperHubScreen(tourId: tourId),
            ),
            tourId: tourId,
          );
        },
      ),
      GoRoute(
        path: '/holiday-calendar',
        pageBuilder: (context, state) => _desktopShellPage(
          state,
          _DeferredRoute(
            moduleKey: 'holiday_calendar',
            loadLibrary: holiday_calendar.loadLibrary,
            builder: (_) => holiday_calendar.HolidayCalendarScreen(tourId: ''),
          ),
        ),
      ),
      GoRoute(
        path: '/newspaper-reader',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final url =
              state.uri.queryParameters['url'] ?? extra['url'] as String? ?? '';
          return _desktopShellPage(
            state,
            _DeferredRoute(
              moduleKey: 'newspaper_reader',
              loadLibrary: newspaper_reader.loadLibrary,
              builder: (_) => newspaper_reader.AdFreeArticleReaderScreen(
                articleUrl: url,
                initialTitle: extra['title'] as String?,
                initialSourceName: extra['sourceName'] as String?,
                initialImageUrl: extra['imageUrl'] as String?,
              ),
            ),
          );
        },
      ),
      GoRoute(
        path: '/newspaper-browser',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final url =
              state.uri.queryParameters['url'] ?? extra['url'] as String? ?? '';
          final title = state.uri.queryParameters['title'] ??
              extra['title'] as String? ??
              'Web Browser';
          return _desktopShellPage(
            state,
            _DeferredRoute(
              moduleKey: 'newspaper_browser',
              loadLibrary: newspaper_browser.loadLibrary,
              builder: (_) => newspaper_browser.AdBlockBrowserScreen(
                initialUrl: url,
                initialTitle: title,
                paper: extra['paper'] as Newspaper?,
              ),
            ),
          );
        },
      ),
    ],
  );

  /// A tour screen inside the trip bar. See [TripShell] for why this is not a
  /// ShellRoute.
  static Page<void> _tripPage(GoRouterState state, Widget screen,
      {bool hideNavWhileTyping = false}) {
    return _customPageTransition(
      state,
      TripShell(
        tourId: state.pathParameters['tourId']!,
        location: state.uri.path,
        hideNavWhileTyping: hideNavWhileTyping,
        child: screen,
      ),
      key: pageKeyFor(state),
    );
  }

  /// A top-level screen wrapped with the unified 3-column desktop shell on desktop (>= 900px),
  /// while preserving its native standalone mobile layout (< 900px) with zero regressions.
  static Page<void> _desktopShellPage(
    GoRouterState state,
    Widget screen, {
    String? tourId,
  }) {
    final effectiveTourId = tourId ??
        state.pathParameters['tourId'] ??
        state.uri.queryParameters['tourId'] ??
        ActiveGroup.instance.current ??
        '';

    return _customPageTransition(
      state,
      TripShell(
        tourId: effectiveTourId,
        location: state.uri.path,
        guardMembership: false,
        ownMobileScaffold: true,
        child: screen,
      ),
      key: pageKeyFor(state),
    );
  }

  static Page<void> _customPageTransition(
    GoRouterState state,
    Widget child, {
    ValueKey<String>? key,
  }) {
    return CustomTransitionPage<void>(
      key: key ?? state.pageKey,
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return AppMotion.pageTransition(context, animation, child);
      },
      transitionDuration: AppMotion.page,
    );
  }
}

class GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _subscription;

  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen(
          (dynamic _) => notifyListeners(),
        );
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

/// Loads a deferred route chunk on demand and renders synchronously once cached.
class _DeferredRoute extends StatefulWidget {
  final String moduleKey;
  final Future<void> Function() loadLibrary;
  final WidgetBuilder builder;

  const _DeferredRoute({
    required this.moduleKey,
    required this.loadLibrary,
    required this.builder,
  });

  static final Set<String> _loaded = <String>{};
  static final Map<String, Future<void>> _pending = <String, Future<void>>{};

  @override
  State<_DeferredRoute> createState() => _DeferredRouteState();
}

class _DeferredRouteState extends State<_DeferredRoute> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (!_DeferredRoute._loaded.contains(widget.moduleKey)) {
      _startLoad();
    }
  }

  void _startLoad({bool rebuild = false}) {
    if (rebuild && mounted) {
      setState(() => _error = null);
    } else {
      _error = null;
    }
    final future = _DeferredRoute._pending[widget.moduleKey] ??=
        widget.loadLibrary().then((_) {
      _DeferredRoute._loaded.add(widget.moduleKey);
      _DeferredRoute._pending.remove(widget.moduleKey);
    }).catchError((Object error) {
      _DeferredRoute._pending.remove(widget.moduleKey);
      throw error;
    });
    future.then((_) {
      if (mounted) setState(() {});
    }, onError: (Object error) {
      if (mounted) setState(() => _error = error);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_DeferredRoute._loaded.contains(widget.moduleKey)) {
      return widget.builder(context);
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off_rounded, size: 42),
                const SizedBox(height: 12),
                const Text(
                  'Could not load this screen',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _startLoad(rebuild: true),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
