import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../repositories/auth_repository.dart';
import 'session_manager.dart';

class AuthViewModel extends ChangeNotifier {
  AuthViewModel({required AuthRepository authRepository})
      : _repo = authRepository {
    // Wire SessionManager — delegates expiry check and callback here.
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
  String? _lastLoggedInName;
  bool _forcedPasswordLogin = false;

  int _biometricFailCount = 0;
  static const int _maxBiometricAttempts = 3;

  bool _isSigningIn = false;
  bool _isBiometricInProgress = false;
  bool _initCompleted = false;

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

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> _init() async {
    _isSigningIn = false;
    _isBiometricInProgress = false;

    _setLoading(true);

    _biometricsAvailable = await _repo.isBiometricLoginAvailable();
    _biometricLoginEnabled = await _repo.isBiometricLoginEnabled();
    _lastLoggedInName = await _repo.getLastLoggedInName();

    if (!_biometricsAvailable && _biometricLoginEnabled) {
      _biometricLoginEnabled = false;
      await _repo.setBiometricLoginEnabled(false);
    }

    _biometricButtonVisible = _biometricsAvailable &&
        _biometricLoginEnabled &&
        (_lastLoggedInName != null);

    _isLoading = false;
    notifyListeners();

    final restored = await _repo.restoreSession();

    if (_isSigningIn || _isBiometricInProgress) {
      _initCompleted = true;
      return;
    }

    if (restored != null) {
      _currentUser = restored;
      _status = AuthStatus.authenticated;
      notifyListeners();
      _sessionManager.start(); // ← SessionManager starts here
    } else {
      if (!_isSigningIn && !_isBiometricInProgress) {
        _status = AuthStatus.unauthenticated;
        notifyListeners();
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

    _errorMessage = null;
    _isLoading = true;
    notifyListeners();

    final result =
        await _repo.signInWithEmail(email: email, password: password);

    if (result.success) {
      await _refreshBiometricState();
      _currentUser = result.user!;
      _status = AuthStatus.authenticated;
      _isLoading = false;
      _isSigningIn = false;
      notifyListeners();
      _sessionManager.start(); // ← SessionManager starts after login
      return true;
    } else {
      _errorMessage = result.errorMessage;
      _status = AuthStatus.unauthenticated;
      _isLoading = false;
      _isSigningIn = false;
      notifyListeners();
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
    notifyListeners();

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
      notifyListeners();
      return true;
    } else {
      _errorMessage = result.errorMessage;
      _status = AuthStatus.unauthenticated;
      _isSigningIn = false;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ── Google Sign-In ────────────────────────────────────────────────────────

  Future<bool> signInWithGoogle() async {
    if (_isSigningIn) return false;
    _isSigningIn = true;

    _errorMessage = null;
    _isLoading = true;
    notifyListeners();

    final result = await _repo.signInWithGoogle();

    if (result.success) {
      await _refreshBiometricState();
      _currentUser = result.user!;
      _status = AuthStatus.authenticated;
      _isLoading = false;
      _isSigningIn = false;
      notifyListeners();
      _sessionManager.start(); // ← SessionManager starts after Google login
      return true;
    } else {
      _errorMessage = result.errorMessage;
      _status = AuthStatus.unauthenticated;
      _isLoading = false;
      _isSigningIn = false;
      notifyListeners();
      return false;
    }
  }

  // ── Biometric Sign-In ─────────────────────────────────────────────────────

  Future<bool> signInWithBiometrics() async {
    if (!_biometricButtonVisible) {
      _errorMessage = 'Biometric login is not available.';
      notifyListeners();
      return false;
    }

    if (_forcedPasswordLogin) {
      _errorMessage = 'Please sign in with your password.';
      notifyListeners();
      return false;
    }

    if (_isSigningIn || _isBiometricInProgress) return false;
    _isSigningIn = true;
    _isBiometricInProgress = true;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _repo.authenticateWithBiometrics();

      if (result.success) {
        _biometricFailCount = 0;
        _forcedPasswordLogin = false;

        _biometricsAvailable = await _repo.isBiometricLoginAvailable();
        _biometricLoginEnabled = await _repo.isBiometricLoginEnabled();
        _lastLoggedInName = await _repo.getLastLoggedInName();
        _biometricButtonVisible = _biometricsAvailable &&
            _biometricLoginEnabled &&
            (_lastLoggedInName != null);

        _isBiometricInProgress = false;
        _isSigningIn = false;
        _currentUser = result.user!;
        _isLoading = false;
        _status = AuthStatus.authenticated;
        notifyListeners();

        _sessionManager.start(); // ← SessionManager starts after biometric
        return true;
      } else {
        final msg = result.errorMessage?.toLowerCase() ?? '';

        final isCancelled = msg.contains('cancel') ||
            msg.contains('not successful') ||
            result.errorMessage == null;

        final isCredentialError = msg.contains('no saved') ||
            msg.contains('no account') ||
            msg.contains('session expired') ||
            msg.contains('profile not found') ||
            msg.contains('saved credentials') ||
            msg.contains('saved account');

        if (!isCancelled && !isCredentialError) {
          _biometricFailCount++;
        }

        _isBiometricInProgress = false;
        _isSigningIn = false;
        _isLoading = false;

        if (isCredentialError) {
          _errorMessage = result.errorMessage;
        } else if (_biometricFailCount >= _maxBiometricAttempts) {
          _forcedPasswordLogin = true;
          _biometricButtonVisible = false;
          _errorMessage =
              'Too many failed attempts. Please sign in with your password.';
        } else if (!isCancelled) {
          final remaining = biometricAttemptsRemaining;
          _errorMessage =
              '${result.errorMessage ?? 'Biometric failed.'} '
              '$remaining attempt${remaining == 1 ? '' : 's'} remaining.';
        } else {
          _errorMessage = null;
        }

        notifyListeners();
        return false;
      }
    } catch (e) {
      _isBiometricInProgress = false;
      _isSigningIn = false;
      _isLoading = false;
      _errorMessage = 'Biometric error: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  // ── Password Reset ────────────────────────────────────────────────────────

  Future<bool> sendPasswordReset(String email) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _repo.sendPasswordResetEmail(email);

    _isLoading = false;
    if (!result.success) _errorMessage = result.errorMessage;
    notifyListeners();
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
    notifyListeners();
  }

  // ── Session / Activity ────────────────────────────────────────────────────

  /// Called on every user tap/scroll (wired via Listener in HomeView).
  /// Delegates to SessionManager which resets the inactivity timer.
  void recordActivity() {
    if (!isAuthenticated) return;
    _repo.refreshSession();
    _sessionManager.recordActivity(); // ← SessionManager resets timer
  }

  // ── Sign-Out ──────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    _sessionManager.cancel(); // ← SessionManager stopped on sign-out
    _isSigningIn = false;
    _isBiometricInProgress = false;

    await _repo.signOut();

    _currentUser = null;
    _status = AuthStatus.unauthenticated;
    _isLoading = false;
    notifyListeners();
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Called by SessionManager when the 5-min inactivity timeout fires.
  /// Sets status to sessionExpired → AuthGate rebuilds → LoginView shown.
  Future<void> _onSessionExpired() async {
    if (!isAuthenticated || _isSigningIn || _isBiometricInProgress) return;
    _currentUser = null;
    _status = AuthStatus.sessionExpired;
    _isLoading = false;
    notifyListeners();
  }

  void _setStatus(AuthStatus status) {
    if (_isBiometricInProgress &&
        status == AuthStatus.unauthenticated &&
        _status != AuthStatus.unauthenticated) {
      return;
    }
    _status = status;
    notifyListeners();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    notifyListeners();
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
    notifyListeners();
  }

  @override
  void dispose() {
    _sessionManager.cancel(); // ← always clean up
    super.dispose();
  }
}

enum AuthStatus {
  initial,
  authenticated,
  unauthenticated,
  sessionExpired,
}