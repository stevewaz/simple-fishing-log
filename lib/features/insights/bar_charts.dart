import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// A labelled horizontal bar per item — species mix, top waters. Hand-drawn rather than a
/// charting library: it's two shapes, it themes for free, and every row is a proper
/// accessibility node ("Largemouth Bass: 12 catches").
class HorizontalBars extends StatelessWidget {
  const HorizontalBars({super.key, required this.items, required this.color, this.labelWidth = 120});

  final List<({String label, int value})> items;
  final Color color;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final maxValue = items.fold<int>(1, (m, e) => e.value > m ? e.value : m);
    final muted = context.scheme.onSurfaceVariant;

    return Column(
      children: [
        for (final item in items)
          Semantics(
            label: '${item.label}: ${item.value} ${item.value == 1 ? 'catch' : 'catches'}',
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: labelWidth,
                      child: Text(item.label, style: context.text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) => Align(
                          alignment: Alignment.centerLeft,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                            height: 20,
                            width: (constraints.maxWidth * item.value / maxValue).clamp(4.0, constraints.maxWidth),
                            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      child: Text(
                        '${item.value}',
                        textAlign: TextAlign.end,
                        style: context.text.bodySmall!.copyWith(
                          color: muted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A column per category — catches by hour, by moon phase. [labelFor] returns the text under
/// each column, or null to skip it (the hour chart labels every third hour).
class VerticalBars extends StatelessWidget {
  const VerticalBars({
    super.key,
    required this.values,
    required this.labelFor,
    required this.semanticLabelFor,
    required this.color,
    this.height = 140,
    this.showCounts = false,
  });

  final List<int> values;
  final String? Function(int index) labelFor;
  final String Function(int index) semanticLabelFor;
  final Color color;
  final double height;
  final bool showCounts;

  @override
  Widget build(BuildContext context) {
    final maxValue = values.fold<int>(1, (m, v) => v > m ? v : m);
    final muted = context.scheme.onSurfaceVariant;
    final captionStyle = context.text.labelSmall!.copyWith(color: muted, height: 1.1);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Semantics(
              label: semanticLabelFor(i),
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: height,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (showCounts && values[i] > 0) Text('${values[i]}', style: captionStyle),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                              height: values[i] == 0 ? 2 : (height - (showCounts ? 16 : 0)) * values[i] / maxValue,
                              decoration: BoxDecoration(
                                color: values[i] == 0 ? context.scheme.outlineVariant : color,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 28,
                        child: Text(labelFor(i) ?? '', style: captionStyle, textAlign: TextAlign.center, maxLines: 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
