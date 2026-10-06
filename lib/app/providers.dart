import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart' show TileProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_data.dart';
import '../data/services/conditions_provider.dart';
import '../data/services/location_service.dart';
import '../data/services/place_service.dart';
import '../data/sync/sync_service.dart';
import '../domain/catalog/gear_catalog.dart';
import '../domain/insights/insights_engine.dart';
import '../domain/models/catch_entry.dart';
import '../domain/models/catch_photo.dart';
import '../domain/models/conditions.dart';
import '../domain/models/trip.dart';

/// Overridden in `main()` with the opened local database.
final appDataProvider = Provider<AppData>((ref) {
  throw UnimplementedError('appDataProvider must be overridden with an opened AppData');
});

// ---- Services (swappable in tests) ----

final locationServiceProvider = Provider<LocationService>((ref) => const GeolocatorLocationService());

final placeServiceProvider = Provider<PlaceService>((ref) => OsmPlaceService());

final conditionsProviderProvider = Provider<ConditionsProvider>((ref) => OpenMeteoConditionsProvider());

/// How map tiles are fetched. Null means flutter_map's default (network + on-device cache).
/// Override to point at a different provider, add offline tile packs, or — in tests — avoid
/// the network and the cache's platform channel.
final tileProviderOverrideProvider = Provider<TileProvider?>((ref) => null);

/// Nothing leaves the device until a real gateway (Firebase) is plugged in here.
final syncGatewayProvider = Provider<SyncGateway>((ref) => const NoopSyncGateway());

// ---- Data ----

final catchesProvider = StreamProvider<List<CatchEntry>>(
  (ref) => ref.watch(appDataProvider).catches.watchAll(),
);

final catchProvider = StreamProvider.family<CatchEntry?, String>(
  (ref, id) => ref.watch(appDataProvider).catches.watch(id),
);

final tripsProvider = StreamProvider<List<Trip>>(
  (ref) => ref.watch(appDataProvider).trips.watchAll(),
);

final tripProvider = StreamProvider.family<Trip?, String>(
  (ref, id) => ref.watch(appDataProvider).trips.watch(id),
);

final activeTripProvider = Provider<Trip?>((ref) {
  final trips = ref.watch(tripsProvider).value ?? const <Trip>[];
  for (final t in trips) {
    if (t.isActive) return t;
  }
  return null;
});

final catchesForTripProvider = Provider.family<List<CatchEntry>, String>((ref, tripId) {
  final all = ref.watch(catchesProvider).value ?? const <CatchEntry>[];
  return [for (final c in all) if (c.tripId == tripId) c];
});

// ---- Photos ----

final photosProvider = StreamProvider<List<CatchPhoto>>(
  (ref) => ref.watch(appDataProvider).photos.watchAll(),
);

/// The first photo of each catch, by catch id. One metadata query feeds every list row.
final primaryPhotoByCatchProvider = Provider<Map<String, CatchPhoto>>((ref) {
  final photos = ref.watch(photosProvider).value ?? const <CatchPhoto>[];
  final result = <String, CatchPhoto>{};
  for (final p in photos) {
    final existing = result[p.catchId];
    if (existing == null || p.sortIndex < existing.sortIndex) result[p.catchId] = p;
  }
  return result;
});

class PhotoRequest {
  const PhotoRequest(this.photoId, {this.thumbnail = true});

  final String photoId;
  final bool thumbnail;

  @override
  bool operator ==(Object other) =>
      other is PhotoRequest && other.photoId == photoId && other.thumbnail == thumbnail;

  @override
  int get hashCode => Object.hash(photoId, thumbnail);
}

/// Bytes for one photo, read lazily from the blob store. Thumbnails are kept briefly after
/// the last listener leaves so scrolling a list doesn't re-read them; full images are not.
final photoBytesProvider = FutureProvider.autoDispose.family<Uint8List?, PhotoRequest>((ref, request) async {
  if (request.thumbnail) {
    final link = ref.keepAlive();
    final timer = Timer(const Duration(minutes: 2), link.close);
    ref.onDispose(timer.cancel);
  }
  final photos = ref.watch(appDataProvider).photos;
  return request.thumbnail ? photos.thumbBytes(request.photoId) : photos.fullBytes(request.photoId);
});

// ---- Derived ----

/// Computed from *all* catches, never a filtered view — filtering out the true heaviest fish
/// must never promote a lighter one to trophy status.
final personalBestIdsProvider = Provider<Set<String>>((ref) {
  final all = ref.watch(catchesProvider).value ?? const <CatchEntry>[];
  return {for (final b in InsightsEngine.personalBests(all.map(CatchSummary.fromEntry))) b.entryId};
});

final insightsReportProvider = Provider<InsightsReport>((ref) {
  final all = ref.watch(catchesProvider).value ?? const <CatchEntry>[];
  return InsightsEngine.compute(all.map(CatchSummary.fromEntry).toList());
});

