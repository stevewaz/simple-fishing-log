import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// "How to read this": the NOAA and Canadian charts are in meters and use chart notation, which
/// an angler who thinks in feet and has never read a nautical chart would otherwise find baffling.
Future<void> showChartHelp(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const ChartHelpSheet(),
    );

class ChartHelpSheet extends StatelessWidget {
  const ChartHelpSheet({super.key});

  @override
  Widget build(BuildContext context) {
    Widget point(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: context.fish.currentWater),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.text.fishHeadline),
                    const SizedBox(height: 2),
                    Text(body, style: context.text.fishBody.copyWith(color: context.scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reading the water chart', style: context.text.fishTitle),
            const SizedBox(height: 4),
            Text(
              'Official nautical charts (NOAA in the US, the Canadian Hydrographic Service in Canada), drawn under '
                  'your catches.',
              style: context.text.fishBody.copyWith(color: context.scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            point(
              Icons.straighten,
              'Depths are in meters',
              'The small numbers are water depth. A subscript is tenths of a meter, so 2₇ means 2.7 m — about '
                  '8.9 ft. Multiply meters by 3.28 for feet.',
            ),
            point(
              Icons.water,
              'Shading shows depth',
              'Darker blue is shallower water; it lightens as it gets deeper. Thin grey lines are depth contours.',
            ),
            point(
              Icons.place_outlined,
              'Marks and hazards',
              'Buoys, lights, channels, rocks, wrecks and obstructions are charted, along with marinas and boat ramps.',
            ),
            point(
              Icons.zoom_in,
              'Zoom in for detail',
              'Depth numbers appear once you zoom in past street-level-ish scale (zoom 10 and closer).',
            ),
            point(
              Icons.public,
              'US and Canadian waters',
              'Charts cover coastal waters, the Great Lakes (both the US and Ontario shores) and some rivers. Small '
                  'inland lakes are not charted — there the map is just the standard map.',
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(Metrics.controlCornerRadius),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: context.scheme.onTertiaryContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'For planning and fishing spots only — not for navigation.',
                      style: context.text.fishBody.copyWith(color: context.scheme.onTertiaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
