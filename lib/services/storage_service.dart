import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Provides an encrypted key-value store backed by `flutter_secure_storage`.
/// All sensitive data (tokens, user IDs, biometric flags) MUST go through this
/// service. SharedPreferences is intentionally NOT used anywhere in this app.
class StorageService {
  StorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
                keyCipherAlgorithm:
                    KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
                storageCipherAlgorithm:
                    StorageCipherAlgorithm.AES_GCM_NoPadding,
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
                synchronizable: false,
              ),
              webOptions: WebOptions(
                dbName: 'skyfit_pro_secure',
                publicKey: 'skyfit_pro',
              ),
            );

  final FlutterSecureStorage _storage;

  // ── Storage keys ──────────────────────────────────────────────────────────

  static const String kUidKey = 'skyfit_uid';
  static const String kEmailKey = 'skyfit_email';

  // Password stored encrypted for biometric silent re-auth only.
  // Cleared on every manual sign-out (when biometrics is disabled).
  // Re-saved on every successful email/password login.
  static const String kPasswordKey = 'skyfit_password';

  static const String kAccessTokenKey = 'skyfit_access_token';
  static const String kRefreshTokenKey = 'skyfit_refresh_token';
  static const String kBiometricsEnabledKey = 'skyfit_biometrics_enabled';
  static const String kLastActivityKey = 'skyfit_last_activity';
  static const String kOnboardingCompleteKey = 'skyfit_onboarding_complete';
  static const String kLastCityKey = 'skyfit_last_city';

  // Survives sign-out so biometric button reappears on next launch.
  static const String kLastLoggedInUidKey = 'skyfit_last_logged_in_uid';
  static const String kLastLoggedInNameKey = 'skyfit_last_logged_in_name';

  // FIX GOOGLE BIOMETRIC: Tracks which provider was used to sign in
  // ('google' or 'email') so biometric re-auth knows which path to take.
  // Google users have no stored password, so they must re-auth via
  // GoogleSignIn.signInSilently() instead of signInWithEmailAndPassword().
  static const String kAuthProviderKey = 'skyfit_auth_provider';

  // ── Initialisation ────────────────────────────────────────────────────────

  Future<void> init() async {
    try {
      await _storage.containsKey(key: kUidKey);
    } catch (_) {}
  }

  // ── Generic CRUD ──────────────────────────────────────────────────────────

  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      throw StorageException('Failed to read key "$key": $e');
    }
  }

  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      throw StorageException('Failed to write key "$key": $e');
    }
  }

  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      throw StorageException('Failed to delete key "$key": $e');
    }
  }

  Future<bool> containsKey(String key) async {
    try {
      return await _storage.containsKey(key: key);
    } catch (e) {
      throw StorageException('Failed to check key "$key": $e');
    }
  }

  Future<Map<String, String>> readAll() async {
    try {
      return await _storage.readAll();
    } catch (e) {
      throw StorageException('Failed to read all keys: $e');
    }
  }

  Future<void> deleteAll() async {
    try {
      await _storage.deleteAll();
    } catch (e) {
      throw StorageException('Failed to delete all keys: $e');
    }
  }

  // ── Typed convenience methods ─────────────────────────────────────────────

  Future<void> saveUid(String uid) => write(kUidKey, uid);
  Future<String?> getUid() => read(kUidKey);

  Future<void> saveEmail(String email) => write(kEmailKey, email);
  Future<String?> getEmail() => read(kEmailKey);

  Future<void> savePassword(String password) => write(kPasswordKey, password);
  Future<String?> getPassword() => read(kPasswordKey);
  Future<void> clearPassword() => delete(kPasswordKey);

  Future<void> saveAccessToken(String token) => write(kAccessTokenKey, token);
  Future<String?> getAccessToken() => read(kAccessTokenKey);

  Future<void> saveRefreshToken(String token) =>
      write(kRefreshTokenKey, token);
  Future<String?> getRefreshToken() => read(kRefreshTokenKey);

  Future<void> setBiometricsEnabled(bool enabled) =>
      write(kBiometricsEnabledKey, enabled.toString());
  Future<bool> getBiometricsEnabled() async {
    final val = await read(kBiometricsEnabledKey);
    return val == 'true';
  }

  Future<void> updateLastActivity() =>
      write(kLastActivityKey, DateTime.now().toIso8601String());

  Future<DateTime?> getLastActivity() async {
    final val = await read(kLastActivityKey);
    if (val == null) return null;
    return DateTime.tryParse(val);
  }

  Future<bool> hasLastActivity() => containsKey(kLastActivityKey);

  Future<void> setOnboardingComplete(bool complete) =>
      write(kOnboardingCompleteKey, complete.toString());
  Future<bool> getOnboardingComplete() async {
    final val = await read(kOnboardingCompleteKey);
    return val == 'true';
  }

  Future<void> saveLastCity(String city) => write(kLastCityKey, city);
  Future<String?> getLastCity() => read(kLastCityKey);

  // ── Last logged-in account ────────────────────────────────────────────────

  Future<void> saveLastLoggedInUid(String uid) =>
      write(kLastLoggedInUidKey, uid);
  Future<String?> getLastLoggedInUid() => read(kLastLoggedInUidKey);
  Future<bool> hasLastLoggedInUid() => containsKey(kLastLoggedInUidKey);

  Future<void> saveLastLoggedInName(String name) =>
      write(kLastLoggedInNameKey, name);
  Future<String?> getLastLoggedInName() => read(kLastLoggedInNameKey);

  Future<void> clearLastLoggedInAccount() async {
    await delete(kLastLoggedInUidKey);
    await delete(kLastLoggedInNameKey);
  }

  // ── Auth provider ─────────────────────────────────────────────────────────

  /// FIX GOOGLE BIOMETRIC: Saves the sign-in provider so biometric re-auth
  /// can choose the correct path ('google' vs 'email').
  /// Must be called after every successful sign-in.
  Future<void> saveAuthProvider(String provider) =>
      write(kAuthProviderKey, provider);

  /// Returns the stored auth provider ('google' or 'email'), or null if
  /// the user has never signed in on this device.
  Future<String?> getAuthProvider() => read(kAuthProviderKey);

  // ── Session helpers ───────────────────────────────────────────────────────

  /// FIX 2: Returns true if lastActivity is null (missing key) OR expired.
  ///
  /// Treating null as "expired" means callers only need ONE check instead of
  /// a separate hasLastActivity() gate. This eliminates the race window where
  /// signOut() deletes the key but biometric re-auth hasn't written it yet.
  Future<bool> isSessionExpired(Duration timeout) async {
    final lastActivity = await getLastActivity();
    if (lastActivity == null) return true;
    return DateTime.now().difference(lastActivity) > timeout;
  }

  /// Clears auth-related keys on sign-out.
  ///
  /// Does NOT clear:
  ///   • kLastLoggedInUidKey / kLastLoggedInNameKey — survive sign-out so the
  ///     biometric button reappears on next launch.
  ///   • kEmailKey — needed for biometric silent re-auth.
  ///   • kLastActivityKey — cleared separately via [clearSessionActivity] to
  ///     avoid racing biometric re-auth's [updateLastActivity] call.
  ///   • kPasswordKey — cleared separately via [clearPassword] in signOut when
  ///     biometrics is disabled.
  ///   • kAuthProviderKey — must survive sign-out so biometric re-auth on
  ///     next launch still knows whether the user is a Google or email user.
  Future<void> clearAuthData() async {
    await delete(kUidKey);
    await delete(kAccessTokenKey);
    await delete(kRefreshTokenKey);
  }

  /// Clears the session activity timestamp.
  ///
  /// Must be called AFTER [clearAuthData] and AFTER Firebase sign-out.
  /// Keeping this separate prevents a race where biometric re-auth writes
  /// lastActivity and clearAuthData() immediately deletes it again.
  Future<void> clearSessionActivity() async {
    await delete(kLastActivityKey);
  }
}

// ── Exception ─────────────────────────────────────────────────────────────────

class StorageException implements Exception {
  final String message;
  const StorageException(this.message);

  @override
  String toString() => 'StorageException: $message';
}