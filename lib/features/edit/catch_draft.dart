import 'dart:typed_data';

import '../../core/format/number_format.dart';
import '../../domain/catalog/species_catalog.dart';
import '../../domain/models/catch_entry.dart';
import '../../domain/models/conditions.dart';
import '../../domain/models/json_helpers.dart';
import '../../domain/models/units.dart';

/// The single source of truth for the entry form, replacing a pile of mirrored per-field
/// state. Numeric fields are held as the text the angler typed and parsed with the
/// locale-aware [parseDecimal] on save, so "2,5" in a comma-decimal locale is never lost.
class CatchDraft {
  CatchDraft({this.id, this.locale});

  /// Existing entry id when editing; null for a new catch (an id is minted on first save).
  final String? id;

  /// Parsing/formatting locale. Null means the app's current locale.
  final String? locale;

  String speciesName = '';
  DateTime date = DateTime.now();

  String locationName = '';
  String waterBodyName = '';
  List<String> waterSuggestions = const [];
  double? latitude;
  double? longitude;
  String depthText = '';
  LengthUnit depthUnit = LengthUnit.feet;

  String weightText = '';
  MassUnit weightUnit = MassUnit.pounds;
  String lengthText = '';
  LengthUnit lengthUnit = LengthUnit.inches;

  String airTemperatureText = '';
  String waterTemperatureText = '';
  String windSpeedText = '';
  String windDirectionText = '';
  String waterConditions = '';

  bool wasFromBoat = false;
  bool wasReleased = true;
  int rating = 0;

  String rodReel = '';
  String baitLure = '';
  String lineType = '';
  String technique = '';
  String notes = '';

  String? tripId;

  /// Bytes of the photo currently shown in the form (already downscaled), if any.
  Uint8List? photoBytes;

  /// True when [photoBytes] was picked/removed in this session and must be written on save.
  bool photoChanged = false;

  /// Fields the form doesn't expose (pressure, cloud cover, provider, capture time) ride
  /// along from the original entry — editing a catch must never silently drop them.
  Conditions _baseConditions = Conditions.none;

  /// Fixed for now, as in the original: a full unit-preference system is a later concern.
  static const String temperatureUnitLabel = '°F';
  static const String windSpeedUnitLabel = 'mph';

  CatchDraft.fromEntry(CatchEntry entry, {this.locale}) : id = entry.id {
    speciesName = entry.speciesName;
    date = entry.date.toLocal();
    locationName = entry.locationName;
    waterBodyName = entry.waterBodyName ?? '';
    latitude = entry.latitude;
    longitude = entry.longitude;

    final depth = entry.depth;
    if (depth != null) {
      depthText = formatForInput(depth.value, locale: locale);
      depthUnit = depth.unit;
    }
    final weight = entry.weight;
    if (weight != null) {
      weightText = formatForInput(weight.value, locale: locale);
      weightUnit = weight.unit;
    }
    final length = entry.length;
    if (length != null) {
      lengthText = formatForInput(length.value, locale: locale);
      lengthUnit = length.unit;
    }

    final c = entry.conditions;
    _baseConditions = c;
    if (c.airTempC != null) {
      airTemperatureText = formatForInput(celsiusToFahrenheit(c.airTempC!), locale: locale);
    }
    if (c.waterTempC != null) {
      waterTemperatureText = formatForInput(celsiusToFahrenheit(c.waterTempC!), locale: locale);
    }
    if (c.windSpeedMS != null) {
      windSpeedText = formatForInput(metersPerSecondToMph(c.windSpeedMS!), locale: locale);
    }
    if (c.windDirectionDegrees != null) {
      windDirectionText = formatForInput(c.windDirectionDegrees!, locale: locale);
    }
    waterConditions = c.waterConditions ?? '';

    wasFromBoat = entry.wasFromBoat;
    wasReleased = entry.wasReleased;
    rating = entry.rating;

    rodReel = entry.gear.rodReel ?? '';
    baitLure = entry.gear.baitLure ?? '';
    lineType = entry.gear.lineType ?? '';
    technique = entry.gear.technique ?? '';
    notes = entry.notes ?? '';
    tripId = entry.tripId;
  }

