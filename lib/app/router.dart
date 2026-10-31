import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'di/injection.dart';
import '../features/auth/presentation/cubit/auth_cubit.dart';
import '../features/auth/presentation/cubit/auth_state.dart';
import '../features/auth/presentation/pages/login_screen.dart';
import '../features/offline_vault/presentation/pages/offline_vault_screen.dart';
import '../features/trust/presentation/pages/trust_dashboard_screen.dart';
import '../features/explorer/presentation/pages/explorer_profile_screen.dart';

import '../features/notifications/presentation/pages/notification_settings_screen.dart';
import '../features/auth/presentation/pages/account_deletion_page.dart';
import '../features/chat/presentation/pages/chats_list_screen.dart';
import '../features/chat/presentation/pages/chat_screen.dart';
import '../features/chat/presentation/pages/call_screen.dart';
import '../features/chat/presentation/pages/starred_messages_screen.dart';

import '../features/tour_group/presentation/pages/tour_group_hub_screen.dart';
import '../features/tour_group/presentation/pages/expense_ledger_screen.dart';
import '../features/tour_group/presentation/pages/tour_logistics_hub_screen.dart';
import '../features/tour_group/presentation/pages/holiday_calendar_screen.dart';
import '../features/tour_group/presentation/pages/family_dates_screen.dart';
import '../features/tour_group/presentation/pages/family_dependents_screen.dart';
import '../features/tour_group/presentation/pages/family_tasks_screen.dart';
import '../features/tour_group/presentation/pages/tide_beach_guide_screen.dart';
import '../features/tour_group/presentation/pages/group_channels_screen.dart';
import '../features/tour_group/presentation/pages/tour_checklist_screen.dart';
import '../features/tour_group/presentation/pages/tour_instafeed_screen.dart';
import '../features/tour_group/presentation/pages/family_safety_hub_screen.dart';
import '../features/tour_group/presentation/pages/journey_tracker_screen.dart';
import '../features/tour_group/presentation/pages/notice_board_screen.dart';
import '../features/tour_group/presentation/pages/tour_quiz_screen.dart';
import '../features/tour_group/presentation/widgets/tour_membership_guard.dart';
import '../features/tour_group/presentation/pages/tour_scrapbook_screen.dart';
import '../features/tour_group/presentation/widgets/trip_shell.dart';
import 'tour_page_key.dart';
import '../features/game_zone/teen_patti/teen_patti_screen.dart';

import '../features/game_zone/game_zone_hub_screen.dart';
import '../features/game_zone/card29/card29_screen.dart';
import '../features/game_zone/chess/chess_screen.dart';
import '../features/game_zone/ludo/ludo_screen.dart';
import '../features/game_zone/carrom/carrom_screen.dart';
import '../features/game_zone/online/online_game_table_screen.dart';
import '../features/notifications/presentation/pages/notification_center_screen.dart';
import '../features/newspaper/presentation/pages/newspaper_hub_screen.dart';
import '../features/newspaper/presentation/pages/adfree_article_reader_screen.dart';
import '../features/newspaper/presentation/pages/adblock_browser_screen.dart';
import '../features/newspaper/domain/models/newspaper_models.dart';

import '../features/offline_vault/presentation/cubit/vault_cubit.dart';

