/// Centralised access to all environment-injected configuration.
///
/// All values are sourced from `--dart-define` flags at build time, so NO
/// secrets are ever hard-coded or committed to version control.
///
/// ── How to run / build ─────────────────────────────────────────────────────
///
///   flutter run \
///     --dart-define=OPENWEATHER_API_KEY=your_key \
///     --dart-define=FIREBASE_API_KEY=your_key \
///     --dart-define=FIREBASE_AUTH_DOMAIN=your_project.firebaseapp.com \
///     --dart-define=FIREBASE_PROJECT_ID=your_project_id \
///     --dart-define=FIREBASE_STORAGE_BUCKET=your_project.appspot.com \
///     --dart-define=FIREBASE_MESSAGING_SENDER_ID=123456789 \
///     --dart-define=FIREBASE_APP_ID=1:123456789:web:abcdef
///
///   Or, for CI/CD, use a `.env` file loaded via `--dart-define-from-file`:
///
///   flutter build web --dart-define-from-file=.env
///
///  ⚠️  NEVER commit the `.env` file.  Add it to `.gitignore`.
///
/// ── .env file format ───────────────────────────────────────────────────────
///
///   OPENWEATHER_API_KEY=abc123
///   FIREBASE_API_KEY=abc123
///   FIREBASE_AUTH_DOMAIN=myproject.firebaseapp.com
///   FIREBASE_PROJECT_ID=myproject
///   FIREBASE_STORAGE_BUCKET=myproject.appspot.com
///   FIREBASE_MESSAGING_SENDER_ID=1234567890
///   FIREBASE_APP_ID=1:1234567890:web:abc123def456
///
/// ───────────────────────────────────────────────────────────────────────────

abstract final class EnvConfig {
  // ── OpenWeatherMap ────────────────────────────────────────────────────────

  /// OpenWeatherMap API key.
  /// Obtain from https://home.openweathermap.org/api_keys
  static const String openWeatherApiKey = String.fromEnvironment(
    'OPENWEATHER_API_KEY',
    defaultValue: '',
  );

  // ── Firebase ──────────────────────────────────────────────────────────────

  /// Firebase Web API key.
  static const String firebaseApiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: '',
  );

  /// Firebase Auth domain, e.g. `my-project.firebaseapp.com`.
  static const String firebaseAuthDomain = String.fromEnvironment(
    'FIREBASE_AUTH_DOMAIN',
    defaultValue: '',
  );

  /// Firebase project ID, e.g. `my-project`.
  static const String firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: '',
  );

  /// Firebase Storage bucket, e.g. `my-project.appspot.com`.
  static const String firebaseStorageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
    defaultValue: '',
  );

  /// Firebase Cloud Messaging sender ID.
  static const String firebaseMessagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: '',
  );

  /// Firebase app ID (web).
  static const String firebaseAppId = String.fromEnvironment(
    'FIREBASE_APP_ID',
    defaultValue: '',
  );

  // ── Validation ────────────────────────────────────────────────────────────

  /// Throws an [EnvironmentException] if any required key is missing.
  /// Call once in [main] before Firebase.initializeApp.
  static void validate() {
    final missing = <String>[];

    if (openWeatherApiKey.isEmpty) missing.add('OPENWEATHER_API_KEY');
    if (firebaseApiKey.isEmpty) missing.add('FIREBASE_API_KEY');
    if (firebaseAuthDomain.isEmpty) missing.add('FIREBASE_AUTH_DOMAIN');
    if (firebaseProjectId.isEmpty) missing.add('FIREBASE_PROJECT_ID');
    if (firebaseStorageBucket.isEmpty) missing.add('FIREBASE_STORAGE_BUCKET');
    if (firebaseMessagingSenderId.isEmpty) {
      missing.add('FIREBASE_MESSAGING_SENDER_ID');
    }
    if (firebaseAppId.isEmpty) missing.add('FIREBASE_APP_ID');

    if (missing.isNotEmpty) {
      throw EnvironmentException(
        'Missing required --dart-define values: ${missing.join(', ')}\n'
        'See lib/utils/env_config.dart for setup instructions.',
      );
    }
  }

  /// Returns true when all required keys are present.
  static bool get isConfigured =>
      openWeatherApiKey.isNotEmpty &&
      firebaseApiKey.isNotEmpty &&
      firebaseProjectId.isNotEmpty;
}

// ── Exception ─────────────────────────────────────────────────────────────────

class EnvironmentException implements Exception {
  final String message;
  const EnvironmentException(this.message);

  @override
  String toString() => 'EnvironmentException: $message';
}