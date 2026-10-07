import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_fishing_log/core/widgets/noaa_chart_tile_provider.dart';

const _half = 20037508.342789244;

/// lon/lat → Web Mercator meters (the textbook formula, independent of the code under test).
(double, double) _mercator(double lon, double lat) {
  final x = lon * _half / 180;
  final y = math.log(math.tan((90 + lat) * math.pi / 360)) / (math.pi / 180) * _half / 180;
  return (x, y);
}

/// lon/lat → slippy-map tile (also independent).
(int, int) _slippy(double lat, double lon, int z) {
  final n = 1 << z;
  final x = ((lon + 180) / 360 * n).floor();
  final latRad = lat * math.pi / 180;
  final y = ((1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) / 2 * n).floor();
  return (x, y);
}

void main() {
  group('tileBounds (slippy-map tile → Web Mercator meters)', () {
    test('the single zoom-0 tile is the whole world', () {
      final b = NoaaChartTileProvider.tileBounds(0, 0, 0);
      expect(b.minX, closeTo(-_half, 1e-6));
      expect(b.maxX, closeTo(_half, 1e-6));
      expect(b.minY, closeTo(-_half, 1e-6));
      expect(b.maxY, closeTo(_half, 1e-6));
    });

    test('zoom 1 splits the world into quadrants, with y growing southward', () {
      final nw = NoaaChartTileProvider.tileBounds(1, 0, 0);
      expect(nw.minX, closeTo(-_half, 1e-6));
      expect(nw.maxX, closeTo(0, 1e-6));
      expect(nw.minY, closeTo(0, 1e-6));
      expect(nw.maxY, closeTo(_half, 1e-6));

      final se = NoaaChartTileProvider.tileBounds(1, 1, 1);
      expect(se.minX, closeTo(0, 1e-6));
      expect(se.maxX, closeTo(_half, 1e-6));
      expect(se.minY, closeTo(-_half, 1e-6));
      expect(se.maxY, closeTo(0, 1e-6));
    });

    test('tiles are square and the right size at every zoom', () {
      for (final z in [3, 10, 15, 19]) {
        final b = NoaaChartTileProvider.tileBounds(z, 5, 7);
        expect(b.maxX - b.minX, closeTo(b.maxY - b.minY, 1e-6));
        expect(b.maxX - b.minX, closeTo(2 * _half / (1 << z), 1e-3));
      }
    });

    test('adjacent tiles share an edge (no gaps or overlaps in the mosaic)', () {
      final a = NoaaChartTileProvider.tileBounds(11, 556, 757);
      final right = NoaaChartTileProvider.tileBounds(11, 557, 757);
      final below = NoaaChartTileProvider.tileBounds(11, 556, 758);
      expect(a.maxX, closeTo(right.minX, 1e-6));
      expect(a.minY, closeTo(below.maxY, 1e-6));
    });

    test('the tile covering a real Lake Erie spot contains that spot, at every zoom', () {
      const lat = 41.46, lon = -82.71; // Sandusky Bay
      final (px, py) = _mercator(lon, lat);
      for (final z in [10, 11, 13, 16, 18]) {
        final (tx, ty) = _slippy(lat, lon, z);
        final b = NoaaChartTileProvider.tileBounds(z, tx, ty);
        expect(px, inInclusiveRange(b.minX, b.maxX), reason: 'x at z$z');
        expect(py, inInclusiveRange(b.minY, b.maxY), reason: 'y at z$z');
      }
    });
  });

  group('urlFor', () {
    test('asks the Maritime Chart Server for a transparent 256 px PNG in EPSG:3857', () {
      final uri = Uri.parse(NoaaChartTileProvider.urlFor(11, 556, 757));
      expect(uri.host, 'gis.charttools.noaa.gov');
      expect(uri.path, endsWith('/MaritimeChartService/MapServer/export'));
      final q = uri.queryParameters;
      expect(q['f'], 'image');
      expect(q['transparent'], 'true');
      expect(q['bboxSR'], '3857');
      expect(q['imageSR'], '3857');
      expect(q['size'], '256,256');
      expect(q['format'], 'png32');
    });

    test('the bbox parameter is the tile bounds, in minX,minY,maxX,maxY order', () {
      final b = NoaaChartTileProvider.tileBounds(11, 556, 757);
      final bbox = Uri.parse(NoaaChartTileProvider.urlFor(11, 556, 757))
          .queryParameters['bbox']!
          .split(',')
          .map(double.parse)
          .toList();
      expect(bbox, [b.minX, b.minY, b.maxX, b.maxY]);
      expect(bbox[0], lessThan(bbox[2]));
      expect(bbox[1], lessThan(bbox[3]));
    });

    test('the chart only draws from zoom 10 (below it the service paints a boundary grid)', () {
      expect(NoaaChartTileProvider.minZoom, 10);
    });

    test('the Canadian Hydrographic Service takes the same request, from its own server', () {
      final chs = Uri.parse(NoaaChartTileProvider.urlFor(11, 556, 757, exportUrl: NoaaChartTileProvider.chsEndpoint));
      expect(chs.host, 'egisp.dfo-mpo.gc.ca');
      expect(chs.path, endsWith('/MapServer/export'));
      final noaa = Uri.parse(NoaaChartTileProvider.urlFor(11, 556, 757));
      expect(chs.queryParameters, noaa.queryParameters, reason: 'same bbox, size, format and flags');
    });
  });

  group('the tile provider', () {
    final layer = TileLayer(urlTemplate: 'unused');
    const tile = TileCoordinates(556, 757, 11);

    test('asks NOAA unless told otherwise', () {
      final provider = NoaaChartTileProvider(cachingProvider: const DisabledMapCachingProvider());
      addTearDown(provider.dispose);
      expect(provider.getTileUrl(tile, layer), startsWith(NoaaChartTileProvider.endpoint));
    });

    test('asks the server it was given', () {
      final provider = NoaaChartTileProvider(
        exportUrl: NoaaChartTileProvider.chsEndpoint,
        cachingProvider: const DisabledMapCachingProvider(),
      );
      addTearDown(provider.dispose);
      expect(provider.getTileUrl(tile, layer), startsWith(NoaaChartTileProvider.chsEndpoint));
    });
  });
}
