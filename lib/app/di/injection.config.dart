// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:cloud_firestore/cloud_firestore.dart' as _i3;
import 'package:cloud_functions/cloud_functions.dart' as _i7;
import 'package:firebase_auth/firebase_auth.dart' as _i4;
import 'package:firebase_crashlytics/firebase_crashlytics.dart' as _i9;
import 'package:firebase_messaging/firebase_messaging.dart' as _i6;
import 'package:firebase_remote_config/firebase_remote_config.dart' as _i8;
import 'package:firebase_storage/firebase_storage.dart' as _i5;
import 'package:get_it/get_it.dart' as _i1;
import 'package:injectable/injectable.dart' as _i2;

import '../../core/database/app_database.dart' as _i10;
import '../../core/network/secure_network_client.dart' as _i11;
import '../../core/security/hive_encryption_service.dart' as _i12;
import '../../core/services/feature_flags.dart' as _i47;
import '../../features/auth/data/repositories/auth_repository_impl.dart'
    as _i15;
import '../../features/auth/domain/repositories/i_auth_repository.dart' as _i14;
import '../../features/auth/domain/usecases/get_current_profile_usecase.dart'
    as _i41;
import '../../features/auth/domain/usecases/sign_in_email_usecase.dart' as _i42;
import '../../features/auth/domain/usecases/sign_in_google_usecase.dart'
    as _i43;
import '../../features/auth/domain/usecases/sign_out_usecase.dart' as _i44;
import '../../features/auth/domain/usecases/update_profile_usecase.dart'
    as _i45;
import '../../features/auth/domain/usecases/verify_otp_usecase.dart' as _i46;
import '../../features/auth/presentation/cubit/auth_cubit.dart' as _i70;
import '../../features/explorer/data/repositories/explorer_repository_impl.dart'
    as _i36;
import '../../features/explorer/domain/repositories/i_explorer_repository.dart'
    as _i35;
import '../../features/explorer/domain/usecases/get_explorer_profile_usecase.dart'
    as _i68;
import '../../features/explorer/domain/usecases/get_top_explorers_usecase.dart'
    as _i69;
import '../../features/feed/data/repositories/feed_repository_impl.dart'
    as _i17;
import '../../features/feed/domain/repositories/i_feed_repository.dart' as _i16;
import '../../features/feed/domain/usecases/get_smart_feed_usecase.dart'
    as _i32;
import '../../features/feed/presentation/bloc/feed_cubit.dart' as _i73;
import '../../features/map/data/repositories/map_repository_impl.dart' as _i19;
import '../../features/map/domain/repositories/i_map_repository.dart' as _i18;
import '../../features/map/domain/usecases/confirm_pin_usecase.dart' as _i56;
import '../../features/map/domain/usecases/create_draft_pin_usecase.dart'
    as _i57;
import '../../features/map/domain/usecases/get_nearby_pins_usecase.dart'
    as _i58;
import '../../features/map/presentation/bloc/map_bloc.dart' as _i59;
import '../../features/notifications/data/fcm_service.dart' as _i28;
import '../../features/offline_vault/data/datasources/sync_manager.dart'
    as _i20;
import '../../features/offline_vault/data/repositories/offline_repository_impl.dart'
    as _i34;
import '../../features/offline_vault/domain/repositories/i_offline_repository.dart'
    as _i33;
import '../../features/offline_vault/domain/usecases/delete_vault_usecase.dart'
    as _i52;
import '../../features/offline_vault/domain/usecases/download_vault_usecase.dart'
    as _i53;
import '../../features/offline_vault/domain/usecases/get_vault_status_usecase.dart'
    as _i54;
import '../../features/offline_vault/domain/usecases/sync_outbox_usecase.dart'
    as _i55;
import '../../features/offline_vault/presentation/cubit/vault_cubit.dart'
    as _i64;
import '../../features/ota/data/repositories/ota_repository_impl.dart' as _i30;
import '../../features/ota/domain/repositories/i_ota_repository.dart' as _i29;
import '../../features/ota/domain/usecases/check_for_updates_usecase.dart'
    as _i31;
import '../../features/ota/presentation/cubit/ota_cubit.dart' as _i66;
import '../../features/premium_guide/data/repositories/guide_repository_impl.dart'
    as _i40;
import '../../features/premium_guide/domain/repositories/i_guide_repository.dart'
    as _i39;
import '../../features/premium_guide/domain/usecases/create_premium_guide_usecase.dart'
    as _i48;
