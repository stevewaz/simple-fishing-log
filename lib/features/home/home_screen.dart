import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/format/dates.dart';
import '../../core/format/number_format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/catch_widgets.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/icons.dart';
import '../../domain/astro/moon_phase.dart';
import '../../domain/astro/solunar_calculator.dart';
import '../../domain/models/units.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: ContentColumn(
            child: Column(
              spacing: Metrics.sectionSpacing,
              children: const [_WeatherCard(), _MoonCard(), _RecentCatchesCard()],
            ),
          ),
        ),
      ),
    );
  }
}

class _WeatherCard extends ConsumerWidget {
  const _WeatherCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(locationControllerProvider);
    final muted = context.text.fishBody.copyWith(color: context.scheme.onSurfaceVariant);

    Widget body;
    if (location.fix == null) {
      body = _LocationPrompt(state: location, what: 'current conditions');
    } else {
      final conditions = ref.watch(homeConditionsProvider);
      body = conditions.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => Text("Weather isn't available right now.", style: muted),
        data: (c) {
          if (c == null || (c.airTempC == null && c.windSpeedMS == null)) {
            return Text("Weather isn't available right now.", style: muted);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                spacing: Metrics.cardSpacing,
                children: [
                  if (c.airTempC != null)
                    Expanded(
                      child: StatTile(
                        title: 'Air Temp',
                        value: '${formatWholeNumber(celsiusToFahrenheit(c.airTempC!))}°F',
                        icon: const Icon(Icons.thermostat),
                      ),
                    ),
                  if (c.windSpeedMS != null)
                    Expanded(
                      child: StatTile(
                        title: 'Wind',
                        value: '${formatWholeNumber(metersPerSecondToMph(c.windSpeedMS!))} mph',
                        icon: const Icon(Icons.air),
                      ),
                    ),
                ],
              ),
              if (c.weatherCondition != null) ...[
                const SizedBox(height: Metrics.cardSpacing),
                Text(c.weatherCondition!, style: muted),
              ],
            ],
          );
        },
      );
    }

    return SectionCard(title: 'Current Conditions', child: body);
  }
}

class _MoonCard extends ConsumerWidget {
  const _MoonCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(locationControllerProvider);
    final now = DateTime.now();
    final phase = MoonPhase.fromDate(now);
    final fix = location.fix;
    final solunar = fix == null
        ? null
        : SolunarCalculator.calculate(
            now,
            latitude: fix.latitude,
            longitude: fix.longitude,
            dayStart: localDayStart(now),
          );
    final muted = context.text.fishCaption.copyWith(color: context.scheme.onSurfaceVariant);

    return SectionCard(
      title: 'Moon',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            spacing: Metrics.cardSpacing,
            children: [
              MoonIcon.forDate(now, size: 44, lit: context.fish.lureAccent),
              Text(phase.label, style: context.text.fishBody),
            ],
          ),
          const SizedBox(height: Metrics.cardSpacing),
          if (solunar != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                SolunarRows(title: 'Major', periods: solunar.majorPeriods),
                SolunarRows(title: 'Minor', periods: solunar.minorPeriods),
              ],
            )
          else
            _LocationPrompt(state: location, what: "today's solunar windows", compact: true),
          const SizedBox(height: 8),
          Text('Folklore, not forecast — shown for curiosity, not prediction.', style: muted),
        ],
      ),
    );
  }
}

/// "Major  6:12 AM–8:12 AM". Shared with the catch detail screen.
class SolunarRows extends StatelessWidget {
  const SolunarRows({super.key, required this.title, required this.periods});

  final String title;
  final List<SolunarPeriod> periods;

  @override
  Widget build(BuildContext context) {
    if (periods.isEmpty) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 56,
          child: Text(title, style: context.text.fishCaption.copyWith(color: context.scheme.onSurfaceVariant)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              for (final p in periods) Text(formatTimeRange(p.start, p.end), style: context.text.fishBody),
            ],
          ),
        ),
      ],
    );
  }
}

/// The message (and, where useful, the one button) shown when there's no position yet.
class _LocationPrompt extends ConsumerWidget {
  const _LocationPrompt({required this.state, required this.what, this.compact = false});

  final LocationState state;
  final String what;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = (compact ? context.text.fishCaption : context.text.fishBody)
        .copyWith(color: context.scheme.onSurfaceVariant);
    final controller = ref.read(locationControllerProvider.notifier);

    if (state.status == LocationStatus.locating) {
      return Row(
        spacing: 12,
        children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          Text('Finding your location…', style: style),
        ],
      );
    }

    final (String message, String? action, VoidCallback? onAction) = switch (state.status) {
      // A browser has no "app settings" screen to open — the user changes the site's
      // permission from the address bar, so there is no button to offer.
      LocationStatus.blocked when kIsWeb => (
          "Location is blocked for this site. Allow it from your browser's address bar, then reload.",
          null,
          null,
        ),
      LocationStatus.blocked => (
          'Location access is turned off for this app.',
          'Open Settings',
          () => ref.read(locationServiceProvider).openSettings(),
        ),
      LocationStatus.servicesOff => ('Location services are turned off on this device.', null, null),
      LocationStatus.failed => ("Couldn't get your location.", 'Try again', controller.refresh),
      _ => ('Allow location access to see $what.', 'Allow Location', controller.refresh),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: style),
        if (action != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.my_location, size: 18),
            label: Text(action),
          ),
        ],
      ],
    );
  }
}

class _RecentCatchesCard extends ConsumerWidget {
  const _RecentCatchesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catches = ref.watch(catchesProvider).value ?? const [];
    final recent = catches.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text('Recent Catches', style: context.text.fishHeadline)),
        const SizedBox(height: Metrics.cardSpacing),
        if (recent.isEmpty)
          SurfaceCard(
            padding: const EdgeInsets.all(Metrics.sectionSpacing),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Log your first catch to see it here.',
                    style: context.text.fishBody.copyWith(color: context.scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => context.push(Routes.newCatch()),
                    icon: const Icon(Icons.add),
                    label: const Text('Log a Catch'),
                  ),
                ],
              ),
            ),
          )
        else
          Column(
            spacing: Metrics.cardSpacing,
            children: [
              for (final entry in recent)
                CatchCard(
                  entry: entry,
                  onTap: () => context.push(Routes.catchIn(Routes.home, entry.id)),
                ),
            ],
          ),
      ],
    );
  }
}
