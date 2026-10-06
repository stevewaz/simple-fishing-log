import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/catch_widgets.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/icons.dart';
import '../../domain/geo.dart';
import '../../domain/models/catch_entry.dart';
import 'archive_actions.dart';

enum _CatchSort { newest, nearest }

class CatchListScreen extends ConsumerStatefulWidget {
  const CatchListScreen({super.key});

  @override
  ConsumerState<CatchListScreen> createState() => _CatchListScreenState();
}

class _CatchListScreenState extends ConsumerState<CatchListScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  _CatchSort _sort = _CatchSort.newest;
  ({double lat, double lon})? _here;
  bool _locating = false;

  /// Rows swiped away this frame. A `Dismissible` must leave the tree synchronously, but the
  /// database stream that removes the item is asynchronous — this bridges the gap.
  final Set<String> _swiped = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CatchEntry> _visible(List<CatchEntry> all) {
    final q = _query.trim().toLowerCase();
    var list = all.where((e) => !_swiped.contains(e.id)).toList();
    if (q.isNotEmpty) {
      list = list
          .where((e) =>
              e.speciesName.toLowerCase().contains(q) ||
              e.locationName.toLowerCase().contains(q) ||
              (e.waterBodyName?.toLowerCase().contains(q) ?? false))
          .toList();
    }
    final here = _here;
    if (_sort == _CatchSort.nearest && here != null) {
      double distance(CatchEntry e) => e.hasCoordinate
          ? haversineMeters(here.lat, here.lon, e.latitude!, e.longitude!)
          : double.infinity;
      list.sort((a, b) => distance(a).compareTo(distance(b)));
    }
    return list;
  }

  /// One-shot fix, requested only when "Nearest to Me" is actually chosen — no location
  /// prompt for anglers who never open the sort menu.
  Future<void> _selectSort(_CatchSort sort) async {
    setState(() => _sort = sort);
    if (sort != _CatchSort.nearest || _here != null) return;
    setState(() => _locating = true);
    try {
      final fix = await ref.read(locationServiceProvider).currentLocation();
      if (mounted) setState(() => _here = (lat: fix.latitude, lon: fix.longitude));
    } catch (_) {
      if (mounted) {
        setState(() => _sort = _CatchSort.newest);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't get your location, so the list stays newest-first.")),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _delete(CatchEntry entry) async {
    final repo = ref.read(appDataProvider).catches;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _swiped.add(entry.id));
    await repo.delete(entry.id);
    if (!mounted) return;
    setState(() => _swiped.remove(entry.id));
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted ${entry.displaySpecies}'),
          action: SnackBarAction(label: 'Undo', onPressed: () => repo.restore(entry.id)),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final catchesAsync = ref.watch(catchesProvider);
    final all = catchesAsync.value ?? const <CatchEntry>[];
    final hasAny = all.isNotEmpty;
    final visible = _visible(all);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fishing Log'),
        actions: [
          PopupMenuButton<_CatchSort>(
            tooltip: 'Sort',
            icon: _locating
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.swap_vert),
            initialValue: _sort,
            onSelected: _selectSort,
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: _CatchSort.newest,
                checked: _sort == _CatchSort.newest,
                child: const Text('Newest First'),
              ),
              CheckedPopupMenuItem(
                value: _CatchSort.nearest,
                checked: _sort == _CatchSort.nearest,
                child: const Text('Nearest to Me'),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Import Logbook',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: () => ArchiveActions.import(context, ref),
          ),
          if (hasAny)
            Builder(
              builder: (context) => IconButton(
                tooltip: 'Export Logbook',
                icon: const Icon(Icons.ios_share),
                onPressed: () => ArchiveActions.export(context, ref),
              ),
            ),
        ],
      ),
      floatingActionButton: hasAny
          ? FloatingActionButton.extended(
              onPressed: () => context.push(Routes.newCatch()),
              icon: const Icon(Icons.add),
              label: const Text('Log a Catch'),
            )
          : null,
      body: SafeArea(
        child: Builder(builder: (context) {
          if (catchesAsync.isLoading && !catchesAsync.hasValue) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!hasAny) {
            return EmptyState(
              icon: const FishIcon(size: 36),
              title: 'No Catches Yet',
              message: "Log your first catch and it'll show up here.",
              actionLabel: 'Log a Catch',
              onAction: () => context.push(Routes.newCatch()),
            );
          }
          return Column(
            children: [
              ContentColumn(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: SearchBar(
                  controller: _searchController,
                  hintText: 'Search species or water',
                  leading: const Icon(Icons.search),
                  elevation: const WidgetStatePropertyAll(0),
                  backgroundColor: WidgetStatePropertyAll(context.scheme.surfaceContainerLow),
                  side: WidgetStatePropertyAll(BorderSide(color: context.scheme.outlineVariant)),
                  onChanged: (v) => setState(() => _query = v),
                  trailing: [
                    if (_query.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                  ],
                ),
              ),
              Expanded(
                child: visible.isEmpty
                    ? EmptyState(
                        icon: const Icon(Icons.search_off),
                        title: 'No Results',
                        message: 'No catches match "${_query.trim()}".',
                      )
                    : ListView.separated(
                        // Room so the last card clears the floating action button.
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final entry = visible[index];
                          return Center(
                            key: ValueKey(entry.id),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: Metrics.listItemMaxWidth),
                              child: Dismissible(
                                key: ValueKey(entry.id),
                                direction: DismissDirection.endToStart,
                                background: const _DeleteBackground(),
                                onDismissed: (_) => _delete(entry),
                                child: CatchCard(
                                  entry: entry,
                                  onTap: () => context.push(Routes.catchIn(Routes.log, entry.id)),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      decoration: BoxDecoration(
        color: context.scheme.errorContainer,
        borderRadius: BorderRadius.circular(Metrics.cardCornerRadius),
      ),
      child: Icon(Icons.delete_outline, color: context.scheme.onErrorContainer),
    );
  }
}
