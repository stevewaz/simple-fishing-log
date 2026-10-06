import 'package:sembast/sembast.dart';

/// Tiny key/value store for app state that isn't a catch, trip or photo. Not synced.
class SettingsRepository {
  SettingsRepository(this._db) : _store = StoreRef<String, Object?>('settings');

  final Database _db;
  final StoreRef<String, Object?> _store;

  static const _lastLocation = 'lastLocation';
  static const _lastPulledAt = 'syncLastPulledAt';

  /// The last place the app learned the angler was — lets Home show solunar times
  /// immediately (and offline) instead of waiting on a fresh GPS fix. Replaces the Swift
  /// app's App Group hand-off to its widget.
  Future<({double latitude, double longitude, DateTime at})?> lastLocation() async {
    final v = await _store.record(_lastLocation).get(_db);
    if (v is! Map) return null;
    final lat = v['lat'];
    final lon = v['lon'];
    final at = DateTime.tryParse('${v['at']}');
    if (lat is! num || lon is! num || at == null) return null;
    return (latitude: lat.toDouble(), longitude: lon.toDouble(), at: at.toUtc());
  }

  Future<void> saveLastLocation(double latitude, double longitude, {DateTime? at}) =>
      _store.record(_lastLocation).put(_db, {
        'lat': latitude,
        'lon': longitude,
        'at': (at ?? DateTime.now()).toUtc().toIso8601String(),
      });

  Future<DateTime?> syncLastPulledAt(String collection) async {
    final v = await _store.record('$_lastPulledAt:$collection').get(_db);
    return v is String ? DateTime.tryParse(v)?.toUtc() : null;
  }

  Future<void> saveSyncLastPulledAt(String collection, DateTime at) =>
      _store.record('$_lastPulledAt:$collection').put(_db, at.toUtc().toIso8601String());
}
