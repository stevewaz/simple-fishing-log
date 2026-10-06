import 'package:intl/intl.dart';

import '../../domain/models/units.dart';

/// Locale-aware decimal parsing for text fields.
///
/// This is where the original "2,5 silently became nothing in a comma-decimal locale" bug
/// dies: `double.tryParse` only ever understands ".", and `NumberFormat.parse` mis-reads
/// "2.5" as 25 in a German locale. Anglers type on decimal keypads that offer either
/// separator, so we accept both and resolve ambiguity with the rules below:
///
/// * both separators present → the one that appears last is the decimal separator;
/// * one separator, repeated ("1.234.567") → grouping only;
/// * one separator, once → decimal, *unless* it is not the locale's decimal separator and
///   exactly three digits follow it ("1,234" in en_US is one thousand two hundred thirty-four).
double? parseDecimal(String? text, {String? locale}) {
  if (text == null) return null;
  final s = text.replaceAll(RegExp(r'[\s   ]'), '');
  if (s.isEmpty) return null;
  if (!RegExp(r'^[+-]?[\d.,]+$').hasMatch(s)) return null;

  final localeDecimal = decimalSeparatorFor(locale);
  final lastDot = s.lastIndexOf('.');
  final lastComma = s.lastIndexOf(',');

  String? decimalSep;
  if (lastDot >= 0 && lastComma >= 0) {
    decimalSep = lastDot > lastComma ? '.' : ',';
    // The decimal separator may only occur once; the other is grouping.
    if (decimalSep.allMatches(s).length != 1) return null;
  } else if (lastDot >= 0 || lastComma >= 0) {
    final sep = lastDot >= 0 ? '.' : ',';
    final count = sep.allMatches(s).length;
    if (count == 1) {
      final digitsAfter = s.length - s.lastIndexOf(sep) - 1;
      final looksLikeGrouping = sep != localeDecimal && digitsAfter == 3 && s.indexOf(sep) > 0;
      decimalSep = looksLikeGrouping ? null : sep;
    }
  }

  var normalized = s;
  for (final sep in const ['.', ',']) {
    if (sep == decimalSep) continue;
    normalized = normalized.replaceAll(sep, '');
  }
  if (decimalSep != null) normalized = normalized.replaceAll(decimalSep, '.');
  return double.tryParse(normalized);
}

String decimalSeparatorFor(String? locale) =>
    NumberFormat.decimalPattern(locale ?? Intl.defaultLocale).symbols.DECIMAL_SEP;

/// Formats a value for an editable text field: no grouping, up to 3 decimals, locale
/// decimal separator, so the same text round-trips through [parseDecimal].
String formatForInput(double value, {String? locale}) {
  final f = NumberFormat('0.###', locale ?? Intl.defaultLocale);
  return f.format(value);
}

/// Display formatting: up to two fractional digits, locale grouping — "4.2 lb", "1,200 ft".
String formatNumber(double value, {int maxFractionDigits = 2, String? locale}) {
  final pattern = maxFractionDigits <= 0 ? '#,##0' : '#,##0.${'#' * maxFractionDigits}';
  return NumberFormat(pattern, locale ?? Intl.defaultLocale).format(value);
}

/// "4.2 lb" — always in the unit the angler entered (the Swift app's `.asProvided` rule:
/// converting 19 in to "1.6 ft" silently disagrees with what was typed).
String formatMeasurement(Measurement<MeasureUnit> m, {String? locale}) =>
    '${formatNumber(m.value, locale: locale)} ${m.unit.symbol}';

String formatWholeNumber(double value, {String? locale}) =>
    formatNumber(value, maxFractionDigits: 0, locale: locale);
