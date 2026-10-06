import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/conditions.dart';

/// Abstraction over "where auto-captured conditions come from" so the rest of the app never
/// depends on one weather vendor. A missing or unreachable provider must never block saving:
/// callers treat a null/thrown result as normal.
abstract interface class ConditionsProvider {
  /// Current conditions at a place, or null when unavailable for [date].
  Future<Conditions?> currentConditions({
    required double latitude,
    required double longitude,
    required DateTime date,
  });
}

/// Always available, always returns null.
class NullConditionsProvider implements ConditionsProvider {
  const NullConditionsProvider();

  @override
  Future<Conditions?> currentConditions({
    required double latitude,
    required double longitude,
    required DateTime date,
  }) async =>
      null;
}

/// Open-Meteo (https://open-meteo.com): free for non-commercial use, no API key, CORS-enabled
/// (so it works from the web build). This replaces Apple's WeatherKit, which needs a paid
/// Apple Developer entitlement and exists on Apple platforms only.
///
/// Open-Meteo's terms require a commercial plan for commercial use — see the README before
/// shipping a paid app on this.
///
/// Like the WeatherKit original, only *live* conditions are fetched: never for a backdated
/// entry, where "current" would be the wrong weather.
class OpenMeteoConditionsProvider implements ConditionsProvider {
  OpenMeteoConditionsProvider({http.Client? client, this.timeout = const Duration(seconds: 10)})
      : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  static const maxAge = Duration(hours: 24);

  @override
  Future<Conditions?> currentConditions({
    required double latitude,
    required double longitude,
    required DateTime date,
  }) async {
    if (DateTime.now().difference(date).abs() >= maxAge) return null;

    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitude.toStringAsFixed(4),
      'longitude': longitude.toStringAsFixed(4),
      'current': 'temperature_2m,wind_speed_10m,wind_direction_10m,pressure_msl,cloud_cover,weather_code',
      // Three hours back, for the pressure trend.
      'hourly': 'pressure_msl',
      'past_hours': '3',
      'forecast_hours': '1',
      'wind_speed_unit': 'ms',
      'timezone': 'UTC',
    });

    final response = await _client.get(uri).timeout(timeout);
    if (response.statusCode != 200) return null;
    final json = jsonDecode(response.body);
    if (json is! Map) return null;
    return parse(json.cast<String, Object?>());
  }

  /// Exposed for tests; maps an Open-Meteo response to [Conditions].
  static Conditions? parse(Map<String, Object?> json) {
    final current = json['current'];
    if (current is! Map) return null;

    double? number(Object? v) => v is num ? v.toDouble() : null;

    final cloud = number(current['cloud_cover']);
    return Conditions(
      source: ConditionsSource.openMeteo,
      capturedAt: DateTime.now().toUtc(),
      airTempC: number(current['temperature_2m']),
      windSpeedMS: number(current['wind_speed_10m']),
      windDirectionDegrees: number(current['wind_direction_10m']),
      pressureHPa: number(current['pressure_msl']),
      pressureTrend: _pressureTrend(json['hourly']),
      weatherCondition: describeWeatherCode(current['weather_code']),
      cloudCover: cloud == null ? null : (cloud / 100).clamp(0.0, 1.0),
    );
  }

  /// Compares the oldest and newest pressure in the window. A 1 hPa/3 h band counts as
  /// steady, which is the conventional meteorological threshold for a "slow" change.
  static String? _pressureTrend(Object? hourly) {
    if (hourly is! Map) return null;
    final series = hourly['pressure_msl'];
    if (series is! List) return null;
    final values = series.whereType<num>().map((n) => n.toDouble()).toList();
    if (values.length < 2) return null;
    final delta = values.last - values.first;
    if (delta > 1.0) return 'rising';
    if (delta < -1.0) return 'falling';
    return 'steady';
  }

  /// WMO weather interpretation codes → short plain-English labels.
  static String? describeWeatherCode(Object? code) {
    if (code is! num) return null;
    return switch (code.toInt()) {
      0 => 'Clear sky',
      1 => 'Mainly clear',
      2 => 'Partly cloudy',
      3 => 'Overcast',
      45 || 48 => 'Fog',
      51 || 53 || 55 => 'Drizzle',
      56 || 57 => 'Freezing drizzle',
      61 => 'Light rain',
      63 => 'Rain',
      65 => 'Heavy rain',
      66 || 67 => 'Freezing rain',
      71 || 73 || 75 => 'Snow',
      77 => 'Snow grains',
      80 || 81 || 82 => 'Rain showers',
      85 || 86 => 'Snow showers',
      95 => 'Thunderstorm',
      96 || 99 => 'Thunderstorm with hail',
      _ => null,
    };
  }
}
