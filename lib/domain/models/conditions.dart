import 'json_helpers.dart';

/// Where a catch's conditions came from. Raw strings are the stable wire values — they match
/// the Swift app's `ConditionsSource` raw values so old archives import unchanged.
enum ConditionsSource {
  none('none'),
  manual('manual'),
  weatherKit('weatherKit'),
  openMeteo('openMeteo');

  const ConditionsSource(this.raw);
  final String raw;

  static ConditionsSource fromRaw(String? raw) {
    for (final s in values) {
      if (s.raw == raw) return s;
    }
    return ConditionsSource.none;
  }
}

/// Weather and water conditions at the time of a catch. Canonical SI throughout (°C, m/s,
/// hPa) so values stay comparable no matter which provider or unit the angler used.
class Conditions {
  const Conditions({
    this.source = ConditionsSource.none,
    this.capturedAt,
    this.airTempC,
    this.waterTempC,
    this.windSpeedMS,
    this.windDirectionDegrees,
    this.pressureHPa,
    this.pressureTrend,
    this.weatherCondition,
    this.cloudCover,
    this.waterConditions,
  });

  static const none = Conditions();

  final ConditionsSource source;
  final DateTime? capturedAt;
  final double? airTempC;
  final double? waterTempC;
  final double? windSpeedMS;
  final double? windDirectionDegrees;
  final double? pressureHPa;

  /// "rising" / "falling" / "steady".
  final String? pressureTrend;
  final String? weatherCondition;

  /// 0...1.
  final double? cloudCover;

  /// Angler free text ("choppy").
  final String? waterConditions;

  /// True when there is anything worth persisting or exporting. `source` and `capturedAt`
  /// alone don't count — they describe other fields.
  bool get hasData =>
      airTempC != null ||
      waterTempC != null ||
      windSpeedMS != null ||
      windDirectionDegrees != null ||
      pressureHPa != null ||
      waterConditions != null;

  Conditions copyWith({
    ConditionsSource? source,
    DateTime? capturedAt,
    double? airTempC,
    double? waterTempC,
    double? windSpeedMS,
    double? windDirectionDegrees,
    double? pressureHPa,
    String? pressureTrend,
    String? weatherCondition,
    double? cloudCover,
    String? waterConditions,
  }) {
    return Conditions(
      source: source ?? this.source,
      capturedAt: capturedAt ?? this.capturedAt,
      airTempC: airTempC ?? this.airTempC,
      waterTempC: waterTempC ?? this.waterTempC,
      windSpeedMS: windSpeedMS ?? this.windSpeedMS,
      windDirectionDegrees: windDirectionDegrees ?? this.windDirectionDegrees,
      pressureHPa: pressureHPa ?? this.pressureHPa,
      pressureTrend: pressureTrend ?? this.pressureTrend,
      weatherCondition: weatherCondition ?? this.weatherCondition,
      cloudCover: cloudCover ?? this.cloudCover,
      waterConditions: waterConditions ?? this.waterConditions,
    );
  }

  Map<String, Object?> toJson() => compact({
        'conditionsSource': source.raw,
        'conditionsCapturedAt': capturedAt == null ? null : writeDate(capturedAt!),
        'airTempC': airTempC,
        'waterTempC': waterTempC,
        'windSpeedMS': windSpeedMS,
        'windDirectionDegrees': windDirectionDegrees,
        'pressureHPa': pressureHPa,
        'pressureTrend': pressureTrend,
        'weatherCondition': weatherCondition,
        'cloudCover': cloudCover,
        'waterConditions': waterConditions,
      });

  factory Conditions.fromJson(Map<String, Object?> json) => Conditions(
        source: ConditionsSource.fromRaw(readString(json['conditionsSource'])),
        capturedAt: readDate(json['conditionsCapturedAt']),
        airTempC: readDouble(json['airTempC']),
        waterTempC: readDouble(json['waterTempC']),
        windSpeedMS: readDouble(json['windSpeedMS']),
        windDirectionDegrees: readDouble(json['windDirectionDegrees']),
        pressureHPa: readDouble(json['pressureHPa']),
        pressureTrend: readString(json['pressureTrend']),
        weatherCondition: readString(json['weatherCondition']),
        cloudCover: readDouble(json['cloudCover']),
        waterConditions: readString(json['waterConditions']),
      );

  @override
  bool operator ==(Object other) =>
      other is Conditions &&
      other.source == source &&
      other.capturedAt == capturedAt &&
      other.airTempC == airTempC &&
      other.waterTempC == waterTempC &&
      other.windSpeedMS == windSpeedMS &&
      other.windDirectionDegrees == windDirectionDegrees &&
      other.pressureHPa == pressureHPa &&
      other.pressureTrend == pressureTrend &&
      other.weatherCondition == weatherCondition &&
      other.cloudCover == cloudCover &&
      other.waterConditions == waterConditions;

  @override
  int get hashCode => Object.hash(source, capturedAt, airTempC, waterTempC, windSpeedMS,
      windDirectionDegrees, pressureHPa, pressureTrend, weatherCondition, cloudCover, waterConditions);
}

/// Gear is denormalized free text with history-derived autocomplete, not entities: two
/// offline devices creating the same "gear item" would otherwise produce permanent
/// duplicates once sync arrives.
class Gear {
  const Gear({this.rodReel, this.baitLure, this.lineType, this.technique});

  static const none = Gear();

  final String? rodReel;
  final String? baitLure;
  final String? lineType;
  final String? technique;

  bool get hasData => rodReel != null || baitLure != null || lineType != null || technique != null;

  Map<String, Object?> toJson() => compact({
        'rodReel': rodReel,
        'baitLure': baitLure,
        'lineType': lineType,
        'technique': technique,
      });

  factory Gear.fromJson(Map<String, Object?> json) => Gear(
        rodReel: readString(json['rodReel']),
        baitLure: readString(json['baitLure']),
        lineType: readString(json['lineType']),
        technique: readString(json['technique']),
      );

  @override
  bool operator ==(Object other) =>
      other is Gear &&
      other.rodReel == rodReel &&
      other.baitLure == baitLure &&
      other.lineType == lineType &&
      other.technique == technique;

  @override
  int get hashCode => Object.hash(rodReel, baitLure, lineType, technique);
}
