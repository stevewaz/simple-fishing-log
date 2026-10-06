import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/platform/maps_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/catch_widgets.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/map_widgets.dart';
import '../../core/widgets/noaa_chart_tile_provider.dart';
import '../../domain/insights/map_date_range.dart';
import '../../domain/models/catch_entry.dart';
import 'chart_help_sheet.dart';

class CatchMapScreen extends ConsumerStatefulWidget {
  const CatchMapScreen({super.key});

  @override
  ConsumerState<CatchMapScreen> createState() => _CatchMapScreenState();
}

class _CatchMapScreenState extends ConsumerState<CatchMapScreen> {
  final _controller = MapController();
  MapStyleOption _style = MapStyleOption.standard;
  MapDateRange _range = MapDateRange.allTime;
  Set<String> _species = {};
  bool _trails = false;
  String? _selectedId;

  /// Opening the map asks for the angler's position once. The permission prompt is the
  /// direct result of tapping the Map tab, never something that fires on its own.
  bool _askedForLocation = false;

  /// Once the angler pans or zooms themselves, a late GPS fix must not yank the camera away.
  bool _userMoved = false;

  /// Where to zoom when centring on the angler: wide enough to see the water around them
  /// and any nearby catches, not a street-level view.
  static const double _meZoom = 13;

  /// The map's current zoom, tracked only to know whether the depth chart can show detail.
  double _zoom = _meZoom;

  bool get _chartTooFarOut =>
      _style == MapStyleOption.chart && _zoom < NoaaChartTileProvider.minZoom;

  void _trackZoom(double zoom) {
    final crossed = (zoom >= NoaaChartTileProvider.minZoom) != (_zoom >= NoaaChartTileProvider.minZoom);
    _zoom = zoom;
    if (crossed && mounted) setState(() {});
  }

  /// The chart draws nothing useful below zoom 10, so offer a one-tap way in.
  void _zoomToChart() {
    try {
      _controller.move(_controller.camera.center, NoaaChartTileProvider.minZoom + 1);
    } catch (_) {}
  }

  bool get _isFiltering => _range != MapDateRange.allTime || _species.isNotEmpty;

  @override
  void initState() {
    super.initState();
    ref.listenManual<LocationState>(locationControllerProvider, _onLocation, fireImmediately: true);
  }

  void _onLocation(LocationState? previous, LocationState next) {
    // First time here and nobody has been asked yet → ask now.
    if (!_askedForLocation && next.status == LocationStatus.needsPermission) {
      _askedForLocation = true;
      Future.microtask(() => ref.read(locationControllerProvider.notifier).refresh());
    }
    // A fresh fix arrived: bring the camera to it (unless the angler is already exploring).
    final me = _myPosition(next);
    final hadFresh = previous != null && _myPosition(previous) != null;
    if (me != null && !hadFresh && !_userMoved) _moveTo(me);
  }

  /// Only a *fresh* fix counts. The remembered position Home shows instantly is fine for
  /// solunar times, but a pin that says "you are here" must never be stale.
  LatLng? _myPosition(LocationState s) {
    final fix = s.fix;
    if (fix == null || s.isStale) return null;
    return LatLng(fix.latitude, fix.longitude);
  }

