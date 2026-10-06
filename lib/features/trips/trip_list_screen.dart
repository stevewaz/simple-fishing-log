import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/format/dates.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../domain/models/trip.dart';

String tripDisplayName(Trip trip) => trip.title.isEmpty ? formatDate(trip.startDate) : trip.title;

/// Asks before deleting a trip. Its catches are kept either way — only the grouping goes.
Future<bool> confirmDeleteTrip(BuildContext context, Trip trip, int catchCount) async {
  final detail = catchCount == 0
      ? 'This trip has no catches.'
      : 'Its $catchCount ${catchCount == 1 ? 'catch stays' : 'catches stay'} in your log; only the trip is removed.';
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete "${tripDisplayName(trip)}"?'),
      content: Text(detail),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: context.scheme.error,
            foregroundColor: context.scheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

class TripListScreen extends ConsumerStatefulWidget {
  const TripListScreen({super.key});

  @override
  ConsumerState<TripListScreen> createState() => _TripListScreenState();
}

class _TripListScreenState extends ConsumerState<TripListScreen> {
  /// See the Log screen: a swiped `Dismissible` must leave the tree synchronously, while the
  /// database stream that removes it is asynchronous.
  final Set<String> _swiped = {};

  Future<void> _startSession() async {
    await ref.read(appDataProvider).trips.startSession();
  }

  @override
  Widget build(BuildContext context) {
    final tripsAsync = ref.watch(tripsProvider);
    final trips = [for (final t in tripsAsync.value ?? const <Trip>[]) if (!_swiped.contains(t.id)) t];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trips'),
        actions: [
          IconButton(tooltip: 'Start a Session', icon: const Icon(Icons.add), onPressed: _startSession),
        ],
      ),
      body: SafeArea(
        child: tripsAsync.isLoading && !tripsAsync.hasValue
            ? const Center(child: CircularProgressIndicator())
            : trips.isEmpty
                ? EmptyState(
                    icon: const Icon(Icons.sailing_outlined),
                    title: 'No Trips Yet',
                    message: 'Start a session to group catches from a day on the water.',
                    actionLabel: 'Start a Session',
                    onAction: _startSession,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: trips.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final trip = trips[index];
                      return Center(
                        key: ValueKey(trip.id),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: Metrics.listItemMaxWidth),
                          child: Dismissible(
                            key: ValueKey(trip.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 24),
                              decoration: BoxDecoration(
                                color: context.scheme.errorContainer,
                                borderRadius: BorderRadius.circular(Metrics.cardCornerRadius),
                              ),
                              child: Icon(Icons.delete_outline, color: context.scheme.onErrorContainer),
                            ),
                            confirmDismiss: (_) => confirmDeleteTrip(
                              context,
                              trip,
                              ref.read(catchesForTripProvider(trip.id)).length,
                            ),
                            onDismissed: (_) async {
                              setState(() => _swiped.add(trip.id));
                              await ref.read(appDataProvider).trips.delete(trip.id);
                              if (mounted) setState(() => _swiped.remove(trip.id));
                            },
                            child: _TripRow(trip: trip, onTap: () => context.push(Routes.trip(trip.id))),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

class _TripRow extends ConsumerWidget {
  const _TripRow({required this.trip, required this.onTap});

  final Trip trip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(catchesForTripProvider(trip.id)).length;
    final muted = context.text.fishCaption.copyWith(color: context.scheme.onSurfaceVariant);
    final water = trip.waterBodyName;

    return SurfaceCard(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tripDisplayName(trip), style: context.text.fishHeadline),
                const SizedBox(height: 2),
                Text(
                  [
                    if (water != null && water.isNotEmpty) water,
                    '$count ${count == 1 ? 'catch' : 'catches'}',
                  ].join(' · '),
                  style: muted,
                ),
              ],
            ),
          ),
          if (trip.isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: context.scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Active',
                style: context.text.fishCaption.copyWith(
                  color: context.scheme.onTertiaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
