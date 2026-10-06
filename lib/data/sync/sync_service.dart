import '../db/document_store.dart';
import '../repositories/settings_repository.dart';

/// The names of the synced collections. They double as the Firestore collection names
/// (`users/{uid}/catches`, …) when the Firebase adapter is added.
enum SyncCollection {
  catches('catches'),
  trips('trips'),
  photos('photos');

  const SyncCollection(this.path);
  final String path;
}

/// The seam between the local database and a remote (Firebase, later).
///
/// The app is **local-first**: the local database is always the source of truth and the app
/// never waits on this. A gateway only has to move [SyncRecord]s; it needs no knowledge of
/// catches, trips or conflict rules — those live in [SyncService] and [DocumentStore].
///
/// A Firebase adapter implements this with a few dozen lines: `push` writes each record
/// to `users/{uid}/{collection}/{id}` (a tombstone becomes `deletedAt`, or a delete), and
/// `pull` queries `updatedAt > since`. See docs/FIREBASE.md.
abstract interface class SyncGateway {
  /// Upserts [records] on the remote. Must be idempotent — a retry after a dropped
  /// connection will resend the same records.
  Future<void> push(SyncCollection collection, List<SyncRecord> records);

  /// Records on the remote changed after [since] (all of them when null).
  Future<List<SyncRecord>> pull(SyncCollection collection, {DateTime? since});
}

/// The default until Firebase is wired in: nothing leaves the device.
class NoopSyncGateway implements SyncGateway {
  const NoopSyncGateway();

  @override
  Future<void> push(SyncCollection collection, List<SyncRecord> records) async {}

  @override
  Future<List<SyncRecord>> pull(SyncCollection collection, {DateTime? since}) async => const [];
}

class SyncResult {
  const SyncResult({this.pushed = 0, this.pulled = 0, this.applied = 0});

  final int pushed;
  final int pulled;

  /// Pulled records that won last-write-wins and were written locally.
  final int applied;

  @override
  String toString() => 'SyncResult(pushed: $pushed, pulled: $pulled, applied: $applied)';
}

/// One push-then-pull pass, last-write-wins per record.
///
/// Photo *bytes* are not handled here: a Firebase adapter uploads the blobs named by pending
/// photo records (`photos/<id>/full.jpg`, `…/thumb.jpg`) before acknowledging them.
class SyncService {
  SyncService({
    required this.gateway,
    required this.settings,
    required this.stores,
  });

  final SyncGateway gateway;
  final SettingsRepository settings;
  final Map<SyncCollection, DocumentStore<dynamic>> stores;

  bool get isEnabled => gateway is! NoopSyncGateway;

  Future<SyncResult> syncOnce() async {
    if (!isEnabled) return const SyncResult();
    var pushed = 0, pulled = 0, applied = 0;

    for (final entry in stores.entries) {
      final collection = entry.key;
      final store = entry.value;

      // Push first: a local edit must reach the remote before a stale remote copy can be
      // pulled back over it.
      final pending = await store.pendingChanges();
      if (pending.isNotEmpty) {
        await gateway.push(collection, pending);
        for (final record in pending) {
          await store.markSynced(record.id, upTo: record.updatedAt);
        }
        pushed += pending.length;
      }

      final since = await settings.syncLastPulledAt(collection.path);
      final remote = await gateway.pull(collection, since: since);
      var newest = since;
      for (final record in remote) {
        if (await store.applyRemote(record)) applied++;
        if (newest == null || record.updatedAt.isAfter(newest)) newest = record.updatedAt;
      }
      pulled += remote.length;
      if (newest != null && newest != since) {
        await settings.saveSyncLastPulledAt(collection.path, newest);
      }
    }
    return SyncResult(pushed: pushed, pulled: pulled, applied: applied);
  }
}
