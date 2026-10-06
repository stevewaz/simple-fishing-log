import '../../domain/models/json_helpers.dart';

// The wire format of a `.fishlog` archive. Domain classes are never serialized directly:
// that would weld the export format to the storage schema forever. These DTOs *are* the
// format; `archive_mappers.dart` translates.
//
// Key names are deliberately identical to the original Swift app's Codable output
// (including `tripID`), so archives stay interchangeable at format version 1.
//
// Rule throughout: everything optional except `id` and `date`. An importer that hard-fails
// on an unexpected null rejects its own next version's files.

/// 36-char UUID, any case. Ids from the Swift app are upper-case; ours are lower-case.
final RegExp uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Whole-second ISO-8601 with a `Z` — the only form Swift's `.iso8601` decoder accepts
/// (it rejects fractional seconds), so exporting anything else would make our archives
/// unreadable by the old app.
String writeArchiveDate(DateTime d) {
  final utc = d.toUtc();
  return '${utc.toIso8601String().split('.').first}Z';
}

DateTime? readArchiveDate(Object? v) => readDate(v);

class MeasurementDto {
  const MeasurementDto(this.value, this.unit);

  final double value;

  /// A unit symbol such as "lb", "kg", "in", "cm" — never ambiguous.
  final String unit;

  Map<String, Object?> toJson() => {'value': value, 'unit': unit};

  static MeasurementDto? fromJson(Object? json) {
    if (json is! Map) return null;
    final value = readDouble(json['value']);
    final unit = readString(json['unit']);
    if (value == null || unit == null) return null;
    return MeasurementDto(value, unit);
  }
}

class SpeciesRefDto {
  const SpeciesRefDto(this.id, this.name);

  final String id;
  final String name;

  Map<String, Object?> toJson() => {'id': id, 'name': name};

  static SpeciesRefDto? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = readString(json['id']);
    final name = readString(json['name']);
    if (id == null || name == null) return null;
    return SpeciesRefDto(id, name);
  }
}

class LocationDto {
  const LocationDto({this.name, this.waterBody, this.latitude, this.longitude, this.depth});

  final String? name;
  final String? waterBody;
  final double? latitude;
  final double? longitude;
  final MeasurementDto? depth;

  Map<String, Object?> toJson() => compact({
        'name': name,
        'waterBody': waterBody,
        'latitude': latitude,
        'longitude': longitude,
        'depth': depth?.toJson(),
      });

  static LocationDto? fromJson(Object? json) {
    if (json is! Map) return null;
    return LocationDto(
      name: readString(json['name']),
      waterBody: readString(json['waterBody']),
      latitude: readDouble(json['latitude']),
      longitude: readDouble(json['longitude']),
      depth: MeasurementDto.fromJson(json['depth']),
    );
  }
}

class ConditionsDto {
  const ConditionsDto({
    this.airTempC,
    this.waterTempC,
    this.windSpeedMS,
    this.windDirectionDegrees,
    this.pressureHPa,
    this.pressureTrend,
    this.weatherCondition,
    this.cloudCover,
    this.waterConditions,
    this.source,
    this.capturedAt,
  });

  final double? airTempC;
  final double? waterTempC;
  final double? windSpeedMS;
  final double? windDirectionDegrees;
  final double? pressureHPa;
  final String? pressureTrend;
  final String? weatherCondition;
  final double? cloudCover;
  final String? waterConditions;
  final String? source;
  final DateTime? capturedAt;

  Map<String, Object?> toJson() => compact({
        'airTempC': airTempC,
        'waterTempC': waterTempC,
        'windSpeedMS': windSpeedMS,
        'windDirectionDegrees': windDirectionDegrees,
        'pressureHPa': pressureHPa,
        'pressureTrend': pressureTrend,
        'weatherCondition': weatherCondition,
        'cloudCover': cloudCover,
        'waterConditions': waterConditions,
        'source': source,
        'capturedAt': capturedAt == null ? null : writeArchiveDate(capturedAt!),
      });

  static ConditionsDto? fromJson(Object? json) {
    if (json is! Map) return null;
    return ConditionsDto(
      airTempC: readDouble(json['airTempC']),
      waterTempC: readDouble(json['waterTempC']),
      windSpeedMS: readDouble(json['windSpeedMS']),
      windDirectionDegrees: readDouble(json['windDirectionDegrees']),
      pressureHPa: readDouble(json['pressureHPa']),
      pressureTrend: readString(json['pressureTrend']),
      weatherCondition: readString(json['weatherCondition']),
      cloudCover: readDouble(json['cloudCover']),
      waterConditions: readString(json['waterConditions']),
      source: readString(json['source']),
      capturedAt: readArchiveDate(json['capturedAt']),
    );
  }
}

class GearDto {
  const GearDto({this.rodReel, this.baitLure, this.lineType, this.technique});

  final String? rodReel;
  final String? baitLure;
  final String? lineType;
  final String? technique;

  Map<String, Object?> toJson() => compact({
        'rodReel': rodReel,
        'baitLure': baitLure,
        'lineType': lineType,
        'technique': technique,
      });

  static GearDto? fromJson(Object? json) {
    if (json is! Map) return null;
    return GearDto(
      rodReel: readString(json['rodReel']),
      baitLure: readString(json['baitLure']),
      lineType: readString(json['lineType']),
      technique: readString(json['technique']),
    );
  }
}