import '../../features/premium_guide/domain/usecases/purchase_guide_usecase.dart'
    as _i13;
import '../../features/pro_tip/data/repositories/pro_tip_repository_impl.dart'
    as _i22;
import '../../features/pro_tip/domain/repositories/i_pro_tip_repository.dart'
    as _i21;
import '../../features/pro_tip/domain/usecases/add_pro_tip_usecase.dart'
    as _i60;
import '../../features/pro_tip/domain/usecases/get_latest_tips_usecase.dart'
    as _i61;
import '../../features/pro_tip/domain/usecases/get_tips_for_location_usecase.dart'
    as _i62;
import '../../features/pro_tip/domain/usecases/vote_tip_usecase.dart' as _i63;
import '../../features/pro_tip/presentation/cubit/tip_list_cubit.dart' as _i67;
import '../../features/trip_log/data/repositories/trip_log_repository_impl.dart'
    as _i24;
import '../../features/trip_log/domain/repositories/i_trip_log_repository.dart'
    as _i23;
import '../../features/trip_log/domain/usecases/get_trip_logs_for_pin_usecase.dart'
    as _i25;
import '../../features/trip_log/domain/usecases/load_draft_usecase.dart'
    as _i26;
import '../../features/trip_log/domain/usecases/publish_trip_log_usecase.dart'
    as _i65;
import '../../features/trip_log/domain/usecases/save_draft_usecase.dart'
    as _i27;
import '../../features/trip_log/presentation/bloc/trip_log_bloc.dart' as _i72;
import '../../features/trust/data/repositories/trust_repository_impl.dart'
    as _i38;
import '../../features/trust/domain/repositories/i_trust_repository.dart'
    as _i37;
import '../../features/trust/domain/usecases/appeal_flag_usecase.dart' as _i49;
import '../../features/trust/domain/usecases/flag_content_usecase.dart' as _i50;
import '../../features/trust/domain/usecases/get_explorer_score_usecase.dart'
    as _i51;
import '../../features/trust/presentation/bloc/trust_bloc.dart' as _i71;
import 'firebase_module.dart' as _i74;

