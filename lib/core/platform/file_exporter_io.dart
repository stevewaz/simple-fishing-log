import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Writes [bytes] to a temp file and opens the system share sheet.
///
/// [shareOrigin] anchors the popover on iPad; share sheets there crash or misplace without
/// one, which is exactly the trap the Swift app documented around its toolbar ShareLink.
Future<void> exportFile({
  required Uint8List bytes,
  required String fileName,
  String mimeType = 'application/octet-stream',
  Rect? shareOrigin,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File(p.join(dir.path, p.basename(fileName)));
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: mimeType, name: p.basename(fileName))],
      sharePositionOrigin: shareOrigin,
    ),
  );
}
