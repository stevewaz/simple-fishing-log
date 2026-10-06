import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_fishing_log/domain/astro/moon_phase.dart';
import 'package:simple_fishing_log/domain/astro/solunar_calculator.dart';
import 'package:simple_fishing_log/domain/catalog/species_catalog.dart';

/// Compares the Dart ports against output captured from the *original Swift code*
/// (see tool/swift_golden). Any drift in the astronomy or the length-weight table fails here.
void main() {
  final golden = jsonDecode(File('test/fixtures/swift_golden.json').readAsStringSync())
      as Map<String, dynamic>;

  DateTime fromEpoch(num seconds) =>
      DateTime.fromMicrosecondsSinceEpoch((seconds * 1e6).round(), isUtc: true);

  // The two implementations use different libm builds and the Swift side printed 6 decimals,
  // so allow a small tolerance rather than demanding bit equality.
  const tolerance = Duration(milliseconds: 5);

  void expectClose(DateTime? actual, num? expected, String reason) {
    if (expected == null) {
      expect(actual, isNull, reason: reason);
      return;
    }
    expect(actual, isNotNull, reason: reason);
    final diff = actual!.difference(fromEpoch(expected)).abs();
    expect(diff <= tolerance, isTrue, reason: '$reason differs by $diff');
  }

  group('SolunarCalculator matches the Swift original', () {
    final cases = (golden['solunar'] as List).cast<Map<String, dynamic>>();

    test('golden set is non-trivial', () => expect(cases.length, greaterThan(150)));

    for (final c in cases) {
      final label = '${c['loc']} ${fromEpoch(c['date'] as num).toIso8601String()}';
      test(label, () {
        final result = SolunarCalculator.calculate(
          fromEpoch(c['date'] as num),
          latitude: (c['lat'] as num).toDouble(),
          longitude: (c['lon'] as num).toDouble(),
        );

        if (c['none'] == true) {
          expect(result, isNull);
          return;
        }
        expect(result, isNotNull);
        expectClose(result!.transit, c['transit'] as num?, 'transit');
        expectClose(result.antitransit, c['antitransit'] as num?, 'antitransit');
        expectClose(result.moonrise, c['moonrise'] as num?, 'moonrise');
        expectClose(result.moonset, c['moonset'] as num?, 'moonset');

        final major = (c['major'] as List).cast<List>();
        final minor = (c['minor'] as List).cast<List>();
        expect(result.majorPeriods.length, major.length);
        expect(result.minorPeriods.length, minor.length);
        for (var i = 0; i < major.length; i++) {
          expectClose(result.majorPeriods[i].start, major[i][0] as num, 'major[$i].start');
          expectClose(result.majorPeriods[i].end, major[i][1] as num, 'major[$i].end');
        }
        for (var i = 0; i < minor.length; i++) {
          expectClose(result.minorPeriods[i].start, minor[i][0] as num, 'minor[$i].start');
          expectClose(result.minorPeriods[i].end, minor[i][1] as num, 'minor[$i].end');
        }
      });
    }
  });

  test('MoonPhase matches the Swift original over 171 samples', () {
    final samples = (golden['moon'] as List).cast<Map<String, dynamic>>();
    expect(samples.length, greaterThan(100));
    final mismatches = <String>[];
    for (final s in samples) {
      final t = (s['t'] as num).toDouble();
      final actual = MoonPhase.fromDate(
        DateTime.fromMillisecondsSinceEpoch((t * 1000).round(), isUtc: true),
      );
      if (actual.label != s['phase']) mismatches.add('t=$t expected ${s['phase']} got ${actual.label}');
    }
    expect(mismatches, isEmpty);
  });

  test('length-weight estimates match the Swift original', () {
    final samples = (golden['weight'] as List).cast<Map<String, dynamic>>();
    for (final s in samples) {
      final actual = SpeciesCatalog.estimatedWeightPounds(
        speciesId: s['id'] as String,
        lengthInches: (s['len'] as num).toDouble(),
      );
      expect(actual, closeTo((s['lb'] as num).toDouble(), 1e-6), reason: '${s['id']} ${s['len']}');
    }
  });
}
