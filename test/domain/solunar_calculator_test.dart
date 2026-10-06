import 'package:flutter_test/flutter_test.dart';
import 'package:simple_fishing_log/domain/astro/solunar_calculator.dart';

DateTime d(int y, int m, int day, [int h = 12]) => DateTime.utc(y, m, day, h);

void main() {
  /// The explicit regression case: naive rise/set code often returns NaN at high latitude,
  /// which then crashes a formatter downstream. This must return null (or a day with null
  /// rise/set), never NaN or garbage.
  test('polar latitude in December does not produce garbage', () {
    for (var day = 1; day <= 28; day++) {
      final result = SolunarCalculator.calculate(d(2026, 12, day), latitude: 70.0, longitude: 25.0);
      if (result == null) continue;
      for (final v in [result.transit, result.antitransit, result.moonrise, result.moonset]) {
        if (v != null) expect(v.millisecondsSinceEpoch.toDouble().isFinite, isTrue);
      }
    }
  });

  test('mid-latitude produces at least one event on most days', () {
    var daysWithEvent = 0;
    for (var day = 1; day <= 28; day++) {
      if (SolunarCalculator.calculate(d(2026, 6, day), latitude: 41.5, longitude: -82.7) != null) {
        daysWithEvent++;
      }
    }
    // The lunar day (~24h50m) is longer than the calendar day, so some days legitimately
    // have no rise or no set — but the vast majority have at least one event.
    expect(daysWithEvent, greaterThanOrEqualTo(25));
  });

  test('major and minor periods are sorted ascending', () {
    final r = SolunarCalculator.calculate(d(2026, 6, 15), latitude: 41.5, longitude: -82.7)!;
    final major = [...r.majorPeriods]..sort((a, b) => a.start.compareTo(b.start));
    final minor = [...r.minorPeriods]..sort((a, b) => a.start.compareTo(b.start));
    expect(r.majorPeriods, major);
    expect(r.minorPeriods, minor);
  });

  test('periods are two hours wide, centered on the event', () {
    final r = SolunarCalculator.calculate(d(2026, 6, 15), latitude: 41.5, longitude: -82.7)!;
    final transit = r.transit!;
    final period = r.majorPeriods.firstWhere((p) => !p.start.isAfter(transit) && !transit.isBefore(p.start) && !p.end.isBefore(transit));
    expect(period.end.difference(period.start), const Duration(hours: 2));
    expect(transit.difference(period.start), const Duration(hours: 1));
  });

  /// Self-consistency (no external ephemeris needed): successive lunar transits at a fixed
  /// location are spaced roughly one lunar day (~24h50m) apart.
  test('consecutive transits are roughly one lunar day apart', () {
    final transits = [
      for (var day = 1; day <= 5; day++)
        SolunarCalculator.calculate(d(2026, 6, day), latitude: 41.5, longitude: -82.7)?.transit,
    ].whereType<DateTime>().toList();
    expect(transits.length, greaterThanOrEqualTo(4));
    for (var i = 1; i < transits.length; i++) {
      final gap = transits[i].difference(transits[i - 1]);
      expect(gap, greaterThan(const Duration(hours: 23)));
      expect(gap, lessThan(const Duration(hours: 26)));
    }
  });

  test('antitransit is roughly half a lunar day from transit', () {
    final r = SolunarCalculator.calculate(d(2026, 6, 15), latitude: 41.5, longitude: -82.7)!;
    final gap = r.antitransit!.difference(r.transit!).abs();
    expect(gap, greaterThan(const Duration(hours: 12)));
    expect(gap, lessThan(const Duration(hours: 13)));
  });

  group('dayStart (local-day windows)', () {
    // A US-Eastern angler asking at 9 pm local (01:00 UTC next day) used to get the *next*
    // UTC day's windows. With dayStart = local midnight the same moments must be found.
    test('events fall inside the requested 24h window', () {
      final localMidnight = DateTime.utc(2026, 6, 15, 4); // 00:00 EDT
      final r = SolunarCalculator.calculate(
        d(2026, 6, 16, 1),
        latitude: 41.5,
        longitude: -82.7,
        dayStart: localMidnight,
      )!;
      final end = localMidnight.add(const Duration(hours: 24));
      for (final e in [r.transit, r.moonrise, r.moonset]) {
        if (e == null) continue;
        expect(e.isBefore(localMidnight), isFalse);
        expect(e.isBefore(end), isTrue);
      }
    });

    test('default (UTC day) is unchanged when dayStart equals UTC midnight', () {
      final a = SolunarCalculator.calculate(d(2026, 6, 15), latitude: 41.5, longitude: -82.7)!;
      final b = SolunarCalculator.calculate(d(2026, 6, 15),
          latitude: 41.5, longitude: -82.7, dayStart: DateTime.utc(2026, 6, 15))!;
      expect(a.transit, b.transit);
      expect(a.moonrise, b.moonrise);
    });
  });
}
