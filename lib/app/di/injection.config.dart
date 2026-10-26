// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:cloud_firestore/cloud_firestore.dart' as _i974;
import 'package:cloud_functions/cloud_functions.dart' as _i809;
import 'package:firebase_auth/firebase_auth.dart' as _i59;
import 'package:firebase_crashlytics/firebase_crashlytics.dart' as _i141;
import 'package:firebase_messaging/firebase_messaging.dart' as _i892;
import 'package:firebase_remote_config/firebase_remote_config.dart' as _i627;
import 'package:firebase_storage/firebase_storage.dart' as _i457;
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;

import '../../core/database/app_database.dart' as _i50;
import '../../core/network/secure_network_client.dart' as _i216;
import '../../core/security/hive_encryption_service.dart' as _i1061;
import '../../core/services/feature_flags.dart' as _i622;
import '../../features/auth/data/repositories/auth_repository_impl.dart'
    as _i153;
import '../../features/auth/domain/repositories/i_auth_repository.dart'
    as _i589;
import '../../features/auth/domain/usecases/get_current_profile_usecase.dart'
    as _i176;
import '../../features/auth/domain/usecases/sign_in_email_usecase.dart'
    as _i336;
import '../../features/auth/domain/usecases/sign_in_google_usecase.dart'
    as _i138;
import '../../features/auth/domain/usecases/sign_out_usecase.dart' as _i915;
import '../../features/auth/domain/usecases/update_profile_usecase.dart'
    as _i798;
import '../../features/auth/domain/usecases/verify_otp_usecase.dart' as _i503;
import '../../features/auth/presentation/cubit/auth_cubit.dart' as _i117;
import '../../features/explorer/data/repositories/explorer_repository_impl.dart'
    as _i362;
import '../../features/explorer/domain/repositories/i_explorer_repository.dart'
    as _i436;
import '../../features/explorer/domain/usecases/get_explorer_profile_usecase.dart'
    as _i343;
import '../../features/explorer/domain/usecases/get_top_explorers_usecase.dart'
    as _i146;
import '../../features/feed/data/repositories/feed_repository_impl.dart'
    as _i452;
import '../../features/feed/domain/repositories/i_feed_repository.dart'
    as _i695;
import '../../features/feed/domain/usecases/get_saved_trip_logs_usecase.dart'
    as _i360;
import '../../features/feed/domain/usecases/get_smart_feed_usecase.dart'
    as _i436;
import '../../features/feed/presentation/bloc/feed_cubit.dart' as _i80;
import '../../features/map/data/repositories/map_repository_impl.dart' as _i457;
import '../../features/map/domain/repositories/i_map_repository.dart' as _i529;
import '../../features/map/domain/usecases/confirm_pin_usecase.dart' as _i843;
import '../../features/map/domain/usecases/create_draft_pin_usecase.dart'
    as _i562;
import '../../features/map/domain/usecases/get_nearby_pins_usecase.dart'
    as _i1073;
import '../../features/map/presentation/bloc/map_bloc.dart' as _i437;
import '../../features/notifications/data/fcm_service.dart' as _i209;
import '../../features/offline_vault/data/datasources/sync_manager.dart'
    as _i416;
import '../../features/offline_vault/data/repositories/offline_repository_impl.dart'
    as _i784;
import '../../features/offline_vault/domain/repositories/i_offline_repository.dart'
    as _i988;
import '../../features/offline_vault/domain/usecases/delete_vault_usecase.dart'
    as _i1057;
import '../../features/offline_vault/domain/usecases/download_vault_usecase.dart'
    as _i2;
import '../../features/offline_vault/domain/usecases/get_vault_status_usecase.dart'
    as _i958;
import '../../features/offline_vault/domain/usecases/sync_outbox_usecase.dart'
    as _i936;
import '../../features/offline_vault/presentation/cubit/vault_cubit.dart'
    as _i884;
import '../../features/ota/data/repositories/ota_repository_impl.dart'
    as _i1058;
import '../../features/ota/domain/repositories/i_ota_repository.dart' as _i723;
import '../../features/ota/domain/usecases/check_for_updates_usecase.dart'
    as _i46;
import '../../features/ota/presentation/cubit/ota_cubit.dart' as _i965;
import '../../features/pro_tip/data/repositories/pro_tip_repository_impl.dart'
    as _i149;
