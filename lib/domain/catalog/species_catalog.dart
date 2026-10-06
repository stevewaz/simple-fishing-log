enum SpeciesHabitat { freshwater, saltwater, both }

class SpeciesRecord {
  const SpeciesRecord(this.id, this.commonName, this.habitat);

  final String id;
  final String commonName;
  final SpeciesHabitat habitat;

  bool get isCustom => id.startsWith('custom:');
}

/// A bundled static catalog rather than a stored collection: with offline-first sync, two
/// devices creating the same custom species would otherwise produce permanent duplicates.
/// Custom (user-typed) species instead get `id = "custom:" + slug`, which is additive,
/// sync-safe, and needs no merge logic.
abstract final class SpeciesCatalog {
  static const _f = SpeciesHabitat.freshwater;
  static const _s = SpeciesHabitat.saltwater;
  static const _b = SpeciesHabitat.both;

  static const List<SpeciesRecord> all = [
    SpeciesRecord('largemouth-bass', 'Largemouth Bass', _f),
    SpeciesRecord('smallmouth-bass', 'Smallmouth Bass', _f),
    SpeciesRecord('spotted-bass', 'Spotted Bass', _f),
    SpeciesRecord('striped-bass', 'Striped Bass', _b),
    SpeciesRecord('walleye', 'Walleye', _f),
    SpeciesRecord('sauger', 'Sauger', _f),
    SpeciesRecord('northern-pike', 'Northern Pike', _f),
    SpeciesRecord('muskellunge', 'Muskellunge', _f),
    SpeciesRecord('tiger-muskie', 'Tiger Muskie', _f),
    SpeciesRecord('chain-pickerel', 'Chain Pickerel', _f),
    SpeciesRecord('yellow-perch', 'Yellow Perch', _f),
    SpeciesRecord('crappie', 'Crappie', _f),
    SpeciesRecord('bluegill', 'Bluegill', _f),
    SpeciesRecord('sunfish', 'Sunfish', _f),
    SpeciesRecord('rock-bass', 'Rock Bass', _f),
    SpeciesRecord('channel-catfish', 'Channel Catfish', _f),
    SpeciesRecord('blue-catfish', 'Blue Catfish', _f),
    SpeciesRecord('flathead-catfish', 'Flathead Catfish', _f),
    SpeciesRecord('common-carp', 'Common Carp', _f),
    SpeciesRecord('grass-carp', 'Grass Carp', _f),
    SpeciesRecord('rainbow-trout', 'Rainbow Trout', _f),
    SpeciesRecord('brown-trout', 'Brown Trout', _f),
    SpeciesRecord('brook-trout', 'Brook Trout', _f),
    SpeciesRecord('lake-trout', 'Lake Trout', _f),
    SpeciesRecord('steelhead', 'Steelhead', _b),
    SpeciesRecord('chinook-salmon', 'Chinook Salmon', _b),
    SpeciesRecord('coho-salmon', 'Coho Salmon', _b),
    SpeciesRecord('atlantic-salmon', 'Atlantic Salmon', _b),
    SpeciesRecord('gar', 'Gar', _f),
    SpeciesRecord('bowfin', 'Bowfin', _f),
    SpeciesRecord('freshwater-drum', 'Freshwater Drum', _f),
    SpeciesRecord('paddlefish', 'Paddlefish', _f),
    SpeciesRecord('white-bass', 'White Bass', _f),
    SpeciesRecord('hybrid-striped-bass', 'Hybrid Striped Bass', _f),
    SpeciesRecord('red-drum', 'Red Drum (Redfish)', _s),
    SpeciesRecord('speckled-trout', 'Speckled Trout', _s),
    SpeciesRecord('flounder', 'Flounder', _s),
    SpeciesRecord('snook', 'Snook', _s),
    SpeciesRecord('tarpon', 'Tarpon', _s),
    SpeciesRecord('bonefish', 'Bonefish', _s),
    SpeciesRecord('permit', 'Permit', _s),
    SpeciesRecord('mahi-mahi', 'Mahi-Mahi', _s),
    SpeciesRecord('yellowfin-tuna', 'Yellowfin Tuna', _s),
    SpeciesRecord('bluefin-tuna', 'Bluefin Tuna', _s),
    SpeciesRecord('mackerel', 'Mackerel', _s),
    SpeciesRecord('bluefish', 'Bluefish', _s),
    SpeciesRecord('grouper', 'Grouper', _s),
    SpeciesRecord('snapper', 'Snapper', _s),
    SpeciesRecord('sheepshead', 'Sheepshead', _s),
    SpeciesRecord('black-drum', 'Black Drum', _s),
    SpeciesRecord('cobia', 'Cobia', _s),
    SpeciesRecord('halibut', 'Halibut', _s),
    SpeciesRecord('striped-marlin', 'Marlin', _s),
    SpeciesRecord('sailfish', 'Sailfish', _s),
    SpeciesRecord('wahoo', 'Wahoo', _s),
    SpeciesRecord('amberjack', 'Amberjack', _s),
  ];

