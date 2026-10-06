import 'dart:math' as math;

class SolunarPeriod {
  const SolunarPeriod(this.start, this.end);

  final DateTime start;
  final DateTime end;

  @override
  bool operator ==(Object other) => other is SolunarPeriod && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

class SolunarDay {
  const SolunarDay({
    this.transit,
    this.antitransit,
    this.moonrise,
    this.moonset,
    required this.majorPeriods,
    required this.minorPeriods,
  });

  final DateTime? transit;
  final DateTime? antitransit;
  final DateTime? moonrise;
  final DateTime? moonset;
  final List<SolunarPeriod> majorPeriods;
  final List<SolunarPeriod> minorPeriods;
}

/// Real lunar-position math — a low-precision Meeus-style series — deliberately NOT built on
/// `MoonPhase`'s mean-synodic approximation, which carries up to ~14 h of error.
///
/// Presented as folklore, not prediction: solunar theory has essentially no controlled
/// evidence behind it, but it's a beloved convention in this category.
abstract final class SolunarCalculator {
  static const Duration _periodHalfWidth = Duration(hours: 1);

  /// Half of the ~24h50m lunar day (time between successive transits). Approximated as a
  /// constant offset rather than solved for directly — solving the antitransit's own
  /// hour-angle-180 crossing would roughly double this algorithm's complexity for a
  /// folklore-tier feature.
  static const Duration _halfLunarDay = Duration(microseconds: 44712000000); // 12.42 h

  /// Events for the 24 hours starting at [dayStart].
  ///
  /// [dayStart] defaults to 00:00 UTC of [date]'s UTC day, matching the original app. Pass
  /// the *local* midnight to get "today" in the angler's own time zone — without it, a
  /// user in the Americas asking in the evening gets tomorrow's UTC day, i.e. windows that
  /// start hours after they were actually asking about.
  static SolunarDay? calculate(
    DateTime date, {
    required double latitude,
    required double longitude,
    DateTime? dayStart,
  }) {
    final utc = date.toUtc();
    final startOfDay = (dayStart ?? DateTime.utc(utc.year, utc.month, utc.day)).toUtc();

    final transit = _solveEvent(_Event.transit, startOfDay, latitude, longitude);
    final moonrise = _solveEvent(_Event.rise, startOfDay, latitude, longitude);
    final moonset = _solveEvent(_Event.set, startOfDay, latitude, longitude);
    final antitransit = transit?.add(_halfLunarDay);

    if (transit == null && moonrise == null && moonset == null) return null;

    final major = <SolunarPeriod>[
      if (transit != null) _period(transit),
      if (antitransit != null) _period(antitransit),
    ]..sort((a, b) => a.start.compareTo(b.start));
    final minor = <SolunarPeriod>[
      if (moonrise != null) _period(moonrise),
      if (moonset != null) _period(moonset),
    ]..sort((a, b) => a.start.compareTo(b.start));

    return SolunarDay(
      transit: transit,
      antitransit: antitransit,
      moonrise: moonrise,
      moonset: moonset,
      majorPeriods: major,
      minorPeriods: minor,
    );
  }

  static SolunarPeriod _period(DateTime around) =>
      SolunarPeriod(around.subtract(_periodHalfWidth), around.add(_periodHalfWidth));

  /// Meeus, "Astronomical Algorithms" Ch. 15 (rising/transit/setting), adapted for the
  /// Moon's mean parallax (h0 = +0.125°, vs. the Sun/stars' negative refraction-only value)
  /// and using standard positive-east longitude (Meeus's own convention is positive-west).
  static DateTime? _solveEvent(_Event kind, DateTime startOfDay, double latitude, double longitude) {
    const h0 = 0.125;
    final phi = latitude;
    final jd0 = _julianDay(startOfDay);
    final theta0 = _meanSiderealTimeDegrees(jd0);
    final (ra0, dec0) = _equatorialPosition(jd0);

    final m0 = _normalizedFraction((ra0 - longitude - theta0) / 360);

    double m;
    switch (kind) {
      case _Event.transit:
        m = m0;
      case _Event.rise:
      case _Event.set:
        final cosH0 = (_sinDeg(h0) - _sinDeg(phi) * _sinDeg(dec0)) / (_cosDeg(phi) * _cosDeg(dec0));
        // Never rises or never sets today — also what keeps polar latitudes from yielding NaN.
        if (cosH0 < -1 || cosH0 > 1 || cosH0.isNaN) return null;
        final h0Angle = _acosDeg(cosH0);
        m = kind == _Event.rise
            ? _normalizedFraction(m0 - h0Angle / 360)
            : _normalizedFraction(m0 + h0Angle / 360);
    }

    // Two passes, as Meeus recommends: recompute the Moon's position at the improved time
    // estimate rather than trusting the midnight value.
    for (var i = 0; i < 2; i++) {
      final jd = jd0 + m;
      final theta = _normalizeDegrees(theta0 + 360.985647 * m);
      final (ra, dec) = _equatorialPosition(jd);
      final localHourAngle = _normalizeSigned(theta + longitude - ra);

      switch (kind) {
        case _Event.transit:
          m -= localHourAngle / 360;
        case _Event.rise:
        case _Event.set:
          final altitude = _asinDeg(
              _sinDeg(phi) * _sinDeg(dec) + _cosDeg(phi) * _cosDeg(dec) * _cosDeg(localHourAngle));
          final denominator = 360 * _cosDeg(dec) * _cosDeg(phi) * _sinDeg(localHourAngle);
          if (denominator.abs() <= 0.000001) continue;
          m += (altitude - h0) / denominator;
      }
    }

    if (!m.isFinite) return null;
    return startOfDay.add(Duration(microseconds: (m * 86400 * 1e6).round()));
  }

