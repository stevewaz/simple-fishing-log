import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart';
import 'package:simple_fishing_log/data/db/document_store.dart';

import 'test_support.dart';

void main() {
  group('DocumentStore', () {
    test('put then get round-trips and stamps metadata', () async {
      final (data, _, clock) = await openTestData();
      final store = data.catches.store;

      await store.put(sampleCatch('a'));
      expect(await store.get('a'), sampleCatch('a'));

      final record = (await store.everything()).single;
      expect(record.updatedAt, clock());
      expect(record.isDeleted, isFalse);
      // Sync bookkeeping never leaks into the entity JSON.
      expect(record.data.keys.any((k) => k.startsWith('_')), isFalse);
    });

    test('delete is a tombstone: hidden from reads, present for sync', () async {
      final (data, _, clock) = await openTestData();
      final store = data.catches.store;
      await store.put(sampleCatch('a'));
      clock.advance(const Duration(minutes: 1));

      expect(await store.delete('a'), isTrue);

      expect(await store.get('a'), isNull);
      expect(await store.all(), isEmpty);
      expect(await store.exists('a'), isFalse);
      expect(await store.exists('a', includeDeleted: true), isTrue);

      final tombstone = (await store.everything()).single;
      expect(tombstone.isDeleted, isTrue);
      expect(tombstone.data['id'], 'a'); // data kept so a remote can still identify it
    });

    test('deleting a missing or already-deleted record is a no-op', () async {
      final (data, _, _) = await openTestData();
      final store = data.catches.store;
      expect(await store.delete('nope'), isFalse);
      await store.put(sampleCatch('a'));
      expect(await store.delete('a'), isTrue);
      expect(await store.delete('a'), isFalse);
    });

    test('restore undoes a delete', () async {
      final (data, _, clock) = await openTestData();
      final store = data.catches.store;
      await store.put(sampleCatch('a'));
      clock.advance(const Duration(minutes: 1));
      await store.delete('a');
      clock.advance(const Duration(minutes: 1));

      expect(await store.restore('a'), isTrue);
      expect(await store.get('a'), sampleCatch('a'));
      expect(await store.restore('a'), isFalse); // not deleted any more
    });

    test('writing a live value over a tombstone revives it', () async {
      final (data, _, clock) = await openTestData();
      final store = data.catches.store;
      await store.put(sampleCatch('a'));
      await store.delete('a');
      clock.advance(const Duration(minutes: 1));
      await store.put(sampleCatch('a', species: 'Pike'));
      expect((await store.get('a'))!.speciesName, 'Pike');
    });

    test('updatedAt is strictly increasing even with a frozen or backwards clock', () async {
      final (data, _, clock) = await openTestData();
      final store = data.catches.store;
      await store.put(sampleCatch('a'));
      final first = (await store.everything()).single.updatedAt;

      await store.put(sampleCatch('a', species: 'Pike')); // same instant
      final second = (await store.everything()).single.updatedAt;
      expect(second.isAfter(first), isTrue);

      clock.advance(const Duration(hours: -5)); // clock jumps back
      await store.put(sampleCatch('a', species: 'Bass'));
      final third = (await store.everything()).single.updatedAt;
      expect(third.isAfter(second), isTrue);
    });

    test('watchAll emits on change and excludes tombstones', () async {
      final (data, _, _) = await openTestData();
      final store = data.catches.store;

      final emissions = <List<String>>[];
      final sub = store.watchAll().listen((l) => emissions.add([for (final e in l) e.id]..sort()));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await store.put(sampleCatch('a'));
      await store.put(sampleCatch('b'));
      await store.delete('a');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(emissions.first, isEmpty);
      expect(emissions.last, ['b']);
    });

    test('watch(id) follows a single record', () async {
      final (data, _, _) = await openTestData();
      final store = data.catches.store;
      final seen = <String?>[];
      final sub = store.watch('a').listen((e) => seen.add(e?.speciesName));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await store.put(sampleCatch('a', species: 'Pike'));
      await store.put(sampleCatch('a', species: 'Bass'));
      await store.delete('a');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();
      expect(seen, [null, 'Pike', 'Bass', null]);
    });

    test('a corrupt record is skipped instead of failing the whole list', () async {
      final (data, _, _) = await openTestData();
      final store = data.catches.store;
      await store.put(sampleCatch('good'));
      // A document the decoder can't read (id isn't a String), written behind the typed API.
      await stringMapStoreFactory.store('catches').record('bad').put(data.storage.database, {'id': 42});
      expect((await store.all()).map((e) => e.id), ['good']);
    });

    test('putAll writes everything in one transaction', () async {
      final (data, _, _) = await openTestData();
      await data.catches.saveAll([for (var i = 0; i < 25; i++) sampleCatch('c$i')]);
      expect((await data.catches.all()).length, 25);
    });
  });

  group('sync seams', () {
    test('new and edited records are pending until marked synced', () async {
      final (data, _, clock) = await openTestData();
      final store = data.catches.store;
      await store.put(sampleCatch('a'));
      expect((await store.pendingChanges()).map((r) => r.id), ['a']);

      final pushed = (await store.pendingChanges()).single;
      await store.markSynced('a', upTo: pushed.updatedAt);
      expect(await store.pendingChanges(), isEmpty);

      clock.advance(const Duration(minutes: 1));
      await store.put(sampleCatch('a', species: 'Pike'));
      expect((await store.pendingChanges()).map((r) => r.id), ['a']);
    });

    test('an edit made while a push was in flight stays pending', () async {
      final (data, _, clock) = await openTestData();
      final store = data.catches.store;
      await store.put(sampleCatch('a'));
      final pushedVersion = (await store.pendingChanges()).single; // push starts here…

      clock.advance(const Duration(seconds: 5));
      await store.put(sampleCatch('a', species: 'Pike')); // …user edits during the push…

      await store.markSynced('a', upTo: pushedVersion.updatedAt); // …push acknowledged.
      final stillPending = await store.pendingChanges();
      expect(stillPending.map((r) => r.id), ['a']);
      expect(stillPending.single.data['speciesName'], 'Pike');
    });

    test('tombstones are pending so deletions propagate', () async {
      final (data, _, clock) = await openTestData();
      final store = data.catches.store;
      await store.put(sampleCatch('a'));
      await store.markSynced('a', upTo: (await store.pendingChanges()).single.updatedAt);
      clock.advance(const Duration(minutes: 1));
      await store.delete('a');
      final pending = await store.pendingChanges();
      expect(pending.single.isDeleted, isTrue);
    });

    test('applyRemote: a newer remote wins and is not re-pushed', () async {
      final (data, _, clock) = await openTestData();
      final store = data.catches.store;
      await store.put(sampleCatch('a'));
      clock.advance(const Duration(minutes: 10));

      final applied = await store.applyRemote(SyncRecord(
        id: 'a',
        data: sampleCatch('a', species: 'Remote Pike').toJson(),
        updatedAt: clock(),
      ));

      expect(applied, isTrue);
      expect((await store.get('a'))!.speciesName, 'Remote Pike');
      expect(await store.pendingChanges(), isEmpty);
    });

    test('applyRemote: a newer local edit wins (last-write-wins)', () async {
      final (data, _, clock) = await openTestData();
      final store = data.catches.store;
      final remoteTime = clock().add(const Duration(minutes: 1));
      clock.advance(const Duration(minutes: 5));
      await store.put(sampleCatch('a', species: 'Local')); // stamped 12:05, newer than remote

      final applied = await store.applyRemote(
        SyncRecord(id: 'a', data: sampleCatch('a', species: 'Remote').toJson(), updatedAt: remoteTime),
      );

      expect(applied, isFalse);
      expect((await store.get('a'))!.speciesName, 'Local');
      expect((await store.pendingChanges()).map((r) => r.id), ['a']); // still needs to push
    });

    test('applyRemote of an unknown record inserts it; of a tombstone hides it', () async {
      final (data, _, clock) = await openTestData();
      final store = data.catches.store;
      await store.applyRemote(SyncRecord(id: 'new', data: sampleCatch('new').toJson(), updatedAt: clock()));
      expect(await store.get('new'), sampleCatch('new'));

      clock.advance(const Duration(minutes: 1));
      await store.applyRemote(SyncRecord(
        id: 'new',
        data: sampleCatch('new').toJson(),
        updatedAt: clock(),
        deletedAt: clock(),
      ));
      expect(await store.get('new'), isNull);
    });

    test('applyRemote with an equal timestamp is a no-op', () async {
      final (data, _, _) = await openTestData();
      final store = data.catches.store;
      await store.put(sampleCatch('a'));
      final local = (await store.everything()).single;
      final applied = await store.applyRemote(
        SyncRecord(id: 'a', data: sampleCatch('a', species: 'Other').toJson(), updatedAt: local.updatedAt),
      );
      expect(applied, isFalse);
    });
  });

  group('purging tombstones', () {
    test('removes only old tombstones, never live records', () async {
      final (data, _, clock) = await openTestData();
      final store = data.catches.store;
      await store.put(sampleCatch('live'));
      await store.put(sampleCatch('old'));
      await store.delete('old');
      clock.advance(const Duration(days: 40));
      await store.put(sampleCatch('fresh'));
      await store.delete('fresh');

      final purged = await store.purgeTombstones(olderThan: clock().subtract(const Duration(days: 30)));

      expect(purged, ['old']);
      expect(await store.exists('live'), isTrue);
      expect(await store.exists('fresh', includeDeleted: true), isTrue); // recent: kept for Undo
      expect(await store.exists('old', includeDeleted: true), isFalse);
    });

    test('requireSynced keeps tombstones that have not been pushed yet', () async {
      final (data, _, clock) = await openTestData();
      final store = data.catches.store;
      await store.put(sampleCatch('a'));
      await store.delete('a');
      clock.advance(const Duration(days: 40));

      final cutoff = clock().subtract(const Duration(days: 30));
      expect(await store.purgeTombstones(olderThan: cutoff, requireSynced: true), isEmpty);

      final tombstone = (await store.everything()).single;
      await store.markSynced('a', upTo: tombstone.updatedAt);
      expect(await store.purgeTombstones(olderThan: cutoff, requireSynced: true), ['a']);
    });
  });
}
