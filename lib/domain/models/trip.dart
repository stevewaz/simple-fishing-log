import 'json_helpers.dart';

const Object _unset = Object();

/// A fishing session grouping catches from one day on the water.
class Trip {
  const Trip({
    required this.id,
    required this.startDate,
    this.title = '',
    this.endDate,
    this.waterBodyName,
    this.latitude,
    this.longitude,
    this.notes,
    this.isActive = false,
  });

  final String id;
  final DateTime startDate;
  final String title;
  final DateTime? endDate;
  final String? waterBodyName;
  final double? latitude;
  final double? longitude;
  final String? notes;

  /// At most one trip is active; enforced by `TripRepository.startSession`, not the schema.
  final bool isActive;

  Trip copyWith({
    DateTime? startDate,
    String? title,
    Object? endDate = _unset,
    Object? waterBodyName = _unset,
    Object? latitude = _unset,
    Object? longitude = _unset,
    Object? notes = _unset,
    bool? isActive,
  }) {
    return Trip(
      id: id,
      startDate: startDate ?? this.startDate,
      title: title ?? this.title,
      endDate: identical(endDate, _unset) ? this.endDate : endDate as DateTime?,
      waterBodyName: identical(waterBodyName, _unset) ? this.waterBodyName : waterBodyName as String?,
      latitude: identical(latitude, _unset) ? this.latitude : latitude as double?,
      longitude: identical(longitude, _unset) ? this.longitude : longitude as double?,
      notes: identical(notes, _unset) ? this.notes : notes as String?,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, Object?> toJson() => compact({
        'id': id,
        'title': title,
        'startDate': writeDate(startDate),
        'endDate': endDate == null ? null : writeDate(endDate!),
        'waterBodyName': waterBodyName,
        'latitude': latitude,
        'longitude': longitude,
        'notes': notes,
        'isActive': isActive,
      });

  factory Trip.fromJson(Map<String, Object?> json) => Trip(
        id: json['id'] as String,
        startDate: readDate(json['startDate']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        title: readString(json['title']) ?? '',
        endDate: readDate(json['endDate']),
        waterBodyName: readString(json['waterBodyName']),
        latitude: readDouble(json['latitude']),
        longitude: readDouble(json['longitude']),
        notes: readString(json['notes']),
        isActive: readBool(json['isActive']) ?? false,
      );

  @override
  bool operator ==(Object other) =>
      other is Trip &&
      other.id == id &&
      other.startDate == startDate &&
      other.title == title &&
      other.endDate == endDate &&
      other.waterBodyName == waterBodyName &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.notes == notes &&
      other.isActive == isActive;

  @override
  int get hashCode =>
      Object.hash(id, startDate, title, endDate, waterBodyName, latitude, longitude, notes, isActive);
}
