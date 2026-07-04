import 'dart:convert';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/entities/explorer_profile.dart';
import '../../../../core/value_objects/explorer_score.dart';
import '../../../../core/value_objects/trust_tier.dart';
import '../../domain/repositories/i_auth_repository.dart';

class MockOfflineAuthRepository implements IAuthRepository {
  final AppDatabase _database;
  ExplorerProfile? _cachedProfile;

  MockOfflineAuthRepository(this._database);

  Future<void> _initLocalCache() async {
    try {
      final jsonStr = await _database.getProfile('current_user');
      if (jsonStr != null) {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        _cachedProfile = ExplorerProfile.fromJson(map);
      }
    } catch (_) {}
  }

  Future<void> _updateLocalCache(ExplorerProfile profile) async {
    _cachedProfile = profile;
    try {
      final jsonStr = jsonEncode(profile.toJson());
      await _database.saveProfile('current_user', jsonStr);
    } catch (_) {}
  }

  Future<void> _clearLocalCache() async {
    _cachedProfile = null;
    try {
      await _database.deleteProfile('current_user');
    } catch (_) {}
  }

  @override
  Future<Either<Failure, String>> signInWithEmail(String email) async {
    return const Right('123456');
  }

  @override
  Future<Either<Failure, ExplorerProfile>> verifyOtp(String smsCode) async {
    final profile = ExplorerProfile(
      uid: 'mock_offline_user_phone',
      displayName: 'Offline Traveler',
      division: 'Dhaka',
      tier: TrustTier.community,
      badges: ['Offline Explorer'],
      isPioneer: true,
      createdAt: DateTime.now(),
      explorerScore: const ExplorerScore(value: 100, tier: TrustTier.community),
    );
    await _updateLocalCache(profile);
    return Right(profile);
  }

  @override
  Future<Either<Failure, ExplorerProfile>> signInWithGoogle() async {
    final profile = ExplorerProfile(
      uid: 'mock_offline_user_google',
      displayName: 'Google Offline Traveler',
      division: 'Sylhet',
      tier: TrustTier.pioneer,
      badges: ['Offline Explorer', 'Google Verified'],
      isPioneer: true,
      createdAt: DateTime.now(),
      explorerScore: const ExplorerScore(value: 250, tier: TrustTier.pioneer),
    );
    await _updateLocalCache(profile);
    return Right(profile);
  }

  @override
  Future<Either<Failure, Unit>> signOut() async {
    await _clearLocalCache();
    return const Right(unit);
  }

  @override
  Future<Either<Failure, ExplorerProfile?>> getCurrentProfile() async {
    if (_cachedProfile == null) {
      await _initLocalCache();
    }
    return Right(_cachedProfile);
  }

  @override
  Future<Either<Failure, ExplorerProfile>> updateProfile(
      ExplorerProfile profile) async {
    await _updateLocalCache(profile);
    return Right(profile);
  }
}
