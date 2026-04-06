import 'dart:convert';

import '../models/activity_model.dart';
import '../models/user_model.dart';
import '../models/weather_model.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

/// Orchestrates weather data fetching and health activity suggestion logic.
/// ViewModels depend on this repository — never on ApiService directly.
class WeatherRepository {
  WeatherRepository({
    required ApiService apiService,
    required StorageService storageService,
  })  : _api = apiService,
        _storage = storageService;

  final ApiService _api;
  final StorageService _storage;

  static const _cacheKeyPrefix = 'weather_cache_';
  static const _cacheTtl = Duration(minutes: 30);

  // ── Weather fetching ──────────────────────────────────────────────────────

  Future<WeatherModel> getWeatherByCity(String cityName) async {
    final cached = await _tryCache(cityName);
    if (cached != null) return cached;

    final json = await _api.fetchCurrentWeatherByCity(cityName);
    final weather = WeatherModel.fromJson(json);

    final coords = json['coord'] as Map<String, dynamic>?;
    WeatherModel enriched = weather;
    if (coords != null) {
      enriched = await _enrichWithUv(
        weather,
        lat: (coords['lat'] as num).toDouble(),
        lon: (coords['lon'] as num).toDouble(),
      );
    }
    await _saveCache(cityName, enriched);
    return enriched;
  }

  Future<WeatherModel> getWeatherByCoords({
    required double lat,
    required double lon,
  }) async {
    final json = await _api.fetchCurrentWeatherByCoords(lat: lat, lon: lon);
    final weather = WeatherModel.fromJson(json);
    final enriched = await _enrichWithUv(weather, lat: lat, lon: lon);
    await _saveCache(enriched.cityName, enriched);
    return enriched;
  }

  Future<({double lat, double lon})?> geocodeCity(String cityName) async {
    final results = await _api.geocodeCity(cityName);
    if (results.isEmpty) return null;
    final first = results.first as Map<String, dynamic>;
    return (
      lat: (first['lat'] as num).toDouble(),
      lon: (first['lon'] as num).toDouble(),
    );
  }

  // ── Cache helpers ─────────────────────────────────────────────────────────

