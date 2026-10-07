import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:simple_fishing_log/core/widgets/map_widgets.dart';
import 'package:simple_fishing_log/core/widgets/noaa_chart_tile_provider.dart';
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

    testWidgets('no catches, permission not yet asked: the map still opens, and Show My Location works', (tester) async {
      // Home (the first tab) leaves the state at "needs permission"; Map asks on open, so
      // simulate a deny first, then the angler grants it and tries again.
      final location = FakeLocationService(accessState: LocationAccess.askable, fix: null);
      await pumpApp(tester, location: location);
      await openMapTab(tester);
      expect(location.requests, 1, reason: 'asked once on open; the fake denies it');
      // A denied or dismissed prompt must never leave the Map tab without a map.
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byType(MyLocationMarker), findsNothing);
      expect(find.textContaining('Turn on location'), findsOneWidget);
      expect(
        tester.getSize(find.textContaining('Turn on location')).height,
        lessThan(150),
        reason: 'the message must not be squeezed into a tall, narrow column beside its button',
      );

      location.fix = here; // the angler grants permission
      await tester.tap(find.text('Show My Location'));
      await settle(tester);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byType(MyLocationMarker), findsOneWidget);
      expect(find.textContaining('Turn on location'), findsNothing, reason: 'the notice goes away once located');
      // The camera moves from the whole-country view onto the angler.
      final map = tester.getCenter(find.byType(FlutterMap));
      final pin = tester.getCenter(find.byType(MyLocationMarker));
      expect((pin - map).distance, lessThan(4));
    });

    testWidgets('no catches and location blocked: the map still opens and says why there is no pin', (tester) async {
      await pumpApp(tester, location: FakeLocationService(accessState: LocationAccess.blocked, fix: null));
      await openMapTab(tester);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byType(MyLocationMarker), findsNothing);
      expect(find.textContaining('Location is turned off'), findsOneWidget);
      expect(find.text('Show My Location'), findsNothing, reason: 'asking again cannot help while blocked');
    });

    testWidgets('no catches and no fix: opens centred on the remembered position, without a pin', (tester) async {
      await pumpApp(
        tester,
        location: FakeLocationService(accessState: LocationAccess.granted, fix: null),
        seed: (d) => d.settings.saveLastLocation(41.5, -82.7),
      );
      await openMapTab(tester);
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(map.options.initialCenter.latitude, closeTo(41.5, 1e-6));
      expect(map.options.initialCenter.longitude, closeTo(-82.7, 1e-6));
      expect(find.byType(MyLocationMarker), findsNothing, reason: 'a remembered position is not "you are here"');
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

  group('Water chart style', () {
    // Tap the menu item itself (the whole row), not just its text.
    Finder menuItem(String label) => find.ancestor(
          of: find.text(label),
          matching: find.byType(CheckedPopupMenuItem<MapStyleOption>),
        );

    Future<void> chooseStyle(WidgetTester tester, String label) async {
      await tester.tap(find.byTooltip('Map style'));
      await settle(tester);
      await tester.tap(menuItem(label));
      await settle(tester);
    }

    testWidgets('is offered in the style menu and adds the NOAA layer on top of the base map', (tester) async {
      await pumpApp(
        tester,
        location: FakeLocationService(accessState: LocationAccess.granted, fix: here),
        seed: (d) => d.catches.save(located('a', 'Walleye', 41.46, -82.71)),
      );
      await openMapTab(tester);
      expect(find.byType(TileLayer), findsOneWidget, reason: 'standard = one base layer');

      await tester.tap(find.byTooltip('Map style'));
      await settle(tester);
      for (final label in ['Standard', 'Hybrid', 'Satellite', 'Water chart']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await tester.tap(menuItem('Water chart'));
      await settle(tester);

      expect(find.byType(TileLayer), findsNWidgets(3), reason: 'OSM base + NOAA (US) + CHS (Canada) chart overlays');
      expect(find.text('Depths in meters'), findsOneWidget);
    });

    testWidgets('Canadian waters get their own chart, asked for only at Canadian latitudes', (tester) async {
      await pumpApp(
        tester,
        location: FakeLocationService(accessState: LocationAccess.granted, fix: here),
      );
      await openMapTab(tester);
      await chooseStyle(tester, 'Water chart');

      final chs = tester.widgetList<TileLayer>(find.byType(TileLayer)).last;
      expect(chs.urlTemplate, NoaaChartTileProvider.chsEndpoint);
      expect(chs.minZoom, NoaaChartTileProvider.minZoom);
      final bounds = chs.tileBounds!;
      expect(bounds.contains(const LatLng(45.0, -81.5)), isTrue, reason: 'Georgian Bay, Lake Huron');
      expect(bounds.contains(const LatLng(41.7, -82.7)), isTrue, reason: 'Pelee Island, the southern tip');
      expect(bounds.contains(const LatLng(35.1, -90.0)), isFalse, reason: 'Memphis is nowhere near Canada');
    });

    testWidgets('the help sheet explains meters, shading, coverage and "not for navigation"', (tester) async {
      await pumpApp(
        tester,
        location: FakeLocationService(accessState: LocationAccess.granted, fix: here),
      );
      await openMapTab(tester);
      await chooseStyle(tester, 'Water chart');

      await tester.tap(find.text('Depths in meters'));
      await settle(tester);
      expect(find.text('Reading the water chart'), findsOneWidget);
      expect(find.text('Depths are in meters'), findsOneWidget);
      expect(find.textContaining('2.7 m'), findsOneWidget);
      expect(find.textContaining('8.9 ft'), findsOneWidget);
      expect(find.text('US and Canadian waters'), findsOneWidget);
      expect(find.textContaining('Ontario'), findsOneWidget);
      expect(find.textContaining('not for navigation'), findsOneWidget);
    });

    testWidgets('no zoom hint when already zoomed in; chips disappear on other styles', (tester) async {
      await pumpApp(
        tester,
        location: FakeLocationService(accessState: LocationAccess.granted, fix: here),
      );
      await openMapTab(tester); // centred on the angler at zoom 13
      await chooseStyle(tester, 'Water chart');
      expect(find.text('Zoom in for depths'), findsNothing);
      expect(find.text('Depths in meters'), findsOneWidget);

      await chooseStyle(tester, 'Satellite');
      expect(find.text('Depths in meters'), findsNothing);
      expect(find.byType(TileLayer), findsOneWidget);
    });

    testWidgets('zoomed far out, it says so and one tap zooms in until depths can show', (tester) async {
      // Two catches ~1000 km apart: the fitted view is far too wide for chart detail.
      await pumpApp(
        tester,
        location: FakeLocationService(accessState: LocationAccess.blocked, fix: null),
        seed: (d) async {
          await d.catches.save(located('a', 'Walleye', 41.9, -82.0));
          await d.catches.save(located('b', 'Pike', 47.0, -70.0));
        },
      );
      await openMapTab(tester);
      await chooseStyle(tester, 'Water chart');
      expect(find.text('Zoom in for depths'), findsOneWidget);

      await tester.tap(find.text('Zoom in for depths'));
      await settle(tester);
      expect(find.text('Zoom in for depths'), findsNothing);
    });

    testWidgets('on the opening view, the zoom hint goes to the latest catch, not the middle of the map', (tester) async {
      final now = DateTime.now().toUtc();
      CatchEntry at(String id, String species, double lat, double lon, Duration ago) =>
          CatchEntry(id: id, date: now.subtract(ago), speciesName: species, latitude: lat, longitude: lon);
      await pumpApp(
        tester,
        location: FakeLocationService(accessState: LocationAccess.blocked, fix: null),
        seed: (d) async {
          await d.catches.save(at('a', 'Walleye', 41.9, -82.0, const Duration(days: 30)));
          await d.catches.save(at('b', 'Pike', 47.0, -70.0, const Duration(hours: 3))); // the latest
        },
      );
      await openMapTab(tester);
      await chooseStyle(tester, 'Water chart');
      await tester.tap(find.text('Zoom in for depths'));
      await settle(tester);

      final map = tester.getCenter(find.byType(FlutterMap));
      final latest = find.byWidgetPredicate((w) => w is CatchMarker && w.label == 'Pike');
      expect(latest, findsOneWidget);
      expect((tester.getCenter(latest) - map).distance, lessThan(4), reason: 'centred on the latest catch');
    });

    testWidgets('with nothing to zoom to, the zoom hint asks where you are instead of zooming into nowhere',
        (tester) async {
      final location = FakeLocationService(accessState: LocationAccess.askable, fix: null);
      await pumpApp(tester, location: location);
      await openMapTab(tester); // asks once; the fake denies it
      await chooseStyle(tester, 'Water chart');
      expect(find.text('Zoom in for depths'), findsOneWidget, reason: 'the opening view is the whole country');
      expect(location.requests, 1);

      location.fix = here; // the angler grants permission this time
      await tester.tap(find.text('Zoom in for depths'));
      await settle(tester);
      expect(location.requests, 2);
      expect(find.byType(MyLocationMarker), findsOneWidget);
      expect(find.text('Zoom in for depths'), findsNothing);
    });

    testWidgets('once you have moved the map yourself, the zoom hint zooms in where you are looking', (tester) async {
      final location = FakeLocationService(accessState: LocationAccess.askable, fix: null);
      await pumpApp(tester, location: location);
      await openMapTab(tester);
      await chooseStyle(tester, 'Water chart');
      await tester.drag(find.byType(FlutterMap), const Offset(40, 0));
      await settle(tester);

      await tester.tap(find.text('Zoom in for depths'));
      await settle(tester);
      expect(location.requests, 1, reason: 'no new location request: the angler chose this view');
      expect(find.text('Zoom in for depths'), findsNothing);
    });
  });
}

