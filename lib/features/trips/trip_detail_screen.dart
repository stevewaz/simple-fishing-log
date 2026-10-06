import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/format/dates.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/catch_widgets.dart';
import '../../core/widgets/common.dart';
import '../../domain/models/json_helpers.dart';
import '../../domain/models/trip.dart';
import 'trip_list_screen.dart';

class TripDetailScreen extends ConsumerWidget {
  const TripDetailScreen({super.key, required this.tripId});

  final String tripId;

  Future<void> _edit(BuildContext context, WidgetRef ref, Trip trip) async {
    final result = await showDialog<Trip>(context: context, builder: (_) => _EditTripDialog(trip: trip));
    if (result != null) await ref.read(appDataProvider).trips.save(result);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tripProvider(tripId));
    final catches = ref.watch(catchesForTripProvider(tripId));

    return async.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
      error: (_, _) => Scaffold(appBar: AppBar(), body: const Center(child: Text("Couldn't load this trip."))),
      data: (trip) {
        if (trip == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Trip')),
            body: const EmptyState(
              icon: Icon(Icons.sailing_outlined),
              title: 'Trip not found',
              message: 'It may have been deleted.',
            ),
          );
        }
        final muted = context.text.fishBody.copyWith(color: context.scheme.onSurfaceVariant);
        final water = trip.waterBodyName;

        Widget row(String label, String value) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 96, child: Text(label, style: muted)),
                  Expanded(child: Text(value, style: context.text.fishBody)),
                ],
              ),
            );

        return Scaffold(
          appBar: AppBar(
            title: Text(trip.title.isEmpty ? 'Trip' : trip.title),
            actions: [
              if (trip.isActive)
                TextButton(
                  onPressed: () => ref.read(appDataProvider).trips.endSession(trip.id),
                  child: const Text('End Session'),
                ),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (value) async {
                  if (value == 'edit') {
                    await _edit(context, ref, trip);
                  } else if (value == 'delete') {
                    if (await confirmDeleteTrip(context, trip, catches.length) && context.mounted) {
                      final trips = ref.read(appDataProvider).trips;
                      context.pop();
                      await trips.delete(trip.id);
                    }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit'), contentPadding: EdgeInsets.zero),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete'), contentPadding: EdgeInsets.zero),
                  ),
                ],
              ),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              child: ContentColumn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Metrics.sectionSpacing,
                  children: [
                    SurfaceCard(
                      padding: const EdgeInsets.all(Metrics.cardSpacing + 4),
                      child: Column(
                        children: [
                          if (water != null && water.isNotEmpty) row('Water', water),
                          row('Started', formatDateTime(trip.startDate)),
                          if (trip.endDate != null) row('Ended', formatDateTime(trip.endDate!)),
                          row('Catches', '${catches.length}'),
                          if (trip.notes != null && trip.notes!.isNotEmpty) row('Notes', trip.notes!),
                        ],
                      ),
                    ),
                    if (catches.isNotEmpty) ...[
                      Semantics(header: true, child: Text('Catches', style: context.text.fishHeadline)),
                      for (final entry in catches)
                        CatchCard(
                          entry: entry,
                          onTap: () => context.push(Routes.catchIn(Routes.trip(trip.id), entry.id)),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EditTripDialog extends StatefulWidget {
  const _EditTripDialog({required this.trip});

  final Trip trip;

  @override
  State<_EditTripDialog> createState() => _EditTripDialogState();
}

class _EditTripDialogState extends State<_EditTripDialog> {
  late final _title = TextEditingController(text: widget.trip.title);
  late final _water = TextEditingController(text: widget.trip.waterBodyName ?? '');
  late final _notes = TextEditingController(text: widget.trip.notes ?? '');

  @override
  void dispose() {
    _title.dispose();
    _water.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Trip'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Erie morning'),
            ),
            TextField(
              controller: _water,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Lake or river'),
            ),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            widget.trip.copyWith(
              title: _title.text.trim(),
              waterBodyName: nilIfBlank(_water.text),
              notes: nilIfBlank(_notes.text),
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
