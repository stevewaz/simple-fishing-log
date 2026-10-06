// Saves or shares a file in whatever way suits the platform:
//   iOS/Android -> the system share sheet (Save to Files, AirDrop, Drive, mail, …)
//   web         -> a normal browser download
export 'file_exporter_stub.dart'
    if (dart.library.io) 'file_exporter_io.dart'
    if (dart.library.js_interop) 'file_exporter_web.dart';
