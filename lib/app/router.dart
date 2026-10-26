import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'di/injection.dart';
import '../features/auth/presentation/cubit/auth_cubit.dart';
import '../features/auth/presentation/cubit/auth_state.dart';
import '../features/auth/presentation/pages/login_screen.dart';
import '../features/map/presentation/pages/map_screen.dart';
import '../features/trip_log/presentation/pages/trip_log_editor.dart';
import '../core/entities/trip_log.dart';
import '../features/offline_vault/presentation/pages/offline_vault_screen.dart';
import '../features/trust/presentation/pages/trust_dashboard_screen.dart';
import '../features/feed/presentation/pages/home_feed_screen.dart';
import '../features/explorer/presentation/pages/explorer_profile_screen.dart';
import '../features/explorer/presentation/pages/leaderboard_screen.dart';
import 'package:geolocator/geolocator.dart';
import '../core/entities/location_pin.dart';
import '../features/explorer/presentation/pages/explorer_dashboard_screen.dart';
import '../features/explorer/presentation/pages/challenges_screen.dart';
import '../features/explorer/presentation/pages/discover_screen.dart';
import '../features/map/presentation/widgets/ar_compass_screen.dart';

import '../features/premium_guide/presentation/pages/guide_create_screen.dart';
import '../features/premium_guide/presentation/pages/guide_detail_screen.dart';
import '../features/premium_guide/presentation/pages/guide_purchase_screen.dart';
import '../features/notifications/presentation/pages/notification_settings_screen.dart';
import '../features/auth/presentation/pages/account_deletion_page.dart';
import '../features/chat/presentation/pages/chats_list_screen.dart';
import '../features/chat/presentation/pages/chat_screen.dart';
import '../features/chat/presentation/pages/call_screen.dart';
import '../features/chat/presentation/pages/starred_messages_screen.dart';

import '../features/tour_group/presentation/pages/tour_group_hub_screen.dart';
import '../features/tour_group/presentation/pages/expense_ledger_screen.dart';
import '../features/tour_group/presentation/pages/tour_logistics_hub_screen.dart';
import '../features/tour_group/presentation/pages/tide_beach_guide_screen.dart';
import '../features/tour_group/presentation/pages/group_channels_screen.dart';
import '../features/tour_group/presentation/pages/tour_checklist_screen.dart';
import '../features/tour_group/presentation/pages/tour_instafeed_screen.dart';
import '../features/tour_group/presentation/pages/family_safety_hub_screen.dart';
import '../features/tour_group/presentation/pages/journey_tracker_screen.dart';
import '../features/tour_group/presentation/pages/notice_board_screen.dart';
import '../features/tour_group/presentation/pages/tour_quiz_screen.dart';
import '../features/tour_group/presentation/pages/tour_scrapbook_screen.dart';
import '../features/tour_group/presentation/widgets/trip_shell.dart';
import '../features/game_zone/teen_patti/teen_patti_screen.dart';

import '../features/game_zone/game_zone_hub_screen.dart';
import '../features/game_zone/card29/card29_screen.dart';
import '../features/game_zone/chess/chess_screen.dart';
import '../features/game_zone/ludo/ludo_screen.dart';
import '../features/game_zone/carrom/carrom_screen.dart';

import '../features/offline_vault/presentation/cubit/vault_cubit.dart';
import '../features/trip_log/presentation/bloc/trip_log_bloc.dart';

class AppRouter {
  static final _rootNavigatorKey = GlobalKey<NavigatorState>();
  static GlobalKey<NavigatorState> get navigatorKey => _rootNavigatorKey;

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/feed',
    redirect: (context, state) {
      final authState = context.read<AuthCubit>().state;
      final bool loggingIn = state.matchedLocation == '/login';

      if (authState is Unauthenticated) {
        return loggingIn ? null : '/login';
      }

      if (authState is Authenticated && loggingIn) {
        return '/feed';
      }

      return null;
    },
    refreshListenable: GoRouterRefreshStream(getIt<AuthCubit>().stream),
    routes: [
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) =>
            _customPageTransition(state, const LoginScreen()),
      ),
      GoRoute(
        path: '/map',
        pageBuilder: (context, state) =>
            _customPageTransition(state, const MapScreen()),
      ),
      GoRoute(
        path: '/feed',
        pageBuilder: (context, state) =>
            _customPageTransition(state, const HomeFeedScreen()),
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
          ExplorerProfileScreen(uid: state.pathParameters['uid']!),
        ),
      ),
      GoRoute(
        path: '/leaderboard',
        pageBuilder: (context, state) =>
            _customPageTransition(state, const LeaderboardScreen()),
      ),
      GoRoute(
        path: '/dashboard',
        pageBuilder: (context, state) =>
            _customPageTransition(state, const ExplorerDashboardScreen()),
      ),
      GoRoute(
        path: '/challenges',
        pageBuilder: (context, state) =>
            _customPageTransition(state, const ChallengesScreen()),
      ),
      GoRoute(
        path: '/discover',
        pageBuilder: (context, state) =>
            _customPageTransition(state, const DiscoverScreen()),
      ),
      GoRoute(
        path: '/ar',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final nearbyPins = extra?['nearbyPins'] as List<LocationPin>? ?? [];
          final currentPosition = extra?['currentPosition'] as Position?;
          return _customPageTransition(
            state,
            ArCompassScreen(
                nearbyPins: nearbyPins, currentPosition: currentPosition),
          );
        },
      ),
      GoRoute(
        path: '/editor',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final pinId = extra?['pinId'] as String? ?? 'pin_sajek';
          final tripLog = extra?['tripLog'] as TripLog?;
          return _customPageTransition(
            state,
            BlocProvider<TripLogBloc>(
              create: (context) => getIt<TripLogBloc>(),
              child: TripLogEditor(pinId: pinId, existingTripLog: tripLog),
            ),
          );
        },
      ),
      GoRoute(
        path: '/guide/create',
        pageBuilder: (context, state) =>
            _customPageTransition(state, const GuideCreateScreen()),
      ),
      GoRoute(
        path: '/guide/:id',
        pageBuilder: (context, state) => _customPageTransition(
          state,
          PremiumGuideDetailScreen(id: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/guide/purchase',
        pageBuilder: (context, state) {
          final id = state.extra as String? ?? '';
          return _customPageTransition(
              state, PremiumGuidePurchaseScreen(id: id));
        },
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
              remoteUserName: extra['remoteUserName'] as String? ?? 'Traveler',
              remoteAvatarUrl: extra['remoteAvatarUrl'] as String?,
              isCaller: extra['isCaller'] as bool? ?? false,
              isVideoCall: extra['isVideoCall'] as bool? ?? true,
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
        pageBuilder: (context, state) =>
            _customPageTransition(state, const TourGroupHubScreen()),
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
        pageBuilder: (context, state) =>
            _customPageTransition(state, const GameZoneHubScreen()),
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
    );
  }

  static Page<void> _customPageTransition(GoRouterState state, Widget child) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
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
