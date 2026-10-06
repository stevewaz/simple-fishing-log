import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../../domain/geo.dart' as geo;

/// Turns coordinates into names an angler would recognise. Both lookups are best-effort and
/// online-only; offline they simply return nothing and the form stays fully usable.
abstract interface class PlaceService {
  /// "Port Clinton, Ohio" — a locality to prefill the free-text location name.
  Future<String?> locality(double latitude, double longitude);

  /// Named lakes/rivers/ponds within a few km, nearest first.
  Future<List<String>> nearbyWaters(double latitude, double longitude);
}

class NullPlaceService implements PlaceService {
  const NullPlaceService();

  @override
  Future<String?> locality(double latitude, double longitude) async => null;

  @override
  Future<List<String>> nearbyWaters(double latitude, double longitude) async => const [];
}

/// OpenStreetMap services — free and key-less, replacing Apple's CLGeocoder and MKLocalSearch:
///
///  * Nominatim for the locality (https://operations.osmfoundation.org/policies/nominatim/ —
///    max 1 request/second, identify the app; we only call it on an explicit tap);
///  * Overpass for named water features around the point.
///
/// Reverse geocoding alone often names the wrong water feature near shore (a bay instead of
/// the lake it is part of), so water bodies are offered as *suggestions*, restricted to a
/// small radius and sorted by distance — a same-named feature far away must never win.
class OsmPlaceService implements PlaceService {
  OsmPlaceService({
    http.Client? client,
    this.timeout = const Duration(seconds: 12),
    this.searchRadiusMeters = 8000,
    // Nominatim's policy asks for an identifying User-Agent with contact details; set one
    // before shipping (see README → "Before you ship").
    this.userAgent = 'SimpleFishingLog/1.0 (local-first fishing journal)',
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;
  final int searchRadiusMeters;
  final String userAgent;

  // Browsers forbid setting User-Agent and send their own; native clients should identify
  // themselves, and Overpass rejects the default Dart one.
  Map<String, String> get _headers => kIsWeb ? const {} : {'User-Agent': userAgent};

  @override
  Future<String?> locality(double latitude, double longitude) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'jsonv2',
      'lat': latitude.toStringAsFixed(5),
      'lon': longitude.toStringAsFixed(5),
      'zoom': '12',
      'addressdetails': '1',
    });
    final response = await _client.get(uri, headers: _headers).timeout(timeout);
    if (response.statusCode != 200) return null;
    final json = jsonDecode(response.body);
    if (json is! Map) return null;
    return parseLocality(json.cast<String, Object?>());
  }

  static String? parseLocality(Map<String, Object?> json) {
    final address = json['address'];
    if (address is! Map) return null;
    String? pick(List<String> keys) {
      for (final k in keys) {
        final v = address[k];
        if (v is String && v.isNotEmpty) return v;
      }
      return null;
    }

    final place = pick(['city', 'town', 'village', 'hamlet', 'municipality', 'county']);
    final region = pick(['state', 'province', 'region']);
    final parts = [place, region].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  @override
  Future<List<String>> nearbyWaters(double latitude, double longitude) async {
    final r = searchRadiusMeters;
    final around = '(around:$r,$latitude,$longitude)';
    // Lakes/ponds/reservoirs as areas, rivers/streams/canals as lines. `out center` gives
    // each way a representative point so we can rank by distance.
    final query = '[out:json][timeout:15];('
        'way$around["natural"="water"]["name"];'
        'relation$around["natural"="water"]["name"];'
        'way$around["waterway"~"^(river|stream|canal)\$"]["name"];'
        ');out tags center 60;';
    final uri = Uri.https('overpass-api.de', '/api/interpreter', {'data': query});
    final response = await _client.get(uri, headers: _headers).timeout(timeout);
    if (response.statusCode != 200) return const [];
    final json = jsonDecode(response.body);
    if (json is! Map) return const [];
    return parseWaters(json.cast<String, Object?>(), latitude, longitude, radiusMeters: r.toDouble());
  }

  /// Tags that mean a water-coloured polygon that isn't somewhere you fish (splash pads,
  /// pools, fountains) — Overpass happily returns them under `natural=water`.
  static const _notFishable = {'swimming_pool', 'fountain', 'basin', 'reflecting_pool', 'wastewater'};

  static List<String> parseWaters(
    Map<String, Object?> json,
    double latitude,
    double longitude, {
    double radiusMeters = 8000,
    int limit = 5,
  }) {
    final elements = json['elements'];
    if (elements is! List) return const [];

    final found = <(String name, double distance)>[];
    for (final element in elements) {
      if (element is! Map) continue;
      final tags = element['tags'];
      if (tags is! Map) continue;
      final name = tags['name'];
      if (name is! String || name.isEmpty) continue;
      if (tags.containsKey('leisure') ||
          tags.containsKey('tourism') ||
          tags.containsKey('attraction') ||
          _notFishable.contains(tags['water'])) {
        continue;
      }
      final center = element['center'];
      if (center is! Map || center['lat'] is! num || center['lon'] is! num) continue;
      final distance = geo.haversineMeters(
        latitude,
        longitude,
        (center['lat'] as num).toDouble(),
        (center['lon'] as num).toDouble(),
      );
      if (distance >= radiusMeters) continue;
      found.add((name, distance));
    }

    found.sort((a, b) => a.$2.compareTo(b.$2));
    final seen = <String>{};
    return [
      for (final (name, _) in found)
        if (seen.add(name.toLowerCase())) name,
    ].take(limit).toList();
  }

  static double haversineMeters(double lat1, double lon1, double lat2, double lon2) =>
      geo.haversineMeters(lat1, lon1, lat2, lon2);
}
