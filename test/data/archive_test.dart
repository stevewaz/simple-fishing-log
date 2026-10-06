import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_fishing_log/data/archive/archive_dtos.dart';
import 'package:simple_fishing_log/data/archive/archive_mappers.dart';
import 'package:simple_fishing_log/data/archive/archive_package.dart';
import 'package:simple_fishing_log/data/archive/archive_service.dart';
import 'package:simple_fishing_log/domain/models/catch_entry.dart';
import 'package:simple_fishing_log/domain/models/conditions.dart';
import 'package:simple_fishing_log/domain/models/trip.dart';
import 'package:simple_fishing_log/domain/models/units.dart';

import 'test_support.dart';

Uint8List zip(Map<String, Object> files) {
  final archive = Archive();
  for (final e in files.entries) {
    final v = e.value;
    archive.addFile(v is String ? ArchiveFile.string(e.key, v) : ArchiveFile.bytes(e.key, v as List<int>));
  }
  return ZipEncoder().encodeBytes(archive);
}

String manifestJson({int version = 1, int catches = 0, int trips = 0, int photos = 0}) => jsonEncode({
      'formatVersion': version,
      'generator': 'test',
      'exportedAt': '2026-06-15T12:00:00Z',
      'catchCount': catches,
      'tripCount': trips,
      'photoCount': photos,
    });

