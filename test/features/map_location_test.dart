import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:simple_fishing_log/core/widgets/map_widgets.dart';
import 'package:simple_fishing_log/data/services/location_service.dart';
import 'package:simple_fishing_log/domain/models/catch_entry.dart';

import 'test_app.dart';

CatchEntry located(String id, String species, double lat, double lon) => CatchEntry(
      id: id,
      date: DateTime.now().toUtc().subtract(const Duration(hours: 3)),
      speciesName: species,
      latitude: lat,
      longitude: lon,
    );

Future<void> openMapTab(WidgetTester tester) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Map')));
  await settle(tester);
}

void main() {
  const here = LocationFix(41.5, -82.7);

  group('Map: where you are', () {
    testWidgets('opening the map with permission already granted shows the pin, centred on you', (tester) async {
      await pumpApp(
        tester,
        location: FakeLocationService(accessState: LocationAccess.granted, fix: here),
        seed: (d) => d.catches.save(located('a', 'Walleye', 41.9, -82.0)), // catch far from here
      );
      await openMapTab(tester);

      expect(find.byType(MyLocationMarker), findsOneWidget);
      // The camera is on the angler, not fitted to the faraway catch.
      final map = tester.getCenter(find.byType(FlutterMap));
      final pin = tester.getCenter(find.byType(MyLocationMarker));
      expect((pin - map).distance, lessThan(4), reason: 'pin should sit at the middle of the map');
    });

    testWidgets('the first visit asks for permission, once, and then shows the pin', (tester) async {
      final location = FakeLocationService(accessState: LocationAccess.askable, fix: here);
      await pumpApp(tester, location: location, seed: (d) => d.catches.save(located('a', 'Walleye', 41.9, -82.0)));
      expect(location.requests, 0, reason: 'Home does not prompt');

      await openMapTab(tester);
      expect(location.requests, 1, reason: 'opening the Map tab is the angler asking for their location');
      expect(find.byType(MyLocationMarker), findsOneWidget);

      // Leaving and coming back must not prompt again.
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Home')));
      await settle(tester);
      await openMapTab(tester);
      expect(location.requests, 1);
    });

    testWidgets('with no catches at all, the map still opens on the pin', (tester) async {
      await pumpApp(tester, location: FakeLocationService(accessState: LocationAccess.granted, fix: here));
      await openMapTab(tester);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byType(MyLocationMarker), findsOneWidget);
      expect(find.text('No Mapped Catches'), findsNothing);
    });

    testWidgets('a late fix recentres the map from the catches view', (tester) async {
      // Permission is askable and the fix arrives only after the angler taps the button.
      final location = FakeLocationService(accessState: LocationAccess.blocked, fix: here);
      await pumpApp(tester, location: location, seed: (d) => d.catches.save(located('a', 'Walleye', 41.9, -82.0)));
      await openMapTab(tester);
      expect(find.byType(MyLocationMarker), findsNothing, reason: 'no permission → no pin');
      expect(find.byType(FlutterMap), findsOneWidget, reason: 'still shows the catches');

      // The angler fixes the permission in settings, then taps "My location".
      location.accessState = LocationAccess.granted;
      await tester.tap(find.byTooltip('My location'));
      await settle(tester);
      expect(find.byType(MyLocationMarker), findsOneWidget);
      final map = tester.getCenter(find.byType(FlutterMap));
      final pin = tester.getCenter(find.byType(MyLocationMarker));
      expect((pin - map).distance, lessThan(4));
    });

    testWidgets('a remembered (stale) position never gets a "you are here" pin', (tester) async {
      // Remembered from an earlier session, and the fresh fix fails.
      final location = FakeLocationService(accessState: LocationAccess.granted, fix: null);
      await pumpApp(
        tester,
        location: location,
        seed: (d) async {
          await d.settings.saveLastLocation(41.5, -82.7);
          await d.catches.save(located('a', 'Walleye', 41.9, -82.0));
        },
      );
      await openMapTab(tester);
      expect(find.byType(MyLocationMarker), findsNothing);
      expect(find.byType(FlutterMap), findsOneWidget);
    });

    testWidgets('no catches, permission not yet asked: Show My Location works', (tester) async {
      // Home (the first tab) leaves the state at "needs permission"; Map asks on open, so
      // simulate a deny first, then the angler grants it and tries again.
      final location = FakeLocationService(accessState: LocationAccess.askable, fix: null);
      await pumpApp(tester, location: location);
      await openMapTab(tester);
      expect(location.requests, 1, reason: 'asked once on open; the fake denies it');
      expect(find.text('No Mapped Catches'), findsOneWidget);
      expect(find.byType(FlutterMap), findsNothing);

      location.fix = here; // the angler grants permission
      await tester.tap(find.text('Show My Location'));
      await settle(tester);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byType(MyLocationMarker), findsOneWidget);
    });

    testWidgets('blocked permission explains itself instead of silently doing nothing', (tester) async {
      await pumpApp(
        tester,
        location: FakeLocationService(accessState: LocationAccess.blocked, fix: null),
        seed: (d) => d.catches.save(located('a', 'Walleye', 41.9, -82.0)),
      );
      await openMapTab(tester);
      await tester.tap(find.byTooltip('My location'));
      await settle(tester);
      expect(find.textContaining('Location is turned off'), findsOneWidget);
    });

    testWidgets('"Fit all catches" frames the catches and stays available', (tester) async {
      await pumpApp(
        tester,
        location: FakeLocationService(accessState: LocationAccess.granted, fix: here),
        seed: (d) async {
          await d.catches.save(located('a', 'Walleye', 41.9, -82.0));
          await d.catches.save(located('b', 'Pike', 41.95, -82.05));
        },
      );
      await openMapTab(tester);
      expect(find.byTooltip('Fit all catches'), findsOneWidget);
      await tester.tap(find.byTooltip('Fit all catches'));
      await settle(tester);
      // Both catch pins are now on screen (the angler's own pin may be off-screen).
      expect(find.byType(CatchMarker), findsNWidgets(2));
    });

    testWidgets('the pin is a blue dot, not a catch marker', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpApp(tester, location: FakeLocationService(accessState: LocationAccess.granted, fix: here));
      await openMapTab(tester);
      // flutter_map merges sibling semantics (the attribution joins the node), hence contains.
      expect(tester.getSemantics(find.byType(MyLocationMarker)).label, contains('You are here'));
      expect(find.byType(CatchMarker), findsNothing);
      semantics.dispose(); // must be released before the test ends
    });
  });

  group('map options', () {
    testWidgets('the initial centre is the angler when a fix exists', (tester) async {
      await pumpApp(tester, location: FakeLocationService(accessState: LocationAccess.granted, fix: here));
      await openMapTab(tester);
      final options = tester.widget<FlutterMap>(find.byType(FlutterMap)).options;
      expect(options.initialCenter, const LatLng(41.5, -82.7));
      expect(options.initialZoom, 13);
    });
  });
}
