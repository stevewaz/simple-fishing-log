import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../../domain/models/catch_entry.dart';
import '../../domain/models/trip.dart';
import '../repositories/catch_repository.dart';
import '../repositories/photo_repository.dart';
import '../repositories/trip_repository.dart';
import '../services/photo_processor.dart';
import 'archive_dtos.dart';
import 'archive_mappers.dart';
import 'archive_package.dart';

enum ImportStrategy { skipExisting, replaceExisting }

class ImportReport {
  int added = 0;
  int replaced = 0;
  int skipped = 0;
  final List<String> failures = [];

  /// A one-line, human summary for the result dialog.
  String get summary {
    final parts = <String>[
      'Added $added catch${added == 1 ? '' : 'es'}.',
      if (replaced > 0) 'Replaced $replaced.',
      if (skipped > 0) 'Skipped $skipped already in your log.',
      if (failures.isNotEmpty) "${failures.length} item${failures.length == 1 ? '' : 's'} couldn't be read.",
    ];
    return parts.join(' ');
  }
}

class ExportedArchive {
  const ExportedArchive(this.fileName, this.bytes, this.catchCount);

  final String fileName;
  final Uint8List bytes;
  final int catchCount;
}

/// Builds `.fishlog` archives from the live repositories.
class ArchiveExporter {
  ArchiveExporter({
    required this.catches,
    required this.trips,
    required this.photos,
    this.appVersion = '1.0',
  });

  final CatchRepository catches;
  final TripRepository trips;
  final PhotoRepository photos;
  final String appVersion;

  static const fileExtension = 'fishlog';

  Future<ExportedArchive> build({DateTime? now}) async {
    final when = (now ?? DateTime.now());
    final entries = await catches.all();
    final tripList = await trips.all();

    final photoFiles = <String, Uint8List>{};
    final photoByCatch = <String, String>{};
    for (final photo in await photos.store.all()) {
      final catchId = photo.catchId;
      if (photoByCatch.containsKey(catchId)) continue; // one photo per catch in the format
      final bytes = await photos.fullBytes(photo.id);
      if (bytes == null) continue;
      final fileName = '$catchId.jpg';
      photoFiles[fileName] = bytes;
      photoByCatch[catchId] = fileName;
    }

    final bytes = ArchiveWriter.build(
      catches: [for (final e in entries) CatchMapper.toDto(e, photoFileName: photoByCatch[e.id])],
      trips: [for (final t in tripList) TripMapper.toDto(t)],
      photosByFileName: photoFiles,
      generator: 'FishLog $appVersion',
      exportedAt: when.toUtc(),
    );
    return ExportedArchive(
      'FishLog-${DateFormat('yyyy-MM-dd').format(when)}.$fileExtension',
      bytes,
      entries.length,
    );
  }
}

/// Imports an opened [ArchivePackage] into the live repositories.
class ArchiveImporter {
  ArchiveImporter({required this.catches, required this.trips, required this.photos});

  final CatchRepository catches;
  final TripRepository trips;
  final PhotoRepository photos;

  static const _batchSize = 50;

  Future<ImportReport> import(
    ArchivePackage package, {
    ImportStrategy strategy = ImportStrategy.skipExisting,
  }) async {
    final report = ImportReport();

    // Trips first, so catches can resolve their trip. Existing ids are fetched once — never
    // queried per record, which would make a big import an N-query import.
    final localTrips = await trips.all();
    final knownTripIds = <String>{for (final t in localTrips) t.id};
    final existingTrips = {for (final t in localTrips) t.id: t};
    final tripRecords = package.tripRecords;
    for (var i = 0; i < tripRecords.length; i++) {
      final TripDto dto;
      try {
        dto = TripDto.fromJson(tripRecords[i]);
      } catch (_) {
        report.failures.add('Trip $i: couldn\'t decode');
        continue;
      }
      final existing = existingTrips[dto.id];
      if (existing != null) {
        if (strategy == ImportStrategy.replaceExisting) {
          await trips.save(TripMapper.apply(dto, existing));
        }
      } else {
        final trip = TripMapper.apply(dto, Trip(id: dto.id, startDate: dto.startDate));
        await trips.save(trip);
        existingTrips[dto.id] = trip;
      }
      knownTripIds.add(dto.id);
    }

    final localCatches = await catches.all();
    final existingCatchIds = <String>{for (final e in localCatches) e.id};
    final existingById = {for (final e in localCatches) e.id: e};
    final records = package.catchRecords;
    final batch = <CatchEntry>[];
    final photoJobs = <(String catchId, String fileName)>[];

    Future<void> flush() async {
      if (batch.isEmpty) return;
      await catches.saveAll(batch);
      batch.clear();
    }

    for (var i = 0; i < records.length; i++) {
      final CatchDto dto;
      try {
        dto = CatchDto.fromJson(records[i]);
      } catch (_) {
        report.failures.add('Record $i: couldn\'t decode');
        continue;
      }

      final existing = existingById[dto.id];
      if (existingCatchIds.contains(dto.id)) {
        if (strategy != ImportStrategy.replaceExisting) {
          report.skipped++;
          continue;
        }
        final updated = CatchMapper.apply(dto, existing ?? CatchEntry(id: dto.id, date: dto.date));
        batch.add(updated.copyWith(tripId: dto.tripId != null && knownTripIds.contains(dto.tripId) ? dto.tripId : null));
        report.replaced++;
      } else {
        final created = CatchMapper.apply(dto, CatchEntry(id: dto.id, date: dto.date));
        batch.add(created.copyWith(tripId: dto.tripId != null && knownTripIds.contains(dto.tripId) ? dto.tripId : null));
        existingCatchIds.add(dto.id);
        report.added++;
      }
      if (dto.photoFileName != null) photoJobs.add((dto.id, dto.photoFileName!));
      if (batch.length >= _batchSize) await flush();
    }
    await flush();

    for (final (catchId, fileName) in photoJobs) {
      final bytes = package.photoBytes(fileName);
      if (bytes == null) continue; // missing/unsafe/oversized photo: the catch still imports
      final processed = await PhotoProcessor.process(bytes);
      if (processed == null) {
        report.failures.add("Photo for $catchId: unsupported image format");
        continue;
      }
      await photos.replaceForCatch(catchId, processed);
    }
    return report;
  }
}
