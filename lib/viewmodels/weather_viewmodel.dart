import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/activity_model.dart';
import '../models/user_model.dart';
import '../models/weather_model.dart';
import '../repositories/weather_repository.dart';

/// Manages weather state, auto-refresh scheduling and activity suggestions.
/// Depends only on [WeatherRepository].
///
/// ✅ Fix — [_latestUser] caches the most recent UserModel so that
/// auto-refresh, manual refresh, and [refreshSuggestions] always use
/// the up-to-date profile (age, weight, goal) — not a stale snapshot.
class WeatherViewModel extends ChangeNotifier {
  WeatherViewModel({
    required WeatherRepository weatherRepository,
    Duration autoRefreshInterval = const Duration(minutes: 30),
  })  : _repo = weatherRepository,
        _autoRefreshInterval = autoRefreshInterval;

  final WeatherRepository _repo;
  final Duration _autoRefreshInterval;

  // ── State ─────────────────────────────────────────────────────────────────

  WeatherModel? _weather;
  List<ActivityModel> _suggestions = [];
  WeatherStatus _status = WeatherStatus.idle;
  String? _errorMessage;
  String? _currentCity;
  Timer? _refreshTimer;

  /// ✅ Fix — always holds the latest UserModel so auto-refresh and
  /// refreshSuggestions() never use a stale profile snapshot.
  UserModel? _latestUser;

  // ── Public getters ────────────────────────────────────────────────────────

  WeatherModel? get weather => _weather;
  List<ActivityModel> get suggestions => List.unmodifiable(_suggestions);
  WeatherStatus get status => _status;
  String? get errorMessage => _errorMessage;
  String? get currentCity => _currentCity;
  bool get isLoading => _status == WeatherStatus.loading;
  bool get hasData => _weather != null;

  /// Human-readable summary produced by the repository.
  String get weatherSummary =>
      _weather != null ? _repo.buildWeatherSummary(_weather!) : '';

  // ── Fetch operations ──────────────────────────────────────────────────────

  /// Fetches weather by [cityName] and refreshes activity suggestions.
  /// [user] is optional — used to personalise activity recommendations.
  Future<void> fetchWeatherByCity(
    String cityName, {
    UserModel? user,
    bool silent = false,
  }) async {
    if (user != null) _latestUser = user; // ✅ cache latest user
    if (!silent) _setStatus(WeatherStatus.loading);
    _clearError();

    try {
      final weather = await _repo.getWeatherByCity(cityName);
      _weather = weather;
      _currentCity = cityName;
      _updateSuggestions(user: _latestUser);
      _setStatus(WeatherStatus.loaded);
      _scheduleAutoRefresh(cityName: cityName);
    } catch (e) {
      _setError(_mapError(e));
      _setStatus(WeatherStatus.error);
    }
  }

  /// Fetches weather by geographic coordinates.
  Future<void> fetchWeatherByCoords({
    required double lat,
    required double lon,
    UserModel? user,
    bool silent = false,
  }) async {
    if (user != null) _latestUser = user; // ✅ cache latest user
    if (!silent) _setStatus(WeatherStatus.loading);
    _clearError();

    try {
      final weather =
          await _repo.getWeatherByCoords(lat: lat, lon: lon);
      _weather = weather;
      _currentCity = weather.cityName;
      _updateSuggestions(user: _latestUser);
      _setStatus(WeatherStatus.loaded);
      _scheduleAutoRefresh(lat: lat, lon: lon);
    } catch (e) {
      _setError(_mapError(e));
      _setStatus(WeatherStatus.error);
    }
  }

  /// Manually refreshes weather for the last known location.
  /// Always uses [_latestUser] — passing [user] updates the cache first.
  Future<void> refresh({UserModel? user}) async {
    if (user != null) _latestUser = user; // ✅ update cache if provided
    if (_currentCity != null) {
      await fetchWeatherByCity(_currentCity!, user: _latestUser, silent: true);
    }
  }

  // ── Activity suggestions ──────────────────────────────────────────────────

  /// Regenerates activity suggestions for the current weather using the
  /// latest [user] profile.
  ///
  /// ✅ Call this from UserViewModel.updateProfile() whenever the user saves
  /// changes to age, weight, fitnessGoal, etc:
  ///
  /// ```dart
  /// // Inside UserViewModel.updateProfile()
  /// _weatherViewModel?.refreshSuggestions(user: updatedUser);
  /// ```
  void refreshSuggestions({UserModel? user}) {
    if (user != null) _latestUser = user; // ✅ always update cache
    _updateSuggestions(user: _latestUser);
    notifyListeners();
  }

  // ── Auto-refresh ──────────────────────────────────────────────────────────

  /// Schedules a periodic weather refresh.
  /// Always reads [_latestUser] at tick time — never captures a stale snapshot.
  void _scheduleAutoRefresh({
    String? cityName,
    double? lat,
    double? lon,
  }) {
    _cancelAutoRefresh();
    _refreshTimer = Timer.periodic(_autoRefreshInterval, (_) {
      // ✅ Fix — read _latestUser at tick time, not at schedule time
      if (cityName != null) {
        fetchWeatherByCity(cityName, user: _latestUser, silent: true);
      } else if (lat != null && lon != null) {
        fetchWeatherByCoords(
            lat: lat, lon: lon, user: _latestUser, silent: true);
      }
    });
  }

  void _cancelAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  /// Pauses auto-refresh (e.g. when app goes to background).
  void pauseAutoRefresh() => _cancelAutoRefresh();

  /// Resumes auto-refresh with the current city.
  void resumeAutoRefresh({UserModel? user}) {
    if (user != null) _latestUser = user;
    if (_currentCity != null) {
      _scheduleAutoRefresh(cityName: _currentCity);
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  void _updateSuggestions({UserModel? user}) {
    if (_weather == null) return;
    _suggestions = _repo.recommendActivities(
      weather: _weather!,
      user: user,
    );
  }

  void _setStatus(WeatherStatus status) {
    _status = status;
    notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
  }

  String _mapError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('socketexception') ||
        msg.contains('no internet') ||
        msg.contains('network')) {
      return 'No internet connection. Please check your network.';
    }
    if (msg.contains('not found') || msg.contains('404')) {
      return 'City not found. Please check the spelling and try again.';
    }
    if (msg.contains('api key') || msg.contains('401')) {
      return 'Weather service configuration error.';
    }
    if (msg.contains('rate limit') || msg.contains('429')) {
      return 'Too many requests. Please wait a moment and try again.';
    }
    return 'Unable to load weather. Please try again.';
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _cancelAutoRefresh();
    super.dispose();
  }
}

// ── Status enum ───────────────────────────────────────────────────────────────

enum WeatherStatus {
  idle,
  loading,
  loaded,
  error,
}