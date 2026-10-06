/// Curated common values for the gear fields — a starting point for anglers with no logged
/// history yet (history-derived suggestions are empty until they've saved a catch), not an
/// exhaustive list. Free text is always still allowed; this only adds a faster path to it.
abstract final class GearCatalog {
  static const List<String> rodReelTypes = [
    'Spinning rod & reel', 'Baitcasting rod & reel', 'Spincast rod & reel',
    'Fly rod & reel', 'Ice fishing rod & reel', 'Trolling rod & reel',
    'Surf rod & reel',
  ];

  static const List<String> baitLureTypes = [
    'Spinnerbait', 'Crankbait', 'Jerkbait', 'Topwater popper', 'Buzzbait',
    'Swim jig', 'Football jig', 'Flipping jig', 'Soft plastic worm',
    'Soft plastic creature bait', 'Soft plastic swimbait', 'Spoon',
    'Inline spinner', 'Chatterbait / bladed jig', 'Frog', 'Fly',
    'Live bait — minnow', 'Live bait — nightcrawler', 'Live bait — leech',
    'Live bait — crayfish', 'Cut bait', 'Prepared/dough bait',
  ];

  static const List<String> lineTypes = [
    'Monofilament', 'Fluorocarbon', 'Braid', 'Braid with fluorocarbon leader',
    'Braid with monofilament leader', 'Wire leader',
  ];

  static const List<String> techniques = [
    'Casting', 'Trolling', 'Jigging', 'Drift fishing', 'Bottom bouncing',
    'Bobber / float fishing', 'Fly fishing', 'Ice fishing', 'Chumming',
    'Vertical jigging', 'Bank fishing',
  ];

  static List<String> search(String query, List<String> list) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return list;
    return list.where((e) => e.toLowerCase().contains(trimmed)).toList();
  }
}

/// The four free-text gear fields.
enum GearField {
  rodReel('Rod & Reel', 'Rod & reel'),
  baitLure('Bait & Lure', 'Bait or lure'),
  lineType('Line Type', 'Line type'),
  technique('Technique', 'Technique');

  const GearField(this.title, this.fieldLabel);

  final String title;
  final String fieldLabel;

  List<String> get catalog => switch (this) {
        GearField.rodReel => GearCatalog.rodReelTypes,
        GearField.baitLure => GearCatalog.baitLureTypes,
        GearField.lineType => GearCatalog.lineTypes,
        GearField.technique => GearCatalog.techniques,
      };
}
