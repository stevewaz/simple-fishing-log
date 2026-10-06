import '../../domain/models/catch_entry.dart';
import '../../domain/models/conditions.dart';
import '../../domain/models/trip.dart';
import '../../domain/models/units.dart';
import 'archive_dtos.dart';

abstract final class CatchMapper {
  static CatchDto toDto(CatchEntry entry, {String? photoFileName}) {
    final species = entry.speciesName.isEmpty ? null : SpeciesRefDto(entry.speciesId, entry.speciesName);

    final depth = entry.depth == null ? null : MeasurementDto(entry.depth!.value, entry.depth!.unit.symbol);
    final hasLocation = entry.waterBodyName != null ||
        entry.locationName.isNotEmpty ||
        entry.latitude != null ||
        entry.longitude != null ||
        depth != null;
    final location = hasLocation
        ? LocationDto(
            name: entry.locationName.isEmpty ? null : entry.locationName,
            waterBody: entry.waterBodyName,
            latitude: entry.latitude,
            longitude: entry.longitude,
            depth: depth,
          )
        : null;

    final c = entry.conditions;
    final conditions = c.hasData
        ? ConditionsDto(
            airTempC: c.airTempC,
            waterTempC: c.waterTempC,
            windSpeedMS: c.windSpeedMS,
            windDirectionDegrees: c.windDirectionDegrees,
            pressureHPa: c.pressureHPa,
            pressureTrend: c.pressureTrend,
            weatherCondition: c.weatherCondition,
            cloudCover: c.cloudCover,
            waterConditions: c.waterConditions,
            source: c.source.raw,
            capturedAt: c.capturedAt,
          )
        : null;

    final g = entry.gear;
    final gear = g.hasData
        ? GearDto(rodReel: g.rodReel, baitLure: g.baitLure, lineType: g.lineType, technique: g.technique)
        : null;

    return CatchDto(
      id: entry.id,
      date: entry.date,
      species: species,
      location: location,
      weight: entry.weight == null ? null : MeasurementDto(entry.weight!.value, entry.weight!.unit.symbol),
      length: entry.length == null ? null : MeasurementDto(entry.length!.value, entry.length!.unit.symbol),
      conditions: conditions,
      gear: gear,
      wasFromBoat: entry.wasFromBoat,
      wasReleased: entry.wasReleased,
      rating: entry.rating,
      notes: entry.notes,
      tripId: entry.tripId,
      photoFileName: photoFileName,
    );
  }

  /// Applies a decoded DTO onto [base] (an existing entry, or a blank one for a new import).
  /// Fields the DTO leaves out keep [base]'s value, so replacing never wipes data the
  /// archive simply didn't carry. Trip linkage is resolved by the caller.
  static CatchEntry apply(CatchDto dto, CatchEntry base) {
    var entry = base.copyWith(date: dto.date);

    final species = dto.species;
    if (species != null) {
      entry = entry.copyWith(speciesId: species.id, speciesName: species.name);
    }

    final location = dto.location;
    if (location != null) {
      final depth = location.depth;
      entry = entry.copyWith(
        locationName: location.name ?? '',
        waterBodyName: location.waterBody,
        latitude: location.latitude,
        longitude: location.longitude,
        depth: depth == null
            ? entry.depth
            : Measurement(depth.value, LengthUnit.fromSymbol(depth.unit, fallback: LengthUnit.feet)),
      );
    }

    final weight = dto.weight;
    if (weight != null) {
      entry = entry.copyWith(weight: Measurement(weight.value, MassUnit.fromSymbol(weight.unit)));
    }
    final length = dto.length;
    if (length != null) {
      entry = entry.copyWith(length: Measurement(length.value, LengthUnit.fromSymbol(length.unit)));
    }

    final c = dto.conditions;
    if (c != null) {
      entry = entry.copyWith(
        conditions: Conditions(
          source: ConditionsSource.fromRaw(c.source),
          capturedAt: c.capturedAt,
          airTempC: c.airTempC,
          waterTempC: c.waterTempC,
          windSpeedMS: c.windSpeedMS,
          windDirectionDegrees: c.windDirectionDegrees,
          pressureHPa: c.pressureHPa,
          pressureTrend: c.pressureTrend,
          weatherCondition: c.weatherCondition,
          cloudCover: c.cloudCover,
          waterConditions: c.waterConditions,
        ),
      );
    }

    final g = dto.gear;
    if (g != null) {
      entry = entry.copyWith(
        gear: Gear(rodReel: g.rodReel, baitLure: g.baitLure, lineType: g.lineType, technique: g.technique),
      );
    }

    return entry.copyWith(
      wasFromBoat: dto.wasFromBoat,
      wasReleased: dto.wasReleased,
      rating: dto.rating,
      notes: dto.notes ?? entry.notes,
    );
  }
}

abstract final class TripMapper {
  static TripDto toDto(Trip trip) => TripDto(
        id: trip.id,
        title: trip.title.isEmpty ? null : trip.title,
        startDate: trip.startDate,
        endDate: trip.endDate,
        waterBody: trip.waterBodyName,
        latitude: trip.latitude,
        longitude: trip.longitude,
        notes: trip.notes,
      );

  static Trip apply(TripDto dto, Trip base) => base.copyWith(
        title: dto.title ?? '',
        startDate: dto.startDate,
        endDate: dto.endDate,
        waterBodyName: dto.waterBody,
        latitude: dto.latitude,
        longitude: dto.longitude,
        notes: dto.notes,
      );
}
