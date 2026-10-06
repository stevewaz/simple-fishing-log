/// Quick presets rather than a custom date-range picker — these cover what anglers actually
/// ask ("what did I catch this year?") with a single tap.
enum MapDateRange {
  allTime('All Time'),
  thisYear('This Year'),
  last30Days('Last 30 Days'),
  last7Days('Last 7 Days');

  const MapDateRange(this.label);

  final String label;

  /// Compares in the zone of [referenceDate] (local by default). Day arithmetic goes through
  /// the `DateTime` constructor, so "30 days ago" means 30 calendar days and doesn't drift
  /// an hour across a daylight-saving change.
  bool contains(DateTime date, {DateTime? referenceDate}) {
    final ref = referenceDate ?? DateTime.now();
    final d = ref.isUtc ? date.toUtc() : date.toLocal();
    switch (this) {
      case MapDateRange.allTime:
        return true;
      case MapDateRange.thisYear:
        return d.year == ref.year;
      case MapDateRange.last30Days:
        return !d.isBefore(_daysBefore(ref, 30));
      case MapDateRange.last7Days:
        return !d.isBefore(_daysBefore(ref, 7));
    }
  }

  static DateTime _daysBefore(DateTime ref, int days) {
    final args = [ref.year, ref.month, ref.day - days, ref.hour, ref.minute, ref.second, ref.millisecond];
    return ref.isUtc
        ? DateTime.utc(args[0], args[1], args[2], args[3], args[4], args[5], args[6])
        : DateTime(args[0], args[1], args[2], args[3], args[4], args[5], args[6]);
  }
}
