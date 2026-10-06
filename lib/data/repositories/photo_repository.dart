import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../domain/models/catch_photo.dart';
import '../blob/blob_store.dart';
import '../db/document_store.dart';
import '../services/photo_processor.dart';

/// Photo metadata (document store) + bytes (blob store).
///
/// Ordering rule: bytes are written *before* the metadata that points at them, so a crash
/// can leave an orphan blob (harmless, purgeable) but never a record pointing at nothing.
class PhotoRepository {
  PhotoRepository(this._store, this._blobs, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final DocumentStore<CatchPhoto> _store;
  final BlobStore _blobs;
  final Uuid _uuid;

  Stream<List<CatchPhoto>> watchAll() => _store.watchAll();

  Future<List<CatchPhoto>> forCatch(String catchId) async {
    final all = await _store.all();
    return all.where((p) => p.catchId == catchId).toList()
      ..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
  }

  Future<Uint8List?> fullBytes(String photoId) => _blobs.get(blobKeyFull(photoId));
  Future<Uint8List?> thumbBytes(String photoId) => _blobs.get(blobKeyThumb(photoId));

  /// Makes [photo] the catch's one photo, replacing whatever was there. Replaced photos are
  /// removed outright (bytes included): editing a photo has no Undo.
  Future<CatchPhoto> replaceForCatch(String catchId, ProcessedPhoto photo, {DateTime? capturedAt}) async {
    final id = _uuid.v4();
    final record = CatchPhoto(
      id: id,
      catchId: catchId,
      sortIndex: 0,
      capturedAt: capturedAt,
      width: photo.width,
      height: photo.height,
    );
    await _blobs.put(record.fullKey, photo.full);
    await _blobs.put(record.thumbKey, photo.thumb);
    final previous = await forCatch(catchId);
    await _store.put(record);
    for (final old in previous) {
      await _removePhoto(old);
    }
    return record;
  }

  /// The user took the photo off the catch while editing.
  Future<void> removeForCatch(String catchId) async {
    for (final photo in await forCatch(catchId)) {
      await _removePhoto(photo);
    }
  }

  Future<void> _removePhoto(CatchPhoto photo) async {
    await _store.delete(photo.id);
    await _blobs.delete(photo.fullKey);
    await _blobs.delete(photo.thumbKey);
  }

  /// Deleting a catch hides its photos but keeps their bytes, so Undo can bring it all back.
  /// Bytes are reclaimed later by [purgeDeleted].
  Future<void> hideForCatch(String catchId) async {
    for (final photo in await forCatch(catchId)) {
      await _store.delete(photo.id);
    }
  }

  Future<void> unhideForCatch(String catchId) async {
    for (final record in await _store.everything()) {
      if (record.data['catchId'] != catchId || !record.isDeleted) continue;
      // A photo the user replaced or removed earlier is also a tombstone, but its bytes
      // were deleted on the spot — only bring back photos whose bytes survived.
      if (await _blobs.exists(blobKeyFull(record.id))) {
        await _store.restore(record.id);
      }
    }
  }

  /// Hard-removes photos hidden before [olderThan], bytes and all. Bytes are only deleted for
  /// records that were actually purged, so an unsynced photo keeps its bytes until it has
  /// been pushed.
  Future<int> purgeDeleted({required DateTime olderThan, bool requireSynced = false}) async {
    final purged = await _store.purgeTombstones(olderThan: olderThan, requireSynced: requireSynced);
    for (final id in purged) {
      await _blobs.delete(blobKeyFull(id));
      await _blobs.delete(blobKeyThumb(id));
    }
    return purged.length;
  }

  DocumentStore<CatchPhoto> get store => _store;
}
