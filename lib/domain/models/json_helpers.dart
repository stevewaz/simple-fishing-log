/// Small, forgiving readers for stored JSON. Everything is optional on read — a stored
/// document (or, later, a Firestore document written by a newer app version) must never
/// crash the app because a field is missing or has an unexpected type.
library;

double? readDouble(Object? v) => v is num ? v.toDouble() : null;

int? readInt(Object? v) => v is num ? v.toInt() : null;

String? readString(Object? v) => v is String ? v : null;

bool? readBool(Object? v) => v is bool ? v : null;

DateTime? readDate(Object? v) {
  if (v is! String) return null;
  return DateTime.tryParse(v)?.toUtc();
}

String writeDate(DateTime d) => d.toUtc().toIso8601String();

/// Trims, and collapses blank to null — blank gear/notes fields must be absent, not "".
String? nilIfBlank(String? v) {
  final trimmed = v?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// Removes keys whose value is null so stored documents stay compact.
Map<String, Object?> compact(Map<String, Object?> json) =>
    {for (final e in json.entries) if (e.value != null) e.key: e.value};
