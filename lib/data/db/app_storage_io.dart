import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

import '../blob/file_blob_store.dart';
import 'app_storage_base.dart';

/// iOS / Android. Lives in Application Support (not Documents): app data, not user-facing
/// files, and included in the OS's device backups.
Future<AppStorage> openAppStorage() async {
  final support = await getApplicationSupportDirectory();
  final root = Directory(p.join(support.path, 'fishlog'));
  await root.create(recursive: true);

  final db = await databaseFactoryIo.openDatabase(
    p.join(root.path, 'fishlog.db'),
    version: kDatabaseVersion,
    onVersionChanged: onDatabaseVersionChanged,
  );
  final blobs = FileBlobStore(Directory(p.join(root.path, 'blobs')));
  return AppStorage(database: db, blobs: blobs);
}
