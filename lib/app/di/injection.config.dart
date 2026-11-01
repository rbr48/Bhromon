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
import 'package:firebase_storage/firebase_storage.dart' as _i457;
import 'package:firebase_messaging/firebase_messaging.dart' as _i892;
import 'package:firebase_remote_config/firebase_remote_config.dart' as _i627;
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
import '../../features/notifications/data/fcm_service.dart' as _i209;
import '../../features/ota/data/repositories/ota_repository_impl.dart'
    as _i1058;
import '../../features/ota/domain/repositories/i_ota_repository.dart' as _i723;
import '../../features/ota/domain/usecases/check_for_updates_usecase.dart'
    as _i46;
import '../../features/ota/presentation/cubit/ota_cubit.dart' as _i965;
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
    gh.singleton<_i209.FcmService>(() => _i209.FcmService(
          gh<_i892.FirebaseMessaging>(),
          gh<_i974.FirebaseFirestore>(),
        ));
    gh.lazySingleton<_i723.IOtaRepository>(
        () => _i1058.OtaRepositoryImpl(gh<_i216.SecureNetworkClient>()));
    gh.factory<_i46.CheckForUpdatesUseCase>(
        () => _i46.CheckForUpdatesUseCase(gh<_i723.IOtaRepository>()));
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
    gh.factory<_i964.FlagContentUseCase>(
        () => _i964.FlagContentUseCase(gh<_i1000.ITrustRepository>()));
    gh.factory<_i168.AppealFlagUseCase>(
        () => _i168.AppealFlagUseCase(gh<_i1000.ITrustRepository>()));
    gh.factory<_i111.GetExplorerScoreUseCase>(
        () => _i111.GetExplorerScoreUseCase(gh<_i1000.ITrustRepository>()));
    gh.factory<_i965.OtaCubit>(
        () => _i965.OtaCubit(gh<_i46.CheckForUpdatesUseCase>()));
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
    return this;
  }
}

class _$FirebaseModule extends _i616.FirebaseModule {}
