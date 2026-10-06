import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/format/dates.dart';
import '../../core/format/number_format.dart';
import '../../core/platform/maps_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/catch_widgets.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/map_widgets.dart';
import '../../domain/astro/moon_phase.dart';
import '../../domain/astro/solunar_calculator.dart';
import '../../domain/models/catch_entry.dart';
import '../../domain/models/units.dart';
import '../home/home_screen.dart' show SolunarRows;

class CatchDetailScreen extends ConsumerWidget {
  const CatchDetailScreen({super.key, required this.catchId});

  final String catchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(catchProvider(catchId));
    return async.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
      error: (_, _) => Scaffold(appBar: AppBar(), body: const Center(child: Text("Couldn't load this catch."))),
      data: (entry) {
        if (entry == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Catch Details')),
            body: const EmptyState(
              icon: Icon(Icons.search_off),
              title: 'Catch not found',
              message: 'It may have been deleted.',
            ),
          );
        }
        return _CatchDetailView(entry: entry);
      },
    );
  }
}

class _CatchDetailView extends ConsumerWidget {
  const _CatchDetailView({required this.entry});

  final CatchEntry entry;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this catch?'),
        content: Text('${entry.displaySpecies} will be removed from your log. You can undo this right after.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.scheme.error,
              foregroundColor: context.scheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final repo = ref.read(appDataProvider).catches;
    final messenger = ScaffoldMessenger.of(context);
    context.pop();
    await repo.delete(entry.id);
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('Deleted ${entry.displaySpecies}'),
        action: SnackBarAction(label: 'Undo', onPressed: () => repo.restore(entry.id)),
      ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coordinate = entry.hasCoordinate ? LatLng(entry.latitude!, entry.longitude!) : null;
    final solunar = coordinate == null
        ? null
        : SolunarCalculator.calculate(
            entry.date,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            dayStart: localDayStart(entry.date),
          );
    final notes = entry.notes;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Catch Details'),
        actions: [
          TextButton(onPressed: () => context.push(Routes.editCatch(entry.id)), child: const Text('Edit')),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) {
              if (value == 'delete') _confirmDelete(context, ref);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'delete',
                child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete'), contentPadding: EdgeInsets.zero),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: ContentColumn(
            child: Column(
              spacing: Metrics.sectionSpacing,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HeroPhotoHeader(entry: entry),
                SurfaceCard(
                  padding: const EdgeInsets.all(Metrics.cardSpacing + 4),
                  child: _DetailGrid(entry: entry),
                ),
                if (coordinate != null) ...[
                  _MiniMap(entry: entry, coordinate: coordinate),
                  // The mini-map is deliberately non-interactive, so directions live in their
                  // own button rather than making the map tappable.
                  OutlinedButton.icon(
                    onPressed: () => openDirections(
                      latitude: coordinate.latitude,
                      longitude: coordinate.longitude,
                      label: entry.displaySpecies,
                    ),
                    icon: const Icon(Icons.directions_outlined),
                    label: const Text('Directions'),
                  ),
                  if (solunar != null)
                    SectionCard(
                      title: 'Best Times',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 6,
                        children: [
                          SolunarRows(title: 'Major', periods: solunar.majorPeriods),
                          SolunarRows(title: 'Minor', periods: solunar.minorPeriods),
                          const SizedBox(height: 4),
                          Text(
                            'Folklore, not forecast — solunar theory has no controlled evidence behind it.',
                            style: context.text.fishCaption.copyWith(color: context.scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                ],
                if (notes != null && notes.isNotEmpty)
                  SectionCard(title: 'Notes', child: SelectableText(notes, style: context.text.fishBody)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniMap extends ConsumerWidget {
  const _MiniMap({required this.entry, required this.coordinate});

  final CatchEntry entry;
  final LatLng coordinate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The depth chart where the catch was made; outside chart coverage the tiles are
    // transparent and this is just the standard map.
    const style = MapStyleOption.chart;
    return Semantics(
      label: 'Map showing where this fish was caught',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Metrics.cardCornerRadius),
        child: SizedBox(
          height: 180,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: coordinate,
              initialZoom: 15,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
            ),
            children: [
              ...style.tileLayers(provider: ref.watch(tileProviderOverrideProvider)),
              MarkerLayer(markers: [
                Marker(
                  point: coordinate,
                  width: 44,
                  height: 44,
                  child: CatchMarker(selected: true, label: entry.displaySpecies),
                ),
              ]),
              const MapAttribution(style: style),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailGrid extends StatelessWidget {
  const _DetailGrid({required this.entry});

  final CatchEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = entry.conditions;
    final rows = <(String, String)>[
      if (entry.waterBodyName case final w? when w.isNotEmpty) ('Water body', w),
      if (entry.locationName.isNotEmpty) ('Location', entry.locationName),
      if (entry.depth case final d?) ('Depth', formatMeasurement(d)),
      ('Boat', entry.wasFromBoat ? 'Yes' : 'No'),
      ('Released', entry.wasReleased ? 'Yes' : 'No'),
      if (entry.weight case final w?) ('Weight', formatMeasurement(w)),
      if (entry.length case final l?) ('Length', formatMeasurement(l)),
      ('Moon phase', MoonPhase.fromDate(entry.date).label),
      if (c.weatherCondition != null) ('Weather', c.weatherCondition!),
      if (c.airTempC case final t?) ('Air temp', '${formatWholeNumber(celsiusToFahrenheit(t))}°F'),
      if (c.waterTempC case final t?) ('Water temp', '${formatWholeNumber(celsiusToFahrenheit(t))}°F'),
      if (c.windSpeedMS case final w?)
        (
          'Wind',
          [
            '${formatWholeNumber(metersPerSecondToMph(w))} mph',
            if (c.windDirectionDegrees != null) '${formatWholeNumber(c.windDirectionDegrees!)}°',
          ].join(' ')
        ),
      if (c.pressureHPa case final p?)
        ('Pressure', '${formatWholeNumber(p)} hPa${c.pressureTrend == null ? '' : ', ${c.pressureTrend}'}'),
      if (c.waterConditions != null) ('Water', c.waterConditions!),
      if (entry.gear.rodReel != null) ('Rod & reel', entry.gear.rodReel!),
      if (entry.gear.baitLure != null) ('Bait/lure', entry.gear.baitLure!),
      if (entry.gear.lineType != null) ('Line', entry.gear.lineType!),
      if (entry.gear.technique != null) ('Technique', entry.gear.technique!),
    ];

    return Column(
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 112,
                  child: Text(label, style: context.text.fishBody.copyWith(color: context.scheme.onSurfaceVariant)),
                ),
                Expanded(child: Text(value, style: context.text.fishBody)),
              ],
            ),
          ),
      ],
    );
  }
}
