import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:simple_fishing_log/data/blob/file_blob_store.dart';

/// The native (iOS/Android) photo store, run against a real temp directory.
void main() {
  late Directory root;
  late FileBlobStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fishlog_blobs_');
    store = FileBlobStore(root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Uint8List bytes(List<int> v) => Uint8List.fromList(v);

  test('put / get / exists / delete', () async {
    expect(await store.get('photos/a/full.jpg'), isNull);
    expect(await store.exists('photos/a/full.jpg'), isFalse);

    await store.put('photos/a/full.jpg', bytes([1, 2, 3, 255]));
    expect(await store.get('photos/a/full.jpg'), bytes([1, 2, 3, 255]));
    expect(await store.exists('photos/a/full.jpg'), isTrue);

    await store.put('photos/a/full.jpg', bytes([9]));
    expect(await store.get('photos/a/full.jpg'), bytes([9]), reason: 'overwrite');

    await store.delete('photos/a/full.jpg');
    expect(await store.get('photos/a/full.jpg'), isNull);
  });

  test('writes are atomic: no temp file is left behind', () async {
    await store.put('photos/a/full.jpg', bytes([1, 2, 3]));
    final files = [for (final e in root.listSync(recursive: true)) if (e is File) p.basename(e.path)];
    expect(files, ['full.jpg']);
  });

  test('deleting the last blob removes the now-empty per-photo directory', () async {
    await store.put('photos/a/full.jpg', bytes([1]));
    await store.put('photos/a/thumb.jpg', bytes([2]));
    await store.delete('photos/a/full.jpg');
    expect(Directory(p.join(root.path, 'photos', 'a')).existsSync(), isTrue);
    await store.delete('photos/a/thumb.jpg');
    expect(Directory(p.join(root.path, 'photos', 'a')).existsSync(), isFalse);
  });

  test('deleting something that is not there is harmless', () async {
    await store.delete('photos/nope/full.jpg');
  });

  test('keys that could escape the root are refused, and nothing outside is touched', () async {
    final outside = File(p.join(root.parent.path, 'fishlog_escape_probe.txt'))..writeAsStringSync('keep');
    addTearDown(() {
      if (outside.existsSync()) outside.deleteSync();
    });

    for (final bad in ['../fishlog_escape_probe.txt', 'a/../../x', '/etc/passwd', 'a//b', '', 'a/..', r'a\b', '.hidden/x']) {
      expect(() => store.put(bad, bytes([1])), throwsArgumentError, reason: bad);
      expect(() => store.get(bad), throwsArgumentError, reason: bad);
      expect(() => store.delete(bad), throwsArgumentError, reason: bad);
    }
    expect(outside.readAsStringSync(), 'keep');
  });

  test('large payloads round-trip', () async {
    final big = Uint8List.fromList(List.generate(2 * 1024 * 1024, (i) => i % 251));
    await store.put('photos/big/full.jpg', big);
    expect(await store.get('photos/big/full.jpg'), big);
  });
}
