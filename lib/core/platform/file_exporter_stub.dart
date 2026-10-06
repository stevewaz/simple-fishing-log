import 'dart:typed_data';
import 'dart:ui' show Rect;

Future<void> exportFile({
  required Uint8List bytes,
  required String fileName,
  String mimeType = 'application/octet-stream',
  Rect? shareOrigin,
}) =>
    throw UnsupportedError('File export is not supported on this platform.');
