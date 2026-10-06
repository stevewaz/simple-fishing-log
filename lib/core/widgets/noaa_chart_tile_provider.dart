import 'package:flutter_map/flutter_map.dart';

/// Tiles from NOAA's ENC Online (Maritime Chart Server): the official electronic nautical
/// chart for US coastal waters, the Great Lakes and some rivers — depth soundings and
/// contours, depth shading, buoys and lights, channels, hazards, and marinas/ramps.
///
/// It is free and needs no key, and it answers browser (CORS) requests from any origin, so it
/// works from the web build too. It is *not* a slippy-map tile service: it renders a picture
/// for a bounding box, so each tile's Web Mercator bounds are computed and requested via the
/// `export` call. Outside chart coverage (small inland lakes, most of the world) it returns
/// transparent tiles and the map underneath shows through.
///
/// Notes for anyone changing this:
///  * ENC depths are in **meters** (a small subscript is tenths: 2₇ = 2.7 m). The service has
///    no feet option, so the app explains the notation (see `ChartHelpSheet`).
///  * Below zoom 10 the service draws a grid of chart boundaries instead of useful detail, so
///    the layer is only shown from [minZoom].
///  * Public US-government data. Charts are "for planning only, not for navigation".
class NoaaChartTileProvider extends NetworkTileProvider {
  NoaaChartTileProvider({super.httpClient, super.cachingProvider, super.headers});

  static const String endpoint =
      'https://gis.charttools.noaa.gov/arcgis/rest/services/MCS/ENCOnline/MapServer/exts/MaritimeChartService/MapServer/export';

  /// Detail starts to make sense here; see the note above.
  static const double minZoom = 10;

  static const int tileSize = 256;

  /// Half the circumference of the Earth in Web Mercator meters.
  static const double _halfWorld = 20037508.342789244;

  /// The Web Mercator (EPSG:3857) bounds of slippy-map tile [x],[y] at zoom [z].
  static ({double minX, double minY, double maxX, double maxY}) tileBounds(int z, int x, int y) {
    final span = 2 * _halfWorld / (1 << z);
    final minX = -_halfWorld + x * span;
    final maxY = _halfWorld - y * span;
    return (minX: minX, minY: maxY - span, maxX: minX + span, maxY: maxY);
  }

  static String urlFor(int z, int x, int y) {
    final b = tileBounds(z, x, y);
    final query = {
      'bbox': '${b.minX},${b.minY},${b.maxX},${b.maxY}',
      'bboxSR': '3857',
      'imageSR': '3857',
      'size': '$tileSize,$tileSize',
      'format': 'png32',
      'transparent': 'true',
      'dpi': '96',
      'f': 'image',
    };
    return Uri.parse(endpoint).replace(queryParameters: query).toString();
  }

  @override
  String getTileUrl(TileCoordinates coordinates, TileLayer options) =>
      urlFor(coordinates.z, coordinates.x, coordinates.y);

  /// No fallback tile exists for a bounding-box service.
  @override
  String? getTileFallbackUrl(TileCoordinates coordinates, TileLayer options) => null;
}
