import 'package:idb_shim/idb_browser.dart';
import 'package:sembast_web/sembast_web.dart';
import 'package:web/web.dart' as web;

import '../blob/blob_store.dart';
import 'app_storage_base.dart';

/// Web: IndexedDB for both documents and photo bytes.
Future<AppStorage> openAppStorage() async {
  _requestPersistentStorage();
  final db = await databaseFactoryWeb.openDatabase(
    'fishlog',
    version: kDatabaseVersion,
    onVersionChanged: onDatabaseVersionChanged,
  );
  return AppStorage(database: db, blobs: IdbBlobStore(idbFactoryBrowser));
}

/// A local-first web app's data lives only in the browser, and browsers may evict "best
/// effort" storage under pressure. Asking for persistent storage makes eviction a
/// user-initiated action instead of something that silently happens. Fire-and-forget: the
/// browser may decline, and the app works either way.
void _requestPersistentStorage() {
  try {
    web.window.navigator.storage.persist();
  } catch (_) {}
}