class AppRouter {
  static final _rootNavigatorKey = GlobalKey<NavigatorState>();
  static GlobalKey<NavigatorState> get navigatorKey => _rootNavigatorKey;

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/group-hub',
    redirect: (context, state) {
      final authState = context.read<AuthCubit>().state;
      final bool loggingIn = state.matchedLocation == '/login';

      if (authState is Unauthenticated) {
        return loggingIn ? null : '/login';
      }

      if (authState is Authenticated && loggingIn) {
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
        path: '/login',
        pageBuilder: (context, state) =>
            _customPageTransition(state, const LoginScreen()),
      ),
      GoRoute(
        path: '/notifications',
        pageBuilder: (context, state) =>
            _customPageTransition(state, const NotificationCenterScreen()),
      ),
      GoRoute(
        path: '/vault',
        pageBuilder: (context, state) => _customPageTransition(
          state,
          BlocProvider<VaultCubit>(
            create: (context) => getIt<VaultCubit>(),
            child: const OfflineVaultScreen(),
          ),
        ),
      ),
      GoRoute(
        path: '/profile/:uid',
        pageBuilder: (context, state) => _customPageTransition(
          state,
          ExplorerProfileScreen(
            uid: state.pathParameters['uid']!,
            tourId: state.uri.queryParameters['tourId'],
          ),
          key: pageKeyFor(state),
        ),
      ),
      GoRoute(
        path: '/trust',
        pageBuilder: (context, state) =>
            _customPageTransition(state, const TrustDashboardScreen()),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) =>
            _customPageTransition(state, const NotificationSettingsScreen()),
      ),
      GoRoute(
        path: '/delete-account',
        pageBuilder: (context, state) =>
            _customPageTransition(state, const AccountDeletionPage()),
      ),
      GoRoute(
        path: '/chats',
        pageBuilder: (context, state) =>
            _customPageTransition(state, const ChatsListScreen()),
      ),
      GoRoute(
        path: '/chat/:chatId',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final otherUid = extra?['otherUid'] as String?;
          return _customPageTransition(
            state,
            ChatScreen(
              chatId: state.pathParameters['chatId']!,
              otherUid: otherUid,
              sharedTourId: extra?['sharedTourId'] as String?,
              otherEmail: extra?['otherEmail'] as String?,
            ),
          );
        },
      ),
      GoRoute(
        path: '/call/:callId',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return _customPageTransition(
            state,
            CallScreen(
              callId: state.pathParameters['callId']!,
              localUid: extra['localUid'] as String? ?? '',
              remoteUid: extra['remoteUid'] as String? ?? '',
              remoteEmail: extra['remoteEmail'] as String?,
              sharedTourId: extra['sharedTourId'] as String?,
              remoteUserName: extra['remoteUserName'] as String? ?? 'Traveler',
              remoteAvatarUrl: extra['remoteAvatarUrl'] as String?,
              isCaller: extra['isCaller'] as bool? ?? false,
              isVideoCall: extra['isVideoCall'] as bool? ?? true,
              localUserName: extra['localUserName'] as String?,
              localAvatarUrl: extra['localAvatarUrl'] as String?,
            ),
          );
        },
      ),
      GoRoute(
        path: '/starred-messages',
        pageBuilder: (context, state) =>
            _customPageTransition(state, const StarredMessagesScreen()),
      ),
      GoRoute(
        path: '/group-hub',
        pageBuilder: (context, state) => _customPageTransition(
          state,
          TourGroupHubScreen(
            initialTourId: state.uri.queryParameters['tourId'],
          ),
          key: pageKeyFor(state),
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
          TourLogisticsHubScreen(tourId: state.pathParameters['tourId']!),
        ),
      ),
      GoRoute(
        path: '/group/:tourId/calendar',
        pageBuilder: (context, state) => _tripPage(
          state,
          HolidayCalendarScreen(tourId: state.pathParameters['tourId']!),
        ),
      ),
      GoRoute(
        path: '/group/:tourId/family-dates',
        pageBuilder: (context, state) => _tripPage(
          state,
          FamilyDatesScreen(tourId: state.pathParameters['tourId']!),
        ),
      ),
      GoRoute(
        path: '/group/:tourId/dependents',
        pageBuilder: (context, state) => _tripPage(
          state,
          FamilyDependentsScreen(tourId: state.pathParameters['tourId']!),
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
        path: '/group/:tourId/tide',
        pageBuilder: (context, state) => _tripPage(
          state,
          TideBeachGuideScreen(tourId: state.pathParameters['tourId']!),
        ),
      ),
      GoRoute(
        path: '/group/:tourId/channels',
        pageBuilder: (context, state) => _tripPage(
          state,
          GroupChannelsScreen(tourId: state.pathParameters['tourId']!),
        ),
      ),
      GoRoute(
        path: '/group/:tourId/checklist',
        pageBuilder: (context, state) => _tripPage(
          state,
          TourChecklistScreen(tourId: state.pathParameters['tourId']!),
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
          FamilySafetyHubScreen(tourId: state.pathParameters['tourId']!),
        ),
      ),
      GoRoute(
        path: '/group/:tourId/journey',
        pageBuilder: (context, state) => _tripPage(
          state,
          JourneyTrackerScreen(tourId: state.pathParameters['tourId']!),
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
          TourQuizScreen(tourId: state.pathParameters['tourId']!),
        ),
      ),
      GoRoute(
        path: '/group/:tourId/scrapbook',
        pageBuilder: (context, state) => _tripPage(
          state,
          TourScrapbookScreen(tourId: state.pathParameters['tourId']!),
        ),
      ),
      GoRoute(
        path: '/game-zone',
        pageBuilder: (context, state) => _customPageTransition(
          state,
          GameZoneHubScreen(initialTourId: state.uri.queryParameters['tourId']),
          key: pageKeyFor(state),
        ),
      ),
      GoRoute(
        path: '/game-zone/card29',
        pageBuilder: (context, state) =>
            _customPageTransition(state, const Card29Screen()),
      ),
      GoRoute(
        path: '/game-zone/chess',
        pageBuilder: (context, state) =>
            _customPageTransition(state, const ChessScreen()),
      ),
      GoRoute(
        path: '/game-zone/ludo',
        pageBuilder: (context, state) =>
            _customPageTransition(state, const LudoScreen()),
      ),
      GoRoute(
        path: '/game-zone/teen-patti',
        pageBuilder: (context, state) =>
            _customPageTransition(state, const TeenPattiScreen()),
      ),
      GoRoute(
        path: '/game-zone/carrom',
        pageBuilder: (context, state) =>
            _customPageTransition(state, const CarromScreen()),
      ),
      GoRoute(
        path: '/game-zone/table/:tourId/:gameId',
        pageBuilder: (context, state) {
          final tourId = state.pathParameters['tourId']!;
          final gameId = state.pathParameters['gameId']!;
          return _customPageTransition(
            state,
            TourMembershipGuard(
              tourId: tourId,
              child: OnlineGameTableScreen(tourId: tourId, gameId: gameId),
            ),
          );
        },
      ),
      GoRoute(
        path: '/newspaper-hub',
        pageBuilder: (context, state) =>
            _customPageTransition(state, const NewspaperHubScreen()),
      ),
      GoRoute(
        path: '/group/:tourId/news',
        pageBuilder: (context, state) => _tripPage(
          state,
          const NewspaperHubScreen(),
        ),
      ),
      GoRoute(
        path: '/newspaper-reader',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final url =
              state.uri.queryParameters['url'] ?? extra['url'] as String? ?? '';
          return _customPageTransition(
            state,
            AdFreeArticleReaderScreen(
              articleUrl: url,
              initialTitle: extra['title'] as String?,
              initialSourceName: extra['sourceName'] as String?,
              initialImageUrl: extra['imageUrl'] as String?,
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
          return _customPageTransition(
            state,
            AdBlockBrowserScreen(
              initialUrl: url,
              initialTitle: title,
              paper: extra['paper'] as Newspaper?,
            ),
          );
        },
      ),
    ],
  );

  /// A tour screen inside the trip bar. See [TripShell] for why this is not a
  /// ShellRoute.
  static Page<void> _tripPage(GoRouterState state, Widget screen) {
    return _customPageTransition(
      state,
      TripShell(
        tourId: state.pathParameters['tourId']!,
        location: state.uri.path,
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
        return FadeTransition(
          opacity: CurveTween(curve: Curves.easeInOut).animate(animation),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.06, 0.0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.fastOutSlowIn,
              ),
            ),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 320),
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
