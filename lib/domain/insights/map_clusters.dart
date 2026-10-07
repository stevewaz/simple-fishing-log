import 'dart:math' as math;

import '../models/catch_entry.dart';

/// Catches that would sit on top of each other on the map at a given zoom. A single catch is a
/// cluster of one; the map draws those as ordinary markers.
class MapCluster {
  const MapCluster(this.catches, this.latitude, this.longitude);

  final List<CatchEntry> catches;

  /// The middle of the group (a plain average — these are small areas).
  final double latitude;
  final double longitude;

  bool get isSingle => catches.length == 1;
}

/// Above this zoom everything is drawn individually: catches that still overlap are at the same
/// spot, and no amount of zooming in would pull them apart.
const double kMaxClusterZoom = 16;

/// Groups catches that fall in the same [cellSize]-pixel square of the map at [zoom].
///
/// A grid is cheap and, unlike chasing nearest neighbours, gives the same answer for the same
/// zoom every time, so markers don't shuffle as the angler pans. Its one quirk is that two
/// catches either side of a cell edge stay apart, which is fine for tidying a crowded map.
/// Only the whole-number part of [zoom] matters. Catches without a position are ignored.
List<MapCluster> clusterCatches(Iterable<CatchEntry> catches, {required double zoom, double cellSize = 56}) {
  final located = [for (final c in catches) if (c.hasCoordinate) c];
  if (zoom >= kMaxClusterZoom) {
    return [for (final c in located) MapCluster([c], c.latitude!, c.longitude!)];
  }

  final world = 256 * math.pow(2, zoom.floor());
  final cells = <(int, int), List<CatchEntry>>{};
  for (final c in located) {
    final x = (c.longitude! + 180) / 360 * world;
    final sinLat = math.sin(c.latitude!.clamp(-85.05112878, 85.05112878) * math.pi / 180);
    final y = (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) * world;
    cells.putIfAbsent(((x / cellSize).floor(), (y / cellSize).floor()), () => []).add(c);
  }

  return [
    for (final group in cells.values)
      MapCluster(
        group,
        group.fold(0.0, (sum, c) => sum + c.latitude!) / group.length,
        group.fold(0.0, (sum, c) => sum + c.longitude!) / group.length,
      ),
  ];
}
