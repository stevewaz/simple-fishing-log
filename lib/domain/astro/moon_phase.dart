/// Eight-way moon phase from the mean synodic month.
///
/// Pure date math. This approximation carries up to ~14 h of error, which is harmless when
/// choosing one of eight phase labels but is deliberately *not* used for moon rise/set —
/// see `SolunarCalculator` for real lunar-position math.
enum MoonPhase {
  newMoon('New Moon'),
  waxingCrescent('Waxing Crescent'),
  firstQuarter('First Quarter'),
  waxingGibbous('Waxing Gibbous'),
  fullMoon('Full Moon'),
  waningGibbous('Waning Gibbous'),
  lastQuarter('Last Quarter'),
  waningCrescent('Waning Crescent');

  const MoonPhase(this.label);

  final String label;

  /// Reference new moon: 2000-01-06 18:14 UTC.
  static const int _referenceNewMoonEpochSeconds = 947182440;

  /// Mean synodic month, ~29.53 days.
  static const double synodicMonthSeconds = 29.53058867 * 86400;

  /// 0...1 through the synodic month: 0 = new, 0.5 = full.
  static double cycleFraction(DateTime date) {
    final elapsed = date.millisecondsSinceEpoch / 1000 - _referenceNewMoonEpochSeconds;
    final position = elapsed.remainder(synodicMonthSeconds);
    final normalized = position < 0 ? position + synodicMonthSeconds : position;
    return normalized / synodicMonthSeconds;
  }

  static MoonPhase fromDate(DateTime date) {
    final fraction = cycleFraction(date);
    if (fraction < 0.03) return MoonPhase.newMoon;
    if (fraction < 0.22) return MoonPhase.waxingCrescent;
    if (fraction < 0.28) return MoonPhase.firstQuarter;
    if (fraction < 0.47) return MoonPhase.waxingGibbous;
    if (fraction < 0.53) return MoonPhase.fullMoon;
    if (fraction < 0.72) return MoonPhase.waningGibbous;
    if (fraction < 0.78) return MoonPhase.lastQuarter;
    if (fraction < 0.97) return MoonPhase.waningCrescent;
    return MoonPhase.newMoon;
  }
}
