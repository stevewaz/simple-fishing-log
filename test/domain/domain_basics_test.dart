import 'package:flutter_test/flutter_test.dart';
import 'package:simple_fishing_log/domain/astro/moon_phase.dart';
import 'package:simple_fishing_log/domain/catalog/gear_catalog.dart';
import 'package:simple_fishing_log/domain/catalog/species_catalog.dart';
import 'package:simple_fishing_log/domain/insights/insights_engine.dart';
import 'package:simple_fishing_log/domain/insights/map_date_range.dart';
import 'package:simple_fishing_log/domain/models/catch_entry.dart';
import 'package:simple_fishing_log/domain/models/conditions.dart';
import 'package:simple_fishing_log/domain/models/trip.dart';
import 'package:simple_fishing_log/domain/models/units.dart';

CatchSummary summary({
  required String species,
  int daysAgo = 0,
  int hour = 12,
  double? weight,
  String? water,
  String? id,
}) {
  final base = DateTime.utc(2026, 6, 15, hour);
  final date = base.subtract(Duration(days: daysAgo));
  return CatchSummary(
    id: id ?? 'id-${species.hashCode}-$daysAgo-$hour-${weight ?? 0}-${water ?? ''}',
    date: date,
    speciesName: species,
    weightInPounds: weight,
    waterBodyName: water,
    moonPhase: MoonPhase.fromDate(date),
  );
}

