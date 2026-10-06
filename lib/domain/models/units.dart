/// Units and measurements.
///
/// Values are stored as `value + unit symbol`, never as a bare number, so display never
/// depends on device locale. Conversion always goes through an explicit factor table —
/// the Swift original had a trap where `UnitMass(symbol:)` built a brand-new unit with an
/// identity converter and silently corrupted values; here an unknown symbol resolves to a
/// documented fallback instead.
library;

abstract interface class MeasureUnit {
  String get symbol;

  /// Multiplier that converts one of this unit into the SI base unit of its dimension
  /// (kilograms, meters).
  double get toBase;
}

enum MassUnit implements MeasureUnit {
  pounds('lb', 0.45359237),
  ounces('oz', 0.028349523125),
  kilograms('kg', 1),
  grams('g', 0.001);

  const MassUnit(this.symbol, this.toBase);

  @override
  final String symbol;
  @override
  final double toBase;

  static MassUnit fromSymbol(String? symbol, {MassUnit fallback = MassUnit.pounds}) {
    for (final unit in values) {
      if (unit.symbol == symbol) return unit;
    }
    return fallback;
  }
}

enum LengthUnit implements MeasureUnit {
  inches('in', 0.0254),
  feet('ft', 0.3048),
  centimeters('cm', 0.01),
  meters('m', 1);

  const LengthUnit(this.symbol, this.toBase);

  @override
  final String symbol;
  @override
  final double toBase;

  static LengthUnit fromSymbol(String? symbol, {LengthUnit fallback = LengthUnit.inches}) {
    for (final unit in values) {
      if (unit.symbol == symbol) return unit;
    }
    return fallback;
  }
}

class Measurement<U extends MeasureUnit> {
  const Measurement(this.value, this.unit);

  final double value;
  final U unit;

  double valueIn(U target) => identical(unit, target) ? value : value * unit.toBase / target.toBase;

  Measurement<U> convertedTo(U target) => Measurement<U>(valueIn(target), target);

  @override
  bool operator ==(Object other) =>
      other is Measurement<U> && other.value == value && other.unit == unit;

  @override
  int get hashCode => Object.hash(value, unit);

  @override
  String toString() => 'Measurement($value ${unit.symbol})';
}

/// Conditions are stored canonically in SI (°C, m/s) so they stay queryable; these are the
/// only places a Fahrenheit or mph value should be produced.
double celsiusToFahrenheit(double c) => c * 9 / 5 + 32;
double fahrenheitToCelsius(double f) => (f - 32) * 5 / 9;

const double _metersPerSecondPerMph = 0.44704;
double metersPerSecondToMph(double ms) => ms / _metersPerSecondPerMph;
double mphToMetersPerSecond(double mph) => mph * _metersPerSecondPerMph;
