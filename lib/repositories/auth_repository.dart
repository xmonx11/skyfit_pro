import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../services/local_auth_service.dart';
import '../services/storage_service.dart';

/// Orchestrates all authentication flows.
class AuthRepository {
  AuthRepository({
    required StorageService storageService,
    required FirestoreService firestoreService,
    required LocalAuthService localAuthService,
    FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
  })  : _storage = storageService,
        _firestore = firestoreService,
        _localAuth = localAuthService,
        _auth = firebaseAuth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ??
            GoogleSignIn(
              clientId: kIsWeb
                  ? '30679119611-acb04beeo4atek6l1fu5kju52149fkj6.apps.googleusercontent.com'
                  : null,
              scopes: ['email', 'profile'],
            );

  final StorageService _storage;
  final FirestoreService _firestore;
  final LocalAuthService _localAuth;
  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  static const Duration _sessionTimeout = Duration(minutes: 5);

  // ── Auth state ─────────────────────────────────────────────────────────────

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentFirebaseUser => _auth.currentUser;

  // ── Email / Password ───────────────────────────────────────────────────────

  Future<AuthResult> registerWithEmail({
    required String name,
    required String email,
    required String password,
    required int age,
    required double weightKg,
    required double heightCm,
    String? fitnessGoal,
  }) async {
    UserCredential? credential;
    try {
      credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final firebaseUser = credential.user!;
      await firebaseUser.updateDisplayName(name);

      final now = DateTime.now();
      final userModel = UserModel(
        uid: firebaseUser.uid,
        email: email,
        displayName: name,
        photoUrl: null,
        age: age,
        weightKg: weightKg,
        heightCm: heightCm,
        fitnessGoal: fitnessGoal,
        isProfileComplete: true,
        createdAt: now,
        updatedAt: now,
      );

      try {
        await _firestore.createUser(userModel);
      } catch (firestoreError) {
        try {
          await firebaseUser.delete();
        } catch (_) {}
        return AuthResult.failure(
          'Failed to save profile. Please try again.\n(${firestoreError.toString()})',
        );
      }

      await _persistSession(firebaseUser, displayName: name);
      await _storage.savePassword(password);
      await _storage.saveAuthProvider('email');

      return AuthResult.success(userModel);
    } on FirebaseAuthException catch (e) {
      if (credential?.user != null) {
        try {
          await credential!.user!.delete();
        } catch (_) {}
      }
      return AuthResult.failure(_mapFirebaseAuthError(e));
    } catch (e) {
      if (credential?.user != null) {
        try {
          await credential!.user!.delete();
        } catch (_) {}
      }
      return AuthResult.failure('Registration failed: ${e.toString()}');
    }
  }

  Future<AuthResult> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final firebaseUser = credential.user!;
      final userModel = await _firestore.getUser(firebaseUser.uid);

      if (userModel == null) {
        await _auth.signOut();
        return AuthResult.failure(
            'User profile not found. Please contact support.');
      }

      await _persistSession(firebaseUser, displayName: userModel.displayName);
      await _storage.savePassword(password);
      await _storage.saveAuthProvider('email');

