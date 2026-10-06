import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../data/app_data.dart';
import '../data/services/photo_processor.dart';
import '../domain/catalog/species_catalog.dart';
import '../domain/models/catch_entry.dart';
import '../domain/models/conditions.dart';
import '../domain/models/units.dart';

/// Development-only sample data, enabled with `--dart-define=FISHLOG_DEMO=true`. It never
/// runs in a normal build (the flag is a compile-time constant, so the code is tree-shaken
/// out), and it only seeds an *empty* log — it can't overwrite anyone's catches.
///
/// Used to exercise every screen with realistic data and to produce store screenshots.
const bool kSeedDemoData = bool.fromEnvironment('FISHLOG_DEMO');

Future<void> seedDemoData(AppData data, {DateTime? now}) async {
  if ((await data.catches.all()).isNotEmpty) return;
  final rng = math.Random(7);
  final today = (now ?? DateTime.now()).toUtc();
  final localNow = today.toLocal();

  // (name, base lat, base lon, water body)
  const spots = [
    ('Sandusky Bay', 41.4585, -82.7110, 'Lake Erie'),
    ('Kelleys Island shoal', 41.6040, -82.7040, 'Lake Erie'),
    ('Port Clinton reef', 41.5230, -82.9370, 'Lake Erie'),
    ('Maumee River ledge', 41.5000, -83.6500, 'Maumee River'),
  ];
  // (species, min lb, max lb, depth ft)
  const species = [
    ('Smallmouth Bass', 1.5, 5.2, 14.0),
    ('Walleye', 1.8, 7.5, 22.0),
    ('Yellow Perch', 0.3, 1.3, 30.0),
    ('Largemouth Bass', 1.0, 6.1, 8.0),
    ('Northern Pike', 3.0, 11.0, 12.0),
    ('Channel Catfish', 2.0, 9.0, 16.0),
    ('Steelhead', 4.0, 9.5, 10.0),
  ];
  const lures = ['Tube jig', 'Crankbait', 'Spinnerbait', 'Live bait — minnow', 'Soft plastic swimbait', 'Jerkbait'];
  const rods = ['Spinning rod & reel', 'Baitcasting rod & reel'];
  const lines = ['Braid with fluorocarbon leader', 'Fluorocarbon', 'Monofilament'];
  const techniques = ['Casting', 'Trolling', 'Jigging', 'Drift fishing'];
  const notes = [
    'Fish were stacked on the drop-off.',
    'Slow day until the wind picked up.',
    'Caught right at sunrise.',
    'Released after a quick photo.',
  ];

  final pastTrip = await data.trips.startSession(title: 'Kelleys Island weekend', waterBodyName: 'Lake Erie');
  final pastTripId = pastTrip.id;

  final entries = <CatchEntry>[];
  for (var i = 0; i < 36; i++) {
    final s = species[rng.nextInt(species.length)];
    final spot = spots[rng.nextInt(spots.length)];
    final daysAgo = i < 5 ? 0 : 1 + rng.nextInt(75);
    // Morning and evening bites dominate, as they do on the water. Built in *local* time
    // (that's the clock an angler thinks in) and never in the future.
    final hour = [5, 6, 7, 8, 9, 17, 18, 19, 20, 11, 13][rng.nextInt(11)];
    final local = DateTime(localNow.year, localNow.month, localNow.day - daysAgo, hour, rng.nextInt(60));
    final date = (daysAgo == 0 && local.isAfter(localNow)
            ? localNow.subtract(Duration(minutes: 20 + 25 * i))
            : local)
        .toUtc();
    final weight = s.$2 + rng.nextDouble() * (s.$3 - s.$2);
    final withConditions = i % 3 != 0;

    entries.add(CatchEntry(
      id: _uuid(i),
      date: date,
      speciesId: SpeciesCatalog.resolveId(s.$1),
      speciesName: s.$1,
      wasReleased: rng.nextDouble() < 0.8,
      wasFromBoat: rng.nextBool(),
      rating: 0,
      locationName: spot.$1,
      waterBodyName: spot.$4,
      latitude: spot.$2 + (rng.nextDouble() - 0.5) * 0.04,
      longitude: spot.$3 + (rng.nextDouble() - 0.5) * 0.05,
      depth: Measurement(s.$4 + rng.nextInt(8), LengthUnit.feet),
      weight: Measurement(double.parse(weight.toStringAsFixed(1)), MassUnit.pounds),
      length: Measurement(
        double.parse((weight < 1 ? 9 + weight * 4 : 12 + weight * 2.6).toStringAsFixed(1)),
        LengthUnit.inches,
      ),
      conditions: withConditions
          ? Conditions(
              source: ConditionsSource.manual,
              airTempC: 8 + rng.nextDouble() * 18,
              waterTempC: 10 + rng.nextDouble() * 10,
              windSpeedMS: rng.nextDouble() * 9,
              windDirectionDegrees: (rng.nextInt(16) * 22.5),
              waterConditions: ['calm', 'choppy', 'light chop', 'glassy'][rng.nextInt(4)],
            )
          : Conditions.none,
      gear: Gear(
        rodReel: rods[rng.nextInt(rods.length)],
        baitLure: lures[rng.nextInt(lures.length)],
        lineType: lines[rng.nextInt(lines.length)],
        technique: techniques[rng.nextInt(techniques.length)],
      ),
      notes: i % 5 == 0 ? notes[rng.nextInt(notes.length)] : null,
      tripId: (daysAgo >= 20 && daysAgo <= 22) ? pastTripId : null,
    ));
  }
  await data.catches.saveAll(entries);

  // An active session holding today's catches.
  final active = await data.trips.startSession(title: 'Erie morning', waterBodyName: 'Lake Erie');
  for (final e in entries.take(4)) {
    await data.catches.save(e.copyWith(tripId: active.id));
  }
  // Starting the active session ended the earlier one "now"; give it realistic dates.
  await data.trips.save(pastTrip.copyWith(
    startDate: today.subtract(const Duration(days: 22)),
    endDate: today.subtract(const Duration(days: 20)),
    isActive: false,
  ));

  // A handful of photos, drawn on the spot so there's no asset to ship.
  for (var i = 0; i < 8; i++) {
    final processed = await PhotoProcessor.process(_fakePhoto(i));
    if (processed != null) await data.photos.replaceForCatch(entries[i * 3].id, processed);
  }
}

