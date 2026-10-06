import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/catch_entry.dart';
import '../format/dates.dart';
import '../format/number_format.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'icons.dart';

/// A catch's photo (thumbnail or full-size), with a fish placeholder while loading or when
/// there is none.
class CatchPhotoView extends ConsumerWidget {
  const CatchPhotoView({
    super.key,
    required this.catchId,
    this.thumbnail = true,
    this.fit = BoxFit.cover,
    this.placeholder,
  });

  final String catchId;
  final bool thumbnail;
  final BoxFit fit;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = ref.watch(primaryPhotoByCatchProvider)[catchId];
    final fallback = placeholder ?? const FishPlaceholder();
    if (photo == null) return fallback;
    final bytes = ref.watch(photoBytesProvider(PhotoRequest(photo.id, thumbnail: thumbnail)));
    return bytes.when(
      data: (data) => data == null
          ? fallback
          : Image.memory(
              data,
              fit: fit,
              gaplessPlayback: true,
              // A corrupt or undecodable image falls back rather than showing a red error box.
              errorBuilder: (_, _, _) => fallback,
              semanticLabel: 'Photo of catch',
            ),
      loading: () => fallback,
      error: (_, _) => fallback,
    );
  }
}

/// Photo-forward list row used by Home, Log, Trips and the map preview.
class CatchCard extends ConsumerWidget {
  const CatchCard({super.key, required this.entry, this.onTap});

  final CatchEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weight = entry.weight;
    final place = entry.placeLabel;
    final muted = context.scheme.onSurfaceVariant;

    return Semantics(
      button: onTap != null,
      label: [
        entry.displaySpecies,
        formatDate(entry.date),
        ?place,
        if (entry.wasFromBoat) 'from a boat',
        if (weight != null) formatMeasurement(weight),
      ].join(', '),
      child: ExcludeSemantics(
        child: SurfaceCard(
          onTap: onTap,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Metrics.controlCornerRadius),
                child: SizedBox(
                  width: Metrics.thumbnailSize,
                  height: Metrics.thumbnailSize,
                  child: CatchPhotoView(catchId: entry.id),
                ),
              ),
              const SizedBox(width: Metrics.cardSpacing),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.displaySpecies, style: context.text.fishHeadline, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(formatDate(entry.date), style: context.text.fishCaption.copyWith(color: muted)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 12,
                      runSpacing: 2,
                      children: [
                        if (place != null) _Meta(Icons.place_outlined, place),
                        if (entry.wasFromBoat) const _Meta(Icons.directions_boat_outlined, 'Boat'),
                      ],
                    ),
                  ],
                ),
              ),
              if (weight != null) ...[
                const SizedBox(width: 8),
                Text(
                  formatMeasurement(weight),
                  style: context.text.titleSmall!.copyWith(
                    color: muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = context.scheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label, style: context.text.fishCaption.copyWith(color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

/// Full-bleed photo header for the detail screen: photo (or a water gradient), a dark scrim,
/// and the species and date over the bottom edge.
class HeroPhotoHeader extends StatelessWidget {
  const HeroPhotoHeader({super.key, required this.entry});

  final CatchEntry entry;

  @override
  Widget build(BuildContext context) {
    final fish = context.fish;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Metrics.cardCornerRadius),
      child: Stack(
        children: [
          Positioned.fill(
            child: CatchPhotoView(
              catchId: entry.id,
              thumbnail: false,
              placeholder: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [fish.currentWater, fish.abyss],
                  ),
                ),
                child: Center(child: FishIcon(size: 64, color: Colors.white.withValues(alpha: 0.35))),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, fish.abyss.withValues(alpha: 0.85)],
                ),
              ),
            ),
          ),
          // The only non-positioned child, so it sizes the stack: at least the hero height,
          // growing if large text needs more room (a fixed height would clip the title).
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Metrics.heroHeight, minWidth: double.infinity),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(entry.displaySpecies, style: context.text.fishHero.copyWith(color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(
                      formatDateTime(entry.date),
                      style: context.text.fishCaption.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
