import 'dart:async';
import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:injectable/injectable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/media/media_access.dart';
import '../../../../core/security/hive_encryption_service.dart';
import '../../../../core/services/push_device.dart';
import '../../../../core/entities/explorer_profile.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../../core/value_objects/explorer_score.dart';
import '../../../../core/value_objects/trust_tier.dart';
import '../../../chat/data/e2ee/e2ee_chat_controller.dart';
import '../../../tour_group/data/channel_message_cache.dart';
import '../../domain/repositories/i_auth_repository.dart';
import '../google_sign_in_failure.dart';
import '../profile_save_policy.dart';

@LazySingleton(as: IAuthRepository)
class AuthRepositoryImpl implements IAuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  Future<void>? _googleInit;
  final HiveEncryptionService _encryptionService;

  ExplorerProfile? _cachedProfile;
  final String _localBoxName = 'auth_box';
  String? _emailForOtp;
  late final Future<void> _localCacheReady;
  Future<void>? _backgroundRefreshInFlight;

  AuthRepositoryImpl(this._encryptionService) {
    _localCacheReady = _initLocalCache();
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
    } catch (e, stack) {
      logWarning('AuthRepository: failed to init local cache', e, stack);
    }
  }

  Future<void> _updateLocalCache(ExplorerProfile profile) async {
    _cachedProfile = profile;
    try {
      final box =
          await _encryptionService.openEncryptedBox<dynamic>(_localBoxName);
      await box.put('profile', profile.toJson());
    } catch (e, stack) {
      logWarning('AuthRepository: failed to update local cache', e, stack);
    }
  }

  Future<void> _clearLocalCache() async {
    await _localCacheReady;
    _cachedProfile = null;
    try {
      final box =
          await _encryptionService.openEncryptedBox<dynamic>(_localBoxName);
      await box.delete('profile');
    } catch (e, stack) {
      logWarning('AuthRepository: failed to clear local cache', e, stack);
    }
    // The channel messages kept on this device go too, so the next person to use
    // the phone does not see them.
    await ChannelMessageCache(encryption: _encryptionService).clearAll();
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
    return _sendOtpEmailCall(email, purpose: 'login');
  }

  @override
  Future<Either<Failure, String>> sendSignUpOtp(String email) async {
    return _sendOtpEmailCall(email, purpose: 'signup');
  }

  Future<Either<Failure, String>> _sendOtpEmailCall(
    String email, {
    required String purpose,
  }) async {
    try {
      final normalized = email.trim();
      final functions = FirebaseFunctions.instanceFor(region: 'asia-south1');
      await functions.httpsCallable('sendOtpEmail').call<dynamic>({
        'email': normalized,
        'purpose': purpose,
      });
      _emailForOtp = normalized;
      return const Right('Verification code sent');
    } on FirebaseFunctionsException catch (e, stack) {
      final reason = _otpFunctionsReason(e);
      logWarning(
        'AuthRepository: sendOtpEmail ($purpose) failed (${e.code})',
        e,
        stack,
      );
      return Left(AuthFailure(e.message ?? e.toString(), reason: reason));
    } catch (e, stack) {
      logWarning('AuthRepository: sendOtpEmail error', e, stack);
      return Left(AuthFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, ExplorerProfile>> registerWithEmailOtp({
    required String email,
    required String password,
    required String otp,
    String? displayName,
  }) async {
    final normalizedEmail = email.trim();
    final trimmedName = displayName?.trim() ?? '';
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'asia-south1');
      await functions.httpsCallable('registerWithEmailOtp').call<dynamic>({
        'email': normalizedEmail,
        'otp': otp.trim(),
        'password': password,
        if (trimmedName.isNotEmpty) 'displayName': trimmedName,
      });

      final userCredential = await _auth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      final user = userCredential.user;
      if (user == null) {
        logWarning(
            'AuthRepository: post-registration sign-in returned no user');
        return const Left(AuthFailure('Email sign-in returned no user'));
      }
      return await _syncUserWithFirestore(user);
    } on FirebaseFunctionsException catch (e, stack) {
      final reason = _otpFunctionsReason(e);
      logWarning(
        'AuthRepository: registerWithEmailOtp failed (${e.code})',
        e,
        stack,
      );
      return Left(AuthFailure(e.message ?? e.toString(), reason: reason));
    } on FirebaseAuthException catch (e, stack) {
      final reason = _firebaseAuthReason(e.code);
      logWarning(
        'AuthRepository: post-registration auth sign-in failed (${e.code})',
        e,
        stack,
      );
      return Left(AuthFailure('Email registration failed', reason: reason));
    } catch (e, stack) {
      logWarning('AuthRepository: registerWithEmailOtp error', e, stack);
      return const Left(AuthFailure('Email registration failed'));
    }
  }

  @override
  Future<Either<Failure, ExplorerProfile>> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = userCredential.user;
      if (user == null) {
        logWarning('AuthRepository: email/password sign-in returned no user');
        return const Left(AuthFailure('Email sign-in returned no user'));
      }
      return await _syncUserWithFirestore(user);
    } on FirebaseAuthException catch (e, stack) {
      final reason = _firebaseAuthReason(e.code);
      logWarning(
        'AuthRepository: email/password sign-in failed (${e.code})',
        e,
        stack,
      );
      return Left(AuthFailure('Email sign-in failed', reason: reason));
    } catch (e, stack) {
      logWarning('AuthRepository: email/password sign-in error', e, stack);
      return const Left(AuthFailure('Email sign-in failed'));
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

  // google_sign_in 7 needs one initialize() before any other call. Every caller awaits
  // the same run. On Android, serverClientId (Web Client ID from google-services.json)
  // is required by Credential Manager to request a Google ID token.
  static const String _defaultServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '919602851188-19utalf8ermkjdfog5r605s3stc98sfr.apps.googleusercontent.com',
  );

  Future<void> _initGoogleSignIn() => _googleInit ??= _googleSignIn.initialize(
        serverClientId: _defaultServerClientId,
      );

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
        await _initGoogleSignIn();
        final googleUser = await _googleSignIn.authenticate();
        final credential = GoogleAuthProvider.credential(
          idToken: googleUser.authentication.idToken,
        );
        userCredential = await _auth.signInWithCredential(credential);
      }
      final user = userCredential.user;
      if (user == null) {
        logWarning('AuthRepository: Google sign-in returned no user');
        return const Left(AuthFailure('Google sign-in returned no user'));
      }
      return await _syncUserWithFirestore(user);
    } on GoogleSignInException catch (e, stack) {
      return Left(_googleSignInFailure(e, stack, googleSignInFailureReason(e)));
    } on FirebaseAuthException catch (e, stack) {
      return Left(_googleSignInFailure(e, stack, _firebaseAuthReason(e.code)));
    } catch (e, stack) {
      return Left(_googleSignInFailure(e, stack, AuthFailureReason.unknown));
    }
  }

  /// Wraps a Google sign-in error for the sign-in screen. The screen words its
  /// message from [reason], so the raw [error] only goes to the log.
  AuthFailure _googleSignInFailure(
    Object error,
    StackTrace stack,
    AuthFailureReason reason,
  ) {
    if (reason == AuthFailureReason.cancelled) {
      return AuthFailure('Google sign-in cancelled', reason: reason);
    }
    logWarning(
      'AuthRepository: Google sign-in failed (${reason.name})',
      error,
      stack,
    );
    return AuthFailure('Google sign-in failed', reason: reason);
  }

  /// The reason for a Firebase Auth error code from sign-in.
  AuthFailureReason _firebaseAuthReason(String code) {
    // The user closed the account window, or a newer sign-in replaced it.
    if (code == 'popup-closed-by-user' || code == 'cancelled-popup-request') {
      return AuthFailureReason.cancelled;
    }
    return switch (code) {
      'popup-blocked' => AuthFailureReason.popupBlocked,
      'network-request-failed' => AuthFailureReason.network,
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' ||
      'invalid-email' =>
        AuthFailureReason.invalidCredentials,
      'too-many-requests' => AuthFailureReason.tooManyRequests,
      'user-disabled' => AuthFailureReason.userDisabled,
      'email-already-in-use' => AuthFailureReason.emailAlreadyInUse,
      'weak-password' => AuthFailureReason.weakPassword,
      _ => AuthFailureReason.unknown,
    };
  }

  /// Maps Callable Cloud Function exceptions from OTP send/sign-up endpoints.
  AuthFailureReason _otpFunctionsReason(FirebaseFunctionsException e) {
    final msg = (e.message ?? '').toLowerCase();
    return switch (e.code) {
      'already-exists' => AuthFailureReason.emailAlreadyInUse,
      'permission-denied' => AuthFailureReason.otpInvalid,
      'not-found' => AuthFailureReason.otpNotFound,
      'failed-precondition' => msg.contains('expired')
          ? AuthFailureReason.otpExpired
          : AuthFailureReason.emailOtpUnavailable,
      'resource-exhausted' => msg.contains('60 seconds')
          ? AuthFailureReason.otpCooldown
          : AuthFailureReason.tooManyRequests,
      'invalid-argument' => msg.contains('password')
          ? AuthFailureReason.weakPassword
          : AuthFailureReason.invalidCredentials,
      'unavailable' || 'deadline-exceeded' => AuthFailureReason.network,
      _ => AuthFailureReason.unknown,
    };
  }

  @override
  Future<Either<Failure, Unit>> signOut() async {
    try {
      _cachedProfile = null;
      await MediaAccess.instance.clear();
      // Clear local Hive cache immediately for instant logout
      // The encryption account leaves memory, and its keys stay on the device.
      await E2eeChatController.instance.release();
      await _clearLocalCache();

      // Perform remote Firebase and Google sign-out and wait for it
      await _signOutRemotely();

      return const Right(unit);
    } catch (e) {
      return Left(AuthFailure(e.toString()));
    }
  }

  /// Removes this device from the account's push targets. It runs before the
  /// Firebase sign-out, because the rules need the user to still be signed in.
  /// Otherwise the next person to use the phone would get this account's pushes.
  Future<void> _removeThisDeviceToken() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final messaging = FirebaseMessaging.instance;
      // ignore: deprecated_member_use
      final token = await messaging.getToken();
      if (token != null) {
        final user = _firestore.collection('fcm_tokens').doc(uid);
        await user.collection('devices').doc(pushDeviceId(token)).delete();
        final legacy = await user.get();
        if (legacy.data()?['token'] == token) await user.delete();
        // ignore: deprecated_member_use
        await messaging.deleteToken();
      }
    } catch (e, stack) {
      logWarning(
          'AuthRepository: failed to remove this device push token', e, stack);
    }
  }

  Future<void> _signOutRemotely() async {
    try {
      await _removeThisDeviceToken().timeout(const Duration(seconds: 2));
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }

    try {
      await _auth.signOut();
    } catch (e, stack) {
      logWarning(
          'AuthRepository: failed to sign out from Firebase Auth', e, stack);
    }
    // Web signs in through Firebase's popup, so Google Sign-In is only set up on mobile.
    if (!kIsWeb) {
      try {
        await _initGoogleSignIn();
        await _googleSignIn.signOut();
      } catch (e, stack) {
        logWarning(
            'AuthRepository: failed to sign out from GoogleSignIn', e, stack);
      }
    }
  }

  ExplorerProfile _profileFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
    User user,
  ) {
    final data = Map<String, dynamic>.from(doc.data()!);
    data['uid'] = doc.id;
    final existingAvatar = data['avatarUrl'] as String?;
    if ((existingAvatar == null || existingAvatar.trim().isEmpty) &&
        user.photoURL != null &&
        user.photoURL!.isNotEmpty) {
      data['avatarUrl'] = user.photoURL;
      _firestore
          .collection('explorer_profiles')
          .doc(user.uid)
          .update({'avatarUrl': user.photoURL}).catchError((Object e) {
        logWarning('AuthRepository: failed to backfill avatarUrl', e);
      });
    }
    return ExplorerProfile.fromJson(data);
  }

  void _scheduleBackgroundRefresh(User user) {
    _backgroundRefreshInFlight ??= () async {
      try {
        final doc = await _firestore
            .collection('explorer_profiles')
            .doc(user.uid)
            .get()
            .timeout(const Duration(seconds: 8));
        if (doc.exists && doc.data() != null) {
          final fresh = _profileFromSnapshot(doc, user);
          await _updateLocalCache(fresh);
        }
      } catch (e, stack) {
        logDebug(
          'AuthRepository: background profile refresh skipped: $e\n$stack',
        );
      } finally {
        _backgroundRefreshInFlight = null;
      }
    }();
  }

  @override
  Future<Either<Failure, ExplorerProfile?>> getCurrentProfile() async {
    final user = _auth.currentUser;
    if (user == null) return const Right(null);

    await _localCacheReady;
    if (_cachedProfile != null && _cachedProfile!.uid == user.uid) {
      _scheduleBackgroundRefresh(user);
      return Right(_cachedProfile);
    }

    try {
      final cachedDoc = await _firestore
          .collection('explorer_profiles')
          .doc(user.uid)
          .get(const GetOptions(source: Source.cache));
      if (cachedDoc.exists && cachedDoc.data() != null) {
        final profile = _profileFromSnapshot(cachedDoc, user);
        await _updateLocalCache(profile);
        _scheduleBackgroundRefresh(user);
        return Right(profile);
      }
    } catch (e) {
      logDebug('AuthRepository: Firestore cache miss for profile: $e');
    }

    try {
      final doc = await _withRetry(
        () => _firestore.collection('explorer_profiles').doc(user.uid).get(),
      );
      if (doc.exists && doc.data() != null) {
        final profile = _profileFromSnapshot(doc, user);
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
        } catch (e, stack) {
          logWarning(
              'AuthRepository: failed to persist fallback profile', e, stack);
        }
        return Right(fallback);
      }
    } catch (e, stack) {
      logWarning(
          'AuthRepository: error loading profile from remote, falling back',
          e,
          stack);
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
    } catch (e, stack) {
      logWarning(
          'AuthRepository: failed to save fallback profile on error', e, stack);
    }
    return Right(fallback);
  }

  @override
  Future<Either<Failure, ExplorerProfile>> updateProfile(
      ExplorerProfile profile) async {
    final user = _auth.currentUser;
    if (user == null) return const Left(AuthFailure('User not authenticated'));

    // The write goes to the server first. The copy on this device changes only
    // once the server has accepted the save or has queued it, so a refused save
    // leaves nothing changed here.
    try {
      await _withRetry(
        () => _firestore
            .collection('explorer_profiles')
            .doc(user.uid)
            .set(profileSavePayload(profile.toJson()), SetOptions(merge: true)),
      );
    } catch (e, stack) {
      if (isProfileSaveRefused(e)) {
        logWarning(
            'AuthRepository: profile save refused by the server', e, stack);
        return const Left(PermissionFailure('profile save refused'));
      }
      logWarning(
          'AuthRepository: failed to sync profile update to remote', e, stack);
    }

    await _updateLocalCache(profile);

    // Keep Firebase Auth in sync so other services (TourGroupRepository,
    // OnlineGameRepository) always see in-app data via _auth.currentUser.
    await _syncFirebaseAuthProfile(user, profile);
    return Right(profile);
  }

  Future<Either<Failure, ExplorerProfile>> _syncUserWithFirestore(
      User user) async {
    // Every sign-in ends here, so the person's media key is fetched here.
    await MediaAccess.instance.refresh();
    try {
      final doc = await _withRetry(
        () => _firestore.collection('explorer_profiles').doc(user.uid).get(),
      );

      ExplorerProfile profile;
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        data['uid'] = doc.id;
        final existingAvatar = data['avatarUrl'] as String?;
        if ((existingAvatar == null || existingAvatar.trim().isEmpty) &&
            user.photoURL != null &&
            user.photoURL!.isNotEmpty) {
          data['avatarUrl'] = user.photoURL;
          try {
            await _firestore
                .collection('explorer_profiles')
                .doc(user.uid)
                .set({'avatarUrl': user.photoURL}, SetOptions(merge: true));
          } catch (e, st) {
            logWarning('AuthRepository: failed to backfill avatarUrl', e, st);
          }
        }
        profile = ExplorerProfile.fromJson(data);
      } else {
        profile = _buildFallbackProfile(user);
        await _withRetry(() => _firestore
            .collection('explorer_profiles')
            .doc(user.uid)
            .set(profile.toJson()));
      }

      await _updateLocalCache(profile);
      // Push in-app name/avatar to Firebase Auth so services that read
      // _auth.currentUser always see in-app data.
      await _syncFirebaseAuthProfile(user, profile);
      return Right(profile);
    } catch (e, stack) {
      logWarning(
          'AuthRepository: _syncUserWithFirestore failed, building fallback',
          e,
          stack);
      final profile = _buildFallbackProfile(user);
      await _updateLocalCache(profile);
      try {
        await _withRetry(() => _firestore
            .collection('explorer_profiles')
            .doc(user.uid)
            .set(profile.toJson()));
      } catch (innerE, innerStack) {
        logWarning(
            'AuthRepository: failed to set fallback in _syncUserWithFirestore',
            innerE,
            innerStack);
      }
      return Right(profile);
    }
  }

  /// Pushes in-app profile name/avatar to Firebase Auth so that every service
  /// reading `_auth.currentUser?.displayName` / `.photoURL` always reflects
  /// the in-app explorer profile, not the original Google account data.
  Future<void> _syncFirebaseAuthProfile(
      User user, ExplorerProfile profile) async {
    try {
      final needsName = profile.displayName.isNotEmpty &&
          user.displayName != profile.displayName;
      final needsPhoto = profile.avatarUrl != null &&
          profile.avatarUrl!.isNotEmpty &&
          user.photoURL != profile.avatarUrl;

      if (needsName || needsPhoto) {
        await user.updateDisplayName(
            needsName ? profile.displayName : user.displayName);
        await user
            .updatePhotoURL(needsPhoto ? profile.avatarUrl : user.photoURL);
        // Reload so that subsequent reads of _auth.currentUser see the update.
        await user.reload();
      }
    } catch (e, stack) {
      logWarning(
          'AuthRepository: failed to sync Firebase Auth profile', e, stack);
    }
  }

  ExplorerProfile _buildFallbackProfile(User user) {
    return ExplorerProfile(
      uid: user.uid,
      displayName: user.displayName ?? 'New Explorer',
      avatarUrl: (user.photoURL != null && user.photoURL!.isNotEmpty)
          ? user.photoURL
          : null,
      division: 'Dhaka',
      tier: TrustTier.unverified,
      badges: [],
      isPioneer: false,
      createdAt: DateTime.now(),
      explorerScore: const ExplorerScore(value: 0, tier: TrustTier.unverified),
    );
  }
}
