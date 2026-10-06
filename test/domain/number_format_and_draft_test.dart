import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:simple_fishing_log/core/format/number_format.dart';
import 'package:simple_fishing_log/domain/models/conditions.dart';
import 'package:simple_fishing_log/domain/models/catch_entry.dart';
import 'package:simple_fishing_log/domain/models/units.dart';
import 'package:simple_fishing_log/features/edit/catch_draft.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('de');
  });

  group('parseDecimal', () {
    test('parses a plain decimal', () => expect(parseDecimal('4.2', locale: 'en_US'), 4.2));

    test('empty or whitespace parses to null', () {
      expect(parseDecimal(''), isNull);
      expect(parseDecimal('   '), isNull);
      expect(parseDecimal(null), isNull);
    });

    /// Regression for the original bug: `Double("2,5")` only understands "." and silently
    /// lost the fractional part in comma-decimal locales.
    test('German comma decimal parses correctly', () {
      expect(parseDecimal('2,5', locale: 'de'), 2.5);
      expect(double.tryParse('2,5'), isNull); // the naive approach this replaces
    });

    test('either separator is accepted in either locale for small numbers', () {
      expect(parseDecimal('2,5', locale: 'en_US'), 2.5);
      expect(parseDecimal('2.5', locale: 'de'), 2.5);
    });

    test('grouping vs decimal is resolved by position and locale', () {
      expect(parseDecimal('1,234.5', locale: 'en_US'), 1234.5);
      expect(parseDecimal('1.234,5', locale: 'de'), 1234.5);
      expect(parseDecimal('1,234', locale: 'en_US'), 1234); // looks like grouping in en
      expect(parseDecimal('1,234', locale: 'de'), 1.234); // decimal comma in de
      expect(parseDecimal('1.234.567', locale: 'de'), 1234567);
    });

    test('rejects garbage', () {
      expect(parseDecimal('abc'), isNull);
      expect(parseDecimal('1,2,3.4.5'), isNull);
      expect(parseDecimal('4.2 lb'), isNull);
    });

    test('accepts a leading sign and non-breaking spaces', () {
      expect(parseDecimal('-5.5', locale: 'en_US'), -5.5);
      expect(parseDecimal('1 234,5', locale: 'de'), 1234.5);
    });

    test('formatForInput round-trips through parseDecimal in both locales', () {
      for (final locale in ['en_US', 'de']) {
        for (final v in [0.0, 4.2, 12.0, 2.875, 1234.5]) {
          expect(parseDecimal(formatForInput(v, locale: locale), locale: locale), v, reason: '$locale $v');
        }
      }
    });
  });

  group('formatting', () {
    test('measurements keep the unit the angler entered', () {
      expect(formatMeasurement(const Measurement(4.2, MassUnit.pounds), locale: 'en_US'), '4.2 lb');
      expect(formatMeasurement(const Measurement(19, LengthUnit.inches), locale: 'en_US'), '19 in');
      expect(formatMeasurement(const Measurement(1200, LengthUnit.feet), locale: 'en_US'), '1,200 ft');
      expect(formatMeasurement(const Measurement(4.125, MassUnit.kilograms), locale: 'en_US'), '4.13 kg');
    });

    test('whole numbers round', () => expect(formatWholeNumber(71.6, locale: 'en_US'), '72'));
  });

  group('CatchDraft', () {
    CatchDraft draft() => CatchDraft(locale: 'en_US');

    test('round-trips weight and species', () {
      final d = draft()
        ..speciesName = 'Smallmouth Bass'
        ..weightText = '4.2'
        ..weightUnit = MassUnit.pounds;
      final entry = d.toEntry(newId: 'n1');
      expect(entry.speciesName, 'Smallmouth Bass');
      expect(entry.speciesId, 'smallmouth-bass');
      expect(entry.weight, const Measurement(4.2, MassUnit.pounds));
      expect(entry.id, 'n1');
    });

    test('a custom species gets a slug id', () {
      final entry = (draft()..speciesName = 'Tiger Musky Hybrid').toEntry(newId: 'n');
      expect(entry.speciesId, 'custom:tiger-musky-hybrid');
    });

    test('populating from an entry round-trips measurements', () {
      final original = CatchEntry(
        id: 'e1',
        date: DateTime.utc(2026, 6, 15, 12),
        speciesName: 'Walleye',
        weight: const Measurement(2.8, MassUnit.pounds),
      );
      final d = CatchDraft.fromEntry(original, locale: 'en_US');
      expect(d.speciesName, 'Walleye');
      expect(parseDecimal(d.weightText, locale: 'en_US'), 2.8);
      expect(d.weightUnit, MassUnit.pounds);
      expect(d.id, 'e1');
    });

    test('an existing id is kept; newId is ignored', () {
      final original = CatchEntry(id: 'keep', date: DateTime.utc(2026), speciesName: 'Pike');
      expect(CatchDraft.fromEntry(original).toEntry(newId: 'ignored').id, 'keep');
    });

    test('blank gear and notes become null, not empty strings', () {
      final d = draft()
        ..speciesName = 'Bluegill'
        ..rodReel = '   '
        ..notes = '';
      final entry = d.toEntry(newId: 'n');
      expect(entry.gear.rodReel, isNull);
      expect(entry.notes, isNull);
      expect(entry.waterBodyName, isNull);
    });

    test('unparseable numbers become null rather than zero', () {
      final entry = (draft()
            ..speciesName = 'Bass'
            ..weightText = 'heavy')
          .toEntry(newId: 'n');
      expect(entry.weight, isNull);
    });

    test('conditions are typed in °F / mph and stored in °C / m/s', () {
      final d = draft()
        ..speciesName = 'Bass'
        ..airTemperatureText = '77'
        ..waterTemperatureText = '68'
        ..windSpeedText = '10'
        ..windDirectionText = '225';
      final c = d.toEntry(newId: 'n').conditions;
      expect(c.airTempC, closeTo(25, 1e-9));
      expect(c.waterTempC, closeTo(20, 1e-9));
      expect(c.windSpeedMS, closeTo(4.4704, 1e-9));
      expect(c.windDirectionDegrees, 225);
      expect(c.source, ConditionsSource.manual);
    });

    test('no conditions typed stores none', () {
      final c = (draft()..speciesName = 'Bass').toEntry(newId: 'n').conditions;
      expect(c, Conditions.none);
      expect(c.source, ConditionsSource.none);
    });

    test('editing keeps conditions the form does not expose', () {
      final original = CatchEntry(
        id: 'e',
        date: DateTime.utc(2026),
        speciesName: 'Bass',
        conditions: Conditions(
          source: ConditionsSource.openMeteo,
          capturedAt: DateTime.utc(2026, 1, 1, 1),
          airTempC: 20,
          pressureHPa: 1012,
          pressureTrend: 'rising',
          weatherCondition: 'Clear sky',
          cloudCover: 0.1,
        ),
      );
      final d = CatchDraft.fromEntry(original, locale: 'en_US')..airTemperatureText = '50';
      final c = d.toEntry(newId: 'x').conditions;
      expect(c.airTempC, closeTo(10, 1e-9));
      expect(c.pressureHPa, 1012);
      expect(c.pressureTrend, 'rising');
      expect(c.weatherCondition, 'Clear sky');
      expect(c.cloudCover, 0.1);
      expect(c.source, ConditionsSource.openMeteo);
      expect(c.capturedAt, DateTime.utc(2026, 1, 1, 1));
    });

    test('clearing every typed condition on an edit drops them', () {
      final original = CatchEntry(
        id: 'e',
        date: DateTime.utc(2026),
        speciesName: 'Bass',
        conditions: const Conditions(source: ConditionsSource.manual, airTempC: 20),
      );
      final d = CatchDraft.fromEntry(original, locale: 'en_US')..airTemperatureText = '';
      expect(d.toEntry(newId: 'x').conditions, Conditions.none);
    });

    test('applyMeasurement writes plain editable text', () {
      final d = draft()
        ..applyMeasurement(
          length: const Measurement(19.25, LengthUnit.inches),
          weight: const Measurement(3.4, MassUnit.pounds),
        );
      expect(d.lengthText, '19.25');
      expect(d.weightText, '3.4');
      final entry = (d..speciesName = 'Bass').toEntry(newId: 'n');
      expect(entry.length, const Measurement(19.25, LengthUnit.inches));
    });

    test('applyConditions fills fields and stamps the provider', () {
      final d = draft()
        ..applyConditions(Conditions(
          source: ConditionsSource.openMeteo,
          capturedAt: DateTime.utc(2026, 6, 15),
          airTempC: 20,
          windSpeedMS: 4.4704,
          windDirectionDegrees: 90,
          pressureHPa: 1010,
          weatherCondition: 'Overcast',
        ));
      expect(d.airTemperatureText, '68');
      expect(d.windSpeedText, '10');
      final c = (d..speciesName = 'Bass').toEntry(newId: 'n').conditions;
      expect(c.source, ConditionsSource.openMeteo);
      expect(c.pressureHPa, 1010);
      expect(c.weatherCondition, 'Overcast');
    });

    test('canSave requires a species', () {
      expect(draft().canSave, isFalse);
      expect((draft()..speciesName = '  ').canSave, isFalse);
      expect((draft()..speciesName = 'Bass').canSave, isTrue);
    });

    test('the date is stored in UTC', () {
      final entry = (draft()
            ..speciesName = 'Bass'
            ..date = DateTime(2026, 6, 15, 12))
          .toEntry(newId: 'n');
      expect(entry.date.isUtc, isTrue);
    });
  });
}
