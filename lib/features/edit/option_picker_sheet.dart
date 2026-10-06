import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Browse / search / "use what I typed" picker, shared by the species and gear fields (the
/// Swift app's `SpeciesPickerView` and `GearPickerView` were the same pattern twice).
///
/// Free text is always still allowed: the typed query is offered as the first row, so the
/// catalog is only ever a faster path, never a restriction.
Future<String?> showOptionPicker(
  BuildContext context, {
  required String title,
  required String searchHint,
  required List<String> Function(String query) optionsFor,
  String? selected,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _OptionPicker(
      title: title,
      searchHint: searchHint,
      optionsFor: optionsFor,
      selected: selected,
    ),
  );
}

class _OptionPicker extends StatefulWidget {
  const _OptionPicker({
    required this.title,
    required this.searchHint,
    required this.optionsFor,
    this.selected,
  });

  final String title;
  final String searchHint;
  final List<String> Function(String query) optionsFor;
  final String? selected;

  @override
  State<_OptionPicker> createState() => _OptionPickerState();
}

class _OptionPickerState extends State<_OptionPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final trimmed = _query.trim();
    final options = widget.optionsFor(_query);
    final alreadyListed = options.any((o) => o.toLowerCase() == trimmed.toLowerCase());

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: Text(widget.title, style: context.text.fishTitle)),
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  autofocus: false,
                  decoration: InputDecoration(
                    hintText: widget.searchHint,
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              children: [
                if (trimmed.isNotEmpty && !alreadyListed)
                  ListTile(
                    leading: Icon(Icons.add_circle_outline, color: context.fish.lureAccent),
                    title: Text('Use "$trimmed"'),
                    onTap: () => Navigator.pop(context, trimmed),
                  ),
                for (final option in options)
                  ListTile(
                    title: Text(option),
                    trailing: option == widget.selected
                        ? Icon(Icons.check, color: context.fish.currentWater)
                        : null,
                    onTap: () => Navigator.pop(context, option),
                  ),
                if (options.isEmpty && trimmed.isEmpty)
                  const Padding(padding: EdgeInsets.all(24), child: Text('Nothing to show.')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