class CatchDto {
  const CatchDto({
    required this.id,
    required this.date,
    this.species,
    this.location,
    this.weight,
    this.length,
    this.conditions,
    this.gear,
    this.wasFromBoat,
    this.wasReleased,
    this.rating,
    this.notes,
    this.tripId,
    this.photoFileName,
  });

  final String id;
  final DateTime date;
  final SpeciesRefDto? species;
  final LocationDto? location;
  final MeasurementDto? weight;
  final MeasurementDto? length;
  final ConditionsDto? conditions;
  final GearDto? gear;
  final bool? wasFromBoat;
  final bool? wasReleased;
  final int? rating;
  final String? notes;
  final String? tripId;

  /// Filename within the archive's `photos/` directory. Singular — the app only ever
  /// attaches one photo per catch today.
  final String? photoFileName;

  Map<String, Object?> toJson() => compact({
        'id': id,
        'date': writeArchiveDate(date),
        'species': species?.toJson(),
        'location': location?.toJson(),
        'weight': weight?.toJson(),
        'length': length?.toJson(),
        'conditions': conditions?.toJson(),
        'gear': gear?.toJson(),
        'wasFromBoat': wasFromBoat,
        'wasReleased': wasReleased,
        'rating': rating,
        'notes': notes,
        'tripID': tripId,
        'photoFileName': photoFileName,
      });

  /// Throws [FormatException] for a record that can't be used (bad id or missing date). The
  /// importer catches per record so one corrupt entry never rejects the rest.
  factory CatchDto.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('Catch record is not an object');
    final id = readString(json['id']);
    if (id == null || !uuidPattern.hasMatch(id)) throw FormatException('Invalid catch id: $id');
    final date = readArchiveDate(json['date']);
    if (date == null) throw const FormatException('Catch record has no valid date');
    final tripId = readString(json['tripID']);
    return CatchDto(
      id: id.toLowerCase(),
      date: date,
      species: SpeciesRefDto.fromJson(json['species']),
      location: LocationDto.fromJson(json['location']),
      weight: MeasurementDto.fromJson(json['weight']),
      length: MeasurementDto.fromJson(json['length']),
      conditions: ConditionsDto.fromJson(json['conditions']),
      gear: GearDto.fromJson(json['gear']),
      wasFromBoat: readBool(json['wasFromBoat']),
      wasReleased: readBool(json['wasReleased']),
      rating: readInt(json['rating']),
      notes: readString(json['notes']),
      tripId: (tripId != null && uuidPattern.hasMatch(tripId)) ? tripId.toLowerCase() : null,
      photoFileName: readString(json['photoFileName']),
    );
  }
}

class TripDto {
  const TripDto({
    required this.id,
    required this.startDate,
    this.title,
    this.endDate,
    this.waterBody,
    this.latitude,
    this.longitude,
    this.notes,
  });

  final String id;
  final DateTime startDate;
  final String? title;
  final DateTime? endDate;
  final String? waterBody;
  final double? latitude;
  final double? longitude;
  final String? notes;

  Map<String, Object?> toJson() => compact({
        'id': id,
        'title': title,
        'startDate': writeArchiveDate(startDate),
        'endDate': endDate == null ? null : writeArchiveDate(endDate!),
        'waterBody': waterBody,
        'latitude': latitude,
        'longitude': longitude,
        'notes': notes,
      });

  factory TripDto.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('Trip record is not an object');
    final id = readString(json['id']);
    if (id == null || !uuidPattern.hasMatch(id)) throw FormatException('Invalid trip id: $id');
    final start = readArchiveDate(json['startDate']);
    if (start == null) throw const FormatException('Trip record has no valid startDate');
    return TripDto(
      id: id.toLowerCase(),
      startDate: start,
      title: readString(json['title']),
      endDate: readArchiveDate(json['endDate']),
      waterBody: readString(json['waterBody']),
      latitude: readDouble(json['latitude']),
      longitude: readDouble(json['longitude']),
      notes: readString(json['notes']),
    );
  }
}

class ArchiveManifest {
  const ArchiveManifest({
    required this.formatVersion,
    required this.generator,
    required this.exportedAt,
    required this.catchCount,
    required this.tripCount,
    required this.photoCount,
  });

  static const int currentFormatVersion = 1;

  final int formatVersion;
  final String generator;
  final DateTime exportedAt;
  final int catchCount;
  final int tripCount;
  final int photoCount;

  Map<String, Object?> toJson() => {
        'formatVersion': formatVersion,
        'generator': generator,
        'exportedAt': writeArchiveDate(exportedAt),
        'catchCount': catchCount,
        'tripCount': tripCount,
        'photoCount': photoCount,
      };

  factory ArchiveManifest.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('Manifest is not an object');
    final version = readInt(json['formatVersion']);
    final catches = readInt(json['catchCount']);
    final trips = readInt(json['tripCount']);
    final photos = readInt(json['photoCount']);
    if (version == null || catches == null || trips == null || photos == null) {
      throw const FormatException('Manifest is missing required fields');
    }
    return ArchiveManifest(
      formatVersion: version,
      generator: readString(json['generator']) ?? 'unknown',
      exportedAt: readArchiveDate(json['exportedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      catchCount: catches,
      tripCount: trips,
      photoCount: photos,
    );
  }
}
