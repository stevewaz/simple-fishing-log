import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/widgets/map_widgets.dart';
import '../../domain/insights/map_clusters.dart';
import '../../domain/models/catch_entry.dart';

/// The catch markers, with crowded ones merged into counts.
///
/// It reads the map's zoom itself, so only this layer rebuilds as the angler pinches. Personal
/// bests and the selected catch are never merged: a trophy should not vanish into a number, and
/// the catch whose card is open must stay on the map.
class CatchMarkerLayer extends StatelessWidget {
  const CatchMarkerLayer({
    super.key,
    required this.catches,
    required this.personalBests,
    required this.selectedId,
    required this.onSelect,
    required this.onCluster,
  });

  /// Catches that have a position.
  final List<CatchEntry> catches;
  final Set<String> personalBests;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<MapCluster> onCluster;

  @override
  Widget build(BuildContext context) {
    final zoom = MapCamera.of(context).zoom;
    bool pinned(CatchEntry e) => personalBests.contains(e.id) || e.id == selectedId;

    final clusters = clusterCatches([for (final e in catches) if (!pinned(e)) e], zoom: zoom);
    // Personal bests above ordinary catches, and the selected one above everything.
    final pins = [for (final e in catches) if (pinned(e)) e]
      ..sort((a, b) => (a.id == selectedId ? 1 : 0).compareTo(b.id == selectedId ? 1 : 0));

    return MarkerLayer(
      markers: [
        for (final c in clusters)
          if (c.isSingle) _single(c.catches.single) else _cluster(c),
        for (final e in pins) _single(e),
      ],
    );
  }

  Marker _single(CatchEntry e) => Marker(
        point: LatLng(e.latitude!, e.longitude!),
        width: 50,
        height: 50,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSelect(e.id),
          child: CatchMarker(
            personalBest: personalBests.contains(e.id),
            selected: e.id == selectedId,
            label: e.displaySpecies,
          ),
        ),
      );

  Marker _cluster(MapCluster c) => Marker(
        point: LatLng(c.latitude, c.longitude),
        width: 56,
        height: 56,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onCluster(c),
          child: ClusterMarker(count: c.catches.length),
        ),
      );
}
