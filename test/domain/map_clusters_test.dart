import 'package:flutter_test/flutter_test.dart';
import 'package:simple_fishing_log/domain/insights/map_clusters.dart';
import 'package:simple_fishing_log/domain/models/catch_entry.dart';

CatchEntry at(String id, double? lat, double? lon) =>
    CatchEntry(id: id, date: DateTime.utc(2026, 6, 1), speciesName: 'Walleye', latitude: lat, longitude: lon);

List<String> ids(MapCluster c) => [for (final e in c.catches) e.id]..sort();

void main() {
  // Two spots on Saginaw Bay about 1 km apart, and one on Lake Erie about 250 km away.
  final a = at('a', 43.640, -83.840);
  final b = at('b', 43.649, -83.840);
  final far = at('far', 41.46, -82.71);

  group('clusterCatches', () {
    test('zoomed out, catches close together become one cluster at their middle', () {
      final clusters = clusterCatches([a, b], zoom: 8);
      expect(clusters, hasLength(1));
      expect(ids(clusters.single), ['a', 'b']);
      expect(clusters.single.isSingle, isFalse);
      expect(clusters.single.latitude, closeTo(43.6445, 1e-9));
      expect(clusters.single.longitude, closeTo(-83.84, 1e-9));
    });

    test('zooming in pulls them apart again', () {
      final clusters = clusterCatches([a, b], zoom: 14);
      expect(clusters, hasLength(2));
      expect(clusters.every((c) => c.isSingle), isTrue);
    });

    test('catches far apart stay apart once the map is zoomed in past the regional view', () {
      for (final zoom in [5.0, 8.0, 12.0]) {
        expect(clusterCatches([a, far], zoom: zoom), hasLength(2), reason: 'zoom $zoom');
      }
    });

    test('every catch is in exactly one cluster, whatever the zoom', () {
      final all = [a, b, far, at('c', 43.7, -83.9), at('d', 45.0, -84.0)];
      for (final zoom in [2.0, 6.0, 9.0, 12.0, 15.0, 17.0]) {
        final seen = [for (final c in clusterCatches(all, zoom: zoom)) ...ids(c)]..sort();
        expect(seen, ['a', 'b', 'c', 'd', 'far'], reason: 'zoom $zoom');
      }
    });

    test('only the whole-number part of the zoom matters, so markers do not shuffle mid-pinch', () {
      List<List<String>> shape(double zoom) =>
          [for (final c in clusterCatches([a, b, far], zoom: zoom)) ids(c)]..sort((x, y) => x.first.compareTo(y.first));
      expect(shape(8.0), shape(8.99));
      expect(shape(13.0), shape(13.5));
    });

    test('from the max cluster zoom up, everything is drawn individually, even identical spots', () {
      final twin = at('twin', 43.640, -83.840); // exactly where `a` is
      final clusters = clusterCatches([a, twin], zoom: kMaxClusterZoom);
      expect(clusters, hasLength(2));
      expect(clusters.every((c) => c.isSingle), isTrue);
      expect(clusterCatches([a, twin], zoom: kMaxClusterZoom - 1), hasLength(1));
    });

    test('catches with no position are ignored', () {
      final clusters = clusterCatches([a, at('nowhere', null, null), at('half', 43.0, null)], zoom: 8);
      expect(clusters, hasLength(1));
      expect(ids(clusters.single), ['a']);
    });

    test('no catches, no clusters', () {
      expect(clusterCatches(const [], zoom: 8), isEmpty);
    });

    test('the poles do not produce NaN or infinity', () {
      final clusters = clusterCatches([at('n', 90.0, 0.0), at('s', -90.0, 0.0)], zoom: 4);
      expect(clusters, hasLength(2));
    });
  });
}
