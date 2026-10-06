import 'conditions.dart';
import 'json_helpers.dart';
import 'units.dart';

const Object _unset = Object();

/// One logged catch. Immutable; edits go through the entry form's `CatchDraft`, which
/// produces a new instance.
///
/// Identity is a client-generated UUID string — stable, exportable, and safe to create on
/// two offline devices without a server to hand out ids (which is what makes later Firebase
/// sync additive rather than a migration).
class CatchEntry {
  const CatchEntry({
    required this.id,
    required this.date,
    this.speciesId = '',
    this.speciesName = '',
    this.wasReleased = true,
    this.wasFromBoat = false,
    this.rating = 0,
    this.locationName = '',
    this.waterBodyName,
    this.latitude,
    this.longitude,
    this.depth,
    this.weight,
    this.length,
    this.conditions = Conditions.none,
    this.gear = Gear.none,
    this.notes,
    this.tripId,
  });

  final String id;
  final DateTime date;

  /// Stable slug, e.g. `largemouth-bass` or `custom:tiger-musky`.
  final String speciesId;

  /// Denormalized display name; survives catalog changes and export.
  final String speciesName;
  final bool wasReleased;
  final bool wasFromBoat;

  /// 0 = unrated.
  final int rating;

  final String locationName;
  final String? waterBodyName;
  final double? latitude;
  final double? longitude;

  /// Angler-reported — there is no bathymetry layer for inland lakes and rivers.
  final Measurement<LengthUnit>? depth;
  final Measurement<MassUnit>? weight;
  final Measurement<LengthUnit>? length;

  final Conditions conditions;
  final Gear gear;
  final String? notes;
  final String? tripId;

  bool get hasCoordinate => latitude != null && longitude != null;

  String get displaySpecies => speciesName.isEmpty ? 'Unknown species' : speciesName;

  /// Water body if the angler gave one, otherwise the free-text location name.
  String? get placeLabel {
    final water = waterBodyName;
    if (water != null && water.isNotEmpty) return water;
    return locationName.isEmpty ? null : locationName;
  }

  CatchEntry copyWith({
    DateTime? date,
    String? speciesId,
    String? speciesName,
    bool? wasReleased,
    bool? wasFromBoat,
    int? rating,
    String? locationName,
    Object? waterBodyName = _unset,
    Object? latitude = _unset,
    Object? longitude = _unset,
    Object? depth = _unset,
    Object? weight = _unset,
    Object? length = _unset,
    Conditions? conditions,
    Gear? gear,
    Object? notes = _unset,
    Object? tripId = _unset,
  }) {
    return CatchEntry(
      id: id,
      date: date ?? this.date,
      speciesId: speciesId ?? this.speciesId,
      speciesName: speciesName ?? this.speciesName,
      wasReleased: wasReleased ?? this.wasReleased,
      wasFromBoat: wasFromBoat ?? this.wasFromBoat,
      rating: rating ?? this.rating,
      locationName: locationName ?? this.locationName,
      waterBodyName: identical(waterBodyName, _unset) ? this.waterBodyName : waterBodyName as String?,
      latitude: identical(latitude, _unset) ? this.latitude : latitude as double?,
      longitude: identical(longitude, _unset) ? this.longitude : longitude as double?,
      depth: identical(depth, _unset) ? this.depth : depth as Measurement<LengthUnit>?,
      weight: identical(weight, _unset) ? this.weight : weight as Measurement<MassUnit>?,
      length: identical(length, _unset) ? this.length : length as Measurement<LengthUnit>?,
      conditions: conditions ?? this.conditions,
      gear: gear ?? this.gear,
      notes: identical(notes, _unset) ? this.notes : notes as String?,
      tripId: identical(tripId, _unset) ? this.tripId : tripId as String?,
    );
  }

  /// Flat storage shape, mirroring the SwiftData schema. Distinct from the archive DTOs on
  /// purpose: the export wire format must not be welded to the storage schema.
  Map<String, Object?> toJson() => compact({
        'id': id,
        'date': writeDate(date),
        'speciesId': speciesId,
        'speciesName': speciesName,
        'wasReleased': wasReleased,
        'wasFromBoat': wasFromBoat,
        'rating': rating,
        'locationName': locationName,
        'waterBodyName': waterBodyName,
        'latitude': latitude,
        'longitude': longitude,
        'depthValue': depth?.value,
        'depthUnit': depth?.unit.symbol,
        'weightValue': weight?.value,
        'weightUnit': weight?.unit.symbol,
        'lengthValue': length?.value,
        'lengthUnit': length?.unit.symbol,
        ...conditions.toJson(),
        ...gear.toJson(),
        'notes': notes,
        'tripId': tripId,
      });

  factory CatchEntry.fromJson(Map<String, Object?> json) {
    Measurement<U>? measurement<U extends MeasureUnit>(
        String valueKey, String unitKey, U Function(String?) unitFor) {
      final value = readDouble(json[valueKey]);
      if (value == null) return null;
      return Measurement<U>(value, unitFor(readString(json[unitKey])));
    }

    return CatchEntry(
      id: json['id'] as String,
      date: readDate(json['date']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      speciesId: readString(json['speciesId']) ?? '',
      speciesName: readString(json['speciesName']) ?? '',
      wasReleased: readBool(json['wasReleased']) ?? true,
      wasFromBoat: readBool(json['wasFromBoat']) ?? false,
      rating: readInt(json['rating']) ?? 0,
      locationName: readString(json['locationName']) ?? '',
      waterBodyName: readString(json['waterBodyName']),
      latitude: readDouble(json['latitude']),
      longitude: readDouble(json['longitude']),
      depth: measurement('depthValue', 'depthUnit', (s) => LengthUnit.fromSymbol(s, fallback: LengthUnit.feet)),
      weight: measurement('weightValue', 'weightUnit', (s) => MassUnit.fromSymbol(s)),
      length: measurement('lengthValue', 'lengthUnit', (s) => LengthUnit.fromSymbol(s)),
      conditions: Conditions.fromJson(json),
      gear: Gear.fromJson(json),
      notes: readString(json['notes']),
      tripId: readString(json['tripId']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CatchEntry &&
      other.id == id &&
      other.date == date &&
      other.speciesId == speciesId &&
      other.speciesName == speciesName &&
      other.wasReleased == wasReleased &&
      other.wasFromBoat == wasFromBoat &&
      other.rating == rating &&
      other.locationName == locationName &&
      other.waterBodyName == waterBodyName &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.depth == depth &&
      other.weight == weight &&
      other.length == length &&
      other.conditions == conditions &&
      other.gear == gear &&
      other.notes == notes &&
      other.tripId == tripId;

  @override
  int get hashCode => Object.hash(id, date, speciesId, speciesName, wasReleased, wasFromBoat, rating,
      locationName, waterBodyName, latitude, longitude, depth, weight, length, conditions, gear, notes, tripId);
}
