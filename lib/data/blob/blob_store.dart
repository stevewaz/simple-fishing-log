import 'dart:typed_data';

import 'package:idb_shim/idb.dart';

/// Binary storage for photos, kept apart from the document database on purpose.
///
/// Sembast holds its whole database in memory (it is what backs the web build), so putting
/// 400 KB images in it would mean hundreds of megabytes resident. Blobs are read lazily,
/// one at a time, from files (native) or IndexedDB (web).
///
/// Keys look like `photos/<id>/full.jpg`; they double as the object paths a future Firebase
/// Storage adapter would upload to.
abstract interface class BlobStore {
  Future<void> put(String key, Uint8List bytes);
  Future<Uint8List?> get(String key);
  Future<bool> exists(String key);
  Future<void> delete(String key);
}

/// Keys are always built by the app, but they end up in file paths, so refuse anything that
/// could escape the store's root.
final RegExp _safeSegment = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');

List<String> validateBlobKey(String key) {
  final segments = key.split('/');
  if (segments.isEmpty ||
      segments.any((s) => !_safeSegment.hasMatch(s) || s == '.' || s == '..' || s.contains('..'))) {
    throw ArgumentError.value(key, 'key', 'Not a valid blob key');
  }
  return segments;
}

class MemoryBlobStore implements BlobStore {
  final Map<String, Uint8List> _data = {};

  int get length => _data.length;
  Iterable<String> get keys => _data.keys;

  @override
  Future<void> put(String key, Uint8List bytes) async {
    validateBlobKey(key);
    _data[key] = Uint8List.fromList(bytes);
  }

  @override
  Future<Uint8List?> get(String key) async {
    validateBlobKey(key);
    return _data[key];
  }

  @override
  Future<bool> exists(String key) async {
    validateBlobKey(key);
    return _data.containsKey(key);
  }

  @override
  Future<void> delete(String key) async {
    validateBlobKey(key);
    _data.remove(key);
  }
}

/// IndexedDB-backed store. Used on web with the browser factory; also runs on the VM with
/// idb_shim's in-memory factory, which is how it is unit tested.
class IdbBlobStore implements BlobStore {
  IdbBlobStore(this._factory, {this.name = 'fishlog_blobs'});

  final IdbFactory _factory;
  final String name;
  static const _storeName = 'blobs';

  Future<Database>? _db;

  Future<Database> _open() => _db ??= _factory.open(
        name,
        version: 1,
        onUpgradeNeeded: (e) {
          e.database.createObjectStore(_storeName);
        },
      );

  @override
  Future<void> put(String key, Uint8List bytes) async {
    validateBlobKey(key);
    final db = await _open();
    final txn = db.transaction(_storeName, idbModeReadWrite);
    await txn.objectStore(_storeName).put(bytes, key);
    await txn.completed;
  }

  @override
  Future<Uint8List?> get(String key) async {
    validateBlobKey(key);
    final db = await _open();
    final txn = db.transaction(_storeName, idbModeReadOnly);
    final value = await txn.objectStore(_storeName).getObject(key);
    await txn.completed;
    return _asBytes(value);
  }

  @override
  Future<bool> exists(String key) async {
    validateBlobKey(key);
    final db = await _open();
    final txn = db.transaction(_storeName, idbModeReadOnly);
    final count = await txn.objectStore(_storeName).count(key);
    await txn.completed;
    return count > 0;
  }

  @override
  Future<void> delete(String key) async {
    validateBlobKey(key);
    final db = await _open();
    final txn = db.transaction(_storeName, idbModeReadWrite);
    await txn.objectStore(_storeName).delete(key);
    await txn.completed;
  }

  /// Browsers hand binary values back in a few shapes depending on the engine.
  static Uint8List? _asBytes(Object? value) {
    if (value == null) return null;
    if (value is Uint8List) return value;
    if (value is ByteBuffer) return value.asUint8List();
    if (value is List) return Uint8List.fromList(value.cast<int>());
    return null;
  }
}
