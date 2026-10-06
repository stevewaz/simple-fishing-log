import 'package:sembast/sembast.dart';

/// A change as the sync layer sees it: the entity's own JSON plus the bookkeeping needed to
/// reconcile it with a remote copy. Deliberately free of any Firebase type.
class SyncRecord {
  const SyncRecord({
    required this.id,
    required this.data,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;

  /// The entity JSON exactly as `toJson()` produced it (no `_meta` keys).
  final Map<String, Object?> data;
  final DateTime updatedAt;

  /// Non-null for a tombstone: the record was deleted and the deletion must propagate.
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;
}

/// A typed, sync-ready collection on top of a sembast store.
///
/// Local-first rules baked in here, so no caller can forget them:
///  * every write stamps `_updatedAt` (strictly increasing per record);
///  * deletes are **tombstones** (`_deletedAt`), never hard deletes — a remote can't learn
///    about a record that simply vanished;
///  * `_syncedAt` records how far a record has been pushed; anything with
///    `_syncedAt < _updatedAt` is pending.
///
/// Sync metadata lives beside the entity JSON, under underscore keys, so domain models stay
/// free of it and `fromJson` simply ignores it.
class DocumentStore<T> {
  DocumentStore({
    required this._db,
    required String name,
    required this.fromJson,
    required this.toJson,
    required this.idOf,
    DateTime Function()? clock,
  })  : _store = stringMapStoreFactory.store(name),
        _clock = clock ?? DateTime.now;

  final Database _db;
  final StoreRef<String, Map<String, Object?>> _store;
  final DateTime Function() _clock;

  final T Function(Map<String, Object?> json) fromJson;
  final Map<String, Object?> Function(T value) toJson;
  final String Function(T value) idOf;

  static const _createdAt = '_createdAt';
  static const _updatedAt = '_updatedAt';
  static const _deletedAt = '_deletedAt';
  static const _syncedAt = '_syncedAt';

  static final _liveFilter = Filter.isNull(_deletedAt);

  DateTime _now() => _clock().toUtc();

  static DateTime? _readTime(Object? v) => v is String ? DateTime.tryParse(v)?.toUtc() : null;
  static String _writeTime(DateTime t) => t.toUtc().toIso8601String();

  T? _decode(RecordSnapshot<String, Map<String, Object?>>? snapshot) {
    if (snapshot == null) return null;
    try {
      return fromJson(snapshot.value);
    } catch (_) {
      // One unreadable record must not take the whole list down with it.
      return null;
    }
  }

  List<T> _decodeAll(List<RecordSnapshot<String, Map<String, Object?>>> snapshots) =>
      [for (final s in snapshots) ?_decode(s)];

  // ---- Reads (tombstones excluded) ----

  Future<T?> get(String id) async {
    final snapshot = await _store.record(id).getSnapshot(_db);
    if (snapshot == null || snapshot.value.containsKey(_deletedAt)) return null;
    return _decode(snapshot);
  }

  Future<List<T>> all() async =>
      _decodeAll(await _store.find(_db, finder: Finder(filter: _liveFilter)));

  Stream<List<T>> watchAll() => _store
      .query(finder: Finder(filter: _liveFilter))
      .onSnapshots(_db)
      .map(_decodeAll);

  Stream<T?> watch(String id) => _store.record(id).onSnapshot(_db).map((snapshot) {
        if (snapshot == null || snapshot.value.containsKey(_deletedAt)) return null;
        return _decode(snapshot);
      });

  Future<bool> exists(String id, {bool includeDeleted = false}) async {
    final snapshot = await _store.record(id).getSnapshot(_db);
    if (snapshot == null) return false;
    return includeDeleted || !snapshot.value.containsKey(_deletedAt);
  }

  // ---- Writes ----

  Future<void> put(T value, {DatabaseClient? client}) async {
    await _write(client ?? _db, [value]);
  }

  Future<void> putAll(Iterable<T> values, {DatabaseClient? client}) async {
    final list = values.toList();
    if (list.isEmpty) return;
    await _write(client ?? _db, list);
  }

  Future<void> _write(DatabaseClient client, List<T> values) async {
    Future<void> body(DatabaseClient txn) async {
      for (final value in values) {
        final id = idOf(value);
        final record = _store.record(id);
        final existing = await record.get(txn);
        final now = _now();
        final stamped = _strictlyAfter(now, _readTime(existing?[_updatedAt]));
        await record.put(
          txn,
          {
            ...toJson(value),
            _createdAt: existing?[_createdAt] ?? _writeTime(stamped),
            _updatedAt: _writeTime(stamped),
            // Writing a live value revives a tombstone.
            if (existing?[_syncedAt] != null) _syncedAt: existing![_syncedAt],
          },
        );
      }
    }

    if (client is Database) {
      await client.transaction(body);
    } else {
      await body(client);
    }
  }

  /// Per-record monotonic: two edits inside the same millisecond (or after a backwards clock
  /// step) must still order, or last-write-wins sync could pick the older one.
  DateTime _strictlyAfter(DateTime now, DateTime? previous) {
    if (previous == null || now.isAfter(previous)) return now;
    return previous.add(const Duration(milliseconds: 1));
  }

  /// Soft delete. Returns false if there was nothing live to delete.
  Future<bool> delete(String id, {DatabaseClient? client}) async {
    final c = client ?? _db;
    var changed = false;
    Future<void> body(DatabaseClient txn) async {
      final record = _store.record(id);
      final existing = await record.get(txn);
      if (existing == null || existing.containsKey(_deletedAt)) return;
      final stamped = _strictlyAfter(_now(), _readTime(existing[_updatedAt]));
      await record.put(txn, {
        ...existing,
        _deletedAt: _writeTime(stamped),
        _updatedAt: _writeTime(stamped),
      });
      changed = true;
    }

    if (c is Database) {
      await c.transaction(body);
    } else {
      await body(c);
    }
    return changed;
  }

  /// Undo of [delete]. Returns false if the record is gone or wasn't deleted.
  Future<bool> restore(String id, {DatabaseClient? client}) async {
    final c = client ?? _db;
    var changed = false;
    Future<void> body(DatabaseClient txn) async {
      final record = _store.record(id);
      final existing = await record.get(txn);
      if (existing == null || !existing.containsKey(_deletedAt)) return;
      final stamped = _strictlyAfter(_now(), _readTime(existing[_updatedAt]));
      final revived = {...existing}..remove(_deletedAt);
      revived[_updatedAt] = _writeTime(stamped);
      await record.put(txn, revived);
      changed = true;
    }

    if (c is Database) {
      await c.transaction(body);
    } else {
      await body(c);
    }
    return changed;
  }

  /// Hard-deletes tombstones older than [olderThan]. When [requireSynced] is true only those
  /// whose deletion has already been pushed are removed — flip that on once a remote exists.
  /// Returns the ids that were removed.
  Future<List<String>> purgeTombstones({required DateTime olderThan, bool requireSynced = false}) async {
    final cutoff = olderThan.toUtc();
    final candidates = await _store.find(_db, finder: Finder(filter: Filter.notNull(_deletedAt)));
    final doomed = <String>[];
    for (final snapshot in candidates) {
      final deletedAt = _readTime(snapshot.value[_deletedAt]);
      if (deletedAt == null || !deletedAt.isBefore(cutoff)) continue;
      if (requireSynced) {
        final syncedAt = _readTime(snapshot.value[_syncedAt]);
        if (syncedAt == null || syncedAt.isBefore(deletedAt)) continue;
      }
      doomed.add(snapshot.key);
    }
    if (doomed.isEmpty) return const [];
    await _store.records(doomed).delete(_db);
    return doomed;
  }

  // ---- Sync seams ----

  SyncRecord _toSyncRecord(RecordSnapshot<String, Map<String, Object?>> s) {
    final data = {
      for (final e in s.value.entries)
        if (!e.key.startsWith('_')) e.key: e.value,
    };
    return SyncRecord(
      id: s.key,
      data: data,
      updatedAt: _readTime(s.value[_updatedAt]) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      deletedAt: _readTime(s.value[_deletedAt]),
    );
  }

  /// Records (live or tombstoned) that changed since they were last pushed, oldest first.
  Future<List<SyncRecord>> pendingChanges() async {
    final all = await _store.find(_db);
    final pending = <SyncRecord>[];
    for (final s in all) {
      final updated = _readTime(s.value[_updatedAt]);
      final synced = _readTime(s.value[_syncedAt]);
      if (updated != null && (synced == null || synced.isBefore(updated))) {
        pending.add(_toSyncRecord(s));
      }
    }
    pending.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return pending;
  }

  /// Acknowledges a push of the version stamped [upTo]. If the record was edited again while
  /// the push was in flight its `_updatedAt` is newer, so it correctly stays pending.
  Future<void> markSynced(String id, {required DateTime upTo}) async {
    await _db.transaction((txn) async {
      final record = _store.record(id);
      final existing = await record.get(txn);
      if (existing == null) return;
      final current = _readTime(existing[_syncedAt]);
      if (current != null && !upTo.toUtc().isAfter(current)) return;
      await record.put(txn, {...existing, _syncedAt: _writeTime(upTo)});
    });
  }

  /// Merges a record received from a remote, last-write-wins on `updatedAt`. A local edit
  /// that is newer than the remote copy is kept (and will push). Returns whether the remote
  /// version was applied.
  Future<bool> applyRemote(SyncRecord remote) async {
    var applied = false;
    await _db.transaction((txn) async {
      final record = _store.record(remote.id);
      final existing = await record.get(txn);
      final localUpdated = _readTime(existing?[_updatedAt]);
      if (localUpdated != null && !remote.updatedAt.toUtc().isAfter(localUpdated)) return;
      await record.put(txn, {
        ...remote.data,
        _createdAt: existing?[_createdAt] ?? _writeTime(remote.updatedAt),
        _updatedAt: _writeTime(remote.updatedAt),
        _syncedAt: _writeTime(remote.updatedAt),
        if (remote.deletedAt != null) _deletedAt: _writeTime(remote.deletedAt!),
      });
      applied = true;
    });
    return applied;
  }

  /// Every record including tombstones, for diagnostics and tests.
  Future<List<SyncRecord>> everything() async =>
      [for (final s in await _store.find(_db)) _toSyncRecord(s)];
}
