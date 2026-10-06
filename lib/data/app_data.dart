import 'package:uuid/uuid.dart';

import '../domain/models/catch_entry.dart';
import '../domain/models/catch_photo.dart';
import '../domain/models/trip.dart';
import 'archive/archive_service.dart';
import 'db/app_storage_base.dart';
import 'db/document_store.dart';
import 'repositories/catch_repository.dart';
import 'repositories/photo_repository.dart';
import 'repositories/settings_repository.dart';
import 'repositories/trip_repository.dart';
import 'sync/sync_service.dart';

/// The local data layer, wired from a storage backend. This is the one place that knows how
/// the pieces fit together — the app builds it once at startup and tests build it over an
/// in-memory backend.
class AppData {
  factory AppData(AppStorage storage, {DateTime Function()? clock, Uuid? uuid}) {
    final db = storage.database;
    final catchStore = DocumentStore<CatchEntry>(
      db: db,
      name: 'catches',
      fromJson: CatchEntry.fromJson,
      toJson: (e) => e.toJson(),
      idOf: (e) => e.id,
      clock: clock,
    );
    final tripStore = DocumentStore<Trip>(
      db: db,
      name: 'trips',
      fromJson: Trip.fromJson,
      toJson: (t) => t.toJson(),
      idOf: (t) => t.id,
      clock: clock,
    );
    final photoStore = DocumentStore<CatchPhoto>(
      db: db,
      name: 'photos',
      fromJson: CatchPhoto.fromJson,
      toJson: (p) => p.toJson(),
      idOf: (p) => p.id,
      clock: clock,
    );

    final photos = PhotoRepository(photoStore, storage.blobs, uuid: uuid);
    final catches = CatchRepository(catchStore, photos, uuid: uuid);
    final trips = TripRepository(db, tripStore, catchStore, uuid: uuid, clock: clock);
    final settings = SettingsRepository(db);
    return AppData._(storage, catches, trips, photos, settings);
  }

  AppData._(this.storage, this.catches, this.trips, this.photos, this.settings);

  final AppStorage storage;
  final CatchRepository catches;
  final TripRepository trips;
  final PhotoRepository photos;
  final SettingsRepository settings;

  ArchiveExporter exporter({String appVersion = '1.0'}) =>
      ArchiveExporter(catches: catches, trips: trips, photos: photos, appVersion: appVersion);

  ArchiveImporter importer() => ArchiveImporter(catches: catches, trips: trips, photos: photos);

  SyncService syncService(SyncGateway gateway) => SyncService(
        gateway: gateway,
        settings: settings,
        stores: {
          SyncCollection.catches: catches.store,
          SyncCollection.trips: trips.store,
          SyncCollection.photos: photos.store,
        },
      );

  /// Deleted items are kept briefly so Undo works (and, later, so deletions can propagate
  /// to a remote). After [keepFor] they are removed for good, photo bytes included.
  Future<void> purgeOldTombstones({
    Duration keepFor = const Duration(days: 30),
    bool requireSynced = false,
    DateTime? now,
  }) async {
    final cutoff = (now ?? DateTime.now()).toUtc().subtract(keepFor);
    await catches.store.purgeTombstones(olderThan: cutoff, requireSynced: requireSynced);
    await trips.store.purgeTombstones(olderThan: cutoff, requireSynced: requireSynced);
    await photos.purgeDeleted(olderThan: cutoff, requireSynced: requireSynced);
  }
}
