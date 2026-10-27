import 'dart:async';
import 'dart:ui';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/localization/app_localizations.dart';
import 'core/localization/locale_controller.dart';
import 'core/theme/theme_controller.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'app/di/injection.dart';
import 'app/di/environments.dart';
import 'core/sync/sync_worker.dart';
import 'core/utils/app_logger.dart';
import 'app/router.dart';
import 'core/theme/theme.dart';
import 'features/auth/presentation/cubit/auth_cubit.dart';
import 'features/map/presentation/bloc/map_bloc.dart';
import 'features/trust/presentation/bloc/trust_bloc.dart';
import 'features/auth/domain/repositories/i_auth_repository.dart';
import 'features/auth/data/repositories/mock_offline_auth_repository.dart';
import 'features/trip_log/domain/repositories/i_trip_log_repository.dart';
import 'features/trip_log/data/repositories/mock_offline_trip_log_repository.dart';
import 'features/ota/presentation/cubit/ota_cubit.dart';
import 'features/ota/presentation/cubit/ota_state.dart';
import 'features/ota/presentation/widgets/ota_update_dialog.dart';
import 'core/security/device_integrity_service.dart';
import 'core/database/app_database.dart';
import 'features/chat/data/call_notification_service.dart';
import 'features/notifications/geo_fence_service.dart'
    show registerGeoFenceWork;

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Month and weekday names for both languages; see localizedDateFormat.
    await initializeDateFormatting('en');
    await initializeDateFormatting('bn');

    // Edge-to-edge: Android 15 (targetSdk 35) enforces it; opting in here
    // keeps the look identical on older Android versions.
    if (!kIsWeb) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ));
    }

    // Optimize ImageCache to hold up to 300 images & 250MB to prevent constant lazy-loading and jank on feeds
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        250 * 1024 * 1024; // 250 MB
    PaintingBinding.instance.imageCache.maximumSize = 300; // 300 images

    HydratedBloc.storage = await HydratedStorage.build(
      storageDirectory: kIsWeb
          ? HydratedStorage.webStorageDirectory
          : await getApplicationDocumentsDirectory(),
    );

    // Global Sync/Layout Error Boundaries
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      logError('[GlobalError] Synchronous error caught', details.exception,
          details.stack);
      appLogger.handle(details.exception, details.stack);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      logError('[GlobalError] Asynchronous error caught', error, stack);
      appLogger.handle(error, stack);
      return true; // Mark as handled to prevent native crash
    };

    // Component-level error isolation & graceful full-page crash recovery
    ErrorWidget.builder = (FlutterErrorDetails details) {
      logError('[UI Error Boundary] Exception during widget build',
          details.exception, details.stack);
      return LayoutBuilder(
        builder: (context, constraints) {
          // If the crash happened in a subcomponent/card, isolate it so the whole page doesn't break
          final isSubComponent =
              constraints.maxWidth < 320 || constraints.maxHeight < 240;
          if (isSubComponent) {
            return Container(
              margin: const EdgeInsets.all(4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.orangeAccent, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      kDebugMode
                          ? details.exceptionAsString()
                          : 'এই অংশটি লোড করা সম্ভব হয়নি',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          decoration: TextDecoration.none),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }

          // Full page layout error: render graceful recovery screen with redirect options
          return Material(
            color: const Color(0xFF0F172A),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.shield_outlined,
                              color: Colors.redAccent, size: 48),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'সাময়িক ত্রুটি ঘটেছে (Temporary Issue)',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'অ্যাপটি নিরাপদে সচল রাখতে পেজটি রিকভার করা হয়েছে। আপনি ড্যাশবোর্ডে ফিরে যেতে পারেন।',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 13, height: 1.5),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: () {
                            try {
                              AppRouter.router.go('/group-hub');
                            } catch (_) {}
                          },
                          icon: const Icon(Icons.home_rounded, size: 18),
                          label: const Text('হোমে ফিরে যান'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF00BFA5),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                          ),
                        ),
                        if (kDebugMode) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Text(
                              details.exceptionAsString(),
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    };

    // These three don't depend on each other: start them together rather
    // than one after another before the first frame. The integrity result
    // still gates everything else.
    final integrityCheck = DeviceIntegrityService.isDeviceCompromised();
    final hiveInit = Hive.initFlutter();
    final firebaseInit = Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).then<bool>((_) => true, onError: (Object e, StackTrace stack) {
      logWarning(
          'Firebase initialization failed (likely blocked by client adblocker)',
          e,
          stack);
      return false;
    });

    final bool isCompromised = await integrityCheck;
    if (isCompromised) {
      runApp(const SecurityCompromisedApp());
      return;
    }

    await hiveInit;
    try {
      await Hive.openBox<dynamic>('tour_groups_box');
    } catch (e, st) {
      logError('Hive openBox failed at startup, self-healing', e, st);
      try {
        await Hive.deleteBoxFromDisk('tour_groups_box');
        await Hive.openBox<dynamic>('tour_groups_box');
      } catch (inner) {
        logError('Hive self-healing failed', inner);
      }
    }
    await LocaleController.instance.load();
    await ThemeController.instance.load();
    final bool firebaseAvailable = await firebaseInit;

    if (!firebaseAvailable) {
      if (kReleaseMode) {
        // Enforce production dependencies and raise a warning rather than serving dummy mock data
        configureDependencies(environment: Env.prod);
        logError(
            'Firebase initialization failed in release build. Proceeding with production environment config.');
      } else {
        configureDependencies(environment: Env.offline);
        // Register offline mock repositories for auth and trip logs in debug/profile builds
        getIt.registerLazySingleton<IAuthRepository>(
          () => MockOfflineAuthRepository(getIt<AppDatabase>()),
        );
        getIt.registerLazySingleton<ITripLogRepository>(
          () => MockOfflineTripLogRepository(getIt<AppDatabase>()),
        );
      }
    } else {
      configureDependencies(environment: Env.prod);

      if (!kIsWeb) {
        // Wire up Firebase Crashlytics error handlers
        FirebaseCrashlytics.instance
            .setCrashlyticsCollectionEnabled(!kDebugMode);

        final originalOnError = FlutterError.onError;
        FlutterError.onError = (FlutterErrorDetails details) {
          if (originalOnError != null) originalOnError(details);
          FirebaseCrashlytics.instance.recordFlutterFatalError(details);
        };

        PlatformDispatcher.instance.onError = (error, stack) {
          logError('[GlobalError] Asynchronous error caught', error, stack);
          appLogger.handle(error, stack);
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
          return true; // Mark as handled to prevent native crash
        };
      }

      if (!kIsWeb) {
        // ── Firebase App Check — blocks non-genuine app instances ──────────
        try {
          await FirebaseAppCheck.instance.activate(
            // Use playIntegrity on Android (requires Play Store-signed build)
            // Falls back gracefully to debug provider in non-release builds.
            providerAndroid: kReleaseMode
                ? const AndroidPlayIntegrityProvider()
                : const AndroidDebugProvider(),
            providerApple: kReleaseMode
                ? const AppleDeviceCheckProvider()
                : const AppleDebugProvider(),
          );
          logInfo('[AppCheck] Firebase App Check activated successfully');
        } catch (e, stack) {
          logWarning('[AppCheck] Failed to activate App Check', e, stack);
        }
      }

      // ── Firestore offline persistence (one-time setting) ─────────────────
      // Allows Firestore streams to serve from local cache when offline.
      try {
        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
        logInfo('[Firestore] Offline persistence enabled');
      } catch (e, stack) {
        logWarning(
            '[Firestore] Could not enable offline persistence', e, stack);
      }
    }

    runApp(const MyApp());

    // Background job registration and call listener isn't needed to draw the first frame.
    if (firebaseAvailable) {
      CallNotificationService().init();
      if (!kIsWeb) {
        unawaited(_registerBackgroundWork());
      }
    }
  }, (error, stack) {
    logError('[GlobalError] Asynchronous error caught in runZonedGuarded zone',
        error, stack);
    appLogger.handle(error, stack);
    if (!kIsWeb) {
      try {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      } catch (_) {}
    }
  });
}