extension GetItInjectableX on _i1.GetIt {
// initializes the registration of main-scope dependencies inside of GetIt
  _i1.GetIt init({
    String? environment,
    _i2.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i2.GetItHelper(
      this,
      environment,
      environmentFilter,
    );
    final firebaseModule = _$FirebaseModule();
    gh.lazySingleton<_i3.FirebaseFirestore>(() => firebaseModule.firestore);
    gh.lazySingleton<_i4.FirebaseAuth>(() => firebaseModule.auth);
    gh.lazySingleton<_i5.FirebaseStorage>(() => firebaseModule.storage);
    gh.lazySingleton<_i6.FirebaseMessaging>(() => firebaseModule.messaging);
    gh.lazySingleton<_i7.FirebaseFunctions>(() => firebaseModule.functions);
    gh.lazySingleton<_i8.FirebaseRemoteConfig>(
        () => firebaseModule.remoteConfig);
    gh.lazySingleton<_i9.FirebaseCrashlytics>(() => firebaseModule.crashlytics);
    gh.lazySingleton<_i10.AppDatabase>(() => _i10.AppDatabase());
    gh.lazySingleton<_i11.SecureNetworkClient>(
        () => _i11.SecureNetworkClient());
    gh.lazySingleton<_i12.HiveEncryptionService>(
        () => _i12.HiveEncryptionService());
    gh.factory<_i13.PurchaseGuideParams>(() => _i13.PurchaseGuideParams(
          guideId: gh<String>(),
          userId: gh<String>(),
        ));
    gh.lazySingleton<_i14.IAuthRepository>(
        () => _i15.AuthRepositoryImpl(gh<_i12.HiveEncryptionService>()));
    gh.lazySingleton<_i16.IFeedRepository>(() => _i17.FeedRepositoryImpl(
          gh<_i3.FirebaseFirestore>(),
          gh<_i12.HiveEncryptionService>(),
        ));
    gh.lazySingleton<_i18.IMapRepository>(() => _i19.MapRepositoryImpl(
          gh<_i3.FirebaseFirestore>(),
          gh<_i10.AppDatabase>(),
        ));
    gh.lazySingleton<_i20.SyncManager>(() => _i20.SyncManager(
          gh<_i10.AppDatabase>(),
          gh<_i3.FirebaseFirestore>(),
        ));
    gh.lazySingleton<_i21.IProTipRepository>(() => _i22.ProTipRepositoryImpl(
          gh<_i3.FirebaseFirestore>(),
          gh<_i12.HiveEncryptionService>(),
          gh<_i20.SyncManager>(),
        ));
    gh.lazySingleton<_i23.ITripLogRepository>(() => _i24.TripLogRepositoryImpl(
          gh<_i3.FirebaseFirestore>(),
          gh<_i12.HiveEncryptionService>(),
          gh<_i20.SyncManager>(),
        ));
    gh.factory<_i25.GetTripLogsForPinUseCase>(
        () => _i25.GetTripLogsForPinUseCase(gh<_i23.ITripLogRepository>()));
    gh.factory<_i26.LoadDraftUseCase>(
        () => _i26.LoadDraftUseCase(gh<_i23.ITripLogRepository>()));
    gh.factory<_i27.SaveDraftUseCase>(
        () => _i27.SaveDraftUseCase(gh<_i23.ITripLogRepository>()));
    gh.singleton<_i28.FcmService>(() => _i28.FcmService(
          gh<_i6.FirebaseMessaging>(),
          gh<_i3.FirebaseFirestore>(),
        ));
    gh.lazySingleton<_i29.IOtaRepository>(
        () => _i30.OtaRepositoryImpl(gh<_i11.SecureNetworkClient>()));
    gh.factory<_i31.CheckForUpdatesUseCase>(
        () => _i31.CheckForUpdatesUseCase(gh<_i29.IOtaRepository>()));
    gh.factory<_i32.GetSmartFeedUseCase>(() => _i32.GetSmartFeedUseCase(
          gh<_i16.IFeedRepository>(),
          gh<_i12.HiveEncryptionService>(),
        ));
    gh.lazySingleton<_i33.IOfflineRepository>(() => _i34.OfflineRepositoryImpl(
          gh<_i12.HiveEncryptionService>(),
          gh<_i20.SyncManager>(),
          gh<_i3.FirebaseFirestore>(),
          gh<_i10.AppDatabase>(),
        ));
    gh.lazySingleton<_i35.IExplorerRepository>(
        () => _i36.ExplorerRepositoryImpl(gh<_i3.FirebaseFirestore>()));
    gh.lazySingleton<_i37.ITrustRepository>(
        () => _i38.TrustRepositoryImpl(gh<_i3.FirebaseFirestore>()));
    gh.lazySingleton<_i39.IGuideRepository>(
        () => _i40.GuideRepositoryImpl(gh<_i3.FirebaseFirestore>()));
    gh.factory<_i41.GetCurrentProfileUseCase>(
        () => _i41.GetCurrentProfileUseCase(gh<_i14.IAuthRepository>()));
    gh.factory<_i42.SignInEmailUseCase>(
        () => _i42.SignInEmailUseCase(gh<_i14.IAuthRepository>()));
    gh.factory<_i43.SignInGoogleUseCase>(
        () => _i43.SignInGoogleUseCase(gh<_i14.IAuthRepository>()));
    gh.factory<_i44.SignOutUseCase>(
        () => _i44.SignOutUseCase(gh<_i14.IAuthRepository>()));
    gh.factory<_i45.UpdateProfileUseCase>(
        () => _i45.UpdateProfileUseCase(gh<_i14.IAuthRepository>()));
    gh.factory<_i46.VerifyOtpUseCase>(
        () => _i46.VerifyOtpUseCase(gh<_i14.IAuthRepository>()));
    gh.lazySingleton<_i47.FeatureFlags>(
        () => _i47.FeatureFlags(gh<_i8.FirebaseRemoteConfig>()));
    gh.factory<_i48.CreatePremiumGuideUseCase>(
        () => _i48.CreatePremiumGuideUseCase(gh<_i39.IGuideRepository>()));
    gh.factory<_i49.AppealFlagUseCase>(
        () => _i49.AppealFlagUseCase(gh<_i37.ITrustRepository>()));
    gh.factory<_i50.FlagContentUseCase>(
        () => _i50.FlagContentUseCase(gh<_i37.ITrustRepository>()));
    gh.factory<_i51.GetExplorerScoreUseCase>(
        () => _i51.GetExplorerScoreUseCase(gh<_i37.ITrustRepository>()));
    gh.factory<_i52.DeleteVaultUseCase>(
        () => _i52.DeleteVaultUseCase(gh<_i33.IOfflineRepository>()));
    gh.factory<_i53.DownloadVaultUseCase>(
        () => _i53.DownloadVaultUseCase(gh<_i33.IOfflineRepository>()));
    gh.factory<_i54.GetVaultStatusUseCase>(
        () => _i54.GetVaultStatusUseCase(gh<_i33.IOfflineRepository>()));
    gh.factory<_i55.SyncOutboxUseCase>(
        () => _i55.SyncOutboxUseCase(gh<_i33.IOfflineRepository>()));
    gh.factory<_i56.ConfirmPinUseCase>(
        () => _i56.ConfirmPinUseCase(gh<_i18.IMapRepository>()));
    gh.factory<_i57.CreateDraftPinUseCase>(
        () => _i57.CreateDraftPinUseCase(gh<_i18.IMapRepository>()));
    gh.factory<_i58.GetNearbyPinsUseCase>(
        () => _i58.GetNearbyPinsUseCase(gh<_i18.IMapRepository>()));
    gh.factory<_i59.MapBloc>(() => _i59.MapBloc(
          gh<_i58.GetNearbyPinsUseCase>(),
          gh<_i57.CreateDraftPinUseCase>(),
          gh<_i56.ConfirmPinUseCase>(),
        ));
    gh.factory<_i60.AddProTipUseCase>(
        () => _i60.AddProTipUseCase(gh<_i21.IProTipRepository>()));
    gh.factory<_i61.GetLatestTipsUseCase>(
        () => _i61.GetLatestTipsUseCase(gh<_i21.IProTipRepository>()));
    gh.factory<_i62.GetTipsForLocationUseCase>(
        () => _i62.GetTipsForLocationUseCase(gh<_i21.IProTipRepository>()));
    gh.factory<_i63.VoteTipUseCase>(
        () => _i63.VoteTipUseCase(gh<_i21.IProTipRepository>()));
    gh.factory<_i64.VaultCubit>(() => _i64.VaultCubit(
          gh<_i53.DownloadVaultUseCase>(),
          gh<_i52.DeleteVaultUseCase>(),
          gh<_i55.SyncOutboxUseCase>(),
          gh<_i54.GetVaultStatusUseCase>(),
          gh<_i10.AppDatabase>(),
        ));
    gh.factory<_i65.PublishTripLogUseCase>(() => _i65.PublishTripLogUseCase(
          gh<_i23.ITripLogRepository>(),
          gh<_i35.IExplorerRepository>(),
        ));
    gh.factory<_i66.OtaCubit>(
        () => _i66.OtaCubit(gh<_i31.CheckForUpdatesUseCase>()));
    gh.factory<_i67.TipListCubit>(() => _i67.TipListCubit(
          gh<_i60.AddProTipUseCase>(),
          gh<_i63.VoteTipUseCase>(),
          gh<_i62.GetTipsForLocationUseCase>(),
        ));
    gh.factory<_i68.GetExplorerProfileUseCase>(
        () => _i68.GetExplorerProfileUseCase(gh<_i35.IExplorerRepository>()));
    gh.factory<_i69.GetTopExplorersUseCase>(
        () => _i69.GetTopExplorersUseCase(gh<_i35.IExplorerRepository>()));
    gh.factory<_i70.AuthCubit>(() => _i70.AuthCubit(
          gh<_i41.GetCurrentProfileUseCase>(),
          gh<_i42.SignInEmailUseCase>(),
          gh<_i46.VerifyOtpUseCase>(),
          gh<_i43.SignInGoogleUseCase>(),
          gh<_i44.SignOutUseCase>(),
          gh<_i45.UpdateProfileUseCase>(),
        ));
    gh.factory<_i71.TrustBloc>(() => _i71.TrustBloc(
          gh<_i50.FlagContentUseCase>(),
          gh<_i49.AppealFlagUseCase>(),
          gh<_i51.GetExplorerScoreUseCase>(),
        ));
    gh.factory<_i72.TripLogBloc>(() => _i72.TripLogBloc(
          gh<_i65.PublishTripLogUseCase>(),
          gh<_i25.GetTripLogsForPinUseCase>(),
          gh<_i27.SaveDraftUseCase>(),
          gh<_i26.LoadDraftUseCase>(),
          gh<_i4.FirebaseAuth>(),
        ));
    gh.factory<_i73.FeedCubit>(() => _i73.FeedCubit(
          gh<_i32.GetSmartFeedUseCase>(),
          gh<_i61.GetLatestTipsUseCase>(),
          gh<_i69.GetTopExplorersUseCase>(),
        ));
    return this;
  }
}

class _$FirebaseModule extends _i74.FirebaseModule {}
