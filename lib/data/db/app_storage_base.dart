import 'package:sembast/sembast.dart';

import '../blob/blob_store.dart';

/// Everything the app persists locally: the document database and the photo blob store.
class AppStorage {
  const AppStorage({required this.database, required this.blobs});

  final Database database;
  final BlobStore blobs;

  Future<void> close() => database.close();
}

/// Bump when the stored document shapes change in a way that needs a migration, and add the
/// migration to [onDatabaseVersionChanged].
const int kDatabaseVersion = 1;

Future<void> onDatabaseVersionChanged(Database db, int oldVersion, int newVersion) async {
  // v1 is the first schema; nothing to migrate yet. Future migrations go here, keyed on
  // oldVersion, and run inside sembast's own upgrade transaction.
}