import '../../features/pro_tip/domain/repositories/i_pro_tip_repository.dart'
    as _i1005;
import '../../features/pro_tip/domain/usecases/add_pro_tip_usecase.dart'
    as _i862;
import '../../features/pro_tip/domain/usecases/get_latest_tips_usecase.dart'
    as _i242;
import '../../features/pro_tip/domain/usecases/get_tips_for_location_usecase.dart'
    as _i295;
import '../../features/pro_tip/domain/usecases/vote_tip_usecase.dart' as _i303;
import '../../features/pro_tip/presentation/cubit/tip_list_cubit.dart'
    as _i1043;
import '../../features/trip_log/data/repositories/trip_log_repository_impl.dart'
    as _i190;
import '../../features/trip_log/domain/repositories/i_trip_log_repository.dart'
    as _i699;
import '../../features/trip_log/domain/usecases/get_trip_logs_for_pin_usecase.dart'
    as _i402;
import '../../features/trip_log/domain/usecases/load_draft_usecase.dart'
    as _i773;
import '../../features/trip_log/domain/usecases/publish_trip_log_usecase.dart'
    as _i695;
import '../../features/trip_log/domain/usecases/save_draft_usecase.dart'
    as _i304;
import '../../features/trip_log/presentation/bloc/trip_log_bloc.dart' as _i484;
import '../../features/trust/data/repositories/trust_repository_impl.dart'
    as _i842;
import '../../features/trust/domain/repositories/i_trust_repository.dart'
    as _i1000;
import '../../features/trust/domain/usecases/appeal_flag_usecase.dart' as _i168;
import '../../features/trust/domain/usecases/flag_content_usecase.dart'
    as _i964;
import '../../features/trust/domain/usecases/get_explorer_score_usecase.dart'
    as _i111;
import '../../features/trust/presentation/bloc/trust_bloc.dart' as _i905;
import 'firebase_module.dart' as _i616;

