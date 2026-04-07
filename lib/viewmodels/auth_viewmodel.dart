import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../repositories/auth_repository.dart';
import 'session_manager.dart';

class AuthViewModel extends ChangeNotifier {
  AuthViewModel({required AuthRepository authRepository})
      : _repo = authRepository {
    _sessionManager = SessionManager(
      isSessionExpired: _repo.isSessionExpired,
      onSessionExpired: _onSessionExpired,
    );
    _init();
  }

  final AuthRepository _repo;
  late final SessionManager _sessionManager;

  AuthStatus _status = AuthStatus.initial;
  UserModel? _currentUser;
  String? _errorMessage;
  bool _isLoading = false;

  bool _biometricsAvailable = false;
  bool _biometricLoginEnabled = false;
  bool _biometricButtonVisible = false;
  String? _lastLoggedInName = '';
  bool _forcedPasswordLogin = false;

  // Tracks whether last login was Google (no stored password).
  // Restored from storage on app restart so it survives cold starts and
  // correctly drives the forced-login message and biometric re-auth path.
  bool _isGoogleUser = false;

  int _biometricFailCount = 0;
  static const int _maxBiometricAttempts = 3;

  bool _isSigningIn = false;
  bool _isBiometricInProgress = false;
  bool _initCompleted = false;

  // Guard to prevent notifyListeners() after dispose.
  bool _disposed = false;

  // ── Getters ───────────────────────────────────────────────────────────────

  AuthStatus get status => _status;
  UserModel? get currentUser => _currentUser;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get biometricsAvailable => _biometricsAvailable;
  bool get biometricLoginEnabled => _biometricLoginEnabled;
  bool get biometricButtonVisible => _biometricButtonVisible;
  String? get lastLoggedInName => _lastLoggedInName;
  bool get forcedPasswordLogin => _forcedPasswordLogin;
  int get biometricFailCount => _biometricFailCount;
  int get biometricAttemptsRemaining =>
      (_maxBiometricAttempts - _biometricFailCount)
          .clamp(0, _maxBiometricAttempts);

  /// True if the last successful login was via Google.
  /// Used by the UI to show "Sign in with Google" instead of
  /// "Sign in with your password" when forced login is required.
  bool get isGoogleUser => _isGoogleUser;

  // ── Safe notify ───────────────────────────────────────────────────────────

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> _init() async {
    _isSigningIn = false;
    _isBiometricInProgress = false;

    _setLoading(true);

    _biometricsAvailable = await _repo.isBiometricLoginAvailable();
    _biometricLoginEnabled = await _repo.isBiometricLoginEnabled();
    _lastLoggedInName = await _repo.getLastLoggedInName();

    // Restore _isGoogleUser from persistent storage so the flag survives app
    // restarts. Without this, after a cold start the flag is always false —
    // meaning the forced-login banner shows the wrong message ("use your
    // password") for Google users, and the biometric re-auth path doesn't know
    // to use GoogleSignIn.signInSilently().
    final storedProvider = await _repo.getStoredAuthProvider();
    _isGoogleUser = storedProvider == 'google';

    if (!_biometricsAvailable && _biometricLoginEnabled) {
      _biometricLoginEnabled = false;
      await _repo.setBiometricLoginEnabled(false);
    }

    _biometricButtonVisible = _biometricsAvailable &&
        _biometricLoginEnabled &&
        (_lastLoggedInName != null);

    _isLoading = false;
    _notify();

    final restored = await _repo.restoreSession();

    if (_isSigningIn || _isBiometricInProgress) {
      _initCompleted = true;
      return;
    }

    if (restored != null) {
      _currentUser = restored;
      _status = AuthStatus.authenticated;
      _notify();
      _sessionManager.start();
    } else {
      if (!_isSigningIn && !_isBiometricInProgress) {
        _status = AuthStatus.unauthenticated;
        _notify();
      }
    }

    _initCompleted = true;
  }

  // ── Email Sign-In ─────────────────────────────────────────────────────────

  Future<bool> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (_isSigningIn) return false;
    _isSigningIn = true;
    _forcedPasswordLogin = false;
    _biometricFailCount = 0;
    _isGoogleUser = false;

    _errorMessage = null;
    _isLoading = true;
    _notify();

    final result =
        await _repo.signInWithEmail(email: email, password: password);

