import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'blob_store.dart';

/// File-backed [BlobStore] for iOS and Android. dart:io is not available on web, so this
/// lives in its own file and is only imported through `app_storage_io.dart`.
class FileBlobStore implements BlobStore {
  FileBlobStore(this.root);

  final Directory root;

  File _file(String key) => File(p.joinAll([root.path, ...validateBlobKey(key)]));

  @override
  Future<void> put(String key, Uint8List bytes) async {
    final file = _file(key);
    await file.parent.create(recursive: true);
    // Write-then-rename so a crash mid-write never leaves a truncated photo behind.
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
  }

  @override
  Future<Uint8List?> get(String key) async {
    final file = _file(key);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<bool> exists(String key) => _file(key).exists();

  @override
  Future<void> delete(String key) async {
    final file = _file(key);
    if (await file.exists()) await file.delete();
    // Best-effort cleanup of the now-empty per-photo directory.
    final dir = file.parent;
    if (dir.path != root.path && await dir.exists() && (await dir.list().isEmpty)) {
      await dir.delete();
    }
  }
}
