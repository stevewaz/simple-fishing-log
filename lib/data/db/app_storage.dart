// Picks the right storage backend for the platform at compile time:
//   native (iOS/Android) -> sembast file database + files on disk
//   web                  -> sembast on IndexedDB + IndexedDB blobs
export 'app_storage_base.dart';
export 'app_storage_stub.dart'
    if (dart.library.io) 'app_storage_io.dart'
    if (dart.library.js_interop) 'app_storage_web.dart';
