import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/constants.dart';
import '../../app/providers.dart';
import '../../core/platform/file_exporter.dart';
import '../../data/archive/archive_package.dart';

/// The Log screen's Import / Export flows, kept out of the widget so the screen stays about
/// the list.
abstract final class ArchiveActions {
  /// Builds a `.fishlog` archive and hands it to the platform: the share sheet on iOS and
  /// Android, a download on web.
  static Future<void> export(BuildContext context, WidgetRef ref) async {
    // iPad share sheets need an anchor rect, or they misplace or crash.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    final messenger = ScaffoldMessenger.of(context);

    try {
      final archive = await ref.read(appDataProvider).exporter(appVersion: kAppVersion).build();
      await exportFile(
        bytes: archive.bytes,
        fileName: archive.fileName,
        mimeType: 'application/zip',
        shareOrigin: origin,
      );
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't create the export.")));
    }
  }

  static Future<void> import(BuildContext context, WidgetRef ref) async {
    final List<PlatformFile> picked;
    try {
      // Any file type: a custom `.fishlog` extension greys files out in some iOS pickers.
      // Content is validated below, not trusted from the name.
      picked = await FilePicker.pickFiles(type: FileType.any, dialogTitle: 'Import Logbook');
    } catch (_) {
      if (context.mounted) await _alert(context, 'Import', "Couldn't open that file.");
      return;
    }
    if (picked.isEmpty || !context.mounted) return;

    // Validate before touching the log at all: container, manifest, version, size caps.
    final ArchivePackage package;
    try {
      final file = picked.first;
      final size = file.lengthSync();
      if (size != null && size > ArchiveLimits.maxArchiveBytes) {
        throw const ArchiveImportError(ArchiveImportErrorKind.tooLarge);
      }
      final bytes = await _withProgress(context, 'Reading file…', () async {
        final data = await file.readAsBytes();
        // Let the spinner paint before the synchronous unzip.
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return ArchivePackage.open(data);
      });
      package = bytes;
    } on ArchiveImportError catch (e) {
      if (context.mounted) await _alert(context, 'Import', e.message);
      return;
    } catch (_) {
      if (context.mounted) await _alert(context, 'Import', "That file doesn't look like a valid FishLog export.");
      return;
    }
    if (!context.mounted) return;

    final manifest = package.manifest;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Logbook?'),
        content: Text(
          'This file contains ${manifest.catchCount} ${manifest.catchCount == 1 ? 'catch' : 'catches'} '
          'and ${manifest.tripCount} ${manifest.tripCount == 1 ? 'trip' : 'trips'}. '
          'Catches already in your log are skipped, never overwritten.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Import')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final report = await _withProgress(
        context,
        'Importing…',
        () => ref.read(appDataProvider).importer().import(package),
      );
      if (context.mounted) await _alert(context, 'Import', report.summary);
    } catch (_) {
      if (context.mounted) await _alert(context, 'Import', "Import failed. Your existing log wasn't changed.");
    }
  }

  static Future<T> _withProgress<T>(BuildContext context, String message, Future<T> Function() task) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            spacing: 16,
            children: [
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
              Flexible(child: Text(message)),
            ],
          ),
        ),
      ),
    );
    try {
      return await task();
    } finally {
      navigator.pop();
    }
  }

  static Future<void> _alert(BuildContext context, String title, String message) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
}
