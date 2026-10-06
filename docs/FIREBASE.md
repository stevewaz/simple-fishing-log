# Adding Firebase later

The app is local-first: the on-device database is the source of truth and nothing waits on a network.
Firebase is added as a **background mirror**, in three small steps. The seams already exist and are tested.

## What is already in place

| Seam | Where | Why it matters |
|---|---|---|
| Client-generated UUID ids | `CatchEntry.id`, `Trip.id`, `CatchPhoto.id` | Two offline devices can create records with no collisions and no server to hand out ids |
| Sync metadata beside every record | `DocumentStore` (`_updatedAt`, `_deletedAt`, `_syncedAt`) | Knows what changed since the last push |
| Soft deletes (tombstones) | `DocumentStore.delete` | A remote can't learn about a record that simply vanished |
| `pendingChanges()` / `markSynced()` / `applyRemote()` | `DocumentStore` | Everything a sync engine needs; last-write-wins on `_updatedAt` |
| `SyncGateway` (2 methods) + `SyncService` | `lib/data/sync/sync_service.dart` | The algorithm is done and tested against a fake remote |
| Photo bytes keyed `photos/<id>/{full,thumb}.jpg` | `BlobStore` | Those keys are the Firebase Storage object paths |
| `syncGatewayProvider` | `lib/app/providers.dart` | The one place to swap `NoopSyncGateway` for the real one |

## Steps

### 1. Create the project and configure the app

```sh
dart pub global activate flutterfire_cli
flutterfire configure            # generates lib/firebase_options.dart
flutter pub add firebase_core firebase_auth cloud_firestore firebase_storage
```

Initialise in `main()` **after** the local database is open, and don't block on it:

```dart
final data = AppData(await openAppStorage());
runApp(...);                                   // UI first — the app works with no network
unawaited(Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform));
```

### 2. Sign-in

Start with **anonymous auth** so data syncs from the first launch with no sign-up wall, then let the person
*link* Apple / Google / email to that same uid later (`linkWithCredential`) — their catches are never orphaned.
Everything the user has logged before signing in is already in the local database; the first sync simply pushes it.

### 3. Implement `SyncGateway`

Firestore layout: `users/{uid}/catches/{id}`, `users/{uid}/trips/{id}`, `users/{uid}/photos/{id}`. Documents are
the same flat JSON `toJson()` produces, plus `updatedAt` / `deletedAt`.

```dart
class FirestoreSyncGateway implements SyncGateway {
  FirestoreSyncGateway(this._db, this._uid);
  final FirebaseFirestore _db;
  final String _uid;

  CollectionReference<Map<String, dynamic>> _col(SyncCollection c) =>
      _db.collection('users').doc(_uid).collection(c.path);

  @override
  Future<void> push(SyncCollection collection, List<SyncRecord> records) async {
    // Firestore batches are capped at 500 writes.
    for (final chunk in _chunks(records, 400)) {
      final batch = _db.batch();
      for (final r in chunk) {
        batch.set(_col(collection).doc(r.id), {
          ...r.data,
          'updatedAt': Timestamp.fromDate(r.updatedAt),
          'deletedAt': r.deletedAt == null ? null : Timestamp.fromDate(r.deletedAt!),
          'serverTime': FieldValue.serverTimestamp(),   // see "Clock skew" below
        });
      }
      await batch.commit();                              // idempotent: safe to retry
    }
    // Photos: before acknowledging a photo record, upload its bytes with
    // firebase_storage to users/{uid}/<record.id's blob keys> (photos/<id>/full.jpg, thumb.jpg).
  }

  @override
  Future<List<SyncRecord>> pull(SyncCollection collection, {DateTime? since}) async {
    var q = _col(collection).orderBy('serverTime');
    if (since != null) q = q.where('serverTime', isGreaterThan: Timestamp.fromDate(since));
    final snap = await q.get();
    return [for (final d in snap.docs) _toRecord(d)];    // strip the bookkeeping fields back off
  }
}
```

Then override the provider and trigger syncs when it makes sense (app start, after a save, on reconnect):

```dart
syncGatewayProvider.overrideWithValue(FirestoreSyncGateway(FirebaseFirestore.instance, uid)),
// ...
await data.syncService(ref.read(syncGatewayProvider)).syncOnce();
```

Test the adapter the way `SyncService` is tested now — `test/data/services_and_sync_test.dart` has a `FakeRemote`;
run the same scenarios against the Firebase Emulator Suite.

## Decisions to make

* **Clock skew.** Conflict resolution is last-write-wins on the *device* clock (`updatedAt`). A phone with a wrong clock can
  win or lose unfairly. The sketch above pulls by Firestore's `serverTime` (immune to skew for *ordering pulls*); if skew
  matters to you, also compare on server time when resolving.
* **Photo bytes.** Upload full + thumbnail to Storage; consider uploading only on Wi-Fi. A new device can pull thumbnails
  eagerly and full images lazily — `photoBytesProvider` is already lazy.
* **Purging tombstones.** Today deleted rows are purged after 30 days regardless. Once a remote exists, call
  `purgeOldTombstones(requireSynced: true)` so a deletion is never discarded before it has been pushed.
* **Quota.** Photos are capped at 2048 px and re-encoded (~300–500 KB each), so storage grows predictably.
* **Offline persistence.** Leave Firestore's own cache **off** (`Settings(persistenceEnabled: false)`): the sembast database
  already is the offline store, and two caches would disagree.

## Security rules

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
  }
}
```

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /users/{uid}/{allPaths=**} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
  }
}
```

Validate document shape in the rules too (`request.resource.data.keys().hasOnly([...])`, size limits) before launch.
