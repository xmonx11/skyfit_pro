/// Represents current weather data returned by OpenWeatherMap.
class WeatherModel {
  final String cityName;
  final String country;
  final double temperatureCelsius;
  final double feelsLikeCelsius;
  final double humidity;
  final double windSpeedMps;
  final int weatherConditionCode;
  final String weatherMain;
  final String weatherDescription;
  final String weatherIconCode;
  final double? uvIndex;
  final int? visibility; // metres
  final DateTime fetchedAt;

  const WeatherModel({
    required this.cityName,
    required this.country,
    required this.temperatureCelsius,
    required this.feelsLikeCelsius,
    required this.humidity,
    required this.windSpeedMps,
    required this.weatherConditionCode,
    required this.weatherMain,
    required this.weatherDescription,
    required this.weatherIconCode,
    this.uvIndex,
    this.visibility,
    required this.fetchedAt,
  });

  // ── Factory constructors ─────────────────────────────────────────────────

  factory WeatherModel.fromJson(Map<String, dynamic> json) {
    final main = json['main'] as Map<String, dynamic>;
    final wind = json['wind'] as Map<String, dynamic>;
    final weatherList = json['weather'] as List<dynamic>;
    final weather = weatherList.first as Map<String, dynamic>;
    final sys = json['sys'] as Map<String, dynamic>;

    return WeatherModel(
      cityName: json['name'] as String,
      country: sys['country'] as String,
      temperatureCelsius: (main['temp'] as num).toDouble(),
      feelsLikeCelsius: (main['feels_like'] as num).toDouble(),
      humidity: (main['humidity'] as num).toDouble(),
      windSpeedMps: (wind['speed'] as num).toDouble(),
      weatherConditionCode: (weather['id'] as num).toInt(),
      weatherMain: weather['main'] as String,
      weatherDescription: weather['description'] as String,
      weatherIconCode: weather['icon'] as String,
      visibility: json['visibility'] as int?,
      fetchedAt: DateTime.now(),
    );
  }

  // ── Computed helpers ─────────────────────────────────────────────────────

  /// Icon URL for direct use in Image.network.
  String get iconUrl =>
      'https://openweathermap.org/img/wn/$weatherIconCode@2x.png';

  /// Converts wind speed from m/s to km/h.
  double get windSpeedKmh => windSpeedMps * 3.6;

  /// Human-readable temperature string.
  String get tempDisplay => '${temperatureCelsius.round()}°C';

  /// Broad weather category used for activity suggestions.
  WeatherCategory get category {
    // Thunderstorm
    if (weatherConditionCode >= 200 && weatherConditionCode < 300) {
      return WeatherCategory.thunderstorm;
    }
    // Drizzle / Rain
    if (weatherConditionCode >= 300 && weatherConditionCode < 600) {
      return WeatherCategory.rain;
    }
    // Snow / Sleet
    if (weatherConditionCode >= 600 && weatherConditionCode < 700) {
      return WeatherCategory.snow;
    }
    // Atmosphere (fog, haze, smoke)
    if (weatherConditionCode >= 700 && weatherConditionCode < 800) {
      return WeatherCategory.atmosphere;
    }
    // Clear
    if (weatherConditionCode == 800) {
      return WeatherCategory.clear;
    }
    // Clouds
    return WeatherCategory.cloudy;
  }

  /// Whether conditions are safe for outdoor exercise.
  bool get isSafeForOutdoor =>
      (category == WeatherCategory.clear ||
          category == WeatherCategory.cloudy) &&
      temperatureCelsius > 5 &&
      temperatureCelsius < 38 &&
      windSpeedMps < 15;

  /// Extreme heat threshold for safety recommendations.
  bool get isExtremeHeat => temperatureCelsius >= 35;

  /// Extreme cold threshold for safety recommendations.
  bool get isExtremeCold => temperatureCelsius <= 5;

  Map<String, dynamic> toMap() {
    return {
      'cityName': cityName,
      'country': country,
      'temperatureCelsius': temperatureCelsius,
      'feelsLikeCelsius': feelsLikeCelsius,
      'humidity': humidity,
      'windSpeedMps': windSpeedMps,
      'weatherConditionCode': weatherConditionCode,
      'weatherMain': weatherMain,
      'weatherDescription': weatherDescription,
      'weatherIconCode': weatherIconCode,
      'uvIndex': uvIndex,
      'visibility': visibility,
      'fetchedAt': fetchedAt.toIso8601String(),
    };
  }

  WeatherModel copyWith({double? uvIndex}) {
    return WeatherModel(
      cityName: cityName,
      country: country,
      temperatureCelsius: temperatureCelsius,
      feelsLikeCelsius: feelsLikeCelsius,
      humidity: humidity,
      windSpeedMps: windSpeedMps,
      weatherConditionCode: weatherConditionCode,
      weatherMain: weatherMain,
      weatherDescription: weatherDescription,
      weatherIconCode: weatherIconCode,
      uvIndex: uvIndex ?? this.uvIndex,
      visibility: visibility,
      fetchedAt: fetchedAt,
    );
  }

  @override
  String toString() =>
      'WeatherModel($cityName, $country, ${tempDisplay}, $weatherDescription)';
}

/// Broad categorisation of weather for activity recommendation logic.
enum WeatherCategory {
  clear,
  cloudy,
  rain,
  snow,
  thunderstorm,
  atmosphere,
}