import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format/number_format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/icons.dart';
import '../../domain/astro/moon_phase.dart';
import '../../domain/insights/insights_engine.dart';
import '../../domain/models/units.dart';
import 'bar_charts.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Computed once per change and shared by every card, rather than each card recomputing
    // the engine on its own.
    final report = ref.watch(insightsReportProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: SafeArea(
        child: report.totalCatches < InsightsEngine.minimumCatchesForPatterns
            ? EmptyState(
                icon: const Icon(Icons.bar_chart),
                title: 'Keep Logging',
                message: 'Patterns appear once you\'ve logged about ${InsightsEngine.minimumCatchesForPatterns} '
                    "catches — you're at ${report.totalCatches} so far.",
              )
            : SingleChildScrollView(
                child: ContentColumn(
                  child: Column(
                    spacing: Metrics.sectionSpacing,
                    children: [
                      _TotalsCard(report: report),
                      _SpeciesMixCard(report: report),
                      _HourOfDayCard(report: report),
                      _TopWatersCard(report: report),
                      _MoonPhaseCard(report: report),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.report});

  final InsightsReport report;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Totals & Personal Bests',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            spacing: Metrics.cardSpacing,
            children: [
              Expanded(
                child: StatTile(title: 'Total Catches', value: '${report.totalCatches}', icon: const FishIcon(size: 22)),
              ),
              Expanded(
                child: StatTile(
                  title: 'Species Logged',
                  value: '${report.speciesMix.length}',
                  icon: const Icon(Icons.format_list_bulleted),
                ),
              ),
            ],
          ),
          if (report.personalBests.isNotEmpty) ...[
            const SizedBox(height: Metrics.cardSpacing),
            const Divider(),
            const SizedBox(height: 8),
            for (final best in report.personalBests.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.emoji_events, size: 18, color: context.fish.trophy),
                    const SizedBox(width: 8),
                    Expanded(child: Text(best.speciesName, style: context.text.fishBody)),
                    Text(
                      formatMeasurement(Measurement(best.weightInPounds, MassUnit.pounds)),
                      style: context.text.fishBody.copyWith(color: context.scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SpeciesMixCard extends StatelessWidget {
  const _SpeciesMixCard({required this.report});

  final InsightsReport report;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Species Mix',
      child: HorizontalBars(
        items: [for (final s in report.speciesMix.take(8)) (label: s.speciesName, value: s.count)],
        color: context.fish.currentWater,
      ),
    );
  }
}

class _HourOfDayCard extends StatelessWidget {
  const _HourOfDayCard({required this.report});

  final InsightsReport report;

  static String _hourLabel(int h) {
    final hour12 = h % 12 == 0 ? 12 : h % 12;
    return '$hour12${h < 12 ? 'a' : 'p'}';
  }

  @override
  Widget build(BuildContext context) {
    final counts = [for (final h in report.hourOfDayDistribution) h.count];
    return SectionCard(
      title: 'Catches by Hour',
      child: VerticalBars(
        values: counts,
        color: context.fish.currentWater,
        labelFor: (i) => i % 3 == 0 ? _hourLabel(i) : null,
        semanticLabelFor: (i) => '${_hourLabel(i)}: ${counts[i]} ${counts[i] == 1 ? 'catch' : 'catches'}',
      ),
    );
  }
}

class _TopWatersCard extends StatelessWidget {
  const _TopWatersCard({required this.report});

  final InsightsReport report;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Top Waters',
      child: report.waterBodyLeaderboard.isEmpty
          ? Text(
              'No water bodies logged yet.',
              style: context.text.fishBody.copyWith(color: context.scheme.onSurfaceVariant),
            )
          : HorizontalBars(
              items: [for (final w in report.waterBodyLeaderboard) (label: w.waterBodyName, value: w.count)],
              color: context.fish.lureAccent,
            ),
    );
  }
}

class _MoonPhaseCard extends StatelessWidget {
  const _MoonPhaseCard({required this.report});

  final InsightsReport report;

  static const _short = {
    MoonPhase.newMoon: 'New',
    MoonPhase.waxingCrescent: 'Wax.\nCres.',
    MoonPhase.firstQuarter: '1st\nQtr',
    MoonPhase.waxingGibbous: 'Wax.\nGibb.',
    MoonPhase.fullMoon: 'Full',
    MoonPhase.waningGibbous: 'Wan.\nGibb.',
    MoonPhase.lastQuarter: '3rd\nQtr',
    MoonPhase.waningCrescent: 'Wan.\nCres.',
  };

  @override
  Widget build(BuildContext context) {
    final items = report.moonPhaseDistribution;
    return SectionCard(
      title: 'Moon Phase',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VerticalBars(
            values: [for (final m in items) m.count],
            // The Swift app used Abyss here, which is near-black on a dark surface; fall back to
            // the lighter water teal there so the bars stay visible.
            color: Theme.of(context).brightness == Brightness.dark ? context.fish.currentWater : context.fish.abyss,
            height: 150,
            showCounts: true,
            labelFor: (i) => _short[items[i].phase],
            semanticLabelFor: (i) =>
                '${items[i].phase.label}: ${items[i].count} ${items[i].count == 1 ? 'catch' : 'catches'}',
          ),
          const SizedBox(height: 12),
          Text(
            'Folklore, not forecast — shown for curiosity, not prediction.',
            style: context.text.fishCaption.copyWith(color: context.scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
