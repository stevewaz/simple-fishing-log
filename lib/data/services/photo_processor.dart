import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:image/image.dart' as img;

class ProcessedPhoto {
  const ProcessedPhoto({
    required this.full,
    required this.thumb,
    required this.width,
    required this.height,
  });

  /// JPEG, long edge ≤ [PhotoProcessor.maxLongEdge].
  final Uint8List full;

  /// JPEG, long edge ≤ [PhotoProcessor.thumbnailLongEdge]. Stored separately so list rows
  /// never decode a full-size image.
  final Uint8List thumb;
  final int width;
  final int height;
}

/// Downscale + re-encode pipeline for catch photos. Hard caps are non-negotiable: unbounded
/// originals on hundreds of catches is how device storage — and, later, cloud quota — gets
/// exhausted.
///
/// Re-encoding also bakes in EXIF orientation and drops all metadata, which deliberately
/// strips GPS tags from shared photos.
abstract final class PhotoProcessor {
  static const int maxLongEdge = 2048;
  static const int thumbnailLongEdge = 256;
  static const int fullQuality = 82;
  static const int thumbQuality = 70;

  /// Returns null if the bytes aren't an image this decoder understands (e.g. HEIC on web).
  /// Runs on a background isolate where the platform has them, so a large photo doesn't
  /// freeze the UI.
  static Future<ProcessedPhoto?> process(Uint8List bytes) => compute(processSync, bytes);

  @visibleForTesting
  static ProcessedPhoto? processSync(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    var image = img.bakeOrientation(decoded);
    image = _fitLongEdge(image, maxLongEdge);
    final thumb = _fitLongEdge(image, thumbnailLongEdge);

    return ProcessedPhoto(
      full: Uint8List.fromList(img.encodeJpg(image, quality: fullQuality)),
      thumb: Uint8List.fromList(img.encodeJpg(thumb, quality: thumbQuality)),
      width: image.width,
      height: image.height,
    );
  }

  /// Only ever shrinks: a small image is returned untouched rather than upscaled.
  static img.Image _fitLongEdge(img.Image image, int maxEdge) {
    final longEdge = math.max(image.width, image.height);
    if (longEdge <= maxEdge) return image;
    final scale = maxEdge / longEdge;
    return img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }
}