      return AuthResult.success(userModel);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_mapFirebaseAuthError(e));
    } catch (e) {
      return AuthResult.failure('Sign-in failed: ${e.toString()}');
    }
  }

  // ── Google Sign-In ─────────────────────────────────────────────────────────

  Future<AuthResult> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return AuthResult.failure('Google Sign-In was cancelled.');
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final firebaseUser = userCredential.user!;

      final now = DateTime.now();
      UserModel? existing = await _firestore.getUser(firebaseUser.uid);
      final UserModel userModel;

      if (existing == null) {
        userModel = UserModel(
          uid: firebaseUser.uid,
          email: firebaseUser.email ?? googleUser.email,
          displayName:
              firebaseUser.displayName ?? googleUser.displayName ?? 'User',
          photoUrl: firebaseUser.photoURL ?? googleUser.photoUrl,
          age: 0,
          weightKg: 0.0,
          heightCm: 0.0,
          fitnessGoal: null,
          isProfileComplete: false,
          createdAt: now,
          updatedAt: now,
        );
        await _firestore.upsertUser(userModel);
      } else {
        userModel = existing.copyWith(
          photoUrl: firebaseUser.photoURL ?? existing.photoUrl,
          updatedAt: now,
        );
        await _firestore.updateUser(firebaseUser.uid, {
          'photoUrl': userModel.photoUrl,
          'updatedAt': now,
        });
      }

      await _persistSession(firebaseUser, displayName: userModel.displayName);

      // Google users have no password — clear any stale stored password
      // so the biometric flow knows to skip email/password re-authentication
      // and rely on the existing Firebase session instead.
      await _storage.clearPassword();
      await _storage.saveAuthProvider('google');

      return AuthResult.success(userModel);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_mapFirebaseAuthError(e));
    } catch (e) {
      return AuthResult.failure('Google Sign-In failed: ${e.toString()}');
    }
  }

  // ── Biometrics ─────────────────────────────────────────────────────────────

  Future<bool> isBiometricLoginAvailable() async {
    if (kIsWeb) return false;
    return _localAuth.isBiometricsAvailable();
  }

  Future<String?> getLastLoggedInName() => _storage.getLastLoggedInName();

  Future<String?> getStoredAuthProvider() => _storage.getAuthProvider();

  Future<AuthResult> authenticateWithBiometrics() async {
    final String? storedEmail = await _storage.getEmail();
    final String? storedPassword = await _storage.getPassword();
    final String? storedUid = await _storage.getLastLoggedInUid();
    final String? authProvider = await _storage.getAuthProvider();

    // Prompt biometric first
    final result = await _localAuth.authenticate(
      localizedReason: 'Authenticate to access SkyFit Pro',
    );

    if (!result.success) {
      return AuthResult.biometricFailure(
        result.error ?? BiometricAuthError.unknown,
        result.message ?? 'Biometric authentication failed.',
      );
    }

    await _storage.updateLastActivity();

    final String? uid = _auth.currentUser?.uid ?? storedUid;
    if (uid == null || uid.isEmpty) {
      return AuthResult.biometricFailure(
        BiometricAuthError.noSavedAccount,
        'No saved account found. Please sign in first.',
      );
    }

    // If Firebase session is still active, skip re-authentication entirely —
    // biometric just unlocks the app.
    if (_auth.currentUser != null) {
      final userModel = await _firestore.getUser(uid);
      if (userModel == null) {
        return AuthResult.biometricFailure(
          BiometricAuthError.profileNotFound,
          'User profile not found.',
        );
      }
      await _storage.saveLastLoggedInName(userModel.displayName);
      await _storage.saveLastLoggedInUid(uid);
      await _storage.updateLastActivity();
      return AuthResult.success(userModel);
    }

    // ── Firebase session expired — attempt silent re-authentication ──────────

    if (authProvider == 'google') {
      try {
        // Attempt 1: standard silent sign-in using cached account.
        //
        // ROOT CAUSE FIX: This works only if signOut() did NOT call
        // _googleSignIn.signOut(). That call destroys the plugin's local
        // account cache, making signInSilently() permanently return null.
        // The corrected signOut() below skips _googleSignIn.signOut() when
        // biometrics is enabled, so the cache survives logout.
        GoogleSignInAccount? googleUser = await _googleSignIn.signInSilently();

        // Attempt 2: force the plugin to rediscover the device account.
        // Works after app restarts where the plugin instance is fresh.
        if (googleUser == null) {
          googleUser =
              await _googleSignIn.signInSilently(reAuthenticate: true);
        }

        // Attempt 3: Last resort — truly silent interactive sign-in.
        // On Android this uses the account manager to pick the previously
        // authorised account without any visible UI, provided the OAuth
        // grant is still valid. On iOS it fails fast with null.
        if (googleUser == null) {
          googleUser = await _googleSignIn.signIn().catchError((_) => null);

          // Validate the result: if accessToken is null, the account picker
          // was shown (biometric contract broken) — reject the result.
          if (googleUser != null) {
            final probe = await googleUser.authentication;
            if (probe.accessToken == null) {
              googleUser = null;
            }
          }
        }

        if (googleUser == null) {
          return AuthResult.biometricFailure(
            BiometricAuthError.googleSessionExpired,
            'Your Google session has expired. Please sign in with Google again.',
          );
        }

        final googleAuth = await googleUser.authentication;

        // Guard: missing accessToken means the OAuth grant was revoked
        // server-side (e.g. user visited myaccount.google.com and removed
        // your app). Force a manual re-login.
        if (googleAuth.accessToken == null) {
          return AuthResult.biometricFailure(
            BiometricAuthError.googleSessionExpired,
            'Google access was revoked. Please sign in with Google again.',
          );
        }

        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        final userCredential = await _auth.signInWithCredential(credential);
        final firebaseUser = userCredential.user!;

        // Force-refresh the Firebase ID token to ensure it is valid and fresh.
        final token = await firebaseUser.getIdToken(true);
        if (token != null) await _storage.saveAccessToken(token);
        await _storage.saveLastLoggedInUid(firebaseUser.uid);
        await _storage.updateLastActivity();

        final userModel = await _firestore.getUser(firebaseUser.uid);
        if (userModel == null) {
          return AuthResult.biometricFailure(
            BiometricAuthError.profileNotFound,
            'User profile not found.',
          );
        }

        await _storage.saveLastLoggedInName(userModel.displayName);
        return AuthResult.success(userModel);
      } on FirebaseAuthException catch (e) {
        // Token accepted by Google but rejected by Firebase
        // (e.g. account deleted, project access revoked).
        return AuthResult.biometricFailure(
          BiometricAuthError.googleSessionExpired,
          _mapFirebaseAuthError(e),
        );
      } catch (_) {
        // Network error, token revoked, or any other unrecoverable error.
        return AuthResult.biometricFailure(
          BiometricAuthError.googleSessionExpired,
          'Your Google session has expired. Please sign in with Google again.',
        );
      }
    }

    // ── Email/password user — re-authenticate via stored credentials ─────────

    if (storedEmail == null || storedPassword == null) {
      return AuthResult.biometricFailure(
        BiometricAuthError.noSavedCredentials,
        'No saved credentials. Please sign in with your password first.',
      );
    }

    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: storedEmail,
        password: storedPassword,
      );

      final token = await credential.user?.getIdToken();
      if (token != null) await _storage.saveAccessToken(token);
      await _storage.saveEmail(storedEmail);
      await _storage.savePassword(storedPassword);
      if (storedUid != null) await _storage.saveLastLoggedInUid(storedUid);
      await _storage.updateLastActivity();
    } on FirebaseAuthException catch (_) {
      return AuthResult.biometricFailure(
        BiometricAuthError.sessionExpired,
        'Session expired. Please sign in with your password first.',
      );
    }

    final userModel = await _firestore.getUser(uid);
    if (userModel == null) {
      return AuthResult.biometricFailure(
        BiometricAuthError.profileNotFound,
        'User profile not found.',
      );
    }

    await _storage.saveLastLoggedInName(userModel.displayName);
    await _storage.saveLastLoggedInUid(uid);

    return AuthResult.success(userModel);
  }

  Future<void> setBiometricLoginEnabled(bool enabled) async {
    await _storage.setBiometricsEnabled(enabled);
    if (!enabled) await _storage.clearPassword();
  }

  Future<bool> isBiometricLoginEnabled() async {
    if (kIsWeb) return false;
    return _storage.getBiometricsEnabled();
  }

  // ── Session management ─────────────────────────────────────────────────────

  Future<void> refreshSession() => _storage.updateLastActivity();

  Future<bool> isSessionExpired() => _storage.isSessionExpired(_sessionTimeout);

  Future<UserModel?> restoreSession() async {
    try {
      User? firebaseUser = _auth.currentUser;
      if (firebaseUser == null) {
        firebaseUser = await _auth
            .authStateChanges()
            .first
            .timeout(const Duration(seconds: 4), onTimeout: () => null);
      }

      if (firebaseUser == null) return null;

      final isExpired = await isSessionExpired();
      if (isExpired) return null;

      // Valid Firebase session — refresh timestamp so next open won't
      // incorrectly treat a null/stale timestamp as expired.
      await _storage.updateLastActivity();

      return _firestore.getUser(firebaseUser.uid);
    } catch (_) {
      return null;
    }
  }

  // ── Password reset ─────────────────────────────────────────────────────────

  Future<AuthResult> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return AuthResult.successNoUser('Password reset email sent to $email.');
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_mapFirebaseAuthError(e));
    }
  }

  // ── Sign-out ───────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    final biometricEnabled = await isBiometricLoginEnabled();

    await _auth.signOut();

    // ✅ ROOT CAUSE FIX:
    //
    // GoogleSignIn.signOut() destroys the plugin's locally cached
    // GoogleSignInAccount AND revokes the device-level OAuth token cache.
    // After this, signInSilently() always returns null — even with
    // reAuthenticate: true — because there is no account left to restore.
    //
    // When biometric login is enabled, we intentionally skip this call so
    // the cached account survives sign-out and can be silently recovered
    // during the next biometric authentication.
    //
    // Firebase signOut() above already invalidates the server-side session,
    // so skipping the Google plugin's signOut() does NOT leave the user
    // "logged in" anywhere — it only preserves the local account identity
    // needed for signInSilently() to work.
    //
    // When biometric is disabled, full sign-out including Google is correct.
    if (!biometricEnabled) {
      await _googleSignIn.signOut();
    }

    await _storage.clearAuthData();
    await _storage.clearSessionActivity();

    if (!biometricEnabled) {
      await _storage.clearPassword();
    }

    // NOTE: kAuthProviderKey intentionally NOT cleared on sign-out.
    // It must survive sign-out so biometric re-auth on next launch
    // still knows whether the user is a Google or email user.
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<void> _persistSession(User user, {required String displayName}) async {
    await _storage.saveUid(user.uid);
    await _storage.saveEmail(user.email ?? '');
    final token = await user.getIdToken();
    if (token != null) await _storage.saveAccessToken(token);
    await _storage.updateLastActivity();
    await _storage.saveLastLoggedInUid(user.uid);
    await _storage.saveLastLoggedInName(displayName);
  }

  String _mapFirebaseAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'email-already-in-use':
        return 'An account with this email already exists.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'No internet connection.';
      case 'invalid-credential':
        return 'Invalid credentials. Please try again.';
      default:
        return e.message ?? 'An authentication error occurred.';
    }
  }
}

