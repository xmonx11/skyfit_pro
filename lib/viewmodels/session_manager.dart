import 'dart:async';

/// Manages inactivity-based session expiry.
///
/// Usage:
///   1. Call [start] after successful login.
///   2. Call [recordActivity] on every user tap / scroll.
///   3. Listen to [onSessionExpired] to react when the 5-min timeout fires.
///   4. Call [cancel] on sign-out or dispose.
class SessionManager {
  SessionManager({
    this.checkInterval = const Duration(seconds: 30),
    required this.isSessionExpired,
    required this.onSessionExpired,
  });

  /// How often the manager polls for expiry (default: every 30 s).
  final Duration checkInterval;

  /// Callback that returns `true` when the session has been inactive
  /// for more than 5 minutes. Typically delegates to StorageService /
  /// AuthRepository.isSessionExpired().
  final Future<bool> Function() isSessionExpired;

  /// Called once when the session is determined to have expired.
  /// Wire this to set AuthStatus.sessionExpired in AuthViewModel.
  final Future<void> Function() onSessionExpired;

  Timer? _timer;
  bool _isRunning = false;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Start (or restart) the inactivity timer.
  /// Safe to call multiple times — cancels the previous timer first.
  void start() {
    cancel();
    _isRunning = true;
    _timer = Timer.periodic(checkInterval, (_) => _tick());
  }

  /// Reset the timer because the user just interacted with the app.
  /// Also refreshes the lastActivity timestamp via the supplied callback.
  void recordActivity() {
    if (!_isRunning) return;
    start(); // cancel + restart = effective reset
  }

  /// Stop the timer (sign-out, dispose, etc.).
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
  }

  bool get isRunning => _isRunning;

  // ── Private ────────────────────────────────────────────────────────────────

  Future<void> _tick() async {
    if (!_isRunning) return;
    final expired = await isSessionExpired();
    if (expired) {
      cancel();
      await onSessionExpired();
    }
  }
}