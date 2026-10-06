import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:simple_fishing_log/data/blob/blob_store.dart';
import 'package:simple_fishing_log/data/db/document_store.dart';
import 'package:simple_fishing_log/data/services/conditions_provider.dart';
import 'package:simple_fishing_log/data/services/place_service.dart';
import 'package:simple_fishing_log/data/sync/sync_service.dart';
import 'package:simple_fishing_log/domain/models/conditions.dart';

import 'test_support.dart';

/// A recorded Open-Meteo response (from a real call).
const openMeteoSample = {
  'latitude': 41.48978,
  'longitude': -82.69705,
  'current': {
    'time': '2026-10-05T21:30',
    'temperature_2m': 15.3,
    'wind_speed_10m': 3.9,
    'wind_direction_10m': 9,
    'pressure_msl': 1022.2,
    'cloud_cover': 15,
    'weather_code': 0,
  },
  'hourly': {
    'time': ['2026-10-05T18:00', '2026-10-05T19:00', '2026-10-05T20:00', '2026-10-05T21:00'],
    'pressure_msl': [1021.7, 1021.7, 1021.1, 1021.6],
  },
};

void main() {
  group('OpenMeteoConditionsProvider', () {
    test('parses a real response into SI conditions', () {
      final c = OpenMeteoConditionsProvider.parse(openMeteoSample)!;
      expect(c.source, ConditionsSource.openMeteo);
      expect(c.airTempC, 15.3);
      expect(c.windSpeedMS, 3.9);
      expect(c.windDirectionDegrees, 9);
      expect(c.pressureHPa, 1022.2);
      expect(c.cloudCover, closeTo(0.15, 1e-9));
      expect(c.weatherCondition, 'Clear sky');
      expect(c.pressureTrend, 'steady'); // 1021.7 → 1021.6
      expect(c.capturedAt, isNotNull);
    });

    test('pressure trend uses a 1 hPa / 3 h steady band', () {
      String? trend(List<double> series) => OpenMeteoConditionsProvider.parse({
            'current': {'temperature_2m': 10},
            'hourly': {'pressure_msl': series},
          })!.pressureTrend;
      expect(trend([1010, 1011, 1012, 1013]), 'rising');
      expect(trend([1013, 1012, 1011, 1010]), 'falling');
      expect(trend([1010, 1010.5, 1010.2, 1010.8]), 'steady');
      expect(trend([1010]), isNull);
    });

    test('a response without current data yields null', () {
      expect(OpenMeteoConditionsProvider.parse({'error': true}), isNull);
    });

    test('missing fields stay null and do not crash', () {
      final c = OpenMeteoConditionsProvider.parse({'current': {'temperature_2m': 12.0}})!;
      expect(c.airTempC, 12.0);
      expect(c.windSpeedMS, isNull);
      expect(c.cloudCover, isNull);
      expect(c.weatherCondition, isNull);
    });

    test('fetches from the API with the right query and units', () async {
      late Uri requested;
      final client = MockClient((request) async {
        requested = request.url;
        return http.Response(jsonEncode(openMeteoSample), 200);
      });
      final provider = OpenMeteoConditionsProvider(client: client);

      final c = await provider.currentConditions(latitude: 41.5, longitude: -82.7, date: DateTime.now());

      expect(c!.airTempC, 15.3);
      expect(requested.host, 'api.open-meteo.com');
      expect(requested.queryParameters['wind_speed_unit'], 'ms'); // SI, matches storage
      expect(requested.queryParameters['latitude'], '41.5000');
    });

    test('never fetches for a backdated entry', () async {
      var called = false;
      final provider = OpenMeteoConditionsProvider(client: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }));
      final c = await provider.currentConditions(
        latitude: 41.5,
        longitude: -82.7,
        date: DateTime.now().subtract(const Duration(days: 3)),
      );
      expect(c, isNull);
      expect(called, isFalse);
    });

    test('an HTTP error yields null, not an exception', () async {
      final provider = OpenMeteoConditionsProvider(client: MockClient((_) async => http.Response('nope', 500)));
      expect(await provider.currentConditions(latitude: 1, longitude: 1, date: DateTime.now()), isNull);
    });

    test('weather codes map to labels', () {
      expect(OpenMeteoConditionsProvider.describeWeatherCode(2), 'Partly cloudy');
      expect(OpenMeteoConditionsProvider.describeWeatherCode(95), 'Thunderstorm');
      expect(OpenMeteoConditionsProvider.describeWeatherCode(1234), isNull);
      expect(OpenMeteoConditionsProvider.describeWeatherCode('x'), isNull);
    });
  });

  group('OsmPlaceService', () {
    test('locality joins place and region', () {
      expect(
        OsmPlaceService.parseLocality({'address': {'town': 'Port Clinton', 'state': 'Ohio', 'country': 'US'}}),
        'Port Clinton, Ohio',
      );
      expect(OsmPlaceService.parseLocality({'address': {'county': 'Ottawa County', 'state': 'Ohio'}}), 'Ottawa County, Ohio');
      expect(OsmPlaceService.parseLocality({'address': {'country': 'US'}}), isNull);
      expect(OsmPlaceService.parseLocality({}), isNull);
    });

    Map<String, Object?> element(String name, double lat, double lon, [Map<String, Object?> extra = const {}]) => {
          'type': 'way',
          'center': {'lat': lat, 'lon': lon},
          'tags': {'name': name, 'natural': 'water', ...extra},
        };

    test('waters are sorted by distance, deduplicated, and limited', () {
      final json = {
        'elements': [
          element('Far Lake', 41.55, -82.7),
          element('Near Pond', 41.5005, -82.7),
          element('Mid River', 41.52, -82.7),
          element('near pond', 41.501, -82.7), // same name, different case
          element('Another', 41.53, -82.7),
          element('Another 2', 41.531, -82.7),
          element('Another 3', 41.532, -82.7),
        ],
      };
      final waters = OsmPlaceService.parseWaters(json, 41.5, -82.7);
      expect(waters.first, 'Near Pond');
      expect(waters, hasLength(5));
      expect(waters.where((n) => n.toLowerCase() == 'near pond'), hasLength(1));
    });

    test('anything beyond the search radius is dropped, even if it is the only candidate', () {
      final json = {'elements': [element('Very Far Lake', 42.5, -82.7)]};
      expect(OsmPlaceService.parseWaters(json, 41.5, -82.7), isEmpty);
    });

    test('splash pads, pools and attractions are not fishing waters', () {
      final json = {
        'elements': [
          element("Watterin' Hole", 41.5001, -82.7, {'leisure': 'playground', 'tourism': 'attraction'}),
          element('Hotel Pool', 41.5002, -82.7, {'water': 'swimming_pool'}),
          element('Real Lake', 41.505, -82.7, {'water': 'lake'}),
        ],
      };
      expect(OsmPlaceService.parseWaters(json, 41.5, -82.7), ['Real Lake']);
    });

    test('elements without a name or centre are skipped', () {
      final json = {
        'elements': [
          {'type': 'way', 'tags': {'natural': 'water'}, 'center': {'lat': 41.5, 'lon': -82.7}},
          {'type': 'way', 'tags': {'name': 'No Centre'}},
          'garbage',
        ],
      };
      expect(OsmPlaceService.parseWaters(json, 41.5, -82.7), isEmpty);
    });

    test('haversine is roughly right (1° of latitude ≈ 111 km)', () {
      expect(OsmPlaceService.haversineMeters(0, 0, 1, 0), closeTo(111195, 200));
      expect(OsmPlaceService.haversineMeters(41.5, -82.7, 41.5, -82.7), 0);
    });

    test('hits Nominatim and Overpass with the expected requests', () async {
      final seen = <Uri>[];
      final client = MockClient((request) async {
        seen.add(request.url);
        if (request.url.host == 'nominatim.openstreetmap.org') {
          return http.Response(jsonEncode({'address': {'city': 'Sandusky', 'state': 'Ohio'}}), 200);
        }
        return http.Response(jsonEncode({'elements': [element('Sandusky Bay', 41.46, -82.7)]}), 200);
      });
      final service = OsmPlaceService(client: client);

      expect(await service.locality(41.45, -82.7), 'Sandusky, Ohio');
      expect(await service.nearbyWaters(41.45, -82.7), ['Sandusky Bay']);
      expect(seen.map((u) => u.host), ['nominatim.openstreetmap.org', 'overpass-api.de']);
      expect(seen[1].queryParameters['data'], contains('around:8000,41.45,-82.7'));
    });

    test('a failing server yields an empty result for waters', () async {
      final service = OsmPlaceService(client: MockClient((_) async => http.Response('busy', 429)));
      expect(await service.nearbyWaters(1, 1), isEmpty);
      expect(await service.locality(1, 1), isNull);
    });
  });

  group('IdbBlobStore (IndexedDB code path, in-memory factory)', () {
    Uint8List bytes(List<int> v) => Uint8List.fromList(v);

    test('put / get / exists / delete', () async {
      final store = IdbBlobStore(newIdbFactoryMemory(), name: 'blobs-${DateTime.now().microsecondsSinceEpoch}');
      expect(await store.get('photos/a/full.jpg'), isNull);
      expect(await store.exists('photos/a/full.jpg'), isFalse);

      await store.put('photos/a/full.jpg', bytes([1, 2, 3, 250]));
      expect(await store.get('photos/a/full.jpg'), bytes([1, 2, 3, 250]));
      expect(await store.exists('photos/a/full.jpg'), isTrue);

      await store.put('photos/a/full.jpg', bytes([9]));
      expect(await store.get('photos/a/full.jpg'), bytes([9]), reason: 'overwrite');

      await store.delete('photos/a/full.jpg');
      expect(await store.get('photos/a/full.jpg'), isNull);
    });

    test('keys are validated', () async {
      final store = IdbBlobStore(newIdbFactoryMemory(), name: 'blobs-keys');
      for (final bad in ['../x', 'a/../b', '', 'a//b', '/abs', 'a b', 'a/..', 'a\\b']) {
        expect(() => store.put(bad, bytes([1])), throwsArgumentError, reason: bad);
      }
    });
  });

  group('SyncService (fake remote)', () {
    test('is a no-op with the default gateway — nothing leaves the device', () async {
      final (data, _, _) = await openTestData();
      await data.catches.save(sampleCatch('a'));
      final result = await data.syncService(const NoopSyncGateway()).syncOnce();
      expect(result.pushed, 0);
      expect((await data.catches.store.pendingChanges()), hasLength(1), reason: 'still waiting for a real remote');
    });

    test('pushes pending changes, acknowledges them, and does not push again', () async {
      final (data, _, _) = await openTestData();
      await data.catches.save(sampleCatch('a'));
      await data.catches.save(sampleCatch('b'));
      final remote = FakeRemote();
      final sync = data.syncService(remote);

      final first = await sync.syncOnce();
      expect(first.pushed, 2);
      expect(remote.docs[SyncCollection.catches]!.keys, unorderedEquals(['a', 'b']));

      final second = await sync.syncOnce();
      expect(second.pushed, 0);
    });

    test('a local delete propagates as a tombstone', () async {
      final (data, _, clock) = await openTestData();
      await data.catches.save(sampleCatch('a'));
      final remote = FakeRemote();
      final sync = data.syncService(remote);
      await sync.syncOnce();

      clock.advance(const Duration(minutes: 1));
      await data.catches.delete('a');
      await sync.syncOnce();
      expect(remote.docs[SyncCollection.catches]!['a']!.isDeleted, isTrue);
    });

    test('pulls records created on another device', () async {
      final (data, _, clock) = await openTestData();
      final remote = FakeRemote();
      remote.docs[SyncCollection.catches] = {
        'from-phone': SyncRecord(
          id: 'from-phone',
          data: sampleCatch('from-phone', species: 'Pike').toJson(),
          updatedAt: clock().add(const Duration(minutes: 1)),
        ),
      };
      final result = await data.syncService(remote).syncOnce();
      expect(result.pulled, 1);
      expect(result.applied, 1);
      expect((await data.catches.get('from-phone'))!.speciesName, 'Pike');
    });

    test('a remote delete hides the local copy', () async {
      final (data, _, clock) = await openTestData();
      await data.catches.save(sampleCatch('a'));
      final remote = FakeRemote();
      final sync = data.syncService(remote);
      await sync.syncOnce();

      clock.advance(const Duration(minutes: 5));
      remote.docs[SyncCollection.catches]!['a'] = SyncRecord(
        id: 'a',
        data: sampleCatch('a').toJson(),
        updatedAt: clock(),
        deletedAt: clock(),
      );
      await sync.syncOnce();
      expect(await data.catches.get('a'), isNull);
    });

    test('last-write-wins when both sides edited: the newer edit survives on both', () async {
      final (data, _, clock) = await openTestData();
      await data.catches.save(sampleCatch('a', species: 'Original'));
      final remote = FakeRemote();
      final sync = data.syncService(remote);
      await sync.syncOnce();

      clock.advance(const Duration(minutes: 1));
      remote.docs[SyncCollection.catches]!['a'] = SyncRecord(
        id: 'a',
        data: sampleCatch('a', species: 'Remote edit').toJson(),
        updatedAt: clock(),
      );
      clock.advance(const Duration(minutes: 1));
      await data.catches.save(sampleCatch('a', species: 'Local edit')); // newer than the remote edit

      await sync.syncOnce();
      expect((await data.catches.get('a'))!.speciesName, 'Local edit');
      expect(SyncDataOf(remote).speciesOf('a'), 'Local edit');
    });

    test('only pulls what changed since the last pull', () async {
      final (data, _, clock) = await openTestData();
      final remote = FakeRemote();
      final sync = data.syncService(remote);
      remote.docs[SyncCollection.catches] = {
        'one': SyncRecord(id: 'one', data: sampleCatch('one').toJson(), updatedAt: clock()),
      };
      await sync.syncOnce();
      expect(remote.lastSince[SyncCollection.catches], isNull);

      clock.advance(const Duration(minutes: 1));
      await sync.syncOnce();
      expect(remote.lastSince[SyncCollection.catches], isNotNull);
    });

    test('photos sync as metadata records; bytes are named by blob key', () async {
      final (data, _, _) = await openTestData();
      await data.catches.save(sampleCatch('a'));
      final photo = await data.photos.replaceForCatch('a', makePhoto());
      final remote = FakeRemote();
      await data.syncService(remote).syncOnce();
      expect(remote.docs[SyncCollection.photos]!.keys, [photo.id]);
      expect(photo.fullKey, 'photos/${photo.id}/full.jpg');
    });
  });
}

/// An in-memory stand-in for the remote, enough to exercise the sync algorithm.
class FakeRemote implements SyncGateway {
  final Map<SyncCollection, Map<String, SyncRecord>> docs = {};
  final Map<SyncCollection, DateTime?> lastSince = {};

  @override
  Future<void> push(SyncCollection collection, List<SyncRecord> records) async {
    final bucket = docs.putIfAbsent(collection, () => {});
    for (final r in records) {
      final existing = bucket[r.id];
      // A real backend would also apply last-write-wins; keep the newer one.
      if (existing == null || r.updatedAt.isAfter(existing.updatedAt)) bucket[r.id] = r;
    }
  }

  @override
  Future<List<SyncRecord>> pull(SyncCollection collection, {DateTime? since}) async {
    lastSince[collection] = since;
    final bucket = docs[collection] ?? {};
    return [
      for (final r in bucket.values)
        if (since == null || r.updatedAt.isAfter(since)) r,
    ];
  }
}

class SyncDataOf {
  SyncDataOf(this.remote);
  final FakeRemote remote;
  String? speciesOf(String id) => remote.docs[SyncCollection.catches]![id]!.data['speciesName'] as String?;
}