  // MARK: Low-precision lunar position (Meeus, abbreviated dominant-term series)

  static (double, double) _equatorialPosition(double jd) {
    final t = (jd - 2451545.0) / 36525.0;

    final lPrime = _normalizeDegrees(218.3164477 + 481267.88123421 * t);
    final d = _normalizeDegrees(297.8501921 + 445267.1114034 * t);
    final m = _normalizeDegrees(357.5291092 + 35999.0502909 * t);
    final mPrime = _normalizeDegrees(134.9633964 + 477198.8675055 * t);
    final f = _normalizeDegrees(93.2720950 + 483202.0175233 * t);

    final longitude = lPrime +
        6.289 * _sinDeg(mPrime) +
        1.274 * _sinDeg(2 * d - mPrime) +
        0.658 * _sinDeg(2 * d) +
        0.214 * _sinDeg(2 * mPrime) -
        0.186 * _sinDeg(m) -
        0.114 * _sinDeg(2 * f);

    final latitude = 5.128 * _sinDeg(f) +
        0.281 * _sinDeg(mPrime + f) +
        0.278 * _sinDeg(mPrime - f) +
        0.173 * _sinDeg(2 * d - f);

    final obliquity = 23.4392911 - 0.0130042 * t;

    final ra = _atan2Deg(
      _sinDeg(longitude) * _cosDeg(obliquity) - _tanDeg(latitude) * _sinDeg(obliquity),
      _cosDeg(longitude),
    );
    final dec = _asinDeg(
      _sinDeg(latitude) * _cosDeg(obliquity) +
          _cosDeg(latitude) * _sinDeg(obliquity) * _sinDeg(longitude),
    );

    return (_normalizeDegrees(ra), dec);
  }

  // MARK: Time helpers

  static double _julianDay(DateTime date) => date.millisecondsSinceEpoch / 1000 / 86400 + 2440587.5;

  /// Mean (not apparent — nutation is skipped, appropriate for this precision tier)
  /// sidereal time at Greenwich. Meeus eq. 12.4.
  static double _meanSiderealTimeDegrees(double jd) {
    final t = (jd - 2451545.0) / 36525.0;
    final theta = 280.46061837 +
        360.98564736629 * (jd - 2451545.0) +
        0.000387933 * t * t -
        (t * t * t) / 38710000;
    return _normalizeDegrees(theta);
  }

  // MARK: Degree-based trig + normalization

  static const double _rad = math.pi / 180;
  static const double _deg = 180 / math.pi;

  static double _sinDeg(double degrees) => math.sin(degrees * _rad);
  static double _cosDeg(double degrees) => math.cos(degrees * _rad);
  static double _tanDeg(double degrees) => math.tan(degrees * _rad);
  static double _asinDeg(double v) => math.asin(v.clamp(-1.0, 1.0)) * _deg;
  static double _acosDeg(double v) => math.acos(v.clamp(-1.0, 1.0)) * _deg;
  static double _atan2Deg(double y, double x) => math.atan2(y, x) * _deg;

  static double _normalizeDegrees(double degrees) {
    final result = degrees.remainder(360);
    return result < 0 ? result + 360 : result;
  }

  /// Normalizes to (-180, 180], for hour angles where the signed direction matters.
  static double _normalizeSigned(double degrees) {
    var result = _normalizeDegrees(degrees);
    if (result > 180) result -= 360;
    return result;
  }

  static double _normalizedFraction(double value) {
    final result = value.remainder(1);
    return result < 0 ? result + 1 : result;
  }
}

enum _Event { rise, set, transit }