extension GetItInjectableX on _i174.GetIt {
// initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(
      this,
      environment,
      environmentFilter,
    );
    final firebaseModule = _$FirebaseModule();
    gh.lazySingleton<_i974.FirebaseFirestore>(() => firebaseModule.firestore);
    gh.lazySingleton<_i59.FirebaseAuth>(() => firebaseModule.auth);
    gh.lazySingleton<_i457.FirebaseStorage>(() => firebaseModule.storage);
    gh.lazySingleton<_i892.FirebaseMessaging>(() => firebaseModule.messaging);
    gh.lazySingleton<_i809.FirebaseFunctions>(() => firebaseModule.functions);
    gh.lazySingleton<_i627.FirebaseRemoteConfig>(
        () => firebaseModule.remoteConfig);
    gh.lazySingleton<_i141.FirebaseCrashlytics>(
        () => firebaseModule.crashlytics);
    gh.lazySingleton<_i50.AppDatabase>(() => _i50.AppDatabase());
    gh.lazySingleton<_i216.SecureNetworkClient>(
        () => _i216.SecureNetworkClient());
    gh.lazySingleton<_i1061.HiveEncryptionService>(
        () => _i1061.HiveEncryptionService());
    gh.lazySingleton<_i589.IAuthRepository>(
        () => _i153.AuthRepositoryImpl(gh<_i1061.HiveEncryptionService>()));
    gh.lazySingleton<_i695.IFeedRepository>(() => _i452.FeedRepositoryImpl(
          gh<_i974.FirebaseFirestore>(),
          gh<_i1061.HiveEncryptionService>(),
        ));
    gh.lazySingleton<_i529.IMapRepository>(() => _i457.MapRepositoryImpl(
          gh<_i974.FirebaseFirestore>(),
          gh<_i50.AppDatabase>(),
        ));
    gh.lazySingleton<_i416.SyncManager>(() => _i416.SyncManager(
          gh<_i50.AppDatabase>(),
          gh<_i974.FirebaseFirestore>(),
        ));
    gh.lazySingleton<_i1005.IProTipRepository>(() => _i149.ProTipRepositoryImpl(
          gh<_i974.FirebaseFirestore>(),
          gh<_i1061.HiveEncryptionService>(),
          gh<_i416.SyncManager>(),
        ));
    gh.lazySingleton<_i699.ITripLogRepository>(
        () => _i190.TripLogRepositoryImpl(
              gh<_i974.FirebaseFirestore>(),
              gh<_i1061.HiveEncryptionService>(),
              gh<_i416.SyncManager>(),
            ));
    gh.factory<_i304.SaveDraftUseCase>(
        () => _i304.SaveDraftUseCase(gh<_i699.ITripLogRepository>()));
    gh.factory<_i773.LoadDraftUseCase>(
        () => _i773.LoadDraftUseCase(gh<_i699.ITripLogRepository>()));
    gh.factory<_i402.GetTripLogsForPinUseCase>(
        () => _i402.GetTripLogsForPinUseCase(gh<_i699.ITripLogRepository>()));
    gh.singleton<_i209.FcmService>(() => _i209.FcmService(
          gh<_i892.FirebaseMessaging>(),
          gh<_i974.FirebaseFirestore>(),
        ));
    gh.lazySingleton<_i723.IOtaRepository>(
        () => _i1058.OtaRepositoryImpl(gh<_i216.SecureNetworkClient>()));
    gh.factory<_i46.CheckForUpdatesUseCase>(
        () => _i46.CheckForUpdatesUseCase(gh<_i723.IOtaRepository>()));
    gh.factory<_i436.GetSmartFeedUseCase>(() => _i436.GetSmartFeedUseCase(
          gh<_i695.IFeedRepository>(),
          gh<_i1061.HiveEncryptionService>(),
        ));
    gh.lazySingleton<_i988.IOfflineRepository>(
        () => _i784.OfflineRepositoryImpl(
              gh<_i1061.HiveEncryptionService>(),
              gh<_i416.SyncManager>(),
              gh<_i974.FirebaseFirestore>(),
              gh<_i50.AppDatabase>(),
            ));
    gh.lazySingleton<_i436.IExplorerRepository>(
        () => _i362.ExplorerRepositoryImpl(gh<_i974.FirebaseFirestore>()));
    gh.lazySingleton<_i1000.ITrustRepository>(
        () => _i842.TrustRepositoryImpl(gh<_i974.FirebaseFirestore>()));
    gh.factory<_i503.VerifyOtpUseCase>(
        () => _i503.VerifyOtpUseCase(gh<_i589.IAuthRepository>()));
    gh.factory<_i176.GetCurrentProfileUseCase>(
        () => _i176.GetCurrentProfileUseCase(gh<_i589.IAuthRepository>()));
    gh.factory<_i915.SignOutUseCase>(
        () => _i915.SignOutUseCase(gh<_i589.IAuthRepository>()));
    gh.factory<_i798.UpdateProfileUseCase>(
        () => _i798.UpdateProfileUseCase(gh<_i589.IAuthRepository>()));
    gh.factory<_i336.SignInEmailUseCase>(
        () => _i336.SignInEmailUseCase(gh<_i589.IAuthRepository>()));
    gh.factory<_i138.SignInGoogleUseCase>(
        () => _i138.SignInGoogleUseCase(gh<_i589.IAuthRepository>()));
    gh.lazySingleton<_i622.FeatureFlags>(
        () => _i622.FeatureFlags(gh<_i627.FirebaseRemoteConfig>()));
    gh.factory<_i360.GetSavedTripLogsUseCase>(
        () => _i360.GetSavedTripLogsUseCase(gh<_i695.IFeedRepository>()));
    gh.factory<_i964.FlagContentUseCase>(
        () => _i964.FlagContentUseCase(gh<_i1000.ITrustRepository>()));
    gh.factory<_i168.AppealFlagUseCase>(
        () => _i168.AppealFlagUseCase(gh<_i1000.ITrustRepository>()));
    gh.factory<_i111.GetExplorerScoreUseCase>(
        () => _i111.GetExplorerScoreUseCase(gh<_i1000.ITrustRepository>()));
    gh.factory<_i2.DownloadVaultUseCase>(
        () => _i2.DownloadVaultUseCase(gh<_i988.IOfflineRepository>()));
    gh.factory<_i1057.DeleteVaultUseCase>(
        () => _i1057.DeleteVaultUseCase(gh<_i988.IOfflineRepository>()));
    gh.factory<_i936.SyncOutboxUseCase>(
        () => _i936.SyncOutboxUseCase(gh<_i988.IOfflineRepository>()));
    gh.factory<_i958.GetVaultStatusUseCase>(
        () => _i958.GetVaultStatusUseCase(gh<_i988.IOfflineRepository>()));
    gh.factory<_i562.CreateDraftPinUseCase>(
        () => _i562.CreateDraftPinUseCase(gh<_i529.IMapRepository>()));
    gh.factory<_i1073.GetNearbyPinsUseCase>(
        () => _i1073.GetNearbyPinsUseCase(gh<_i529.IMapRepository>()));
    gh.factory<_i843.ConfirmPinUseCase>(
        () => _i843.ConfirmPinUseCase(gh<_i529.IMapRepository>()));
    gh.factory<_i437.MapBloc>(() => _i437.MapBloc(
          gh<_i1073.GetNearbyPinsUseCase>(),
          gh<_i562.CreateDraftPinUseCase>(),
          gh<_i843.ConfirmPinUseCase>(),
        ));
    gh.factory<_i295.GetTipsForLocationUseCase>(
        () => _i295.GetTipsForLocationUseCase(gh<_i1005.IProTipRepository>()));
    gh.factory<_i862.AddProTipUseCase>(
        () => _i862.AddProTipUseCase(gh<_i1005.IProTipRepository>()));
    gh.factory<_i242.GetLatestTipsUseCase>(
        () => _i242.GetLatestTipsUseCase(gh<_i1005.IProTipRepository>()));
    gh.factory<_i303.VoteTipUseCase>(
        () => _i303.VoteTipUseCase(gh<_i1005.IProTipRepository>()));
    gh.factory<_i884.VaultCubit>(() => _i884.VaultCubit(
          gh<_i2.DownloadVaultUseCase>(),
          gh<_i1057.DeleteVaultUseCase>(),
          gh<_i936.SyncOutboxUseCase>(),
          gh<_i958.GetVaultStatusUseCase>(),
          gh<_i50.AppDatabase>(),
        ));
    gh.factory<_i695.PublishTripLogUseCase>(() => _i695.PublishTripLogUseCase(
          gh<_i699.ITripLogRepository>(),
          gh<_i436.IExplorerRepository>(),
        ));
    gh.factory<_i965.OtaCubit>(
        () => _i965.OtaCubit(gh<_i46.CheckForUpdatesUseCase>()));
    gh.factory<_i1043.TipListCubit>(() => _i1043.TipListCubit(
          gh<_i862.AddProTipUseCase>(),
          gh<_i303.VoteTipUseCase>(),
          gh<_i295.GetTipsForLocationUseCase>(),
        ));
    gh.factory<_i343.GetExplorerProfileUseCase>(
        () => _i343.GetExplorerProfileUseCase(gh<_i436.IExplorerRepository>()));
    gh.factory<_i146.GetTopExplorersUseCase>(
        () => _i146.GetTopExplorersUseCase(gh<_i436.IExplorerRepository>()));
    gh.lazySingleton<_i117.AuthCubit>(() => _i117.AuthCubit(
          gh<_i176.GetCurrentProfileUseCase>(),
          gh<_i336.SignInEmailUseCase>(),
          gh<_i503.VerifyOtpUseCase>(),
          gh<_i138.SignInGoogleUseCase>(),
          gh<_i915.SignOutUseCase>(),
          gh<_i798.UpdateProfileUseCase>(),
        ));
    gh.factory<_i905.TrustBloc>(() => _i905.TrustBloc(
          gh<_i964.FlagContentUseCase>(),
          gh<_i168.AppealFlagUseCase>(),
          gh<_i111.GetExplorerScoreUseCase>(),
        ));
    gh.factory<_i484.TripLogBloc>(() => _i484.TripLogBloc(
          gh<_i695.PublishTripLogUseCase>(),
          gh<_i402.GetTripLogsForPinUseCase>(),
          gh<_i304.SaveDraftUseCase>(),
          gh<_i773.LoadDraftUseCase>(),
          gh<_i59.FirebaseAuth>(),
        ));
    gh.factory<_i80.FeedCubit>(() => _i80.FeedCubit(
          gh<_i436.GetSmartFeedUseCase>(),
          gh<_i242.GetLatestTipsUseCase>(),
          gh<_i146.GetTopExplorersUseCase>(),
          gh<_i360.GetSavedTripLogsUseCase>(),
        ));
    return this;
  }
}

class _$FirebaseModule extends _i616.FirebaseModule {}