/// The angler's own past entries for a gear field, ranked by frequency and recency — the
/// "locker" without a gear entity (which would duplicate across offline devices).
final gearSuggestionsProvider = Provider.family<List<String>, GearField>((ref, field) {
  final all = ref.watch(catchesProvider).value ?? const <CatchEntry>[]; // newest first
  return rankGearSuggestions([
    for (final e in all)
      switch (field) {
        GearField.rodReel => e.gear.rodReel,
        GearField.baitLure => e.gear.baitLure,
        GearField.lineType => e.gear.lineType,
        GearField.technique => e.gear.technique,
      },
  ]);
});

/// [valuesNewestFirst] may contain nulls (catches with no value for the field).
List<String> rankGearSuggestions(List<String?> valuesNewestFirst, {int limit = 5}) {
  final frequency = <String, int>{};
  final recencyRank = <String, int>{};
  final displayName = <String, String>{};
  var rank = 0;
  for (final raw in valuesNewestFirst) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) continue;
    final key = value.toLowerCase();
    frequency.update(key, (c) => c + 1, ifAbsent: () => 1);
    recencyRank.putIfAbsent(key, () => rank);
    displayName.putIfAbsent(key, () => value);
    rank++;
  }
  double score(String k) => frequency[k]! - recencyRank[k]! * 0.01;
  final keys = frequency.keys.toList()..sort((a, b) => score(b).compareTo(score(a)));
  return [for (final k in keys.take(limit)) displayName[k]!];
}

// ---- Location & conditions (Home) ----

enum LocationStatus { idle, locating, ready, needsPermission, blocked, servicesOff, failed }

class LocationState {
  const LocationState({this.status = LocationStatus.idle, this.fix, this.isStale = false});

  final LocationStatus status;
  final LocationFix? fix;

  /// True while showing the remembered position and a fresh fix hasn't arrived yet.
  final bool isStale;

  LocationState copyWith({LocationStatus? status, LocationFix? fix, bool? isStale}) => LocationState(
        status: status ?? this.status,
        fix: fix ?? this.fix,
        isStale: isStale ?? this.isStale,
      );
}

/// Owns "where is the angler" for Home. Shows the last remembered position instantly (so
/// solunar windows render offline and without waiting on GPS), and only auto-requests a
/// fresh fix when permission is *already* granted — it never throws a permission prompt at
/// someone who just opened the app; that is an explicit tap.
class LocationController extends Notifier<LocationState> {
  @override
  LocationState build() {
    Future.microtask(_init);
    return const LocationState();
  }

  Future<void> _init() async {
    final last = await ref.read(appDataProvider).settings.lastLocation();
    if (last != null) {
      state = LocationState(
        status: LocationStatus.ready,
        fix: LocationFix(last.latitude, last.longitude),
        isStale: true,
      );
    }
    final access = await ref.read(locationServiceProvider).access();
    switch (access) {
      case LocationAccess.granted:
        await refresh();
      case LocationAccess.askable:
        if (state.fix == null) state = const LocationState(status: LocationStatus.needsPermission);
      case LocationAccess.blocked:
        if (state.fix == null) state = const LocationState(status: LocationStatus.blocked);
      case LocationAccess.servicesOff:
        if (state.fix == null) state = const LocationState(status: LocationStatus.servicesOff);
    }
  }

  /// Requests permission if needed. Call from a user gesture.
  Future<void> refresh() async {
    final previous = state.fix;
    state = state.copyWith(status: LocationStatus.locating);
    try {
      final fix = await ref.read(locationServiceProvider).currentLocation();
      await ref.read(appDataProvider).settings.saveLastLocation(fix.latitude, fix.longitude);
      state = LocationState(status: LocationStatus.ready, fix: fix);
    } on LocationException {
      final access = await ref.read(locationServiceProvider).access();
      state = LocationState(
        status: switch (access) {
          LocationAccess.blocked => LocationStatus.blocked,
          LocationAccess.servicesOff => LocationStatus.servicesOff,
          _ => previous == null ? LocationStatus.failed : LocationStatus.ready,
        },
        fix: previous,
        isStale: previous != null,
      );
    }
  }
}

final locationControllerProvider = NotifierProvider<LocationController, LocationState>(LocationController.new);

/// Live conditions for Home. Re-fetches when the position changes; null when unavailable
/// (offline, no provider) — which is a normal state, not an error.
final homeConditionsProvider = FutureProvider.autoDispose<Conditions?>((ref) async {
  final fix = ref.watch(locationControllerProvider.select((s) => s.fix));
  if (fix == null) return null;
  try {
    return await ref.watch(conditionsProviderProvider).currentConditions(
          latitude: fix.latitude,
          longitude: fix.longitude,
          date: DateTime.now(),
        );
  } catch (_) {
    return null;
  }
});
