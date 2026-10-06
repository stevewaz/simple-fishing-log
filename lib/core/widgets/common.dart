import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'icons.dart';

/// The standard content-layer surface: a rounded card with consistent padding.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Metrics.cardSpacing),
    this.onTap,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Metrics.cardCornerRadius);
    return Material(
      color: color ?? context.scheme.surfaceContainer,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A card with a headline, used by Home, Detail and Insights.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SurfaceCard(
        padding: const EdgeInsets.all(Metrics.cardSpacing + 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Semantics(header: true, child: Text(title, style: context.text.fishHeadline))),
                ?trailing,
              ],
            ),
            const SizedBox(height: Metrics.cardSpacing),
            child,
          ],
        ),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.title, required this.value, this.icon});

  final String title;
  final String value;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$title: $value',
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Metrics.cardSpacing),
          decoration: BoxDecoration(
            color: context.scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(Metrics.controlCornerRadius + 2),
            border: Border.all(color: context.scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                IconTheme(data: IconThemeData(color: context.fish.lureAccent, size: 22), child: icon!),
                const SizedBox(height: 4),
              ],
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: context.text.fishTitle),
              ),
              Text(title, style: context.text.fishCaption.copyWith(color: context.scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One config-driven empty state, used everywhere so illustration and typography stay
/// consistent across screens.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final Widget icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: context.fish.shallows, shape: BoxShape.circle),
                child: IconTheme(
                  data: IconThemeData(color: context.fish.currentWater, size: 36),
                  child: icon,
                ),
              ),
              const SizedBox(height: 16),
              Text(title, style: context.text.fishHeadline, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                message,
                style: context.text.fishBody.copyWith(color: context.scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 20),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Centers page content and caps its width on large screens.
class ContentColumn extends StatelessWidget {
  const ContentColumn({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Metrics.maxContentWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// The fish placeholder shown when a catch has no photo.
class FishPlaceholder extends StatelessWidget {
  const FishPlaceholder({super.key, this.size});

  final double? size;

  @override
  Widget build(BuildContext context) {
    // Tinted toward the water colour so the tile still reads as a tile on a card whose own
    // colour is close to `shallows` (dark mode).
    final fish = context.fish;
    return Container(
      color: Color.alphaBlend(fish.currentWater.withValues(alpha: 0.16), fish.shallows),
      alignment: Alignment.center,
      child: FishIcon(size: size ?? 28, color: fish.currentWater),
    );
  }
}
