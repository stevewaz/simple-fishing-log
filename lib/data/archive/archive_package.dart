import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'archive_dtos.dart';

/// The `.fishlog` container: a single zip file —
///
/// ```
/// manifest.json
/// catches.json
/// trips.json
/// photos/<catch-id>.jpg
/// ```
///
/// The Swift app shipped a directory *package* (an Apple concept). Android and web have no
/// such thing, so the container becomes a zip while the JSON inside is unchanged; an old
/// package folder imports fine once zipped.
enum ArchiveImportErrorKind { notAnArchive, manifestMissing, unsupportedFormatVersion, tooLarge }

class ArchiveImportError implements Exception {
  const ArchiveImportError(this.kind, [this.detail]);

  final ArchiveImportErrorKind kind;
  final Object? detail;

  String get message => switch (kind) {
        ArchiveImportErrorKind.notAnArchive => "That file isn't a FishLog export.",
        ArchiveImportErrorKind.manifestMissing => "That file doesn't look like a valid FishLog export.",
        ArchiveImportErrorKind.unsupportedFormatVersion =>
          'That export was made by a newer version of FishLog. Update the app to import it.',
        ArchiveImportErrorKind.tooLarge => 'That export is too large to import.',
      };

  @override
  String toString() => 'ArchiveImportError($kind${detail == null ? '' : ': $detail'})';
}

abstract final class ArchiveLimits {
  static const int maxArchiveBytes = 512 * 1024 * 1024;
  static const int maxJsonBytes = 100 * 1024 * 1024;
  static const int maxPhotoBytes = 25 * 1024 * 1024;
  static const int maxCatches = 50000;
  static const int maxTrips = 5000;
  static const int maxPhotos = 200000;
}

/// Photo filenames come from the archive, i.e. from whoever made it. They are only ever
/// used to look up an entry in the zip's in-memory index — never to build a filesystem
/// path — but they're still validated, so a hostile name like `../../etc/passwd` can't be
/// matched against anything.
bool isSafePhotoFileName(String name) =>
    name != '.' &&
    name != '..' &&
    RegExp(r'^[A-Za-z0-9._-]{1,128}$').hasMatch(name) &&
    RegExp(r'[A-Za-z0-9]').hasMatch(name);

/// A validated, opened archive. Opening never touches the app's data.
class ArchivePackage {
  ArchivePackage._(this.manifest, this._entries, this._prefix);

  final ArchiveManifest manifest;
  final Map<String, ArchiveFile> _entries;
  final String _prefix;

  /// Validates before anything else: container, manifest, format version, size caps.
  factory ArchivePackage.open(Uint8List bytes) {
    if (bytes.length > ArchiveLimits.maxArchiveBytes) {
      throw const ArchiveImportError(ArchiveImportErrorKind.tooLarge);
    }

    // The decoder is lenient and returns an empty archive for arbitrary bytes, so check the
    // zip signature ("PK") ourselves to give a precise error.
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
      throw const ArchiveImportError(ArchiveImportErrorKind.notAnArchive);
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw ArchiveImportError(ArchiveImportErrorKind.notAnArchive, e);
    }