  bool get hasCoordinate => latitude != null && longitude != null;

  bool get canSave => speciesName.trim().isNotEmpty;

  /// Matches [toEntry]'s species resolution, exposed so the photo-measurement tool can look
  /// up a length-weight divisor before the draft is actually saved.
  String get resolvedSpeciesId => SpeciesCatalog.resolveId(speciesName);

  double? _parse(String text) => parseDecimal(text, locale: locale);

  /// Builds the entry to persist. [newId] is used only when this draft has no [id].
  CatchEntry toEntry({required String newId}) {
    final airC = _parse(airTemperatureText);
    final waterC = _parse(waterTemperatureText);
    final wind = _parse(windSpeedText);
    final windDir = _parse(windDirectionText);
    final waterNote = nilIfBlank(waterConditions);

    final anyTyped = airC != null || waterC != null || wind != null || windDir != null || waterNote != null;
    final base = _baseConditions;
    final conditions = Conditions(
      source: base.source != ConditionsSource.none
          ? base.source
          : (anyTyped ? ConditionsSource.manual : ConditionsSource.none),
      capturedAt: base.capturedAt,
      airTempC: airC == null ? null : fahrenheitToCelsius(airC),
      waterTempC: waterC == null ? null : fahrenheitToCelsius(waterC),
      windSpeedMS: wind == null ? null : mphToMetersPerSecond(wind),
      windDirectionDegrees: windDir,
      pressureHPa: base.pressureHPa,
      pressureTrend: base.pressureTrend,
      weatherCondition: base.weatherCondition,
      cloudCover: base.cloudCover,
      waterConditions: waterNote,
    );

    final depth = _parse(depthText);
    final weight = _parse(weightText);
    final length = _parse(lengthText);
    final water = nilIfBlank(waterBodyName);

    return CatchEntry(
      id: id ?? newId,
      date: date.toUtc(),
      speciesId: resolvedSpeciesId,
      speciesName: speciesName.trim(),
      wasReleased: wasReleased,
      wasFromBoat: wasFromBoat,
      rating: rating,
      locationName: locationName.trim(),
      waterBodyName: water,
      latitude: latitude,
      longitude: longitude,
      depth: depth == null ? null : Measurement(depth, depthUnit),
      weight: weight == null ? null : Measurement(weight, weightUnit),
      length: length == null ? null : Measurement(length, lengthUnit),
      conditions: conditions.hasData ? conditions : Conditions.none,
      gear: Gear(
        rodReel: nilIfBlank(rodReel),
        baitLure: nilIfBlank(baitLure),
        lineType: nilIfBlank(lineType),
        technique: nilIfBlank(technique),
      ),
      notes: nilIfBlank(notes),
      tripId: tripId,
    );
  }

  /// Writes a photo-measurement result into the same text fields manual entry uses, so the
  /// value is still just plain editable text afterward — no separate "measured" state to
  /// keep in sync.
  void applyMeasurement({required Measurement<LengthUnit> length, Measurement<MassUnit>? weight}) {
    lengthText = formatForInput(length.value, locale: locale);
    lengthUnit = length.unit;
    if (weight != null) {
      weightText = formatForInput(weight.value, locale: locale);
      weightUnit = weight.unit;
    }
  }

  /// Fills the conditions fields from a fetched snapshot (values arrive in SI).
  void applyConditions(Conditions snapshot) {
    _baseConditions = Conditions(
      source: snapshot.source,
      capturedAt: snapshot.capturedAt,
      pressureHPa: snapshot.pressureHPa,
      pressureTrend: snapshot.pressureTrend,
      weatherCondition: snapshot.weatherCondition,
      cloudCover: snapshot.cloudCover,
    );
    if (snapshot.airTempC != null) {
      airTemperatureText = formatForInput(celsiusToFahrenheit(snapshot.airTempC!), locale: locale);
    }
    if (snapshot.windSpeedMS != null) {
      windSpeedText = formatForInput(metersPerSecondToMph(snapshot.windSpeedMS!), locale: locale);
    }
    if (snapshot.windDirectionDegrees != null) {
      windDirectionText = formatForInput(snapshot.windDirectionDegrees!, locale: locale);
    }
  }
}
