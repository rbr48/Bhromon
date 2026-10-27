import 'dart:async';
import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:injectable/injectable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../../core/security/hive_encryption_service.dart';
import '../../../../core/entities/explorer_profile.dart';
import '../../../../core/value_objects/explorer_score.dart';
import '../../../../core/value_objects/trust_tier.dart';
import '../../domain/repositories/i_auth_repository.dart';

@LazySingleton(as: IAuthRepository)
class AuthRepositoryImpl implements IAuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final HiveEncryptionService _encryptionService;

  ExplorerProfile? _cachedProfile;
  final String _localBoxName = 'auth_box';
  String? _emailForOtp;

  AuthRepositoryImpl(this._encryptionService) {
    _initLocalCache();
  }

  Future<void> _initLocalCache() async {
    try {
      final box =
          await _encryptionService.openEncryptedBox<dynamic>(_localBoxName);
      final profileJson = box.get('profile');
      if (profileJson != null) {
        _cachedProfile = ExplorerProfile.fromJson(
            Map<String, dynamic>.from(profileJson as Map));
      }
    } catch (error, stack) {
      logError('auth: reading the cached profile failed', error, stack);
    }
  }

  Future<void> _updateLocalCache(ExplorerProfile profile) async {
    _cachedProfile = profile;
    try {
      final box =
          await _encryptionService.openEncryptedBox<dynamic>(_localBoxName);
      await box.put('profile', profile.toJson());
    } catch (error, stack) {
      logError('auth: writing the cached profile failed', error, stack);
    }
  }

  Future<void> _clearLocalCache() async {
    _cachedProfile = null;
    try {
      final box =
          await _encryptionService.openEncryptedBox<dynamic>(_localBoxName);
      await box.delete('profile');
    } catch (error, stack) {
      logError('auth: clearing the cached profile failed', error, stack);
    }
  }

  Future<T> _withRetry<T>(
    Future<T> Function() operation, {
    int maxAttempts = 3,
    Duration perAttemptTimeout = const Duration(seconds: 8),
  }) async {
    int attempt = 0;
    Duration delay = const Duration(milliseconds: 600);
    Object? lastError;

    while (attempt < maxAttempts) {
      try {
        return await operation().timeout(perAttemptTimeout);
      } on TimeoutException catch (e) {
        lastError = e;
      } on FirebaseException catch (e) {
        lastError = e;
        final transient = {
          'unavailable',
          'deadline-exceeded',
          'internal',
          'resource-exhausted',
          'aborted'
        };
        if (!transient.contains(e.code)) rethrow;
      } catch (e) {
        rethrow;
      }
      attempt++;
      if (attempt < maxAttempts) {
        await Future<void>.delayed(delay);
        delay *= 2;
      }
    }
    throw lastError!;
  }

  @override
  Future<Either<Failure, String>> signInWithEmail(String email) async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'asia-south1');
      await functions.httpsCallable('sendOtpEmail').call<dynamic>({
        'email': email,
      });
      _emailForOtp = email;
      return const Right('Verification code sent');
    } on FirebaseFunctionsException catch (e) {
      return Left(AuthFailure(e.message ?? e.toString()));
    } catch (e) {
      return Left(AuthFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, ExplorerProfile>> verifyOtp(String smsCode) async {
    if (_emailForOtp == null) {
      return const Left(AuthFailure(
          'Email address is missing. Please request a code first.'));
    }
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'asia-south1');
      final callableResult =
          await functions.httpsCallable('verifyOtp').call<dynamic>({
        'email': _emailForOtp!,
        'otp': smsCode,
      });

      final customToken = callableResult.data['customToken'] as String;
      final userCredential = await _auth.signInWithCustomToken(customToken);

      return await _syncUserWithFirestore(userCredential.user!);
    } on FirebaseFunctionsException catch (e) {
      return Left(AuthFailure(e.message ?? e.toString()));
    } on FirebaseAuthException catch (e) {
      return Left(AuthFailure(e.message ?? e.toString()));
    } catch (e) {
      return Left(AuthFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, ExplorerProfile>> signInWithGoogle() async {
    try {
      UserCredential userCredential;
      if (kIsWeb) {
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope('profile');
        googleProvider.setCustomParameters({'prompt': 'select_account'});
        userCredential = await _auth.signInWithPopup(googleProvider);
      } else {
        final googleUser = await _googleSignIn.signIn();
        if (googleUser == null) {
          return const Left(AuthFailure('Google Sign-In aborted.'));
        }
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        userCredential = await _auth.signInWithCredential(credential);
      }
      final user = userCredential.user;
      if (user == null) {
        return const Left(
            AuthFailure('Google Sign-In failed: No user returned'));
      }
      return await _syncUserWithFirestore(user);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'popup-closed-by-user') {
        return const Left(AuthFailure('Google Sign-In was cancelled.'));
      }
      return Left(AuthFailure(e.message ?? 'Google Sign-In failed'));
    } catch (e) {
      return Left(AuthFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> signOut() async {
    try {
      // Clear local Hive cache immediately for instant logout
      await _clearLocalCache();

      // Perform remote Firebase and Google sign-out in the background
      _signOutRemotely();

      return const Right(unit);
    } catch (e) {
      return Left(AuthFailure(e.toString()));
    }
  }

  Future<void> _signOutRemotely() async {
    try {
      await _auth.signOut();
    } catch (error, stack) {
      logError('auth: remote sign-out failed', error, stack);
    }
    try {
      if (!kIsWeb) {
        await _googleSignIn.signOut();
      }
    } catch (error, stack) {
      logError('auth: Google sign-out failed', error, stack);
    }
  }

  @override
  Future<Either<Failure, ExplorerProfile?>> getCurrentProfile() async {
    if (_cachedProfile != null) return Right(_cachedProfile);

    final user = _auth.currentUser;
    if (user == null) return const Right(null);

    try {
      final doc = await _withRetry(
        () => _firestore.collection('explorer_profiles').doc(user.uid).get(),
      );
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        data['uid'] = doc.id;
        final profile = ExplorerProfile.fromJson(data);
        await _updateLocalCache(profile);
        return Right(profile);
      } else {
        final fallback = _buildFallbackProfile(user);
        await _updateLocalCache(fallback);
        try {
          await _withRetry(
            () => _firestore
                .collection('explorer_profiles')
                .doc(user.uid)
                .set(fallback.toJson()),
          );
        } catch (error, stack) {
          logError('auth: creating the fallback profile failed', error, stack);
        }
        return Right(fallback);
      }
    } catch (error, stack) {
      logError('auth: retrying the profile write failed', error, stack);
    }

    final fallback = _buildFallbackProfile(user);
    await _updateLocalCache(fallback);
    try {
      await _withRetry(
        () => _firestore
            .collection('explorer_profiles')
            .doc(user.uid)
            .set(fallback.toJson()),
      );
    } catch (error, stack) {
      logError('auth: saving the fallback profile failed', error, stack);
    }
    return Right(fallback);
  }

  @override
  Future<Either<Failure, ExplorerProfile>> updateProfile(
      ExplorerProfile profile) async {
    final user = _auth.currentUser;
    if (user == null) return const Left(AuthFailure('User not authenticated'));

    await _updateLocalCache(profile);

    try {
      await _withRetry(
        () => _firestore
            .collection('explorer_profiles')
            .doc(user.uid)
            .set(profile.toJson(), SetOptions(merge: true)),
      );
    } catch (error, stack) {
      logError('auth: merging the profile failed', error, stack);
    }
    return Right(profile);
  }

  Future<Either<Failure, ExplorerProfile>> _syncUserWithFirestore(
      User user) async {
    try {
      final doc = await _withRetry(
        () => _firestore.collection('explorer_profiles').doc(user.uid).get(),
      );

      ExplorerProfile profile;
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        data['uid'] = doc.id;
        profile = ExplorerProfile.fromJson(data);
      } else {
        profile = _buildFallbackProfile(user);
        await _withRetry(() => _firestore
            .collection('explorer_profiles')
            .doc(user.uid)
            .set(profile.toJson()));
      }

      await _updateLocalCache(profile);
      return Right(profile);
    } catch (e) {
      final profile = _buildFallbackProfile(user);
      await _updateLocalCache(profile);
      try {
        await _withRetry(() => _firestore
            .collection('explorer_profiles')
            .doc(user.uid)
            .set(profile.toJson()));
      } catch (error, stack) {
        logError('auth: updating the profile failed', error, stack);
      }
      return Right(profile);
    }
  }

  ExplorerProfile _buildFallbackProfile(User user) {
    return ExplorerProfile(
      uid: user.uid,
      displayName: user.displayName ?? 'New Explorer',
      division: 'Dhaka',
      tier: TrustTier.unverified,
      badges: [],
      isPioneer: false,
      createdAt: DateTime.now(),
      explorerScore: const ExplorerScore(value: 0, tier: TrustTier.unverified),
    );
  }
}
