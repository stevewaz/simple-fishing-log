import '../astro/moon_phase.dart';
import '../models/catch_entry.dart';
import '../models/units.dart';

/// A plain snapshot of the fields Insights needs — never `CatchEntry` itself. A deliberate
/// testability boundary: [InsightsEngine] stays a pure function over these values.
class CatchSummary {
  const CatchSummary({
    required this.id,
    required this.date,
    required this.speciesName,
    this.weightInPounds,
    this.waterBodyName,
    required this.moonPhase,
  });

  final String id;
  final DateTime date;
  final String speciesName;
  final double? weightInPounds;
  final String? waterBodyName;
  final MoonPhase moonPhase;

  factory CatchSummary.fromEntry(CatchEntry entry) => CatchSummary(
        id: entry.id,
        date: entry.date,
        speciesName: entry.speciesName.isEmpty ? 'Unknown species' : entry.speciesName,
        // Always normalized to pounds here: a 2 kg fish (~4.4 lb) must beat a 4 lb fish even
        // though 2 < 4 as raw stored numbers.
        weightInPounds: entry.weight?.valueIn(MassUnit.pounds),
        waterBodyName: entry.waterBodyName,
        moonPhase: MoonPhase.fromDate(entry.date),
      );
}

class SpeciesCount {
  const SpeciesCount(this.speciesName, this.count);
  final String speciesName;
  final int count;
}

class WaterBodyCount {
  const WaterBodyCount(this.waterBodyName, this.count);
  final String waterBodyName;
  final int count;
}

class HourCount {
  const HourCount(this.hour, this.count);
  final int hour;
  final int count;
}

class MoonPhaseCount {
  const MoonPhaseCount(this.phase, this.count);
  final MoonPhase phase;
  final int count;
}

class PersonalBest {
  const PersonalBest({
    required this.speciesName,
    required this.weightInPounds,
    required this.date,
    required this.entryId,
  });

  final String speciesName;
  final double weightInPounds;
  final DateTime date;
  final String entryId;
}

class InsightsReport {
  const InsightsReport({
    required this.totalCatches,
    required this.personalBests,
    required this.speciesMix,
    required this.hourOfDayDistribution,
    required this.waterBodyLeaderboard,
    required this.moonPhaseDistribution,
  });

  static const empty = InsightsReport(
    totalCatches: 0,
    personalBests: [],
    speciesMix: [],
    hourOfDayDistribution: [],
    waterBodyLeaderboard: [],
    moonPhaseDistribution: [],
  );

  final int totalCatches;
  final List<PersonalBest> personalBests;
  final List<SpeciesCount> speciesMix;
  final List<HourCount> hourOfDayDistribution;
  final List<WaterBodyCount> waterBodyLeaderboard;
  final List<MoonPhaseCount> moonPhaseDistribution;
}

/// Five fixed cards, deliberately not a general query builder. Below
/// [minimumCatchesForPatterns], every pattern is statistically meaningless, so the screen
/// shows a "keep logging" state instead.
abstract final class InsightsEngine {
  static const int minimumCatchesForPatterns = 20;

  /// Heaviest catch per species. Shared by the map's trophy markers and the Insights
  /// personal-best card so the two can't drift apart.
  static List<PersonalBest> personalBests(Iterable<CatchSummary> summaries) {
    final bestBySpecies = <String, PersonalBest>{};
    for (final s in summaries) {
      final weight = s.weightInPounds;
      if (weight == null) continue;
      final existing = bestBySpecies[s.speciesName];
      if (existing != null && existing.weightInPounds >= weight) continue;
      bestBySpecies[s.speciesName] = PersonalBest(
        speciesName: s.speciesName,
        weightInPounds: weight,
        date: s.date,
        entryId: s.id,
      );
    }
    return bestBySpecies.values.toList()
      ..sort((a, b) => b.weightInPounds.compareTo(a.weightInPounds));
  }

  /// [toZone] decides which clock "hour of day" is read from. Production wants the angler's
  /// local hour; tests inject UTC.
  static InsightsReport compute(
    List<CatchSummary> summaries, {
    DateTime Function(DateTime)? toZone,
  }) {
    if (summaries.isEmpty) return InsightsReport.empty;
    final zone = toZone ?? (d) => d.toLocal();

    final speciesCounts = <String, int>{};
    for (final s in summaries) {
      speciesCounts.update(s.speciesName, (c) => c + 1, ifAbsent: () => 1);
    }
    final speciesMix = [
      for (final e in speciesCounts.entries) SpeciesCount(e.key, e.value),
    ]..sort((a, b) => b.count.compareTo(a.count));

    final hourCounts = List<int>.filled(24, 0);
    for (final s in summaries) {
      hourCounts[zone(s.date).hour]++;
    }

    final waterCounts = <String, int>{};
    for (final s in summaries) {
      final name = s.waterBodyName;
      if (name == null || name.isEmpty) continue;
      waterCounts.update(name, (c) => c + 1, ifAbsent: () => 1);
    }
    final waterLeaderboard = ([
      for (final e in waterCounts.entries) WaterBodyCount(e.key, e.value),
    ]..sort((a, b) => b.count.compareTo(a.count)))
        .take(10)
        .toList();

    final moonCounts = <MoonPhase, int>{};
    for (final s in summaries) {
      moonCounts.update(s.moonPhase, (c) => c + 1, ifAbsent: () => 1);
    }

    return InsightsReport(
      totalCatches: summaries.length,
      personalBests: personalBests(summaries),
      speciesMix: speciesMix,
      hourOfDayDistribution: [for (var h = 0; h < 24; h++) HourCount(h, hourCounts[h])],
      waterBodyLeaderboard: waterLeaderboard,
      moonPhaseDistribution: [
        for (final p in MoonPhase.values) MoonPhaseCount(p, moonCounts[p] ?? 0),
      ],
    );
  }
}
