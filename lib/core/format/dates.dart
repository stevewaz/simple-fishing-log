import 'package:intl/intl.dart';

/// Stored dates are UTC; these always render in the device's local time zone and locale
/// (`Intl.defaultLocale`, kept in sync with the app locale by `FishLogApp`).
String formatDate(DateTime d) => DateFormat.yMMMd().format(d.toLocal());

String formatDateTime(DateTime d) => DateFormat.yMMMd().add_jm().format(d.toLocal());

String formatTime(DateTime d) => DateFormat.jm().format(d.toLocal());

String formatTimeRange(DateTime start, DateTime end) => '${formatTime(start)}–${formatTime(end)}';

/// Local midnight at the start of [d]'s local day — the window solunar times are asked for.
DateTime localDayStart(DateTime d) {
  final l = d.toLocal();
  return DateTime(l.year, l.month, l.day);
}