void main() {
  group('units', () {
    test('conversions use explicit factors', () {
      expect(const Measurement(1, MassUnit.kilograms).valueIn(MassUnit.pounds), closeTo(2.20462, 1e-4));
      expect(const Measurement(16, MassUnit.ounces).valueIn(MassUnit.pounds), closeTo(1, 1e-9));
      expect(const Measurement(12, LengthUnit.inches).valueIn(LengthUnit.feet), closeTo(1, 1e-9));
      expect(const Measurement(100, LengthUnit.centimeters).valueIn(LengthUnit.meters), closeTo(1, 1e-9));
    });

    test('unknown symbols resolve to a documented fallback, never an identity unit', () {
      expect(MassUnit.fromSymbol('stone'), MassUnit.pounds);
      expect(LengthUnit.fromSymbol('furlong'), LengthUnit.inches);
      expect(LengthUnit.fromSymbol(null, fallback: LengthUnit.feet), LengthUnit.feet);
      expect(MassUnit.fromSymbol('kg'), MassUnit.kilograms);
    });

    test('temperature and wind conversions', () {
      expect(celsiusToFahrenheit(100), 212);
      expect(fahrenheitToCelsius(32), 0);
      expect(metersPerSecondToMph(mphToMetersPerSecond(12)), closeTo(12, 1e-9));
    });
  });

  group('SpeciesCatalog', () {
    test('search is case-insensitive', () {
      expect(SpeciesCatalog.search('bass'), isNotEmpty);
      expect(SpeciesCatalog.search('BASS'), isNotEmpty);
    });

    test('empty query returns the full catalog', () {
      expect(SpeciesCatalog.search('').length, SpeciesCatalog.all.length);
    });

    test('custom id is slugified', () {
      expect(SpeciesCatalog.customId('Tiger Musky'), 'custom:tiger-musky');
    });

    test('resolveId maps catalog names (any case) back to catalog ids', () {
      expect(SpeciesCatalog.resolveId('smallmouth bass'), 'smallmouth-bass');
      expect(SpeciesCatalog.resolveId('  Walleye '), 'walleye');
      expect(SpeciesCatalog.resolveId('Tiger Musky Hybrid'), 'custom:tiger-musky-hybrid');
    });

    test('ids are unique', () {
      final ids = SpeciesCatalog.all.map((r) => r.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('habitat filter keeps "both" species and the matching habitat', () {
      final salt = SpeciesCatalog.search('', habitat: SpeciesHabitat.saltwater);
      expect(salt.any((r) => r.id == 'tarpon'), isTrue);
      expect(salt.any((r) => r.id == 'striped-bass'), isTrue); // habitat: both
      expect(salt.any((r) => r.id == 'walleye'), isFalse);
    });

    test('weight estimate: zero or negative length has none', () {
      expect(SpeciesCatalog.estimatedWeightPounds(speciesId: 'walleye', lengthInches: 0), isNull);
      expect(SpeciesCatalog.estimatedWeightPounds(speciesId: 'walleye', lengthInches: -3), isNull);
    });
  });

  group('GearCatalog', () {
    test('search filters and an empty query returns everything', () {
      expect(GearCatalog.search('', GearCatalog.lineTypes), GearCatalog.lineTypes);
      expect(GearCatalog.search('BRAID', GearCatalog.lineTypes).every((e) => e.toLowerCase().contains('braid')), isTrue);
    });
  });

  group('MoonPhase', () {
    final reference = DateTime.fromMillisecondsSinceEpoch(947182440 * 1000, isUtc: true);
    final synodic = Duration(microseconds: (MoonPhase.synodicMonthSeconds * 1e6).round());

    test('reference new moon is a new moon', () => expect(MoonPhase.fromDate(reference), MoonPhase.newMoon));

    test('half a synodic month later is a full moon', () {
      expect(MoonPhase.fromDate(reference.add(synodic ~/ 2)), MoonPhase.fullMoon);
    });

    test('a full synodic month later is a new moon again', () {
      expect(MoonPhase.fromDate(reference.add(synodic)), MoonPhase.newMoon);
    });

    test('a date before the reference does not crash and yields a valid phase', () {
      expect(MoonPhase.values, contains(MoonPhase.fromDate(reference.subtract(const Duration(days: 1)))));
    });

    test('cycleFraction is always in [0, 1)', () {
      for (var i = -500; i < 500; i += 7) {
        final f = MoonPhase.cycleFraction(reference.add(Duration(days: i)));
        expect(f, inInclusiveRange(0, 1));
        expect(f, lessThan(1));
      }
    });
  });

  group('InsightsEngine', () {
    DateTime utc(DateTime d) => d.toUtc();

    test('empty input produces an empty report', () {
      final report = InsightsEngine.compute([]);
      expect(report.totalCatches, 0);
      expect(report.personalBests, isEmpty);
      expect(report.speciesMix, isEmpty);
    });

    test('personal best picks the heaviest per species', () {
      final report = InsightsEngine.compute([
        summary(species: 'Bass', weight: 3.0),
        summary(species: 'Bass', weight: 5.5),
        summary(species: 'Bass', weight: 2.0),
        summary(species: 'Walleye', weight: 4.0),
      ]);
      expect(report.personalBests.firstWhere((b) => b.speciesName == 'Bass').weightInPounds, 5.5);
      // Sorted heaviest-first across species.
      expect(report.personalBests.first.speciesName, 'Bass');
    });

    test('species mix counts and sorts descending', () {
      final report = InsightsEngine.compute([
        summary(species: 'Bass', hour: 1), summary(species: 'Bass', hour: 2), summary(species: 'Bass', hour: 3),
        summary(species: 'Walleye', hour: 4), summary(species: 'Walleye', hour: 5),
        summary(species: 'Pike', hour: 6),
      ]);
      expect(report.speciesMix.first.speciesName, 'Bass');
      expect(report.speciesMix.first.count, 3);
      expect(report.speciesMix.length, 3);
    });

    test('hour-of-day distribution covers all 24 hours, zero-filled', () {
      final report = InsightsEngine.compute(
        [summary(species: 'Bass', hour: 6), summary(species: 'Bass', hour: 6, daysAgo: 1)],
        toZone: utc,
      );
      expect(report.hourOfDayDistribution.length, 24);
      expect(report.hourOfDayDistribution.firstWhere((h) => h.hour == 6).count, 2);
      expect(report.hourOfDayDistribution.firstWhere((h) => h.hour == 7).count, 0);
    });

    test('water-body leaderboard excludes null and empty names', () {
      final report = InsightsEngine.compute([
        summary(species: 'Bass', water: 'Lake Erie', hour: 1),
        summary(species: 'Bass', water: 'Lake Erie', hour: 2),
        summary(species: 'Bass', hour: 3),
        summary(species: 'Bass', water: '', hour: 4),
      ]);
      expect(report.waterBodyLeaderboard.length, 1);
      expect(report.waterBodyLeaderboard.first.waterBodyName, 'Lake Erie');
      expect(report.waterBodyLeaderboard.first.count, 2);
    });

    test('water-body leaderboard is capped at ten', () {
      final report = InsightsEngine.compute([
        for (var i = 0; i < 14; i++) summary(species: 'Bass', water: 'Lake $i', hour: i),
      ]);
      expect(report.waterBodyLeaderboard.length, 10);
    });

    test('moon-phase distribution covers all eight phases, zero-filled', () {
      final report = InsightsEngine.compute([summary(species: 'Bass')]);
      expect(report.moonPhaseDistribution.length, MoonPhase.values.length);
      expect(report.moonPhaseDistribution.fold<int>(0, (a, b) => a + b.count), 1);
    });

    test('personalBests carries the winning entry id', () {
      final lighter = summary(species: 'Bass', weight: 3.0, id: 'light');
      final heavier = summary(species: 'Bass', weight: 5.5, id: 'heavy');
      expect(InsightsEngine.personalBests([lighter, heavier]).firstWhere((b) => b.speciesName == 'Bass').entryId, 'heavy');
    });

    test('personalBests excludes entries with no weight', () {
      expect(InsightsEngine.personalBests([summary(species: 'Bass')]), isEmpty);
    });

    /// A 2 kg fish (~4.4 lb) must beat a 4 lb fish even though 2 < 4 as raw stored numbers.
    test('a heavier kilogram entry beats a lighter raw pound value', () {
      final pounds = CatchEntry(id: 'lb', date: DateTime.utc(2026), speciesName: 'Bass', weight: const Measurement(4.0, MassUnit.pounds));
      final kilos = CatchEntry(id: 'kg', date: DateTime.utc(2026), speciesName: 'Bass', weight: const Measurement(2.0, MassUnit.kilograms));
      final bests = InsightsEngine.personalBests([pounds, kilos].map(CatchSummary.fromEntry));
      expect(bests.firstWhere((b) => b.speciesName == 'Bass').entryId, 'kg');
    });

    test('an entry without a species name is summarized as "Unknown species"', () {
      expect(CatchSummary.fromEntry(CatchEntry(id: 'x', date: DateTime.utc(2026))).speciesName, 'Unknown species');
    });
  });

  group('MapDateRange', () {
    final reference = DateTime.utc(2026, 6, 15, 12);

    test('allTime contains every date', () {
      expect(MapDateRange.allTime.contains(reference.subtract(const Duration(days: 36500)), referenceDate: reference), isTrue);
    });

    test('thisYear excludes last year', () {
      expect(MapDateRange.thisYear.contains(reference, referenceDate: reference), isTrue);
      expect(MapDateRange.thisYear.contains(DateTime.utc(2025, 6, 15), referenceDate: reference), isFalse);
    });

    test('last30Days excludes 45 days ago and includes 10', () {
      expect(MapDateRange.last30Days.contains(reference.subtract(const Duration(days: 10)), referenceDate: reference), isTrue);
      expect(MapDateRange.last30Days.contains(reference.subtract(const Duration(days: 45)), referenceDate: reference), isFalse);
    });

    test('last7Days excludes 10 days ago and includes 3', () {
      expect(MapDateRange.last7Days.contains(reference.subtract(const Duration(days: 3)), referenceDate: reference), isTrue);
      expect(MapDateRange.last7Days.contains(reference.subtract(const Duration(days: 10)), referenceDate: reference), isFalse);
    });

    test('the boundary instant itself is inside the window', () {
      expect(MapDateRange.last7Days.contains(DateTime.utc(2026, 6, 8, 12), referenceDate: reference), isTrue);
      expect(MapDateRange.last7Days.contains(DateTime.utc(2026, 6, 8, 11, 59), referenceDate: reference), isFalse);
    });
  });

  group('JSON storage round trip', () {
    test('a fully populated catch survives toJson/fromJson', () {
      final entry = CatchEntry(
        id: 'a1',
        date: DateTime.utc(2026, 6, 15, 12, 30),
        speciesId: 'walleye',
        speciesName: 'Walleye',
        wasReleased: false,
        wasFromBoat: true,
        rating: 4,
        locationName: 'Sandusky Bay',
        waterBodyName: 'Lake Erie',
        latitude: 41.5,
        longitude: -82.7,
        depth: const Measurement(12, LengthUnit.feet),
        weight: const Measurement(2.8, MassUnit.pounds),
        length: const Measurement(21, LengthUnit.inches),
        conditions: Conditions(
          source: ConditionsSource.openMeteo,
          capturedAt: DateTime.utc(2026, 6, 15, 12, 31),
          airTempC: 22.5,
          waterTempC: 18,
          windSpeedMS: 4.2,
          windDirectionDegrees: 225,
          pressureHPa: 1015,
          pressureTrend: 'falling',
          weatherCondition: 'Partly cloudy',
          cloudCover: 0.4,
          waterConditions: 'choppy',
        ),
        gear: const Gear(rodReel: 'Spinning rod & reel', baitLure: 'Crankbait', lineType: 'Braid', technique: 'Trolling'),
        notes: '🎣 emoji + "quotes"',
        tripId: 't1',
      );
      expect(CatchEntry.fromJson(entry.toJson()), entry);
    });

    test('a minimal catch survives and omits null fields', () {
      final entry = CatchEntry(id: 'a2', date: DateTime.utc(2026, 1, 1));
      final json = entry.toJson();
      expect(json.containsKey('weightValue'), isFalse);
      expect(json.containsKey('notes'), isFalse);
      expect(CatchEntry.fromJson(json), entry);
    });

    test('reading tolerates missing fields and wrong types', () {
      final entry = CatchEntry.fromJson({'id': 'x', 'weightValue': 'not a number', 'rating': 'high'});
      expect(entry.weight, isNull);
      expect(entry.rating, 0);
      expect(entry.wasReleased, isTrue); // default
    });

    test('an unknown weight unit falls back instead of corrupting the value', () {
      final entry = CatchEntry.fromJson({'id': 'x', 'weightValue': 3.0, 'weightUnit': 'stone'});
      expect(entry.weight, const Measurement(3.0, MassUnit.pounds));
    });

    test('copyWith can clear nullable fields', () {
      final entry = CatchEntry(id: 'x', date: DateTime.utc(2026), tripId: 't', notes: 'n');
      final cleared = entry.copyWith(tripId: null);
      expect(cleared.tripId, isNull);
      expect(cleared.notes, 'n'); // untouched
    });

    test('trip round trips', () {
      final trip = Trip(
        id: 't1',
        startDate: DateTime.utc(2026, 6, 15, 8),
        title: 'Erie Morning',
        endDate: DateTime.utc(2026, 6, 15, 14),
        waterBodyName: 'Lake Erie',
        latitude: 41.5,
        longitude: -82.7,
        notes: 'windy',
        isActive: true,
      );
      expect(Trip.fromJson(trip.toJson()), trip);
    });

    test('conditions.hasData ignores bookkeeping-only fields', () {
      expect(const Conditions(source: ConditionsSource.manual).hasData, isFalse);
      expect(const Conditions(airTempC: 20).hasData, isTrue);
    });
  });
}