Future<void> _registerBackgroundWork() async {
  if (kIsWeb) return;
  try {
    // SyncWorker.initialize() calls Workmanager().initialize() internally
    // with the single unified callbackDispatcher that handles both sync
    // and geo-fence tasks.
    SyncWorker.initialize();
    SyncWorker.registerPeriodicSync();
    await registerGeoFenceWork();
  } catch (e, stack) {
    logWarning('[SyncWorker] Failed to initialize background sync', e, stack);
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthCubit>(
          create: (context) => getIt<AuthCubit>()..checkAuthStatus(),
        ),
        BlocProvider<MapBloc>(
          create: (context) => getIt<MapBloc>(),
        ),
        BlocProvider<TrustBloc>(
          create: (context) => getIt<TrustBloc>(),
        ),
        BlocProvider<OtaCubit>(
          create: (context) => getIt<OtaCubit>()..triggerCheck(),
        ),
      ],
      child: ListenableBuilder(
        listenable: Listenable.merge(
          [LocaleController.instance, ThemeController.instance],
        ),
        builder: (context, _) => MaterialApp.router(
          title: 'Bhromon',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeController.instance.mode,
          routerConfig: AppRouter.router,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('bn', ''),
            Locale('en', ''),
          ],
          locale: LocaleController.instance.locale,
          builder: (context, child) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final navBg = isDark ? const Color(0xFF161616) : Colors.white;
            return Container(
              color: navBg,
              child: SafeArea(
                top: false,
                left: false,
                right: false,
                bottom: true,
                child: OtaListenerWrapper(child: child ?? const SizedBox()),
              ),
            );
          },
        ),
      ),
    );
  }
}

class OtaListenerWrapper extends StatefulWidget {
  final Widget child;
  const OtaListenerWrapper({super.key, required this.child});

  @override
  State<OtaListenerWrapper> createState() => _OtaListenerWrapperState();
}

class _OtaListenerWrapperState extends State<OtaListenerWrapper> {
  @override
  void initState() {
    super.initState();
    CallNotificationService().init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<OtaCubit>().state;
      if (state is OtaUpdateAvailable) {
        _showUpdateDialog(state);
      }
    });
  }

  void _showUpdateDialog(OtaUpdateAvailable state) {
    final navContext = AppRouter.navigatorKey.currentContext;
    if (navContext != null) {
      showDialog<void>(
        context: navContext,
        barrierDismissible: !state.info.isMandatory,
        builder: (context) => const OtaUpdateDialog(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<OtaCubit, OtaState>(
      listenWhen: (previous, current) =>
          previous is! OtaUpdateAvailable && current is OtaUpdateAvailable,
      listener: (context, state) {
        if (state is OtaUpdateAvailable) {
          _showUpdateDialog(state);
        }
      },
      child: widget.child,
    );
  }
}

class SecurityCompromisedApp extends StatelessWidget {
  const SecurityCompromisedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xFF121212),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.security_update_warning_rounded,
                  color: Colors.redAccent,
                  size: 80,
                ),
                SizedBox(height: 24),
                Text(
                  'Security Violation',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16),
                Text(
                  'Bhromon cannot run on rooted or jailbroken devices because it processes secure transactions and user data. Please use a secure, non-compromised device to continue.',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 16,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