String _uuid(int i) => '00000000-0000-4000-8000-${(1000 + i).toString().padLeft(12, '0')}';

/// A water-coloured gradient with a fish-ish silhouette: just enough to see thumbnails,
/// the hero header and the measuring tool working.
Uint8List _fakePhoto(int seed) {
  const w = 1200, h = 800;
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    final t = y / h;
    final c = img.ColorRgb8((20 + 30 * t).round(), (90 + 60 * (1 - t)).round(), (110 + 40 * (1 - t)).round());
    for (var x = 0; x < w; x++) {
      image.setPixel(x, y, c);
    }
  }
  final body = img.ColorRgb8(150 + seed * 8, 160 + seed * 5, 120 + seed * 3);
  img.fillCircle(image, x: 600, y: 400, radius: 230, color: body);
  img.fillRect(image, x1: 380, y1: 330, x2: 820, y2: 470, color: body);
  img.fillCircle(image, x: 380, y: 400, radius: 70, color: body);
  img.fillPolygon(
    image,
    vertices: [img.Point(780, 400), img.Point(1010, 250), img.Point(1010, 550)],
    color: body,
  );
  img.fillCircle(image, x: 440, y: 380, radius: 14, color: img.ColorRgb8(20, 30, 30));
  return Uint8List.fromList(img.encodeJpg(image, quality: 85));
}