void main() {
  group('DTOs', () {
    test('a catch DTO round-trips through JSON', () {
      final dto = CatchDto(
        id: uuidA,
        date: DateTime.utc(2023, 11, 14, 22, 13, 20),
        species: const SpeciesRefDto('walleye', 'Walleye'),
        location: const LocationDto(
          name: 'Shore',
          waterBody: 'Lake Erie',
          latitude: 41.5,
          longitude: -82.7,
          depth: MeasurementDto(12, 'ft'),
        ),
        weight: const MeasurementDto(4.2, 'lb'),
        wasFromBoat: true,
        wasReleased: true,
        rating: 3,
        notes: '🎣 emoji + "quotes"',
        tripId: uuidB,
        photoFileName: 'abc.jpg',
      );
      final decoded = CatchDto.fromJson(jsonDecode(jsonEncode(dto.toJson())));
      expect(decoded.toJson(), dto.toJson());
      expect(decoded.notes, '🎣 emoji + "quotes"');
      expect(decoded.location!.depth!.unit, 'ft');
    });

    test('dates are written as whole-second ISO-8601 (the only form Swift can read)', () {
      final json = CatchDto(id: uuidA, date: DateTime.utc(2026, 6, 15, 12, 30, 45, 678)).toJson();
      expect(json['date'], '2026-06-15T12:30:45Z');
    });

    test('the trip link uses the Swift key `tripID`', () {
      expect(CatchDto(id: uuidA, date: DateTime.utc(2026), tripId: uuidB).toJson()['tripID'], uuidB);
    });

    test('Swift-style uppercase UUIDs and fractional-free dates decode; ids are lower-cased', () {
      final dto = CatchDto.fromJson({
        'id': 'E621E1F8-C36C-495A-93FC-0C247A3E6E5F',
        'date': '2026-06-15T12:00:00Z',
        'tripID': 'A0A0A0A0-B1B1-4C4C-8D8D-E2E2E2E2E2E2',
      });
      expect(dto.id, 'e621e1f8-c36c-495a-93fc-0c247a3e6e5f');
      expect(dto.tripId, 'a0a0a0a0-b1b1-4c4c-8d8d-e2e2e2e2e2e2');
    });

    test('a record with a bad id or no date is rejected', () {
      expect(() => CatchDto.fromJson({'id': 'not-even-close-to-valid'}), throwsFormatException);
      expect(() => CatchDto.fromJson({'id': uuidA}), throwsFormatException);
      expect(() => CatchDto.fromJson('nope'), throwsFormatException);
    });

    test('a malformed trip link is dropped, not fatal', () {
      final dto = CatchDto.fromJson({'id': uuidA, 'date': '2026-01-01T00:00:00Z', 'tripID': 'garbage'});
      expect(dto.tripId, isNull);
    });

    test('unknown extra fields are ignored (forward compatibility)', () {
      final dto = CatchDto.fromJson({'id': uuidA, 'date': '2026-01-01T00:00:00Z', 'futureField': {'x': 1}});
      expect(dto.id, uuidA);
    });
  });

  group('mappers', () {
    test('an entry maps to a DTO and back without loss', () {
      final entry = CatchEntry(
        id: uuidA,
        date: DateTime.utc(2026, 6, 15, 12),
        speciesId: 'walleye',
        speciesName: 'Walleye',
        wasReleased: false,
        wasFromBoat: true,
        rating: 4,
        locationName: 'Sandusky Bay',
        waterBodyName: 'Lake Erie',
        latitude: 41.5,
        longitude: -82.7,
        depth: const Measurement(12, LengthUnit.feet),
        weight: const Measurement(2.8, MassUnit.pounds),
        length: const Measurement(21, LengthUnit.inches),
        conditions: Conditions(
          source: ConditionsSource.openMeteo,
          capturedAt: DateTime.utc(2026, 6, 15, 12, 1),
          airTempC: 22.5,
          waterTempC: 18,
          windSpeedMS: 4.2,
          windDirectionDegrees: 225,
          pressureHPa: 1015,
          pressureTrend: 'falling',
          weatherCondition: 'Partly cloudy',
          cloudCover: 0.4,
          waterConditions: 'choppy',
        ),
        gear: const Gear(rodReel: 'Spinning rod & reel', baitLure: 'Crankbait', lineType: 'Braid', technique: 'Trolling'),
        notes: 'Good day',
        tripId: uuidB,
      );
      final dto = CatchMapper.toDto(entry);
      expect(dto.tripId, uuidB);
      final back = CatchMapper.apply(CatchDto.fromJson(jsonDecode(jsonEncode(dto.toJson()))), CatchEntry(id: uuidA, date: dto.date));
      // Trip linkage is deliberately not the mapper's job: the importer resolves it against
      // the trips it actually has (see the import tests below).
      expect(back, entry.copyWith(tripId: null));
    });

    test('empty groups are omitted, mirroring the Swift exporter', () {
      final dto = CatchMapper.toDto(CatchEntry(id: uuidA, date: DateTime.utc(2026)));
      expect(dto.species, isNull);
      expect(dto.location, isNull);
      expect(dto.conditions, isNull);
      expect(dto.gear, isNull);
    });

    test('applying onto an existing entry keeps fields the DTO does not carry', () {
      final existing = CatchEntry(
        id: uuidA,
        date: DateTime.utc(2026),
        speciesId: 'walleye',
        speciesName: 'Walleye',
        notes: 'keep me',
        weight: const Measurement(3, MassUnit.pounds),
      );
      final merged = CatchMapper.apply(CatchDto(id: uuidA, date: DateTime.utc(2026, 2)), existing);
      expect(merged.date, DateTime.utc(2026, 2));
      expect(merged.speciesName, 'Walleye');
      expect(merged.notes, 'keep me');
      expect(merged.weight, const Measurement(3, MassUnit.pounds));
    });

    test('an unknown unit symbol falls back instead of corrupting the value', () {
      final entry = CatchMapper.apply(
        CatchDto(id: uuidA, date: DateTime.utc(2026), weight: const MeasurementDto(3, 'stone')),
        CatchEntry(id: uuidA, date: DateTime.utc(2026)),
      );
      expect(entry.weight, const Measurement(3, MassUnit.pounds));
    });
  });

  group('ArchivePackage.open', () {
    test('rejects bytes that are not a zip', () {
      expect(
        () => ArchivePackage.open(Uint8List.fromList(utf8.encode('hello'))),
        throwsA(isA<ArchiveImportError>().having((e) => e.kind, 'kind', ArchiveImportErrorKind.notAnArchive)),
      );
    });

    test('rejects a zip with no manifest', () {
      expect(
        () => ArchivePackage.open(zip({'catches.json': '[]'})),
        throwsA(isA<ArchiveImportError>().having((e) => e.kind, 'kind', ArchiveImportErrorKind.manifestMissing)),
      );
    });

    test('rejects a manifest that is not valid JSON', () {
      expect(
        () => ArchivePackage.open(zip({'manifest.json': '{not json'})),
        throwsA(isA<ArchiveImportError>().having((e) => e.kind, 'kind', ArchiveImportErrorKind.manifestMissing)),
      );
    });

    test('rejects a future format version', () {
      expect(
        () => ArchivePackage.open(zip({'manifest.json': manifestJson(version: 99)})),
        throwsA(isA<ArchiveImportError>().having((e) => e.kind, 'kind', ArchiveImportErrorKind.unsupportedFormatVersion)),
      );
    });

    test('rejects manifests that claim absurd counts', () {
      expect(
        () => ArchivePackage.open(zip({'manifest.json': manifestJson(catches: 999999)})),
        throwsA(isA<ArchiveImportError>().having((e) => e.kind, 'kind', ArchiveImportErrorKind.tooLarge)),
      );
    });

    test('rejects an archive whose real catch list exceeds the cap, whatever the manifest says', () {
      final many = jsonEncode([for (var i = 0; i < ArchiveLimits.maxCatches + 1; i++) <String, Object>{}]);
      final package = ArchivePackage.open(zip({'manifest.json': manifestJson(), 'catches.json': many}));
      expect(() => package.catchRecords, throwsA(isA<ArchiveImportError>()));
    });

    test('accepts a wrapping folder, as made by zipping an old .fishlog package', () {
      final package = ArchivePackage.open(zip({
        'Backup.fishlog/manifest.json': manifestJson(catches: 1),
        'Backup.fishlog/catches.json': jsonEncode([
          {'id': uuidA, 'date': '2026-01-01T00:00:00Z'}
        ]),
      }));
      expect(package.manifest.catchCount, 1);
      expect(package.catchRecords, hasLength(1));
    });

    test('ignores macOS resource-fork junk', () {
      final package = ArchivePackage.open(zip({
        '__MACOSX/._manifest.json': 'junk',
        'manifest.json': manifestJson(),
      }));
      expect(package.manifest.formatVersion, 1);
    });
  });

  group('photo file names', () {
    test('hostile names are rejected', () {
      for (final bad in ['../../etc/passwd', '..', '.', '', 'a/b.jpg', r'a\b.jpg', 'x' * 129, '...', '___']) {
        expect(isSafePhotoFileName(bad), isFalse, reason: bad);
      }
    });

    test('normal names are accepted', () {
      for (final ok in ['$uuidA.jpg', 'photo-1.HEIC', 'a_b.c.png']) {
        expect(isSafePhotoFileName(ok), isTrue, reason: ok);
      }
    });
  });

  group('export / import round trip', () {
    test('an exported archive contains the expected files and a valid manifest', () async {
      final (data, _, _) = await openTestData();
      await data.catches.save(sampleCatch(uuidA));
      final exported = await data.exporter().build(now: DateTime.utc(2026, 6, 15, 12));

      expect(exported.fileName, 'FishLog-2026-06-15.fishlog');
      final archive = ZipDecoder().decodeBytes(exported.bytes);
      final names = archive.files.map((f) => f.name).toSet();
      expect(names, containsAll(['manifest.json', 'catches.json', 'trips.json']));

      final package = ArchivePackage.open(exported.bytes);
      expect(package.manifest.catchCount, 1);
      expect(package.manifest.formatVersion, ArchiveManifest.currentFormatVersion);
    });

    test('full export → import into a fresh database, with a trip and a photo', () async {
      final (source, _, _) = await openTestData();
      final trip = await source.trips.startSession(title: 'Erie Morning');
      await source.catches.save(CatchEntry(
        id: uuidA,
        date: DateTime.utc(2026, 6, 15, 12),
        speciesId: 'smallmouth-bass',
        speciesName: 'Smallmouth Bass',
        waterBodyName: 'Lake Erie',
        weight: const Measurement(4.2, MassUnit.pounds),
        notes: 'Good day',
        tripId: trip.id,
      ));
      await source.photos.replaceForCatch(uuidA, makePhoto(width: 200, height: 120));
      final exported = await source.exporter().build();

      final (dest, _, _) = await openTestData();
      final package = ArchivePackage.open(exported.bytes);
      expect(package.manifest.catchCount, 1);
      expect(package.manifest.photoCount, 1);

      final report = await dest.importer().import(package);
      expect(report.added, 1);
      expect(report.skipped, 0);
      expect(report.failures, isEmpty);

      final imported = (await dest.catches.get(uuidA))!;
      expect(imported.speciesName, 'Smallmouth Bass');
      expect(imported.weight, const Measurement(4.2, MassUnit.pounds));
      expect(imported.notes, 'Good day');
      expect(imported.tripId, trip.id);
      expect((await dest.trips.get(trip.id))!.title, 'Erie Morning');
      expect((await dest.trips.get(trip.id))!.isActive, isFalse, reason: 'imported trips are never active');

      final photos = await dest.photos.forCatch(uuidA);
      expect(photos, hasLength(1));
      expect((await dest.photos.fullBytes(photos.single.id))!.isNotEmpty, isTrue);
    });

    /// Idempotency: importing the same file again with skipExisting must change nothing.
    test('importing the same archive twice skips everything the second time', () async {
      final (source, _, _) = await openTestData();
      await source.catches.save(sampleCatch(uuidA));
      final exported = await source.exporter().build();

      final (dest, _, _) = await openTestData();
      final first = await dest.importer().import(ArchivePackage.open(exported.bytes));
      expect(first.added, 1);
      final second = await dest.importer().import(ArchivePackage.open(exported.bytes));
      expect(second.added, 0);
      expect(second.skipped, 1);
      expect(await dest.catches.all(), hasLength(1));
    });

    test('replaceExisting overwrites a changed catch', () async {
      final (source, _, _) = await openTestData();
      await source.catches.save(sampleCatch(uuidA, species: 'Pike'));
      final exported = await source.exporter().build();

      final (dest, _, _) = await openTestData();
      await dest.catches.save(sampleCatch(uuidA, species: 'Walleye').copyWith(notes: 'mine'));
      final report = await dest.importer().import(ArchivePackage.open(exported.bytes), strategy: ImportStrategy.replaceExisting);
      expect(report.replaced, 1);
      final entry = (await dest.catches.get(uuidA))!;
      expect(entry.speciesName, 'Pike');
      expect(entry.notes, 'mine', reason: 'a field the archive did not carry survives replace');
    });

    test('a catch the angler deleted comes back when they import a backup that still has it', () async {
      final (source, _, _) = await openTestData();
      await source.catches.save(sampleCatch(uuidA));
      final exported = await source.exporter().build();

      final (dest, _, _) = await openTestData();
      await dest.catches.save(sampleCatch(uuidA));
      await dest.catches.delete(uuidA);
      expect(await dest.catches.get(uuidA), isNull);

      final report = await dest.importer().import(ArchivePackage.open(exported.bytes));
      expect(report.added, 1);
      expect(await dest.catches.get(uuidA), isNotNull);
    });

    /// One corrupt record must not reject the rest — "3 of 800 couldn't be read".
    test('a corrupt record is reported and the rest still import', () async {
      final archive = zip({
        'manifest.json': manifestJson(catches: 3),
        'catches.json': jsonEncode([
          {'id': uuidA, 'date': '2026-06-15T12:00:00Z', 'species': {'id': 'walleye', 'name': 'Walleye'}},
          {'id': 'not-even-close-to-valid'},
          {'id': uuidB, 'date': '2026-06-16T12:00:00Z'},
        ]),
      });
      final (dest, _, _) = await openTestData();
      final report = await dest.importer().import(ArchivePackage.open(archive));
      expect(report.added, 2);
      expect(report.failures, hasLength(1));
      expect(report.failures.single, contains('Record 1'));
    });

    test('duplicate ids inside one archive import once', () async {
      final archive = zip({
        'manifest.json': manifestJson(catches: 2),
        'catches.json': jsonEncode([
          {'id': uuidA, 'date': '2026-06-15T12:00:00Z'},
          {'id': uuidA, 'date': '2026-06-15T12:00:00Z'},
        ]),
      });
      final (dest, _, _) = await openTestData();
      final report = await dest.importer().import(ArchivePackage.open(archive));
      expect(report.added, 1);
      expect(report.skipped, 1);
    });

    /// The security guard: a hostile filename embedded in an otherwise-valid archive must
    /// never be used to reach anything — it should just yield no photo, not a crash.
    test('a path-traversal photo name is rejected and the catch still imports', () async {
      final archive = zip({
        'manifest.json': manifestJson(catches: 1),
        'catches.json': jsonEncode([
          {'id': uuidA, 'date': '2026-06-15T12:00:00Z', 'photoFileName': '../../etc/passwd'}
        ]),
        'photos/passwd': 'secret',
      });
      final (dest, blobs, _) = await openTestData();
      final report = await dest.importer().import(ArchivePackage.open(archive));
      expect(report.added, 1);
      expect(await dest.photos.forCatch(uuidA), isEmpty);
      expect(blobs.length, 0);
    });

    test('a photo that is not an image is reported, the catch still imports', () async {
      final archive = zip({
        'manifest.json': manifestJson(catches: 1, photos: 1),
        'catches.json': jsonEncode([
          {'id': uuidA, 'date': '2026-06-15T12:00:00Z', 'photoFileName': 'a.jpg'}
        ]),
        'photos/a.jpg': 'definitely not an image',
      });
      final (dest, _, _) = await openTestData();
      final report = await dest.importer().import(ArchivePackage.open(archive));
      expect(report.added, 1);
      expect(report.failures, hasLength(1));
      expect(await dest.photos.forCatch(uuidA), isEmpty);
    });

    test('a missing photo file does not fail the import', () async {
      final archive = zip({
        'manifest.json': manifestJson(catches: 1),
        'catches.json': jsonEncode([
          {'id': uuidA, 'date': '2026-06-15T12:00:00Z', 'photoFileName': 'missing.jpg'}
        ]),
      });
      final (dest, _, _) = await openTestData();
      final report = await dest.importer().import(ArchivePackage.open(archive));
      expect(report.added, 1);
      expect(report.failures, isEmpty);
    });

    test('a catch whose trip is neither in the archive nor local loses the link', () async {
      final archive = zip({
        'manifest.json': manifestJson(catches: 1),
        'catches.json': jsonEncode([
          {'id': uuidA, 'date': '2026-06-15T12:00:00Z', 'tripID': uuidC}
        ]),
      });
      final (dest, _, _) = await openTestData();
      await dest.importer().import(ArchivePackage.open(archive));
      expect((await dest.catches.get(uuidA))!.tripId, isNull);
    });

    test('a catch whose trip already exists locally keeps the link', () async {
      final archive = zip({
        'manifest.json': manifestJson(catches: 1),
        'catches.json': jsonEncode([
          {'id': uuidA, 'date': '2026-06-15T12:00:00Z', 'tripID': uuidC}
        ]),
      });
      final (dest, _, _) = await openTestData();
      await dest.trips.save(Trip(id: uuidC, startDate: DateTime.utc(2026)));
      await dest.importer().import(ArchivePackage.open(archive));
      expect((await dest.catches.get(uuidA))!.tripId, uuidC);
    });

    test('a large import is batched and complete', () async {
      final records = [
        for (var i = 0; i < 175; i++)
          {
            'id': '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
            'date': '2026-06-15T12:00:00Z',
          }
      ];
      final archive = zip({'manifest.json': manifestJson(catches: records.length), 'catches.json': jsonEncode(records)});
      final (dest, _, _) = await openTestData();
      final report = await dest.importer().import(ArchivePackage.open(archive));
      expect(report.added, 175);
      expect(await dest.catches.all(), hasLength(175));
    });

    test('exporting excludes deleted catches', () async {
      final (data, _, _) = await openTestData();
      await data.catches.save(sampleCatch(uuidA));
      await data.catches.save(sampleCatch(uuidB));
      await data.catches.delete(uuidB);
      final package = ArchivePackage.open((await data.exporter().build()).bytes);
      expect(package.manifest.catchCount, 1);
    });

    test('report summary reads naturally', () {
      final r = ImportReport()
        ..added = 1
        ..skipped = 2;
      expect(r.summary, 'Added 1 catch. Skipped 2 already in your log.');
      r.added = 3;
      expect(r.summary, startsWith('Added 3 catches.'));
    });
  });
}
