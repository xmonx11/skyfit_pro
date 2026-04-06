import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Wraps the `local_auth` package to provide biometric / device-credential
/// authentication. Returns typed results so callers never deal with raw
/// plugin exceptions.
///
/// Web is gracefully handled — all methods return safe defaults since
/// `local_auth` is a mobile-only plugin (Android / iOS).
class LocalAuthService {
  LocalAuthService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  // ── Device capability checks ──────────────────────────────────────────────

  Future<bool> isBiometricsAvailable() async {
    if (kIsWeb) return false;

    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();
      final enrolled = await _auth.getAvailableBiometrics();

      if (!canCheck || !isDeviceSupported) return false;
      return enrolled.isNotEmpty;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<List<BiometricType>> getAvailableBiometrics() async {
    if (kIsWeb) return [];

    try {
      return await _auth.getAvailableBiometrics();
    } on MissingPluginException {
      return [];
    } on PlatformException {
      return [];
    }
  }

  // ── Authentication ────────────────────────────────────────────────────────

  /// Prompts biometrics ONLY — no PIN/pattern/password fallback.
  /// The app-level 3-strike counter in AuthViewModel is the only fallback,
  /// as required by the lab specification.
  Future<BiometricAuthResult> authenticate({
    String localizedReason = 'Please authenticate to access SkyFit Pro',
    bool stickyAuth = true,
  }) async {
    if (kIsWeb) {
      return BiometricAuthResult(
        success: false,
        error: BiometricAuthError.notAvailable,
        message: 'Biometric authentication is not supported on web.',
      );
    }

    try {
      final available = await isBiometricsAvailable();
      if (!available) {
        return BiometricAuthResult(
          success: false,
          error: BiometricAuthError.notAvailable,
          message: 'Biometrics not available on this device.',
        );
      }

      final authenticated = await _auth.authenticate(
        localizedReason: localizedReason,
        options: AuthenticationOptions(
          biometricOnly: true,   // ✅ fingerprint/FaceID only — no PIN screen
          stickyAuth: stickyAuth,
          sensitiveTransaction: true,
          useErrorDialogs: false, // ✅ disables OS-level PIN fallback dialog
        ),
      );

      if (authenticated) {
        return BiometricAuthResult(success: true);
      } else {
        return BiometricAuthResult(
          success: false,
          error: BiometricAuthError.failed,
          message: 'Authentication was not successful.',
        );
      }
    } on MissingPluginException {
      return BiometricAuthResult(
        success: false,
        error: BiometricAuthError.notAvailable,
        message: 'Biometric plugin not available on this platform.',
      );
    } on PlatformException catch (e) {
      return _mapPlatformException(e);
    }
  }

  Future<void> cancelAuthentication() async {
    if (kIsWeb) return;
    try {
      await _auth.stopAuthentication();
    } catch (_) {}
  }

  // ── Private ───────────────────────────────────────────────────────────────

  BiometricAuthResult _mapPlatformException(PlatformException e) {
    switch (e.code) {
      case 'NotEnrolled':
        return BiometricAuthResult(
          success: false,
          error: BiometricAuthError.notEnrolled,
          message: 'No biometrics enrolled on this device.',
        );
      case 'LockedOut':
      case 'PermanentlyLockedOut':
        return BiometricAuthResult(
          success: false,
          error: BiometricAuthError.lockedOut,
          message:
              'Biometric sensor is locked out. Please sign in with your password.',
        );
      case 'NotAvailable':
        return BiometricAuthResult(
          success: false,
          error: BiometricAuthError.notAvailable,
          message: 'Biometric hardware not available.',
        );
      default:
        return BiometricAuthResult(
          success: false,
          error: BiometricAuthError.unknown,
          message: e.message ?? 'An unknown error occurred.',
        );
    }
  }
}

// ── Result types ──────────────────────────────────────────────────────────────

enum BiometricAuthError {
  notAvailable,
  notEnrolled,
  lockedOut,
  failed,
  unknown,
}

class BiometricAuthResult {
  final bool success;
  final BiometricAuthError? error;
  final String? message;

  const BiometricAuthResult({
    required this.success,
    this.error,
    this.message,
  });

  @override
  String toString() =>
      'BiometricAuthResult(success: $success, error: $error, message: $message)';
}