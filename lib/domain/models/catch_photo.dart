import 'json_helpers.dart';

/// Metadata for one catch photo. The bytes live in the `BlobStore` under
/// [fullKey] / [thumbKey] — never inside the document database, which is held in memory
/// on web.
///
/// The storage layer supports many photos per catch (`sortIndex`); the UI currently
/// surfaces one, as the original did.
class CatchPhoto {
  const CatchPhoto({
    required this.id,
    required this.catchId,
    this.sortIndex = 0,
    this.capturedAt,
    this.caption,
    this.width = 0,
    this.height = 0,
  });

  final String id;
  final String catchId;
  final int sortIndex;
  final DateTime? capturedAt;
  final String? caption;
  final int width;
  final int height;

  /// Blob keys double as the future Firebase Storage object paths.
  String get fullKey => blobKeyFull(id);
  String get thumbKey => blobKeyThumb(id);

  Map<String, Object?> toJson() => compact({
        'id': id,
        'catchId': catchId,
        'sortIndex': sortIndex,
        'capturedAt': capturedAt == null ? null : writeDate(capturedAt!),
        'caption': caption,
        'width': width,
        'height': height,
      });

  factory CatchPhoto.fromJson(Map<String, Object?> json) => CatchPhoto(
        id: json['id'] as String,
        catchId: readString(json['catchId']) ?? '',
        sortIndex: readInt(json['sortIndex']) ?? 0,
        capturedAt: readDate(json['capturedAt']),
        caption: readString(json['caption']),
        width: readInt(json['width']) ?? 0,
        height: readInt(json['height']) ?? 0,
      );
}

String blobKeyFull(String photoId) => 'photos/$photoId/full.jpg';
String blobKeyThumb(String photoId) => 'photos/$photoId/thumb.jpg';
