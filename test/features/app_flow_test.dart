import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_fishing_log/data/services/location_service.dart';
import 'package:simple_fishing_log/domain/models/catch_entry.dart';
import 'package:simple_fishing_log/domain/models/conditions.dart' show Gear;
import 'package:simple_fishing_log/domain/models/units.dart';

import 'test_app.dart';

CatchEntry catchOf(String id, String species, {double? lb, String? water, DateTime? date}) => CatchEntry(
      id: id,
      date: date ?? DateTime.now().toUtc().subtract(const Duration(hours: 2)),
      speciesId: species.toLowerCase().replaceAll(' ', '-'),
      speciesName: species,
      waterBodyName: water,
      weight: lb == null ? null : Measurement(lb, MassUnit.pounds),
    );

void main() {
  group('navigation shell', () {
    testWidgets('phone width uses a bottom bar with five tabs', (tester) async {
      await pumpApp(tester, size: const Size(400, 800));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      for (final label in ['Home', 'Log', 'Map', 'Trips', 'Insights']) {
        expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)), findsOneWidget);
      }
    });

    testWidgets('wide screens switch to a navigation rail', (tester) async {
      await pumpApp(tester, size: const Size(1200, 800));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('tabs switch and keep their own pages', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Trips')));
      await settle(tester);
      expect(find.text('No Trips Yet'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Insights')));
      await settle(tester);
      expect(find.text('Keep Logging'), findsOneWidget);
    });
  });

  group('Home', () {
    testWidgets('empty log invites the first catch and shows the moon', (tester) async {
      await pumpApp(tester);
      expect(find.text('Log your first catch to see it here.'), findsOneWidget);
      expect(find.text('Log a Catch'), findsOneWidget);
      expect(find.text('Moon'), findsOneWidget);
      expect(find.textContaining('Folklore, not forecast'), findsOneWidget);
    });

    testWidgets('does not prompt for location on its own; offers a button instead', (tester) async {
      final location = FakeLocationService(accessState: LocationAccess.askable, fix: const LocationFix(41.5, -82.7));
      await pumpApp(tester, location: location);
      expect(location.requests, 0, reason: 'opening the app must never throw a permission prompt');
      expect(find.text('Allow location access to see current conditions.'), findsOneWidget);

      await tester.tap(find.text('Allow Location').first);
      await settle(tester);
      expect(location.requests, 1);
      // With a position, solunar windows appear.
      expect(find.text('Major'), findsOneWidget);
    });

    testWidgets('fetches a fix automatically when permission is already granted', (tester) async {
      final location = FakeLocationService(accessState: LocationAccess.granted, fix: const LocationFix(41.5, -82.7));
      await pumpApp(tester, location: location);
      expect(location.requests, 1);
      expect(find.text('Major'), findsOneWidget);
      // No weather provider result → a calm message, not an error.
      expect(find.text("Weather isn't available right now."), findsOneWidget);
    });

    testWidgets('remembers the last position and shows solunar immediately next time', (tester) async {
      final location = FakeLocationService(accessState: LocationAccess.askable);
      await pumpApp(
        tester,
        location: location,
        seed: (data) => data.settings.saveLastLocation(41.5, -82.7),
      );
      expect(find.text('Major'), findsOneWidget, reason: 'from the remembered location, with no GPS');
      expect(location.requests, 0);
    });

    testWidgets('shows recent catches (at most five), newest first', (tester) async {
      await pumpApp(
        tester,
        seed: (data) async {
          for (var i = 0; i < 7; i++) {
            await data.catches.save(catchOf('c$i', 'Fish $i', date: DateTime.now().toUtc().subtract(Duration(hours: i + 1))));
          }
        },
      );
      expect(find.text('Fish 0'), findsOneWidget);
      expect(find.text('Fish 4'), findsOneWidget);
      expect(find.text('Fish 5'), findsNothing);
    });
  });

  group('Log', () {
    testWidgets('empty state offers to log a catch', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Log')));
      await settle(tester);
      expect(find.text('No Catches Yet'), findsOneWidget);
    });

    testWidgets('search filters by species and water, and can be cleared', (tester) async {
      await pumpApp(
        tester,
        seed: (data) async {
          await data.catches.save(catchOf('a', 'Walleye', water: 'Lake Erie'));
          await data.catches.save(catchOf('b', 'Northern Pike', water: 'Rideau Lake'));
        },
      );
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Log')));
      await settle(tester);
      expect(find.text('Walleye'), findsOneWidget);
      expect(find.text('Northern Pike'), findsOneWidget);

      await tester.enterText(find.byType(SearchBar), 'rideau');
      await settle(tester);
      expect(find.text('Walleye'), findsNothing);
      expect(find.text('Northern Pike'), findsOneWidget);

      await tester.enterText(find.byType(SearchBar), 'zzz');
      await settle(tester);
      expect(find.text('No Results'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear search'));
      await settle(tester);
      expect(find.text('Walleye'), findsOneWidget);
    });

    testWidgets('swipe to delete, then Undo brings the catch back', (tester) async {
      final h = await pumpApp(tester, seed: (data) => data.catches.save(catchOf('a', 'Walleye', lb: 3)));
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Log')));
      await settle(tester);

      await tester.drag(find.text('Walleye').last, const Offset(-600, 0));
      await settle(tester);
      expect(find.text('Walleye'), findsNothing);
      expect(find.text('Deleted Walleye'), findsOneWidget);
      expect(await tester.runAsync(() => h.data.catches.get('a')), isNull);

      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(find.text('Walleye'), findsOneWidget);
      expect(await tester.runAsync(() => h.data.catches.get('a')), isNotNull);
    });
  });

  group('New catch form', () {
    Future<void> openForm(WidgetTester tester) async {
      await tester.tap(find.text('Log a Catch').first);
      await settle(tester);
    }

    testWidgets('Save stays disabled until a species is entered', (tester) async {
      await pumpApp(tester);
      await openForm(tester);
      expect(find.text('New Catch'), findsOneWidget);

      FilledButton save() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));
      expect(save().onPressed, isNull);

      await tester.enterText(find.widgetWithText(TextField, 'Species'), 'Walleye');
      await tester.pump();
      expect(save().onPressed, isNotNull);
    });

    testWidgets('saves a catch with a comma-decimal weight and returns to the log', (tester) async {
      final h = await pumpApp(tester);
      await openForm(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Species'), 'Smallmouth Bass');
      await tester.enterText(find.widgetWithText(TextField, 'Weight'), '4,5');
      await tester.enterText(find.widgetWithText(TextField, 'Lake or river'), 'Lake Erie');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);

      final saved = (await tester.runAsync(() => h.data.catches.all()))!;
      expect(saved, hasLength(1));
      expect(saved.single.speciesId, 'smallmouth-bass'); // resolved from the catalog name
      expect(saved.single.weight, const Measurement(4.5, MassUnit.pounds));
      expect(saved.single.waterBodyName, 'Lake Erie');
      expect(find.text('New Catch'), findsNothing); // form closed
      expect(find.text('Smallmouth Bass'), findsOneWidget); // visible on Home's recent list
    });

    testWidgets('changing the unit stores the number in that unit', (tester) async {
      final h = await pumpApp(tester);
      await openForm(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Species'), 'Walleye');
      await tester.enterText(find.widgetWithText(TextField, 'Weight'), '2');
      await tester.tap(find.text('kg'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);
      expect((await tester.runAsync(() => h.data.catches.all()))!.single.weight, const Measurement(2.0, MassUnit.kilograms));
    });

    testWidgets('closing a form with unsaved changes asks before discarding', (tester) async {
      await pumpApp(tester);
      await openForm(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Species'), 'Walleye');
      await tester.pump(); // a real user always has a frame between typing and tapping
      await tester.tap(find.byTooltip('Cancel'));
      await settle(tester);
      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.text('Keep Editing'));
      await settle(tester);
      expect(find.text('New Catch'), findsOneWidget);

      await tester.tap(find.byTooltip('Cancel'));
      await settle(tester);
      await tester.tap(find.text('Discard'));
      await settle(tester);
      expect(find.text('New Catch'), findsNothing);
    });

    testWidgets('closing an untouched form needs no confirmation', (tester) async {
      await pumpApp(tester);
      await openForm(tester);
      await tester.tap(find.byTooltip('Cancel'));
      await settle(tester);
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('New Catch'), findsNothing);
    });

    testWidgets('new catches default to the active trip', (tester) async {
      final h = await pumpApp(tester, seed: (data) => data.trips.startSession(title: 'Erie morning'));
      await openForm(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Species'), 'Walleye');
      await tester.pump(); // let the Save button enable
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);
      final trip = (await tester.runAsync(() => h.data.trips.all()))!.single;
      expect((await tester.runAsync(() => h.data.catches.all()))!.single.tripId, trip.id);
    });

    testWidgets('gear suggestions come from the angler\'s own history', (tester) async {
      await pumpApp(
        tester,
        seed: (data) async {
          for (var i = 0; i < 3; i++) {
            await data.catches.save(catchOf('h$i', 'Walleye').copyWith(gear: const Gear(baitLure: 'Tube jig')));
          }
          await data.catches.save(catchOf('x', 'Walleye').copyWith(gear: const Gear(baitLure: 'Spoon')));
        },
      );
      // The floating "Log a Catch" button lives on the Log tab.
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Log')));
      await settle(tester);
      await tester.tap(find.text('Log a Catch').first);
      await settle(tester);
      await tester.dragUntilVisible(find.text('Bait or lure').first, find.byType(Scrollable).first, const Offset(0, -200));
      expect(find.widgetWithText(ActionChip, 'Tube jig'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'Spoon'), findsOneWidget);
    });
  });

  group('Catch detail', () {
    testWidgets('shows the catch and opens the editor prefilled', (tester) async {
      await pumpApp(
        tester,
        seed: (data) => data.catches.save(
          catchOf('a', 'Walleye', lb: 4.2, water: 'Lake Erie').copyWith(
            notes: 'Fish were stacked on the drop-off.',
            wasFromBoat: true,
          ),
        ),
      );
      await tester.tap(find.text('Walleye'));
      await settle(tester);

      expect(find.text('Catch Details'), findsOneWidget);
      expect(find.text('Lake Erie'), findsOneWidget);
      expect(find.text('4.2 lb'), findsOneWidget);
      expect(find.text('Fish were stacked on the drop-off.'), findsOneWidget);
      expect(find.text('Boat'), findsOneWidget);

      await tester.tap(find.text('Edit'));
      await settle(tester);
      expect(find.text('Edit Catch'), findsOneWidget);
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Species')).controller!.text, 'Walleye');
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Weight')).controller!.text, '4.2');
    });

    testWidgets('editing and saving updates the catch in place', (tester) async {
      final h = await pumpApp(tester, seed: (data) => data.catches.save(catchOf('a', 'Walleye', lb: 4.2)));
      await tester.tap(find.text('Walleye'));
      await settle(tester);
      await tester.tap(find.text('Edit'));
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Weight'), '5,1');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);

      final all = (await tester.runAsync(() => h.data.catches.all()))!;
      expect(all, hasLength(1));
      expect(all.single.id, 'a');
      expect(all.single.weight!.value, 5.1);
      expect(find.text('5.1 lb'), findsOneWidget); // detail screen reflects it live
    });

    testWidgets('a deleted catch shows a not-found message instead of crashing', (tester) async {
      final h = await pumpApp(tester, seed: (data) => data.catches.save(catchOf('a', 'Walleye')));
      await tester.tap(find.text('Walleye'));
      await settle(tester);
      await real(tester, () => h.data.catches.delete('a'));
      expect(find.text('Catch not found'), findsOneWidget);
    });

    testWidgets('delete from the detail screen confirms, closes, and offers Undo', (tester) async {
      final h = await pumpApp(tester, seed: (data) => data.catches.save(catchOf('a', 'Walleye')));
      await tester.tap(find.text('Walleye'));
      await settle(tester);
      await tester.tap(find.byTooltip('More'));
      await settle(tester);
      await tester.tap(find.text('Delete'));
      await settle(tester);
      expect(find.text('Delete this catch?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await settle(tester);

      expect(find.text('Catch Details'), findsNothing);
      expect(find.text('Deleted Walleye'), findsOneWidget);
      expect(await tester.runAsync(() => h.data.catches.get('a')), isNull);
      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(await tester.runAsync(() => h.data.catches.get('a')), isNotNull);
    });
  });

  group('Trips', () {
    testWidgets('start a session, see it Active, then end it', (tester) async {
      final h = await pumpApp(tester);
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Trips')));
      await settle(tester);
      await tester.tap(find.text('Start a Session'));
      await settle(tester);
      expect(find.text('Active'), findsOneWidget);

      await tester.tap(find.text('Active'));
      await settle(tester);
      await tester.tap(find.text('End Session'));
      await settle(tester);
      expect((await tester.runAsync(() => h.data.trips.all()))!.single.isActive, isFalse);
      expect(find.text('End Session'), findsNothing);
    });

    testWidgets('a trip can be named from its detail screen', (tester) async {
      final h = await pumpApp(tester, seed: (data) => data.trips.startSession());
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Trips')));
      await settle(tester);
      await tester.tap(find.text('Active'));
      await settle(tester);
      await tester.tap(find.byTooltip('More'));
      await settle(tester);
      await tester.tap(find.text('Edit'));
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Erie morning');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);
      expect((await tester.runAsync(() => h.data.trips.all()))!.single.title, 'Erie morning');
      expect(find.text('Erie morning'), findsWidgets);
    });

    testWidgets('deleting a trip asks first and keeps its catches', (tester) async {
      final h = await pumpApp(
        tester,
        seed: (data) async {
          final trip = await data.trips.startSession(title: 'Weekend');
          await data.catches.save(catchOf('a', 'Walleye').copyWith(tripId: trip.id));
        },
      );
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Trips')));
      await settle(tester);
      expect(find.textContaining('1 catch'), findsOneWidget);

      await tester.drag(find.text('Weekend'), const Offset(-600, 0));
      await settle(tester);
      expect(find.text('Delete "Weekend"?'), findsOneWidget);
      expect(find.textContaining('stays in your log'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await settle(tester);

      expect(await tester.runAsync(() => h.data.trips.all()), isEmpty);
      final kept = await tester.runAsync(() => h.data.catches.get('a'));
      expect(kept, isNotNull);
      expect(kept!.tripId, isNull);
    });

    testWidgets('cancelling the delete keeps the trip', (tester) async {
      final h = await pumpApp(tester, seed: (data) => data.trips.startSession(title: 'Weekend'));
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Trips')));
      await settle(tester);
      await tester.drag(find.text('Weekend'), const Offset(-600, 0));
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(find.text('Weekend'), findsOneWidget);
      expect(await tester.runAsync(() => h.data.trips.all()), hasLength(1));
    });
  });

  group('Insights', () {
    testWidgets('below the threshold it says how far along you are', (tester) async {
      await pumpApp(
        tester,
        seed: (data) async {
          for (var i = 0; i < 5; i++) {
            await data.catches.save(catchOf('c$i', 'Walleye'));
          }
        },
      );
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Insights')));
      await settle(tester);
      expect(find.text('Keep Logging'), findsOneWidget);
      expect(find.textContaining("you're at 5 so far"), findsOneWidget);
    });

    testWidgets('at twenty catches the five cards appear', (tester) async {
      await pumpApp(
        tester,
        seed: (data) async {
          for (var i = 0; i < 20; i++) {
            await data.catches.save(catchOf('c$i', i.isEven ? 'Walleye' : 'Pike', lb: 1.0 + i, water: 'Lake Erie'));
          }
        },
      );
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Insights')));
      await settle(tester);
      expect(find.text('Totals & Personal Bests'), findsOneWidget);
      expect(find.text('Total Catches'), findsOneWidget);
      expect(find.text('20'), findsWidgets);
      expect(find.text('Species Mix'), findsOneWidget);
      await tester.dragUntilVisible(find.text('Moon Phase'), find.byType(Scrollable).first, const Offset(0, -300));
      expect(find.text('Top Waters'), findsOneWidget);
      expect(find.text('Catches by Hour'), findsOneWidget);
    });
  });

  group('Map', () {
    testWidgets('with no located catches it still shows the map and explains the missing pin', (tester) async {
      await pumpApp(tester, seed: (data) => data.catches.save(catchOf('a', 'Walleye')));
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Map')));
      await settle(tester);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.textContaining('Catches with a saved location will appear here'), findsOneWidget);
    });
  });
}
