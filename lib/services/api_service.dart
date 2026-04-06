import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../utils/env_config.dart';

/// Thin HTTP wrapper around OpenWeatherMap REST API.
/// This class knows NOTHING about business logic — it only performs HTTP calls
/// and returns raw decoded JSON.  All domain decisions live in repositories.
class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const String _baseUrl = 'https://api.openweathermap.org/data/2.5';
  static const Duration _timeout = Duration(seconds: 10);

  // ── Current Weather ──────────────────────────────────────────────────────

  /// Fetches current weather by city name.
  /// Returns raw JSON map on success; throws [ApiException] on failure.
  Future<Map<String, dynamic>> fetchCurrentWeatherByCity(
      String cityName) async {
    final uri = Uri.parse('$_baseUrl/weather').replace(queryParameters: {
      'q': cityName,
      'appid': EnvConfig.openWeatherApiKey,
      'units': 'metric',
    });

    return _get(uri);
  }

  /// Fetches current weather by geographic coordinates.
  Future<Map<String, dynamic>> fetchCurrentWeatherByCoords({
    required double lat,
    required double lon,
  }) async {
    final uri = Uri.parse('$_baseUrl/weather').replace(queryParameters: {
      'lat': lat.toString(),
      'lon': lon.toString(),
      'appid': EnvConfig.openWeatherApiKey,
      'units': 'metric',
    });

    return _get(uri);
  }

  // ── UV Index ─────────────────────────────────────────────────────────────

  /// Fetches the current UV index for coordinates.
  /// Part of the One Call API — uses a separate endpoint.
  Future<Map<String, dynamic>> fetchUvIndex({
    required double lat,
    required double lon,
  }) async {
    final uri =
        Uri.parse('https://api.openweathermap.org/data/3.0/onecall')
            .replace(queryParameters: {
      'lat': lat.toString(),
      'lon': lon.toString(),
      'appid': EnvConfig.openWeatherApiKey,
      'exclude': 'minutely,hourly,daily,alerts',
      'units': 'metric',
    });

    return _get(uri);
  }

  // ── 5-Day Forecast ───────────────────────────────────────────────────────

  /// Fetches a 5-day / 3-hour forecast by city name.
  Future<Map<String, dynamic>> fetchForecastByCity(String cityName) async {
    final uri =
        Uri.parse('$_baseUrl/forecast').replace(queryParameters: {
      'q': cityName,
      'appid': EnvConfig.openWeatherApiKey,
      'units': 'metric',
    });

    return _get(uri);
  }

  // ── Geocoding ────────────────────────────────────────────────────────────

  /// Resolves a city name to lat/lon coordinates using OWM's Geocoding API.
  Future<List<dynamic>> geocodeCity(String cityName) async {
    final uri =
        Uri.parse('https://api.openweathermap.org/geo/1.0/direct')
            .replace(queryParameters: {
      'q': cityName,
      'limit': '5',
      'appid': EnvConfig.openWeatherApiKey,
    });

    final raw = await _getList(uri);
    return raw;
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(Uri uri) async {
    try {
      final response = await _client.get(uri).timeout(_timeout);
      _validateStatus(response);
      return json.decode(response.body) as Map<String, dynamic>;
    } on SocketException {
      throw ApiException(
          message: 'No internet connection.', statusCode: null);
    } on HttpException {
      throw ApiException(
          message: 'HTTP error occurred.', statusCode: null);
    } on FormatException {
      throw ApiException(
          message: 'Invalid response format.', statusCode: null);
    }
  }

  Future<List<dynamic>> _getList(Uri uri) async {
    try {
      final response = await _client.get(uri).timeout(_timeout);
      _validateStatus(response);
      return json.decode(response.body) as List<dynamic>;
    } on SocketException {
      throw ApiException(
          message: 'No internet connection.', statusCode: null);
    } on HttpException {
      throw ApiException(
          message: 'HTTP error occurred.', statusCode: null);
    } on FormatException {
      throw ApiException(
          message: 'Invalid response format.', statusCode: null);
    }
  }

  void _validateStatus(http.Response response) {
    if (response.statusCode == 200 || response.statusCode == 201) return;

    String message;
    switch (response.statusCode) {
      case 401:
        message = 'Invalid API key.';
        break;
      case 404:
        message = 'Location not found.';
        break;
      case 429:
        message = 'API rate limit exceeded. Please try again later.';
        break;
      case 500:
      case 502:
      case 503:
        message = 'Weather service is unavailable. Please try again.';
        break;
      default:
        message = 'Unexpected error (${response.statusCode}).';
    }

    throw ApiException(message: message, statusCode: response.statusCode);
  }

  void dispose() => _client.close();
}

// ── Exception type ───────────────────────────────────────────────────────────

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException({required this.message, required this.statusCode});

  @override
  String toString() => 'ApiException($statusCode): $message';
}