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

      // FIX 1: Sequential awaits — no Future.wait() for storage writes.
      await _persistSession(firebaseUser, displayName: name);
      await _storage.savePassword(password);

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

      // FIX 1: Sequential writes — each storage op completes before the next.
      await _persistSession(firebaseUser, displayName: userModel.displayName);
      await _storage.savePassword(password);

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
          heightCm: 170.0,
          fitnessGoal: null,
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

      // FIX 1: Sequential writes.
      await _persistSession(firebaseUser, displayName: userModel.displayName);
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

  Future<AuthResult> authenticateWithBiometrics() async {
    // FIX 5: Snapshot credentials BEFORE the biometric prompt opens, because
    // some OEM GMS implementations fire a spurious Firebase sign-out the moment
    // the fingerprint UI becomes visible.
    final String? storedEmail = await _storage.getEmail();
    final String? storedPassword = await _storage.getPassword();
    final String? storedUid = await _storage.getLastLoggedInUid();

    // Step 1 – Biometric prompt (fingerprint / FaceID only, no PIN fallback).
    final result = await _localAuth.authenticate(
      localizedReason: 'Authenticate to access SkyFit Pro',
    );

    if (!result.success) {
      return AuthResult.failure(
          result.message ?? 'Biometric authentication failed.');
    }

    // FIX 5 & 1: Write lastActivity IMMEDIATELY after biometric success,
    // sequentially, so restoreSession() never races this write.
    await _storage.updateLastActivity();

    // Step 2 – Resolve UID from snapshot; do NOT trust _auth.currentUser here.
    final String? uid = _auth.currentUser?.uid ?? storedUid;
    if (uid == null || uid.isEmpty) {
      return AuthResult.failure(
          'No saved account found. Please sign in with your password first.');
    }

    // Step 3 – Firebase re-auth (GMS may have invalidated the session).
    if (storedEmail == null || storedPassword == null) {
      return AuthResult.failure(
          'No saved credentials. Please sign in with your password first.');
    }

    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: storedEmail,
        password: storedPassword,
      );

      // FIX 1: Sequential writes — each completes before the next.
      final token = await credential.user?.getIdToken();
      if (token != null) await _storage.saveAccessToken(token);
      await _storage.saveEmail(storedEmail);
      await _storage.savePassword(storedPassword);
      if (storedUid != null) await _storage.saveLastLoggedInUid(storedUid);

      // FIX 5: Second updateLastActivity after re-auth ensures the key is
      // always fresh; eliminates any residual race with isSessionExpired().
      await _storage.updateLastActivity();
    } on FirebaseAuthException catch (_) {
      return AuthResult.failure(
          'Session expired. Please sign in with your password first.');
    }

    // Step 4 – Load user profile.
    final userModel = await _firestore.getUser(uid);
    if (userModel == null) {
      return AuthResult.failure('User profile not found.');
    }

    // Step 5 – Persist name + UID for next launch.
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
      // FIX 2: Wait for Firebase auth state with a generous timeout to handle
      // OEMs (Oppo, Xiaomi) that initialise Firebase asynchronously.
      User? firebaseUser = _auth.currentUser;
      if (firebaseUser == null) {
        firebaseUser = await _auth
            .authStateChanges()
            .first
            .timeout(const Duration(seconds: 4), onTimeout: () => null);
      }

      // No Firebase user → nothing to restore.
      if (firebaseUser == null) return null;

      // FIX 2: Check expiry AFTER confirming Firebase user exists.
      // isSessionExpired returns true when lastActivity is null, treating
      // missing key the same as expired — no separate hasLastActivity() gate.
      final isExpired = await isSessionExpired();
      if (isExpired) {
        // FIX 2 & 6: Do NOT sign out here — biometric re-auth may be in
        // progress and may have just written lastActivity. Let AuthViewModel's
        // session timer handle the forced sign-out.
        return null;
      }

      // FIX 1: Sequential write.
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

    // FIX 6: Sign out from Firebase FIRST, then clear local storage.
    // This ensures the Firebase session is definitively ended before any
    // storage keys are deleted, preventing a narrow window where Firebase
    // is still "logged in" but local state is partially cleared.
    await _auth.signOut();
    await _googleSignIn.signOut();

    // FIX 6: Clear auth data AFTER Firebase sign-out is complete.
    await _storage.clearAuthData();

    // FIX 6: Clear session activity AFTER Firebase sign-out.
    // This is kept separate from clearAuthData() to avoid racing biometric
    // re-auth (which writes lastActivity) — see StorageService for full notes.
    await _storage.clearSessionActivity();

    if (!biometricEnabled) {
      await _storage.clearPassword();
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// FIX 1: All storage writes are sequential — no Future.wait().
  /// Order matters: uid → email → token → lastActivity → lastLoggedInUid → name.
  Future<void> _persistSession(User user, {required String displayName}) async {
    await _storage.saveUid(user.uid);
    await _storage.saveEmail(user.email ?? '');
    final token = await user.getIdToken();
    if (token != null) await _storage.saveAccessToken(token);
    // lastActivity MUST be written before this call returns, so that any
    // subsequent isSessionExpired() call sees a valid timestamp.
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

class AuthResult {
  final bool success;
  final UserModel? user;
  final String? errorMessage;
  final String? successMessage;

  const AuthResult._({
    required this.success,
    this.user,
    this.errorMessage,
    this.successMessage,
  });

  factory AuthResult.success(UserModel user) =>
      AuthResult._(success: true, user: user);

  factory AuthResult.successNoUser(String message) =>
      AuthResult._(success: true, successMessage: message);

  factory AuthResult.failure(String message) =>
      AuthResult._(success: false, errorMessage: message);

  @override
  String toString() => success
      ? 'AuthResult.success(uid: ${user?.uid})'
      : 'AuthResult.failure($errorMessage)';
}