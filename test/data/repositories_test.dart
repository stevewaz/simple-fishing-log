import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_fishing_log/data/services/photo_processor.dart';
import 'package:simple_fishing_log/domain/models/trip.dart';

import 'test_support.dart';

void main() {
  group('CatchRepository', () {
    test('lists newest first', () async {
      final (data, _, _) = await openTestData();
      await data.catches.saveAll([
        sampleCatch('old', date: DateTime.utc(2025, 1, 1)),
        sampleCatch('new', date: DateTime.utc(2026, 6, 1)),
        sampleCatch('mid', date: DateTime.utc(2025, 9, 1)),
      ]);
      expect((await data.catches.all()).map((e) => e.id), ['new', 'mid', 'old']);
      expect((await data.catches.watchAll().first).map((e) => e.id), ['new', 'mid', 'old']);
    });

    test('delete hides the catch and its photo; restore brings both back', () async {
      final (data, blobs, clock) = await openTestData();
      await data.catches.save(sampleCatch('c1'));
      final photo = await data.photos.replaceForCatch('c1', makePhoto());
      expect(await data.photos.forCatch('c1'), hasLength(1));

      clock.advance(const Duration(minutes: 1));
      await data.catches.delete('c1');
      expect(await data.catches.get('c1'), isNull);
      expect(await data.photos.forCatch('c1'), isEmpty);
      // Bytes are kept, so Undo can restore the photo.
      expect(await blobs.exists(photo.fullKey), isTrue);

      clock.advance(const Duration(minutes: 1));
      await data.catches.restore('c1');
      expect(await data.catches.get('c1'), isNotNull);
      final restored = await data.photos.forCatch('c1');
      expect(restored.map((p) => p.id), [photo.id]);
      expect(await data.photos.thumbBytes(photo.id), isNotNull);
    });

    test('restore does not resurrect a photo the user had replaced earlier', () async {
      final (data, _, clock) = await openTestData();
      await data.catches.save(sampleCatch('c1'));
      await data.photos.replaceForCatch('c1', makePhoto());
      clock.advance(const Duration(minutes: 1));
      final current = await data.photos.replaceForCatch('c1', makePhoto(width: 80));

      clock.advance(const Duration(minutes: 1));
      await data.catches.delete('c1');
      clock.advance(const Duration(minutes: 1));
      await data.catches.restore('c1');

      final photos = await data.photos.forCatch('c1');
      expect(photos.map((p) => p.id), [current.id]); // only the live one; the replaced bytes are gone
    });
  });

  group('PhotoRepository', () {
    test('writes bytes, then metadata, and serves both sizes', () async {
      final (data, blobs, _) = await openTestData();
      final photo = await data.photos.replaceForCatch('c1', makePhoto(width: 300, height: 200));

      expect(photo.width, 300);
      expect(photo.height, 200);
      expect(await blobs.exists('photos/${photo.id}/full.jpg'), isTrue);
      expect(await blobs.exists('photos/${photo.id}/thumb.jpg'), isTrue);
      expect((await data.photos.fullBytes(photo.id))!.isNotEmpty, isTrue);
    });

    test('replacing a photo deletes the old bytes immediately', () async {
      final (data, blobs, _) = await openTestData();
      final first = await data.photos.replaceForCatch('c1', makePhoto());
      final second = await data.photos.replaceForCatch('c1', makePhoto());

      expect(await blobs.exists(first.fullKey), isFalse);
      expect(await blobs.exists(second.fullKey), isTrue);
      expect((await data.photos.forCatch('c1')).map((p) => p.id), [second.id]);
    });

    test('removeForCatch deletes the photo and its bytes', () async {
      final (data, blobs, _) = await openTestData();
      final photo = await data.photos.replaceForCatch('c1', makePhoto());
      await data.photos.removeForCatch('c1');
      expect(await data.photos.forCatch('c1'), isEmpty);
      expect(await blobs.exists(photo.thumbKey), isFalse);
    });

    test('purgeOldTombstones reclaims bytes of long-deleted catches only', () async {
      final (data, blobs, clock) = await openTestData();
      await data.catches.save(sampleCatch('gone'));
      await data.catches.save(sampleCatch('kept'));
      final gonePhoto = await data.photos.replaceForCatch('gone', makePhoto());
      final keptPhoto = await data.photos.replaceForCatch('kept', makePhoto());
      await data.catches.delete('gone');

      clock.advance(const Duration(days: 10));
      await data.purgeOldTombstones(now: clock());
      expect(await blobs.exists(gonePhoto.fullKey), isTrue, reason: 'still inside the Undo window');

      clock.advance(const Duration(days: 40));
      await data.purgeOldTombstones(now: clock());
      expect(await blobs.exists(gonePhoto.fullKey), isFalse);
      expect(await blobs.exists(gonePhoto.thumbKey), isFalse);
      expect(await data.catches.store.exists('gone', includeDeleted: true), isFalse);
      expect(await blobs.exists(keptPhoto.fullKey), isTrue);
      expect(await data.catches.get('kept'), isNotNull);
    });
  });

  group('TripRepository', () {
    test('startSession creates an active trip', () async {
      final (data, _, clock) = await openTestData();
      final trip = await data.trips.startSession();
      expect(trip.isActive, isTrue);
      expect(trip.startDate, clock());
      expect((await data.trips.all()).single.id, trip.id);
    });

    test('at most one trip is active: starting a session ends the previous one', () async {
      final (data, _, clock) = await openTestData();
      final first = await data.trips.startSession();
      clock.advance(const Duration(hours: 3));
      final second = await data.trips.startSession();

      final trips = await data.trips.all();
      expect(trips.where((t) => t.isActive).map((t) => t.id), [second.id]);
      final ended = trips.firstWhere((t) => t.id == first.id);
      expect(ended.endDate, clock());
    });

    test('endSession deactivates and stamps the end', () async {
      final (data, _, clock) = await openTestData();
      final trip = await data.trips.startSession();
      clock.advance(const Duration(hours: 2));
      await data.trips.endSession(trip.id);
      final ended = (await data.trips.get(trip.id))!;
      expect(ended.isActive, isFalse);
      expect(ended.endDate, clock());
    });

    test('endSession on an inactive trip changes nothing', () async {
      final (data, _, clock) = await openTestData();
      final trip = await data.trips.startSession();
      await data.trips.endSession(trip.id);
      final endedAt = (await data.trips.get(trip.id))!.endDate;
      clock.advance(const Duration(hours: 5));
      await data.trips.endSession(trip.id);
      expect((await data.trips.get(trip.id))!.endDate, endedAt);
    });

    test('deleting a trip detaches its catches instead of destroying them', () async {
      final (data, _, _) = await openTestData();
      final trip = await data.trips.startSession();
      await data.catches.save(sampleCatch('a').copyWith(tripId: trip.id));
      await data.catches.save(sampleCatch('b').copyWith(tripId: 'other-trip'));

      await data.trips.delete(trip.id);

      expect(await data.trips.get(trip.id), isNull);
      expect((await data.catches.get('a'))!.tripId, isNull);
      expect(await data.catches.get('a'), isNotNull);
      expect((await data.catches.get('b'))!.tripId, 'other-trip');
    });

    test('lists newest first', () async {
      final (data, _, _) = await openTestData();
      await data.trips.save(Trip(id: 'old', startDate: DateTime.utc(2025)));
      await data.trips.save(Trip(id: 'new', startDate: DateTime.utc(2026)));
      expect((await data.trips.all()).map((t) => t.id), ['new', 'old']);
    });
  });

  group('SettingsRepository', () {
    test('remembers the last location', () async {
      final (data, _, _) = await openTestData();
      expect(await data.settings.lastLocation(), isNull);
      await data.settings.saveLastLocation(41.5, -82.7, at: DateTime.utc(2026, 6, 15));
      final loc = (await data.settings.lastLocation())!;
      expect(loc.latitude, 41.5);
      expect(loc.longitude, -82.7);
      expect(loc.at, DateTime.utc(2026, 6, 15));
    });
  });

  group('PhotoProcessor', () {
    test('downscales to the long-edge cap and produces a small thumbnail', () {
      final processed = PhotoProcessor.processSync(makeJpeg(width: 3000, height: 1500))!;
      expect(processed.width, PhotoProcessor.maxLongEdge);
      expect(processed.height, 1024);
      expect(processed.thumb.length, lessThan(processed.full.length));
    });

    test('never upscales a small image', () {
      final processed = PhotoProcessor.processSync(makeJpeg(width: 100, height: 60))!;
      expect(processed.width, 100);
      expect(processed.height, 60);
    });

    test('portrait images are capped on the long (vertical) edge', () {
      final processed = PhotoProcessor.processSync(makeJpeg(width: 1500, height: 3000))!;
      expect(processed.height, PhotoProcessor.maxLongEdge);
      expect(processed.width, 1024);
    });

    test('returns null for bytes that are not an image', () {
      expect(PhotoProcessor.processSync(Uint8List.fromList(utf8.encode('definitely not an image'))), isNull);
    });
  });
}