    final entries = <String, ArchiveFile>{};
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final name = file.name.replaceAll('\\', '/');
      if (name.startsWith('__MACOSX/') || name.split('/').last.startsWith('._')) continue;
      entries[name] = file;
    }

    // Accept the files at the root, or inside one wrapping folder (zipping an old `.fishlog`
    // package folder produces `Name.fishlog/manifest.json`).
    String? prefix;
    for (final name in entries.keys) {
      final parts = name.split('/');
      if (parts.last == 'manifest.json' && parts.length <= 2) {
        prefix = parts.length == 2 ? '${parts.first}/' : '';
        break;
      }
    }
    if (prefix == null) throw const ArchiveImportError(ArchiveImportErrorKind.manifestMissing);

    final package = ArchivePackage._(
      ArchiveManifest(
        formatVersion: 0,
        generator: '',
        exportedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        catchCount: 0,
        tripCount: 0,
        photoCount: 0,
      ),
      entries,
      prefix,
    );

    final ArchiveManifest manifest;
    try {
      manifest = ArchiveManifest.fromJson(package._readJson('manifest.json'));
    } on ArchiveImportError {
      rethrow;
    } catch (e) {
      throw ArchiveImportError(ArchiveImportErrorKind.manifestMissing, e);
    }

    if (manifest.formatVersion > ArchiveManifest.currentFormatVersion) {
      throw ArchiveImportError(ArchiveImportErrorKind.unsupportedFormatVersion, manifest.formatVersion);
    }
    if (manifest.catchCount > ArchiveLimits.maxCatches ||
        manifest.tripCount > ArchiveLimits.maxTrips ||
        manifest.photoCount > ArchiveLimits.maxPhotos) {
      throw const ArchiveImportError(ArchiveImportErrorKind.tooLarge);
    }
    return ArchivePackage._(manifest, entries, prefix);
  }

  Object? _readJson(String name) {
    final file = _entries['$_prefix$name'];
    if (file == null) throw const ArchiveImportError(ArchiveImportErrorKind.manifestMissing);
    if (file.size > ArchiveLimits.maxJsonBytes) {
      throw const ArchiveImportError(ArchiveImportErrorKind.tooLarge);
    }
    final bytes = file.readBytes();
    if (bytes == null || bytes.length > ArchiveLimits.maxJsonBytes) {
      throw const ArchiveImportError(ArchiveImportErrorKind.tooLarge);
    }
    return jsonDecode(utf8.decode(bytes));
  }

  /// Raw record list, or empty if the file is absent. Records are decoded one at a time by
  /// the importer so a single corrupt entry doesn't reject the rest.
  List<Object?> _records(String name, int maxCount) {
    if (!_entries.containsKey('$_prefix$name')) return const [];
    final json = _readJson(name);
    if (json is! List) return const [];
    if (json.length > maxCount) throw const ArchiveImportError(ArchiveImportErrorKind.tooLarge);
    return json;
  }

  List<Object?> get catchRecords => _records('catches.json', ArchiveLimits.maxCatches);
  List<Object?> get tripRecords => _records('trips.json', ArchiveLimits.maxTrips);

  /// Bytes of a photo, or null if the name is unsafe, the entry is missing, or it's too big.
  Uint8List? photoBytes(String fileName) {
    if (!isSafePhotoFileName(fileName)) return null;
    final file = _entries['${_prefix}photos/$fileName'];
    if (file == null || file.size > ArchiveLimits.maxPhotoBytes) return null;
    final bytes = file.readBytes();
    if (bytes == null || bytes.isEmpty || bytes.length > ArchiveLimits.maxPhotoBytes) return null;
    return bytes;
  }
}

abstract final class ArchiveWriter {
  /// [photos] maps catch id → JPEG bytes.
  static Uint8List build({
    required List<CatchDto> catches,
    required List<TripDto> trips,
    required Map<String, Uint8List> photosByFileName,
    required String generator,
    DateTime? exportedAt,
  }) {
    final manifest = ArchiveManifest(
      formatVersion: ArchiveManifest.currentFormatVersion,
      generator: generator,
      exportedAt: exportedAt ?? DateTime.now().toUtc(),
      catchCount: catches.length,
      tripCount: trips.length,
      photoCount: photosByFileName.length,
    );

    String encode(Object value) => const JsonEncoder.withIndent('  ').convert(value);

    final archive = Archive()
      ..addFile(ArchiveFile.string('manifest.json', encode(manifest.toJson())))
      ..addFile(ArchiveFile.string('catches.json', encode([for (final c in catches) c.toJson()])))
      ..addFile(ArchiveFile.string('trips.json', encode([for (final t in trips) t.toJson()])));

    // Photos are already JPEG: storing them uncompressed saves time and gains nothing.
    for (final entry in photosByFileName.entries) {
      archive.addFile(ArchiveFile.noCompress('photos/${entry.key}', entry.value.length, entry.value));
    }
    return ZipEncoder().encodeBytes(archive);
  }
}
