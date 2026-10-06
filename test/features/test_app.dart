import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_fishing_log/app/app.dart';
import 'package:simple_fishing_log/app/providers.dart';
import 'package:simple_fishing_log/data/app_data.dart';
import 'package:simple_fishing_log/data/services/conditions_provider.dart';
import 'package:simple_fishing_log/data/services/location_service.dart';
import 'package:simple_fishing_log/data/services/place_service.dart';
import 'package:simple_fishing_log/domain/models/conditions.dart';

import '../data/test_support.dart';

class FakeLocationService implements LocationService {
  FakeLocationService({this.accessState = LocationAccess.askable, this.fix});

  LocationAccess accessState;
  LocationFix? fix;
  int requests = 0;

  @override
  Future<LocationAccess> access() async => accessState;

  @override
  Future<LocationFix> currentLocation() async {
    requests++;
    final f = fix;
    if (f == null) throw const LocationException('Location permission was not granted.');
    accessState = LocationAccess.granted;
    return f;
  }

  @override
  Future<void> openSettings() async {}
}

class FakeConditions implements ConditionsProvider {
  FakeConditions([this.result]);

  Conditions? result;

  @override
  Future<Conditions?> currentConditions({
    required double latitude,
    required double longitude,
    required DateTime date,
  }) async =>
      result;
}

class TestHarness {
  TestHarness(this.data, this.clock, this.location, this.conditions);

  final AppData data;
  final TestClock clock;
  final FakeLocationService location;
  final FakeConditions conditions;
}

/// Opens an in-memory data layer (on the real event loop — sembast needs it) and pumps the
/// whole app over it with fake network/GPS services.
Future<TestHarness> pumpApp(
  WidgetTester tester, {
  Size size = const Size(420, 900),
  FakeLocationService? location,
  FakeConditions? conditions,
  Future<void> Function(AppData data)? seed,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  late AppData data;
  late TestClock clock;
  await tester.runAsync(() async {
    final opened = await openTestData(start: DateTime.now().toUtc());
    data = opened.$1;
    clock = opened.$3;
    if (seed != null) await seed(data);
  });

  final loc = location ?? FakeLocationService();
  final cond = conditions ?? FakeConditions();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      appDataProvider.overrideWithValue(data),
      locationServiceProvider.overrideWithValue(loc),
      conditionsProviderProvider.overrideWithValue(cond),
      placeServiceProvider.overrideWithValue(const NullPlaceService()),
      // No network and no cache directory (a platform channel) in widget tests.
      tileProviderOverrideProvider.overrideWithValue(
        NetworkTileProvider(cachingProvider: const DisabledMapCachingProvider()),
      ),
    ],
    child: const FishLogApp(),
  ));
  await settle(tester);
  return TestHarness(data, clock, loc, cond);
}

/// Lets streams, futures and animations finish.
///
/// The database lives on the real event loop while widget code runs in the test's fake-async
/// zone, so one UI-triggered write (a save, a delete) is a chain of steps that each need a
/// real turn *and* a pump to continue. Alternate the two enough times for the longest chain
/// (a catch delete also hides its photos) to drain.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 4)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
}

/// Runs [body] on the real event loop, then lets the UI catch up.
Future<void> real(WidgetTester tester, Future<void> Function() body) async {
  await tester.runAsync(body);
  await settle(tester);
}