// ── Result type ────────────────────────────────────────────────────────────────

/// Typed biometric error codes — eliminates string matching in AuthViewModel.
enum BiometricAuthError {
  /// Biometric hardware/enrollment not available.
  notAvailable,

  /// No biometrics enrolled on the device.
  notEnrolled,

  /// Sensor locked out after too many attempts.
  lockedOut,

  /// Authentication attempt failed (wrong finger, face mismatch, etc.).
  failed,

  /// User cancelled the biometric prompt.
  cancelled,

  /// No Firebase / Google session, and stored provider is 'google'.
  googleSessionExpired,

  /// Firebase session expired for an email/password user.
  sessionExpired,

  /// No stored email/password credentials found.
  noSavedCredentials,

  /// No saved account UID found on device.
  noSavedAccount,

  /// Firestore user profile missing.
  profileNotFound,

  /// Unknown / unclassified error.
  unknown,
}

class AuthResult {
  final bool success;
  final UserModel? user;
  final String? errorMessage;
  final String? successMessage;

  /// Typed biometric error — non-null only when the failure originated
  /// from the biometric authentication path. Use this in AuthViewModel
  /// instead of string-matching errorMessage.
  final BiometricAuthError? biometricError;

  const AuthResult._({
    required this.success,
    this.user,
    this.errorMessage,
    this.successMessage,
    this.biometricError,
  });

  factory AuthResult.success(UserModel user) =>
      AuthResult._(success: true, user: user);

  factory AuthResult.successNoUser(String message) =>
      AuthResult._(success: true, successMessage: message);

  factory AuthResult.failure(String message) =>
      AuthResult._(success: false, errorMessage: message);

  /// Use this for all biometric-path failures so the ViewModel can switch
  /// on [biometricError] instead of fragile string contains() checks.
  factory AuthResult.biometricFailure(
    BiometricAuthError error,
    String message,
  ) =>
      AuthResult._(
        success: false,
        errorMessage: message,
        biometricError: error,
      );

  @override
  String toString() => success
      ? 'AuthResult.success(uid: ${user?.uid})'
      : 'AuthResult.failure($errorMessage, biometricError: $biometricError)';
}