  Future<WeatherModel?> _tryCache(String cityName) async {
    try {
      final raw = await _storage.read('$_cacheKeyPrefix$cityName');
      if (raw == null) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final fetched = DateTime.parse(map['fetchedAt'] as String);
      if (DateTime.now().difference(fetched) > _cacheTtl) return null;
      return WeatherModel.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCache(String cityName, WeatherModel w) async {
    try {
      await _storage.write('$_cacheKeyPrefix$cityName', jsonEncode(w.toMap()));
    } catch (_) {}
  }

  // ── Activity recommendation ───────────────────────────────────────────────
  //
  // Lab requirement matrix:
  // Priority 1  — Extreme Heat (≥35°C) + Overweight      → Swimming / Light Stretching
  // Priority 2  — Rain / Snow / Storm / Atmosphere        → Indoor Yoga / Bodyweight Circuit
  // Priority 3  — Clear + Elderly (age ≥ 50)              → Morning Walk / Tai Chi
  // Priority 4a — Clear + Young + Normal/Athletic BMI     → Outdoor Run / HIIT
  // Priority 4b — Clear + Young + Overweight/Obese        → Walk / Outdoor Yoga / Swimming
  // Default     — Scored fallback
  //
  // Enhancement: BMI filter applied before goal sorting so unsafe activities
  // (e.g. intense HIIT for obese users) are removed from the pool entirely,
  // not just ranked lower.

  List<ActivityModel> recommendActivities({
    required WeatherModel weather,
    UserModel? user,
    int maxResults = 5,
    List<ActivityModel> catalogue = kDefaultActivities,
  }) {
    final bool isExtremeHeat = weather.temperatureCelsius >= 35;

    final bool isRainOrSnow =
        weather.category == WeatherCategory.rain ||
        weather.category == WeatherCategory.snow ||
        weather.category == WeatherCategory.thunderstorm ||
        weather.category == WeatherCategory.atmosphere;

    final bool isClear =
        weather.category == WeatherCategory.clear ||
        weather.category == WeatherCategory.cloudy;

    final bool isElderly    = user?.isElderly ?? false;
    final bool isOverweight = user?.isOverweight ?? false;

    // ── Priority 1: Extreme Heat + Overweight ──────────────────────────────
    if (isExtremeHeat && isOverweight) {
      final picks = _pickFromCatalogue(
        catalogue,
        preferredIds: ['swimming', 'light_stretching', 'stretching'],
        fallbackTags: ['low-impact', 'recovery', 'heat'],
        maxResults: maxResults,
      );
      final filtered = _filterByBmi(picks, user: user);
      return _sortByGoal(filtered, user: user);
    }

    // ── Priority 2: Rain / Snow / Thunder / Atmosphere ────────────────────
    if (isRainOrSnow) {
      final picks = _pickFromCatalogue(
        catalogue,
        preferredIds: [
          'home_yoga',
          'bodyweight_circuit',
          'bodyweight_strength',
          'treadmill_run',
          'indoor_cycling',
        ],
        fallbackTags: ['flexibility', 'bodyweight', 'strength'],
        maxResults: maxResults,
      );
      final filtered = _filterByBmi(picks, user: user);
      return _sortByGoal(filtered, user: user);
    }

    // ── Priority 3: Clear + Elderly (age >= 50) ───────────────────────────
    if (isClear && isElderly) {
      final picks = _pickFromCatalogue(
        catalogue,
        preferredIds: [
          'morning_walk',
          'tai_chi',
          'outdoor_yoga',
          'stretching',
          'light_stretching',
        ],
        fallbackTags: ['low-impact', 'elderly', 'recovery', 'mindfulness'],
        maxResults: maxResults,
      );
      final filtered = _filterByBmi(picks, user: user);
      return _sortByGoal(filtered, user: user);
    }

    // ── Priority 4a: Clear + Young + Normal/Athletic BMI ──────────────────
    if (isClear && !isElderly && !isOverweight) {
      final picks = _pickFromCatalogue(
        catalogue,
        preferredIds: [
          'outdoor_run',
          'hiit_park',
          'outdoor_cycling',
          'outdoor_yoga',
          'swimming',
        ],
        fallbackTags: ['cardio', 'endurance', 'hiit', 'strength'],
        maxResults: maxResults,
      );
      final filtered = _filterByBmi(picks, user: user);
      return _sortByGoal(filtered, user: user);
    }

    // ── Priority 4b: Clear + Young + Overweight/Obese ─────────────────────
    if (isClear && !isElderly && isOverweight) {
      final picks = _pickFromCatalogue(
        catalogue,
        preferredIds: [
          'morning_walk',
          'outdoor_yoga',
          'swimming',
          'stretching',
          'outdoor_cycling',
        ],
        fallbackTags: ['low-impact', 'cardio', 'recovery'],
        maxResults: maxResults,
      );
      final filtered = _filterByBmi(picks, user: user);
      return _sortByGoal(filtered, user: user);
    }

    // ── Default: scored fallback ───────────────────────────────────────────
    return _scoredFallback(
      catalogue: catalogue,
      weather: weather,
      user: user,
      maxResults: maxResults,
    );
  }

  /// Returns a human-readable weather summary used in the UI headline.
  String buildWeatherSummary(WeatherModel weather) {
    final temp = weather.tempDisplay;
    final desc = _capitalise(weather.weatherDescription);
    final city = weather.cityName;

    switch (weather.category) {
      case WeatherCategory.clear:
        return '$desc in $city ($temp) — great day for outdoor training!';
      case WeatherCategory.cloudy:
        return '$desc in $city ($temp) — decent conditions for exercise.';
      case WeatherCategory.rain:
        return '$desc in $city ($temp) — take it indoors today.';
      case WeatherCategory.snow:
        return '$desc in $city ($temp) — cold outside, train indoors.';
      case WeatherCategory.thunderstorm:
        return 'Thunderstorm in $city ($temp) — stay safe indoors.';
      case WeatherCategory.atmosphere:
        return '$desc in $city ($temp) — limited visibility, train indoors.';
    }
  }

  // ── Private: BMI-based activity filter ───────────────────────────────────
  //
  // Removes activities that are unsafe or inappropriate for the user's
  // current BMI category BEFORE goal-based re-ranking.
  //
  // BMI Categories (WHO):
  //   < 18.5  → Underweight  : avoid intense cardio, prefer moderate + strength
  //   18.5–24.9 → Normal     : no restrictions
  //   25–29.9 → Overweight   : remove intense activities
  //   ≥ 30    → Obese        : remove intense activities, prefer low-impact only

  List<ActivityModel> _filterByBmi(
    List<ActivityModel> pool, {
    UserModel? user,
  }) {
    if (user == null) return pool;

    final bmi = user.bmi;
    if (bmi <= 0) return pool;

    // Obese (BMI >= 30) — only light/moderate activities allowed
    if (bmi >= 30) {
      final filtered = pool
          .where((a) => a.difficulty != ActivityDifficulty.intense)
          .toList();
      // Guarantee at least 1 result even if all picks were intense
      return filtered.isNotEmpty ? filtered : pool;
    }

    // Overweight (BMI 25–29.9) — remove intense activities
    if (bmi >= 25) {
      final filtered = pool
          .where((a) => a.difficulty != ActivityDifficulty.intense)
          .toList();
      return filtered.isNotEmpty ? filtered : pool;
    }

    // Underweight (BMI < 18.5) — avoid intense cardio, keep strength/moderate
    if (bmi < 18.5) {
      final filtered = pool.where((a) {
        // Allow strength activities even if intense
        if (a.tags.contains('strength') || a.tags.contains('bodyweight')) {
          return true;
        }
        // Block intense cardio for underweight users
        if (a.difficulty == ActivityDifficulty.intense &&
            a.tags.contains('cardio')) {
          return false;
        }
        return true;
      }).toList();
      return filtered.isNotEmpty ? filtered : pool;
    }

    // Normal BMI (18.5–24.9) — no restrictions
    return pool;
  }

  // ── Private: pick by preferred IDs first, then fallback tags ─────────────

  List<ActivityModel> _pickFromCatalogue(
    List<ActivityModel> catalogue, {
    required List<String> preferredIds,
    required List<String> fallbackTags,
    required int maxResults,
  }) {
    final result = <ActivityModel>[];

    for (final id in preferredIds) {
      if (result.length >= maxResults) break;
      final match = catalogue.where((a) => a.id == id).firstOrNull;
      if (match != null && !result.contains(match)) result.add(match);
    }

    if (result.length < maxResults) {
      final fallbacks = catalogue.where(
        (a) =>
            !result.contains(a) &&
            a.tags.any((t) => fallbackTags.contains(t)),
      );
      for (final a in fallbacks) {
        if (result.length >= maxResults) break;
        result.add(a);
      }
    }

    if (result.length < maxResults) {
      final remaining = catalogue.where((a) => !result.contains(a));
      for (final a in remaining) {
        if (result.length >= maxResults) break;
        result.add(a);
      }
    }

    return result;
  }

  // ── Private: sort by fitness goal ────────────────────────────────────────
  //
  // Two-tier scoring system:
  //   Tier A (+10 bonus)  — activity.primaryGoal exactly matches user goal
  //   Tier B (0–7 pts)    — tag/difficulty signals per goal

  List<ActivityModel> _sortByGoal(
    List<ActivityModel> pool, {
    UserModel? user,
  }) {
    final goal = user?.fitnessGoal;
    if (goal == null) return pool;

    int score(ActivityModel a) {
      int s = 0;

      // ── Tier A: primaryGoal exact match bonus ─────────────────────────
      if (a.primaryGoal == goal) s += 10;

      // ── Tier B: tag / difficulty signals ─────────────────────────────
      switch (goal) {
        case 'Weight Loss':
          if (a.tags.contains('cardio')) s += 3;
          if (a.tags.contains('hiit')) s += 2;
          if (a.tags.contains('full-body')) s += 1;
          break;

        case 'Muscle Gain':
          if (a.tags.contains('strength')) s += 3;
          if (a.tags.contains('bodyweight')) s += 2;
          if (a.difficulty == ActivityDifficulty.moderate ||
              a.difficulty == ActivityDifficulty.intense) s += 1;
          break;

        case 'Endurance':
          if (a.tags.contains('endurance')) s += 3;
          if (a.tags.contains('cardio')) s += 2;
          if (a.durationMinutes >= 40) s += 2;
          break;

        case 'Flexibility':
          if (a.tags.contains('flexibility')) s += 3;
          if (a.tags.contains('mindfulness')) s += 2;
          if (a.tags.contains('recovery')) s += 1;
          break;

        case 'General Fitness':
        default:
          if (a.difficulty == ActivityDifficulty.moderate) s += 2;
          if (a.tags.length >= 2) s += 1;
          break;
      }

      return s;
    }

    return List<ActivityModel>.from(pool)
      ..sort((a, b) => score(b).compareTo(score(a)));
  }

  // ── Private: scored fallback ──────────────────────────────────────────────

  List<ActivityModel> _scoredFallback({
    required List<ActivityModel> catalogue,
    required WeatherModel weather,
    UserModel? user,
    required int maxResults,
  }) {
    final suitable = catalogue.where((a) => a.suitableFor(weather)).toList();

    // Apply BMI filter before scoring
    final bmiFiltered = _filterByBmi(suitable, user: user);

    final scored = bmiFiltered.map((activity) {
      int score = 0;

      if (weather.category == WeatherCategory.clear &&
          activity.location == ActivityLocation.outdoor) score += 20;

      if ((weather.category == WeatherCategory.rain ||
              weather.category == WeatherCategory.snow ||
              weather.category == WeatherCategory.thunderstorm) &&
          activity.location == ActivityLocation.indoor) score += 20;

      if (weather.temperatureCelsius > 32 &&
          activity.location == ActivityLocation.outdoor &&
          activity.difficulty == ActivityDifficulty.intense) score -= 15;

      if (weather.windSpeedMps > 12 &&
          activity.location == ActivityLocation.outdoor) score -= 10;

      if ((weather.temperatureCelsius < 5 ||
              weather.temperatureCelsius > 35) &&
          activity.tags.contains('recovery')) score += 10;

      // Goal-based tag scoring
      if (user?.fitnessGoal != null) {
        final goal = user!.fitnessGoal!;

        // Tier A: primaryGoal exact match
        if (activity.primaryGoal == goal) score += 10;

        // Tier B: tag signals per goal
        switch (goal) {
          case 'Weight Loss':
            if (activity.tags.contains('cardio')) score += 5;
            if (activity.tags.contains('hiit')) score += 5;
            if (activity.tags.contains('full-body')) score += 3;
            break;
          case 'Muscle Gain':
            if (activity.tags.contains('strength')) score += 5;
            if (activity.tags.contains('bodyweight')) score += 5;
            break;
          case 'Endurance':
            if (activity.tags.contains('endurance')) score += 5;
            if (activity.tags.contains('cardio')) score += 3;
            if (activity.durationMinutes >= 40) score += 3;
            break;
          case 'Flexibility':
            if (activity.tags.contains('flexibility')) score += 5;
            if (activity.tags.contains('recovery')) score += 3;
            break;
          case 'General Fitness':
          default:
            if (activity.difficulty == ActivityDifficulty.moderate) score += 3;
            break;
        }
      }

      // Duration as a tiebreaker
      score += (activity.durationMinutes / 10).round();

      return _ScoredActivity(activity: activity, score: score);
    }).toList();

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(maxResults).map((s) => s.activity).toList();
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<WeatherModel> _enrichWithUv(
    WeatherModel weather, {
    required double lat,
    required double lon,
  }) async {
    try {
      final uvData = await _api.fetchUvIndex(lat: lat, lon: lon);
      final current = uvData['current'] as Map<String, dynamic>?;
      final uvi =
          current != null ? (current['uvi'] as num?)?.toDouble() : null;
      return weather.copyWith(uvIndex: uvi);
    } catch (_) {
      return weather;
    }
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ── Private helper class ──────────────────────────────────────────────────────

class _ScoredActivity {
  final ActivityModel activity;
  final int score;
  const _ScoredActivity({required this.activity, required this.score});
}