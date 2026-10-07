import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../app/constants.dart';
import '../theme/app_theme.dart';
import 'icons.dart';
import 'noaa_chart_tile_provider.dart';

/// Map styles, as in the Swift app: Standard, Hybrid and Satellite. Satellite imagery renders
/// the actual shoreline of lakes and rivers, which a vector style only approximates — useful
/// for pinpointing coves, inlets and river bends.
///
/// Tiles come from public, key-less servers so the app works out of the box. Both have usage
/// terms that rule out heavy or commercial use — before shipping, point these at a provider
/// you have an account with (MapTiler, Stadia, Mapbox…); this is the only place to change.
enum MapStyleOption {
  standard('Standard', Icons.map_outlined),
  hybrid('Hybrid', Icons.layers_outlined),
  satellite('Satellite', Icons.satellite_alt_outlined),

  /// NOAA (US) and Canadian Hydrographic Service nautical charts over OpenStreetMap: depth
  /// soundings and contours, depth shading, buoys, hazards and ramps. Elsewhere it is simply
  /// the standard map.
  chart('Water chart', Icons.waves);

  const MapStyleOption(this.label, this.icon);

  final String label;
  final IconData icon;

  static const _osm = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const _esriImagery =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
  static const _esriLabels =
      'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}';

  /// [provider] overrides how tiles are fetched; null uses flutter_map's default (network,
  /// with its on-device cache on iOS/Android). Tests and a future offline-tiles feature
  /// swap it via `tileProviderOverrideProvider`.
  List<Widget> tileLayers({TileProvider? provider}) {
    TileLayer layer(String url) => TileLayer(
          urlTemplate: url,
          userAgentPackageName: kPackageId,
          maxNativeZoom: this == MapStyleOption.standard || this == MapStyleOption.chart ? 19 : 18,
          tileProvider: provider,
        );
    return switch (this) {
      MapStyleOption.standard => [layer(_osm)],
      MapStyleOption.satellite => [layer(_esriImagery)],
      MapStyleOption.hybrid => [layer(_esriImagery), layer(_esriLabels)],
      MapStyleOption.chart => [
          layer(_osm),
          TileLayer(
            // NoaaChartTileProvider builds its own bounding-box URLs and ignores this; it is
            // only here so a generic provider swapped in (tests, offline packs) can't throw.
            urlTemplate: NoaaChartTileProvider.endpoint,
            userAgentPackageName: kPackageId,
            minZoom: NoaaChartTileProvider.minZoom,
            maxNativeZoom: 18,
            tileProvider: provider ?? _noaaChartProvider,
          ),
          // NOAA draws nothing in Canadian waters (the Ontario side of the Great Lakes), so the
          // Canadian Hydrographic Service's chart goes on top. Both are transparent where the
          // other has the coverage; the bounds only stop it being asked about the rest of the
          // world.
          TileLayer(
            urlTemplate: NoaaChartTileProvider.chsEndpoint,
            userAgentPackageName: kPackageId,
            minZoom: NoaaChartTileProvider.minZoom,
            maxNativeZoom: 18,
            tileBounds: _canada,
            tileProvider: provider ?? _chsChartProvider,
          ),
        ],
    };
  }

  /// One shared instance of each, so their on-device tile caches survive rebuilds.
  static final NoaaChartTileProvider _noaaChartProvider = NoaaChartTileProvider();
  static final NoaaChartTileProvider _chsChartProvider =
      NoaaChartTileProvider(exportUrl: NoaaChartTileProvider.chsEndpoint);

  /// A rough box around Canada, from Pelee Island in Lake Erie north.
  static final LatLngBounds _canada = LatLngBounds(const LatLng(41.6, -141.1), const LatLng(83.2, -52.5));

  String get attribution => switch (this) {
        MapStyleOption.standard => '© OpenStreetMap contributors',
        MapStyleOption.satellite || MapStyleOption.hybrid => 'Imagery © Esri, Maxar, Earthstar Geographics',
        MapStyleOption.chart =>
          'Charts: NOAA ENC, Canadian Hydrographic Service · depths in meters · © OpenStreetMap contributors',
      };
}

class MapAttribution extends StatelessWidget {
  const MapAttribution({super.key, required this.style});

  final MapStyleOption style;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: LayoutBuilder(
        builder: (context, constraints) => Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          // Never wider than the map, so a long credit wraps instead of overflowing.
          constraints: BoxConstraints(maxWidth: constraints.maxWidth - 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(style.attribution, style: const TextStyle(fontSize: 10, color: Colors.black87)),
        ),
      ),
    );
  }
}

/// The pin for one catch: a fish on water-teal, or a trophy on gold for a species' personal
/// best.
class CatchMarker extends StatelessWidget {
  const CatchMarker({super.key, this.personalBest = false, this.selected = false, this.label});

  final bool personalBest;
  final bool selected;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final fish = context.fish;
    final fill = personalBest ? fish.trophy : fish.currentWater;
    final fg = personalBest ? const Color(0xFF3D2A00) : Colors.white;
    final size = selected ? 46.0 : 38.0;
    return Semantics(
      label: '${personalBest ? 'Personal best, ' : ''}${label ?? 'Catch'}',
      button: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: selected ? 3 : 2),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        alignment: Alignment.center,
        child: personalBest
            ? Icon(Icons.emoji_events, size: size * 0.55, color: fg)
            : FishIcon(size: size * 0.58, color: fg),
      ),
    );
  }
}

/// Several catches that would overlap at this zoom: a count in a haloed disc, bigger than a
/// single catch's pin so the two are never confused. Tapping it zooms in.
class ClusterMarker extends StatelessWidget {
  const ClusterMarker({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final fill = context.fish.currentWater;
    return Semantics(
      label: '$count catches close together. Double tap to zoom in.',
      button: true,
      child: ExcludeSemantics(
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: fill.withValues(alpha: 0.3), shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 2))],
            ),
            alignment: Alignment.center,
            child: Text(
              count > 99 ? '99+' : '$count',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
        ),
      ),
    );
  }
}

/// The angler's own position: the familiar blue dot with a soft halo, deliberately unlike
/// the teal fish pins so it can never be mistaken for a catch.
class MyLocationMarker extends StatelessWidget {
  const MyLocationMarker({super.key});

  static const Color blue = Color(0xFF1A73E8);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'You are here',
      child: ExcludeSemantics(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: blue.withValues(alpha: 0.18), shape: BoxShape.circle),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: blue,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 5, offset: Offset(0, 1))],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