  void _moveTo(LatLng point) {
    // The map may not be attached yet (it is created after the first frame).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _controller.move(point, _meZoom);
      } catch (_) {}
    });
  }

  Future<void> _goToMe() async {
    final notifier = ref.read(locationControllerProvider.notifier);
    await notifier.refresh();
    if (!mounted) return;
    final state = ref.read(locationControllerProvider);
    final me = _myPosition(state);
    if (me != null) {
      _userMoved = false;
      _moveTo(me);
      return;
    }
    final message = switch (state.status) {
      LocationStatus.blocked => 'Location is turned off for this app. Allow it in your device or browser settings.',
      LocationStatus.servicesOff => 'Location services are turned off on this device.',
      _ => "Couldn't get your location.",
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  List<CatchEntry> _filtered(List<CatchEntry> mapped) => [
        for (final e in mapped)
          if (_range.contains(e.date) && (_species.isEmpty || _species.contains(e.speciesName))) e,
      ];

  /// A single catch (or several in one cove) would otherwise zoom to the street. Capping at
  /// zoom 13 matches the Swift app's 0.02° minimum span.
  static const double _maxFitZoom = 13;

  CameraFit _fitFor(List<CatchEntry> entries) => CameraFit.coordinates(
        coordinates: [for (final e in entries) LatLng(e.latitude!, e.longitude!)],
        padding: const EdgeInsets.fromLTRB(56, 96, 56, 56),
        maxZoom: _maxFitZoom,
      );

  void _fitCatches(List<CatchEntry> entries) {
    if (entries.isEmpty) return;
    _userMoved = true; // an explicit camera choice: don't let a late fix override it
    // The map may not be attached yet on the first frame after a filter change.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _controller.fitCamera(_fitFor(entries));
      } catch (_) {}
    });
  }

  /// One polyline per trip with 2+ mapped catches, in chronological order. A single-catch
  /// trip has nothing to connect, so it's skipped instead of drawing a zero-length line.
  List<Polyline> _tripTrails(List<CatchEntry> entries) {
    if (!_trails) return const [];
    final byTrip = <String, List<CatchEntry>>{};
    for (final e in entries) {
      final id = e.tripId;
      if (id != null) byTrip.putIfAbsent(id, () => []).add(e);
    }
    return [
      for (final group in byTrip.values)
        if (group.length >= 2)
          Polyline(
            points: [
              for (final e in (group..sort((a, b) => a.date.compareTo(b.date)))) LatLng(e.latitude!, e.longitude!),
            ],
            strokeWidth: 3,
            color: context.fish.lureAccent,
          ),
    ];
  }

  Future<void> _openFilters(List<String> available) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _FilterSheet(
        range: _range,
        species: _species,
        available: available,
        onChanged: (range, species) {
          setState(() {
            _range = range;
            _species = species;
            _selectedId = null;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(catchesProvider).value ?? const <CatchEntry>[];
    final location = ref.watch(locationControllerProvider);
    final me = _myPosition(location);
    final mapped = [for (final e in all) if (e.hasCoordinate) e];
    final filtered = _filtered(mapped);
    final personalBests = ref.watch(personalBestIdsProvider);
    final available = ({for (final e in mapped) e.speciesName}.toList()..sort());
    final selected = filtered.where((e) => e.id == _selectedId).firstOrNull;

    Widget body;
    if (me == null && mapped.isEmpty) {
      // Nothing to centre on and nothing to plot — but the angler can still ask for "here".
      final canAsk = location.status != LocationStatus.blocked && location.status != LocationStatus.servicesOff;
      body = EmptyState(
        icon: const Icon(Icons.map_outlined),
        title: 'No Mapped Catches',
        message: location.status == LocationStatus.locating
            ? 'Finding your location…'
            : 'Catches with a saved location will appear here. Turn on location to see where you are.',
        actionLabel: canAsk && location.status != LocationStatus.locating ? 'Show My Location' : null,
        onAction: canAsk ? _goToMe : null,
      );
    } else if (me == null && filtered.isEmpty) {
      body = EmptyState(
        icon: const Icon(Icons.map_outlined),
        title: 'No Catches Match',
        message: 'Try a different species or date range.',
        actionLabel: 'Clear Filters',
        onAction: () => setState(() {
          _range = MapDateRange.allTime;
          _species = {};
        }),
      );
    } else {
      // Personal bests last, so a trophy is never hidden under a regular marker.
      final ordered = [...filtered]..sort((a, b) {
          final pa = personalBests.contains(a.id) ? 1 : 0;
          final pb = personalBests.contains(b.id) ? 1 : 0;
          return pa.compareTo(pb);
        });
      body = Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              // Where the angler is takes priority; with no fix, frame the catches instead.
              initialCenter: me ?? const LatLng(0, 0),
              initialZoom: me != null ? _meZoom : 2,
              initialCameraFit: me == null && filtered.isNotEmpty ? _fitFor(filtered) : null,
              minZoom: 2,
              maxZoom: 19,
              onTap: (_, _) => setState(() => _selectedId = null),
              onMapReady: () => _trackZoom(_controller.camera.zoom),
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) _userMoved = true;
                _trackZoom(camera.zoom);
              },
            ),
            children: [
              ..._style.tileLayers(provider: ref.watch(tileProviderOverrideProvider)),
              PolylineLayer(polylines: _tripTrails(filtered)),
              // The angler's own pin sits under the catch markers.
              if (me != null)
                MarkerLayer(markers: [
                  Marker(point: me, width: 44, height: 44, child: const MyLocationMarker()),
                ]),
              MarkerLayer(markers: [
                for (final e in ordered)
                  Marker(
                    point: LatLng(e.latitude!, e.longitude!),
                    width: 50,
                    height: 50,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _selectedId = e.id),
                      child: CatchMarker(
                        personalBest: personalBests.contains(e.id),
                        selected: e.id == _selectedId,
                        label: e.displaySpecies,
                      ),
                    ),
                  ),
              ]),
              MapAttribution(style: _style),
            ],
          ),
          Positioned(
            top: 12,
            right: 12,
            child: _MapControls(
              style: _style,
              isFiltering: _isFiltering,
              showsTrails: _trails,
              isLocating: location.status == LocationStatus.locating,
              hasCatches: filtered.isNotEmpty,
              onStyle: (s) => setState(() => _style = s),
              onFilters: () => _openFilters(available),
              onTrails: () => setState(() => _trails = !_trails),
              onMyLocation: _goToMe,
              onFitCatches: () => _fitCatches(filtered),
            ),
          ),
          // Top-left notices: filter hint and water-chart helpers. Right side stays clear of the
          // control column.
          if ((_isFiltering && filtered.isEmpty) || _style == MapStyleOption.chart)
            Positioned(
              left: 12,
              right: 72,
              top: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  if (_isFiltering && filtered.isEmpty)
                    Material(
                      color: context.scheme.surface.withValues(alpha: 0.96),
                      elevation: 3,
                      borderRadius: BorderRadius.circular(Metrics.controlCornerRadius),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                        child: Row(
                          children: [
                            const Expanded(child: Text('No catches match these filters.')),
                            TextButton(
                              onPressed: () => setState(() {
                                _range = MapDateRange.allTime;
                                _species = {};
                              }),
                              child: const Text('Clear'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_style == MapStyleOption.chart)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (_chartTooFarOut)
                          ActionChip(
                            avatar: const Icon(Icons.zoom_in, size: 18),
                            label: const Text('Zoom in for depths'),
                            onPressed: _zoomToChart,
                            backgroundColor: context.scheme.surface,
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.help_outline, size: 18),
                          label: const Text('Depths in meters'),
                          onPressed: () => showChartHelp(context),
                          backgroundColor: context.scheme.surface,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          if (selected != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: Metrics.maxContentWidth),
                  child: _SelectedPreview(
                    entry: selected,
                    onClose: () => setState(() => _selectedId = null),
                    onDetails: () => context.push(Routes.catchIn(Routes.map, selected.id)),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return Scaffold(appBar: AppBar(title: const Text('Map')), body: body);
  }
}

class _MapControls extends StatelessWidget {
  const _MapControls({
    required this.style,
    required this.isFiltering,
    required this.showsTrails,
    required this.isLocating,
    required this.hasCatches,
    required this.onStyle,
    required this.onFilters,
    required this.onTrails,
    required this.onMyLocation,
    required this.onFitCatches,
  });

  final MapStyleOption style;
  final bool isFiltering;
  final bool showsTrails;
  final bool isLocating;
  final bool hasCatches;
  final ValueChanged<MapStyleOption> onStyle;
  final VoidCallback onFilters;
  final VoidCallback onTrails;
  final VoidCallback onMyLocation;
  final VoidCallback onFitCatches;

  @override
  Widget build(BuildContext context) {
    final fish = context.fish;
    ButtonStyle tonal(bool active) => IconButton.styleFrom(
          backgroundColor: active ? fish.shallows : context.scheme.surface,
          foregroundColor: active ? context.scheme.onPrimaryContainer : context.scheme.onSurface,
          elevation: 3,
          shadowColor: Colors.black54,
          fixedSize: const Size(48, 48),
        );

    return Column(
      spacing: 10,
      children: [
        PopupMenuButton<MapStyleOption>(
          tooltip: 'Map style',
          initialValue: style,
          onSelected: onStyle,
          style: tonal(false),
          icon: Icon(style.icon),
          itemBuilder: (_) => [
            for (final s in MapStyleOption.values)
              CheckedPopupMenuItem(
                value: s,
                checked: s == style,
                child: Text(s.label),
              ),
          ],
        ),
        IconButton(
          tooltip: 'My location',
          style: tonal(false),
          onPressed: isLocating ? null : onMyLocation,
          icon: isLocating
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.my_location),
        ),
        IconButton(
          tooltip: 'Filter catches',
          style: tonal(isFiltering),
          onPressed: onFilters,
          icon: Icon(isFiltering ? Icons.filter_alt : Icons.filter_alt_outlined),
        ),
        IconButton(
          tooltip: showsTrails ? 'Hide trip trails' : 'Show trip trails',
          style: tonal(showsTrails),
          onPressed: onTrails,
          icon: const Icon(Icons.route_outlined),
        ),
        IconButton(
          tooltip: 'Fit all catches',
          style: tonal(false),
          onPressed: hasCatches ? onFitCatches : null,
          icon: const Icon(Icons.center_focus_strong_outlined),
        ),
      ],
    );
  }
}

class _SelectedPreview extends StatelessWidget {
  const _SelectedPreview({required this.entry, required this.onClose, required this.onDetails});

  final CatchEntry entry;
  final VoidCallback onClose;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.scheme.surface.withValues(alpha: 0.96),
      elevation: 6,
      borderRadius: BorderRadius.circular(Metrics.cardCornerRadius + 4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                CatchCard(entry: entry, onTap: onDetails),
                Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton(
                    tooltip: 'Close',
                    icon: Icon(Icons.cancel, color: context.scheme.onSurfaceVariant),
                    onPressed: onClose,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onDetails,
                  icon: const Icon(Icons.info_outline),
                  label: const Text('Details'),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => openDirections(
                    latitude: entry.latitude!,
                    longitude: entry.longitude!,
                    label: entry.displaySpecies,
                  ),
                  icon: const Icon(Icons.directions_outlined),
                  label: const Text('Directions'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.range,
    required this.species,
    required this.available,
    required this.onChanged,
  });

  final MapDateRange range;
  final Set<String> species;
  final List<String> available;
  final void Function(MapDateRange range, Set<String> species) onChanged;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late MapDateRange _range = widget.range;
  late Set<String> _species = {...widget.species};

  void _update() => widget.onChanged(_range, {..._species});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Filter catches', style: context.text.fishTitle)),
                TextButton(
                  onPressed: _range == MapDateRange.allTime && _species.isEmpty
                      ? null
                      : () {
                          setState(() {
                            _range = MapDateRange.allTime;
                            _species = {};
                          });
                          _update();
                        },
                  child: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Date range', style: context.text.fishHeadline),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in MapDateRange.values)
                  ChoiceChip(
                    label: Text(r.label),
                    selected: _range == r,
                    onSelected: (_) {
                      setState(() => _range = r);
                      _update();
                    },
                  ),
              ],
            ),
            if (widget.available.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Species', style: context.text.fishHeadline),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in widget.available)
                    FilterChip(
                      label: Text(s.isEmpty ? 'Unknown species' : s),
                      selected: _species.contains(s),
                      onSelected: (on) {
                        setState(() => on ? _species.add(s) : _species.remove(s));
                        _update();
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
