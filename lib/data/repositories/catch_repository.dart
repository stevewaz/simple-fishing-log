import 'package:uuid/uuid.dart';

import '../../domain/models/catch_entry.dart';
import '../db/document_store.dart';
import 'photo_repository.dart';

class CatchRepository {
  CatchRepository(this._store, this._photos, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final DocumentStore<CatchEntry> _store;
  final PhotoRepository _photos;
  final Uuid _uuid;

  String newId() => _uuid.v4();

  /// Newest first.
  Stream<List<CatchEntry>> watchAll() => _store.watchAll().map(_newestFirst);
  Stream<CatchEntry?> watch(String id) => _store.watch(id);
  Future<CatchEntry?> get(String id) => _store.get(id);
  Future<List<CatchEntry>> all() async => _newestFirst(await _store.all());

  List<CatchEntry> _newestFirst(List<CatchEntry> entries) =>
      [...entries]..sort((a, b) => b.date.compareTo(a.date));

  Future<void> save(CatchEntry entry) => _store.put(entry);
  Future<void> saveAll(Iterable<CatchEntry> entries) => _store.putAll(entries);

  /// Soft delete: the catch and its photos disappear from every list but can be brought
  /// back with [restore] (this is what the Undo snackbar calls).
  Future<void> delete(String id) async {
    await _store.delete(id);
    await _photos.hideForCatch(id);
  }

  Future<void> restore(String id) async {
    await _store.restore(id);
    await _photos.unhideForCatch(id);
  }

  /// Whether this id exists at all, deleted or not — used by import so a catch the angler
  /// deleted comes back when they import a backup that still has it.
  Future<bool> existsLive(String id) => _store.exists(id);

  DocumentStore<CatchEntry> get store => _store;
}