  static SpeciesRecord? recordForId(String id) {
    for (final r in all) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Exact (case-insensitive) common-name match, used to resolve what the angler typed back
  /// to a catalog id.
  static SpeciesRecord? recordForName(String name) {
    final needle = name.trim().toLowerCase();
    for (final r in all) {
      if (r.commonName.toLowerCase() == needle) return r;
    }
    return null;
  }

  static List<SpeciesRecord> search(String query, {SpeciesHabitat? habitat}) {
    final trimmed = query.trim().toLowerCase();
    final results = all.where((record) {
      if (habitat != null &&
          habitat != SpeciesHabitat.both &&
          record.habitat != SpeciesHabitat.both &&
          record.habitat != habitat) {
        return false;
      }
      return trimmed.isEmpty || record.commonName.toLowerCase().contains(trimmed);
    }).toList();
    results.sort((a, b) => a.commonName.compareTo(b.commonName));
    return results;
  }

  /// Builds a stable, sync-safe identifier for a species name the catalog doesn't have.
  static String customId(String name) {
    final slug = name.trim().toLowerCase().replaceAll(' ', '-');
    return 'custom:$slug';
  }

  /// What the entry form stores for whatever the angler typed.
  static String resolveId(String typedName) =>
      recordForName(typedName)?.id ?? customId(typedName);

  /// Divisor `k` in the standard fisheries cube formula `weight(lb) = length(in)^3 / k`,
  /// published (with variation) by state wildlife agencies as a rough length-only weight
  /// proxy. Slimmer-bodied fish (pike, walleye) carry less weight per inch than deep-bodied
  /// ones (bluegill, catfish) — a starting estimate for measure-from-photo, not a scale.
  static const Map<String, double> _lengthWeightDivisors = {
    'largemouth-bass': 1200, 'smallmouth-bass': 1260, 'spotted-bass': 1250,
    'striped-bass': 1500, 'walleye': 2700, 'sauger': 2700,
    'northern-pike': 3500, 'muskellunge': 2800, 'tiger-muskie': 2800,
    'chain-pickerel': 3200, 'yellow-perch': 1200, 'crappie': 1200,
    'bluegill': 950, 'sunfish': 950, 'rock-bass': 1150,
    'channel-catfish': 900, 'blue-catfish': 850, 'flathead-catfish': 800,
    'common-carp': 850, 'grass-carp': 950,
    'rainbow-trout': 1050, 'brown-trout': 1100, 'brook-trout': 1150,
    'lake-trout': 1050, 'steelhead': 1050,
    'chinook-salmon': 1050, 'coho-salmon': 1150, 'atlantic-salmon': 1100,
  };

  /// Middling body-shape fallback (matches largemouth bass) for species without a specific
  /// divisor — mainly saltwater species and custom entries.
  static const double _genericLengthWeightDivisor = 1200;

  /// Rough weight estimate from a single length. Always an approximation: the formula can't
  /// know this particular fish's girth or condition.
  static double? estimatedWeightPounds({required String speciesId, required double lengthInches}) {
    if (lengthInches <= 0) return null;
    final divisor = _lengthWeightDivisors[speciesId] ?? _genericLengthWeightDivisor;
    return (lengthInches * lengthInches * lengthInches) / divisor;
  }
}
