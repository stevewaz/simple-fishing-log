import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'data/app_data.dart';
import 'data/db/app_storage.dart';
import 'dev/demo_data.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Local-first: everything the app needs is opened from the device before the first frame.
  // There is no network dependency (and, until Firebase is added, no account) at startup.
  final data = AppData(await openAppStorage());
  if (kSeedDemoData) await seedDemoData(data);

  // Reclaim photos and rows from catches deleted long enough ago that Undo is moot.
  unawaited(data.purgeOldTombstones());

  runApp(ProviderScope(
    overrides: [appDataProvider.overrideWithValue(data)],
    child: const FishLogApp(),
  ));
}
