import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:sembast/sembast_memory.dart';
import 'package:simple_fishing_log/data/app_data.dart';
import 'package:simple_fishing_log/data/blob/blob_store.dart';
import 'package:simple_fishing_log/data/db/app_storage_base.dart';
import 'package:simple_fishing_log/data/services/photo_processor.dart';
import 'package:simple_fishing_log/domain/models/catch_entry.dart';

int _counter = 0;

/// A controllable clock for the in-memory data layer.
class TestClock {
  TestClock([DateTime? start]) : _now = start ?? DateTime.utc(2026, 6, 15, 12);

  DateTime _now;
  DateTime call() => _now;
  void advance(Duration d) => _now = _now.add(d);
}

/// A fully in-memory data layer whose notion of "now" the test controls.
Future<(AppData, MemoryBlobStore, TestClock)> openTestData({DateTime? start}) async {
  final clock = TestClock(start);
  final db = await newDatabaseFactoryMemory().openDatabase('test-${DateTime.now().microsecondsSinceEpoch}-${_counter++}');
  final blobs = MemoryBlobStore();
  final data = AppData(AppStorage(database: db, blobs: blobs), clock: clock.call);
  return (data, blobs, clock);
}

CatchEntry sampleCatch(String id, {String species = 'Walleye', DateTime? date}) => CatchEntry(
      id: id,
      date: date ?? DateTime.utc(2026, 6, 15, 12),
      speciesId: species.toLowerCase(),
      speciesName: species,
    );

/// A real, decodable JPEG of the given size.
Uint8List makeJpeg({int width = 64, int height = 48}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(30, 110, 119));
  return Uint8List.fromList(img.encodeJpg(image, quality: 80));
}

ProcessedPhoto makePhoto({int width = 64, int height = 48}) {
  final processed = PhotoProcessor.processSync(makeJpeg(width: width, height: height));
  return processed!;
}

const String uuidA = '11111111-1111-4111-8111-111111111111';
const String uuidB = '22222222-2222-4222-8222-222222222222';
const String uuidC = '33333333-3333-4333-8333-333333333333';
