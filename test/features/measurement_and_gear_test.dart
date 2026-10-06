import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:simple_fishing_log/app/providers.dart' show rankGearSuggestions;
import 'package:simple_fishing_log/core/theme/app_theme.dart';
import 'package:simple_fishing_log/domain/models/units.dart';
import 'package:simple_fishing_log/features/edit/photo_measurement_screen.dart';

Uint8List png(int w, int h) => Uint8List.fromList(img.encodePng(img.Image(width: w, height: h)));

void main() {
  group('rankGearSuggestions (history → suggestions)', () {
    test('ranks by frequency, with recency breaking ties', () {
      // Newest first.
      final result = rankGearSuggestions(['Spoon', 'Tube jig', 'Tube jig', 'Crankbait', 'Tube jig', 'Crankbait']);
      expect(result.first, 'Tube jig'); // 3 uses
      expect(result[1], 'Crankbait'); // 2 uses
      expect(result[2], 'Spoon'); // 1 use
    });

    test('is case-insensitive and keeps the first-seen spelling', () {
      expect(rankGearSuggestions(['Braid', 'braid', 'BRAID', 'Mono']), ['Braid', 'Mono']);
    });

    test('ignores blanks and nulls, trims whitespace, and honours the limit', () {
      expect(rankGearSuggestions([null, '', '   ', ' Fly ']), ['Fly']);
      expect(rankGearSuggestions([for (var i = 0; i < 12; i++) 'Lure $i']).length, 5);
      expect(rankGearSuggestions([]), isEmpty);
    });

    test('among equal counts the more recent value wins', () {
      expect(rankGearSuggestions(['New', 'Old']).first, 'New');
    });
  });

  group('PhotoMeasurementScreen', () {
    // A 1000×500 photo letterboxed into the screen. Points are tapped by *image fraction*,
    // so the maths is checked independently of how the screen happens to be laid out.
    Future<Rect> pumpMeasure(WidgetTester tester, {String speciesId = 'largemouth-bass', void Function(MeasurementResult?)? onResult}) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  final r = await Navigator.of(context).push<MeasurementResult>(MaterialPageRoute(
                    builder: (_) => PhotoMeasurementScreen(
                      imageBytes: png(10, 5),
                      imageSize: const Size(1000, 500),
                      speciesId: speciesId,
                    ),
                  ));
                  onResult?.call(r);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return tester.getRect(find.byKey(const Key('measureArea')));
    }

    /// The measuring surface *now*: the layout shifts when the Custom field appears, so the
    /// position must be re-read rather than captured once.
    Rect area(WidgetTester t) => t.getRect(find.byKey(const Key('measureArea')));

    /// Screen position of a point given as a fraction of the *image* (not the box).
    Offset at(Rect box, double fx, double fy) {
      final fitted = applyBoxFit(BoxFit.contain, const Size(1000, 500), box.size).destination;
      final rect = Alignment.center.inscribe(fitted, box);
      return Offset(rect.left + fx * rect.width, rect.top + fy * rect.height);
    }

    testWidgets('walks through four taps and computes length from the reference', (tester) async {
      await pumpMeasure(tester);
      expect(find.textContaining('tap one end'), findsOneWidget);

      // Bill = 6.14 in. Reference spans 0.1→0.6 of the width = 500 px → 81.43 px/in.
      await tester.tapAt(at(area(tester), 0.1, 0.5));
      await tester.pump();
      expect(find.textContaining('other end'), findsOneWidget);
      await tester.tapAt(at(area(tester), 0.6, 0.5));
      await tester.pump();
      expect(find.textContaining('nose'), findsOneWidget);
      // Fish spans 0.1→0.4 = 300 px → 300 / (500/6.14) = 3.684 in.
      await tester.tapAt(at(area(tester), 0.1, 0.2));
      await tester.pump();
      expect(find.textContaining('tail'), findsOneWidget);
      await tester.tapAt(at(area(tester), 0.4, 0.2));
      await tester.pump();

      expect(find.textContaining('fine-tune'), findsOneWidget);
      expect(find.text('3.68 in'), findsOneWidget);
    });

    testWidgets('"Use" returns the length and a species-based weight estimate', (tester) async {
      MeasurementResult? result;
      await pumpMeasure(tester, onResult: (r) => result = r);

      await tester.tap(find.text('Custom'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '10'); // a 10-inch reference
      await tester.pump();

      // Reference 500 px = 10 in → 50 px/in. Fish 400 px → 8 in. (Different row heights too.)
      await tester.tapAt(at(area(tester), 0.1, 0.8));
      await tester.tapAt(at(area(tester), 0.6, 0.8));
      await tester.pump();
      await tester.tapAt(at(area(tester), 0.2, 0.3));
      await tester.tapAt(at(area(tester), 0.6, 0.3));
      await tester.pump();
      expect(find.text('8 in'), findsOneWidget);

      await tester.tap(find.text('Use'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.length.unit, LengthUnit.inches);
      expect(result!.length.value, 8.0);
      // Largemouth: 8³ / 1200 = 0.4267 lb.
      expect(result!.weight!.unit, MassUnit.pounds);
      expect(result!.weight!.value, closeTo(0.43, 0.01));
    });

    testWidgets('a diagonal fish is measured along its length, not its width', (tester) async {
      await pumpMeasure(tester);
      await tester.tap(find.text('Custom'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '10');
      await tester.pump();
      // Reference: horizontal, 500 px = 10 in. Fish: 300 px right and 200 px down in image
      // space → 360.56 px → 7.21 in. (A screen-space shortcut that ignored the image's own
      // aspect ratio would get this wrong.)
      await tester.tapAt(at(area(tester), 0.1, 0.9));
      await tester.tapAt(at(area(tester), 0.6, 0.9));
      await tester.pump();
      await tester.tapAt(at(area(tester), 0.1, 0.1));
      await tester.tapAt(at(area(tester), 0.4, 0.5));
      await tester.pump();
      expect(find.text('7.21 in'), findsOneWidget);
    });

    testWidgets('Use is disabled until all four points are placed; Reset starts over', (tester) async {
      await pumpMeasure(tester);
      TextButton use() => tester.widget<TextButton>(find.widgetWithText(TextButton, 'Use'));
      expect(use().onPressed, isNull);

      await tester.tapAt(at(area(tester), 0.1, 0.5));
      await tester.tapAt(at(area(tester), 0.6, 0.5));
      await tester.tapAt(at(area(tester), 0.1, 0.2));
      await tester.pump();
      expect(use().onPressed, isNull);
      await tester.tapAt(at(area(tester), 0.4, 0.2));
      await tester.pump();
      expect(use().onPressed, isNotNull);

      await tester.tap(find.text('Reset'));
      await tester.pump();
      expect(use().onPressed, isNull);
      expect(find.textContaining('tap one end'), findsOneWidget);
    });

    testWidgets('taps in the letterbox (outside the photo) are ignored', (tester) async {
      final box = await pumpMeasure(tester);
      // The image is 2:1 inside a tall box, so there is empty space above it.
      await tester.tapAt(Offset(box.center.dx, box.top + 5));
      await tester.pump();
      expect(find.textContaining('tap one end'), findsOneWidget, reason: 'still waiting for the first point');
    });

    testWidgets('a custom reference needs a length before it can measure', (tester) async {
      await pumpMeasure(tester);
      await tester.tap(find.text('Custom'));
      await tester.pump();
      await tester.tapAt(at(area(tester), 0.1, 0.5));
      await tester.tapAt(at(area(tester), 0.6, 0.5));
      await tester.tapAt(at(area(tester), 0.1, 0.2));
      await tester.tapAt(at(area(tester), 0.4, 0.2));
      await tester.pump();
      TextButton use() => tester.widget<TextButton>(find.widgetWithText(TextButton, 'Use'));
      expect(use().onPressed, isNull, reason: 'no known length entered yet');
    });
  });
}