    if (result.success) {
      _isGoogleUser = false;
      await _refreshBiometricState();
      _currentUser = result.user!;
      _status = AuthStatus.authenticated;
      _isLoading = false;
      _isSigningIn = false;
      _notify();
      _sessionManager.start();
      return true;
    } else {
      _errorMessage = result.errorMessage;
      _status = AuthStatus.unauthenticated;
      _isLoading = false;
      _isSigningIn = false;
      _notify();
      return false;
    }
  }

  // ── Register ──────────────────────────────────────────────────────────────

  Future<bool> registerWithEmail({
    required String name,
    required String email,
    required String password,
    required int age,
    required double weightKg,
    required double heightCm,
    String? fitnessGoal,
  }) async {
    _isSigningIn = true;

    _errorMessage = null;
    _isLoading = true;
    _notify();

    final result = await _repo.registerWithEmail(
      name: name,
      email: email,
      password: password,
      age: age,
      weightKg: weightKg,
      heightCm: heightCm,
      fitnessGoal: fitnessGoal,
    );

    if (result.success) {
      await _repo.signOut();
      _currentUser = null;
      _status = AuthStatus.unauthenticated;
      _isSigningIn = false;
      _isLoading = false;
      _notify();
      return true;
    } else {
      _errorMessage = result.errorMessage;
      _status = AuthStatus.unauthenticated;
      _isSigningIn = false;
      _isLoading = false;
      _notify();
      return false;
    }
  }

  // ── Google Sign-In ────────────────────────────────────────────────────────

  Future<bool> signInWithGoogle() async {
    if (_isSigningIn) return false;
    _isSigningIn = true;
    _isGoogleUser = true;

    _errorMessage = null;
    _isLoading = true;
    _notify();

    final result = await _repo.signInWithGoogle();

    if (result.success) {
      await _refreshBiometricState();
      _currentUser = result.user!;
      _status = AuthStatus.authenticated;
      _isLoading = false;
      _isSigningIn = false;
      _notify();
      _sessionManager.start();
      return true;
    } else {
      _isGoogleUser = false;
      _errorMessage = result.errorMessage;
      _status = AuthStatus.unauthenticated;
      _isLoading = false;
      _isSigningIn = false;
      _notify();
      return false;
    }
  }

  // ── Biometric Sign-In ─────────────────────────────────────────────────────

  Future<bool> signInWithBiometrics() async {
    if (!_biometricButtonVisible) {
      _errorMessage = 'Biometric login is not available.';
      _notify();
      return false;
    }

    if (_forcedPasswordLogin) {
      _errorMessage = _isGoogleUser
          ? 'Please sign in with Google to continue.'
          : 'Please sign in with your password.';
      _notify();
      return false;
    }

    if (_isSigningIn || _isBiometricInProgress) return false;
    _isSigningIn = true;
    _isBiometricInProgress = true;

    _isLoading = true;
    _errorMessage = null;
    _notify();

    try {
      final result = await _repo.authenticateWithBiometrics();

      if (result.success) {
        _biometricFailCount = 0;
        _forcedPasswordLogin = false;

        await _refreshBiometricState();

        _isBiometricInProgress = false;
        _isSigningIn = false;
        _currentUser = result.user!;
        _isLoading = false;
        _status = AuthStatus.authenticated;
        _notify();

        _sessionManager.start();
        return true;
      } else {
        // Use typed BiometricAuthError — no fragile string matching.
        final error = result.biometricError;

        final isCancelled = error == BiometricAuthError.cancelled ||
            error == BiometricAuthError.failed && result.errorMessage == null;

        final isCredentialError =
            error == BiometricAuthError.googleSessionExpired ||
                error == BiometricAuthError.sessionExpired ||
                error == BiometricAuthError.noSavedCredentials ||
                error == BiometricAuthError.noSavedAccount ||
                error == BiometricAuthError.profileNotFound;

        final isHardwareError = error == BiometricAuthError.notAvailable ||
            error == BiometricAuthError.notEnrolled;

        final isLockedOut = error == BiometricAuthError.lockedOut;

        // Only count as a strike if it's a real failed attempt —
        // not a cancel, not a credential/hardware/lockout error.
        if (!isCancelled &&
            !isCredentialError &&
            !isHardwareError &&
            !isLockedOut) {
          _biometricFailCount++;
        }

        _isBiometricInProgress = false;
        _isSigningIn = false;
        _isLoading = false;

        if (isCredentialError) {
          // Hide biometric button — no valid credentials/session stored.
          // User must do a full login (email or Google) before biometric works.
          _biometricButtonVisible = false;

          // If Google session expired, mark as Google user so the UI shows
          // the correct forced-login message. Also restored from storage in
          // _init() but set explicitly here for within-session occurrences.
          if (error == BiometricAuthError.googleSessionExpired) {
            _isGoogleUser = true;
          }

          _errorMessage = result.errorMessage;
        } else if (isLockedOut) {
          // Device-level lockout — force password/Google login.
          _forcedPasswordLogin = true;
          _biometricButtonVisible = false;
          _errorMessage = result.errorMessage;
        } else if (_biometricFailCount >= _maxBiometricAttempts) {
          _forcedPasswordLogin = true;
          _biometricButtonVisible = false;
          // Show provider-appropriate message.
          _errorMessage = _isGoogleUser
              ? 'Too many failed attempts. Please sign in with Google.'
              : 'Too many failed attempts. Please sign in with your password.';
        } else if (!isCancelled) {
          final remaining = biometricAttemptsRemaining;
          _errorMessage = '${result.errorMessage ?? 'Biometric failed.'} '
              '$remaining attempt${remaining == 1 ? '' : 's'} remaining.';
        } else {
          // User cancelled — clear error silently.
          _errorMessage = null;
        }

        _notify();
        return false;
      }
    } catch (e) {
      _isBiometricInProgress = false;
      _isSigningIn = false;
      _isLoading = false;
      _errorMessage = 'Biometric error: ${e.toString()}';
      _notify();
      return false;
    }
  }

  // ── Password Reset ────────────────────────────────────────────────────────

  Future<bool> sendPasswordReset(String email) async {
    _isLoading = true;
    _errorMessage = null;
    _notify();

    final result = await _repo.sendPasswordResetEmail(email);

    _isLoading = false;
    if (!result.success) _errorMessage = result.errorMessage;
    _notify();
    return result.success;
  }

  // ── Biometric toggle ──────────────────────────────────────────────────────

  Future<void> setBiometricLoginEnabled(bool enabled) async {
    if (enabled && !_biometricsAvailable) return;
    await _repo.setBiometricLoginEnabled(enabled);
    _biometricLoginEnabled = enabled;
    _biometricButtonVisible = _biometricsAvailable &&
        _biometricLoginEnabled &&
        (_lastLoggedInName != null);
    if (!enabled) {
      _forcedPasswordLogin = false;
      _biometricFailCount = 0;
    }
    _notify();
  }

  // ── Session / Activity ────────────────────────────────────────────────────

  void recordActivity() {
    if (!isAuthenticated) return;
    _repo.refreshSession();
    _sessionManager.recordActivity();
  }

  // ── Sign-Out ──────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    _sessionManager.cancel();
    _isSigningIn = false;
    _isBiometricInProgress = false;

    // Do NOT reset _isGoogleUser to false on sign-out.
    // The flag must survive sign-out so that on next app open (before
    // _init() restores it from storage) the UI still shows the correct
    // forced-login message if biometric re-auth fails.
    // _isGoogleUser is reset only on a successful email sign-in,
    // or when Google sign-in itself fails.

    await _repo.signOut();

    _currentUser = null;
    _status = AuthStatus.unauthenticated;
    _isLoading = false;
    _notify();
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<void> _onSessionExpired() async {
    if (!isAuthenticated || _isSigningIn || _isBiometricInProgress) return;
    _currentUser = null;
    _status = AuthStatus.sessionExpired;
    _isLoading = false;
    _notify();
  }

  void _setStatus(AuthStatus status) {
    if (_isBiometricInProgress &&
        status == AuthStatus.unauthenticated &&
        _status != AuthStatus.unauthenticated) {
      return;
    }
    _status = status;
    _notify();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    _notify();
  }

  void _setError(String message) {
    _errorMessage = message;
    _notify();
  }

  void _clearError() {
    _errorMessage = null;
  }

  void _handleSignOut() {
    _currentUser = null;
    _biometricFailCount = 0;
    _forcedPasswordLogin = false;
    _isSigningIn = false;
    _isBiometricInProgress = false;
    _isGoogleUser = false;
    _sessionManager.cancel();
    _setStatus(AuthStatus.unauthenticated);
  }

  Future<void> _refreshBiometricState() async {
    _biometricsAvailable = await _repo.isBiometricLoginAvailable();
    _biometricLoginEnabled = await _repo.isBiometricLoginEnabled();
    _lastLoggedInName = await _repo.getLastLoggedInName();
    _biometricButtonVisible = _biometricsAvailable &&
        _biometricLoginEnabled &&
        (_lastLoggedInName != null);
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionManager.cancel();
    super.dispose();
  }
}

enum AuthStatus {
  initial,
  authenticated,
  unauthenticated,
  sessionExpired,
}