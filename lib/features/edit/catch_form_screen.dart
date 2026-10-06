import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers.dart';
import '../../core/format/dates.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/services/location_service.dart';
import '../../data/services/photo_processor.dart';
import '../../domain/astro/moon_phase.dart';
import '../../domain/catalog/gear_catalog.dart';
import '../../domain/catalog/species_catalog.dart';
import '../../domain/models/units.dart';
import 'catch_draft.dart';
import 'option_picker_sheet.dart';
import 'photo_measurement_screen.dart';

/// New / edit form. One screen for both: [catchId] null means a new catch.
class CatchFormScreen extends ConsumerStatefulWidget {
  const CatchFormScreen({super.key, this.catchId});

  final String? catchId;

  @override
  ConsumerState<CatchFormScreen> createState() => _CatchFormScreenState();
}

class _CatchFormScreenState extends ConsumerState<CatchFormScreen> {
  CatchDraft? _draft;
  bool _notFound = false;
  bool _dirty = false;
  bool _saving = false;

  bool _locating = false;
  String? _locationError;

  bool _processingPhoto = false;
  ProcessedPhoto? _pendingPhoto;
  Size? _photoSize;

  bool _fetchingConditions = false;

  final _species = TextEditingController();
  final _weight = TextEditingController();
  final _length = TextEditingController();
  final _depth = TextEditingController();
  final _waterBody = TextEditingController();
  final _locationName = TextEditingController();
  final _airTemp = TextEditingController();
  final _waterTemp = TextEditingController();
  final _windSpeed = TextEditingController();
  final _windDir = TextEditingController();
  final _waterConditions = TextEditingController();
  final _rodReel = TextEditingController();
  final _baitLure = TextEditingController();
  final _lineType = TextEditingController();
  final _technique = TextEditingController();
  final _notes = TextEditingController();

  late final Map<GearField, TextEditingController> _gear = {
    GearField.rodReel: _rodReel,
    GearField.baitLure: _baitLure,
    GearField.lineType: _lineType,
    GearField.technique: _technique,
  };

  List<TextEditingController> get _controllers => [
        _species, _weight, _length, _depth, _waterBody, _locationName, _airTemp, _waterTemp,
        _windSpeed, _windDir, _waterConditions, _rodReel, _baitLure, _lineType, _technique, _notes,
      ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final data = ref.read(appDataProvider);
    final id = widget.catchId;
    CatchDraft draft;
    if (id == null) {
      draft = CatchDraft();
      // A session is "a day on the water": new catches belong to the active one by default.
      // Read from the repository, not a provider: a stream provider may not have emitted yet
      // when the form opens straight from a link.
      draft.tripId = (await data.trips.all()).where((t) => t.isActive).firstOrNull?.id;
    } else {
      final entry = await data.catches.get(id);
      if (entry == null) {
        if (mounted) setState(() => _notFound = true);
        return;
      }
      draft = CatchDraft.fromEntry(entry);
      final photo = (await data.photos.forCatch(id)).firstOrNull;
      if (photo != null) {
        draft.photoBytes = await data.photos.fullBytes(photo.id);
        _photoSize = Size(photo.width.toDouble(), photo.height.toDouble());
      }
    }
    if (!mounted) return;

    _species.text = draft.speciesName;
    _weight.text = draft.weightText;
    _length.text = draft.lengthText;
    _depth.text = draft.depthText;
    _waterBody.text = draft.waterBodyName;
    _locationName.text = draft.locationName;
    _airTemp.text = draft.airTemperatureText;
    _waterTemp.text = draft.waterTemperatureText;
    _windSpeed.text = draft.windSpeedText;
    _windDir.text = draft.windDirectionText;
    _waterConditions.text = draft.waterConditions;
    _rodReel.text = draft.rodReel;
    _baitLure.text = draft.baitLure;
    _lineType.text = draft.lineType;
    _technique.text = draft.technique;
    _notes.text = draft.notes;

    // Listen only after the initial fill so loading the form doesn't mark it as edited.
    for (final c in _controllers) {
      c.addListener(_markDirty);
    }
    setState(() => _draft = draft);
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  /// Pulls the text fields into the draft. The draft is the single source of truth for
  /// saving; the controllers are just the editing surface.
  void _syncDraft() {
    final d = _draft!;
    d.speciesName = _species.text;
    d.weightText = _weight.text;
    d.lengthText = _length.text;
    d.depthText = _depth.text;
    d.waterBodyName = _waterBody.text;
    d.locationName = _locationName.text;
    d.airTemperatureText = _airTemp.text;
    d.waterTemperatureText = _waterTemp.text;
    d.windSpeedText = _windSpeed.text;
    d.windDirectionText = _windDir.text;
    d.waterConditions = _waterConditions.text;
    d.rodReel = _rodReel.text;
    d.baitLure = _baitLure.text;
    d.lineType = _lineType.text;
    d.technique = _technique.text;
    d.notes = _notes.text;
  }

  // ---- Actions ----

  Future<void> _save() async {
    if (_saving) return;
    _syncDraft();
    final draft = _draft!;
    if (!draft.canSave) return;

    setState(() => _saving = true);
    final data = ref.read(appDataProvider);
    try {
      final entry = draft.toEntry(newId: data.catches.newId());
      await data.catches.save(entry);
      if (draft.photoChanged) {
        final photo = _pendingPhoto;
        if (photo != null) {
          await data.photos.replaceForCatch(entry.id, photo);
        } else {
          await data.photos.removeForCatch(entry.id);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't save this catch.")));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _dirty = false); // saved: leaving is not "discarding"
    context.pop();
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text("This catch hasn't been saved."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep Editing')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<void> _pickDate() async {
    final draft = _draft!;
    final date = await showDatePicker(
      context: context,
      initialDate: draft.date,
      firstDate: DateTime(1970),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(draft.date));
    if (!mounted) return;
    setState(() {
      draft.date = DateTime(date.year, date.month, date.day, time?.hour ?? draft.date.hour, time?.minute ?? draft.date.minute);
      _dirty = true;
    });
  }

  Future<void> _browseSpecies() async {
    final picked = await showOptionPicker(
      context,
      title: 'Species',
      searchHint: 'Search species',
      optionsFor: (q) => [for (final r in SpeciesCatalog.search(q)) r.commonName],
      selected: _species.text,
    );
    if (picked != null) _species.text = picked;
  }

  Future<void> _browseGear(GearField field) async {
    final controller = _gear[field]!;
    final picked = await showOptionPicker(
      context,
      title: field.title,
      searchHint: 'Search ${field.title.toLowerCase()}',
      optionsFor: (q) => GearCatalog.search(q, field.catalog),
      selected: controller.text,
    );
    if (picked != null) controller.text = picked;
  }

  Future<void> _captureLocation() async {
    final draft = _draft!;
    setState(() {
      _locating = true;
      _locationError = null;
      draft.waterSuggestions = const [];
    });
    try {
      final fix = await ref.read(locationServiceProvider).currentLocation();
      if (!mounted) return;
      setState(() {
        draft.latitude = fix.latitude;
        draft.longitude = fix.longitude;
        _dirty = true;
      });
      ref.read(appDataProvider).settings.saveLastLocation(fix.latitude, fix.longitude);

      // Best-effort naming, online only. Failure here is silent: the coordinates are
      // already saved and everything stays typeable by hand.
      final places = ref.read(placeServiceProvider);
      try {
        final locality = await places.locality(fix.latitude, fix.longitude);
        if (mounted && locality != null && _locationName.text.trim().isEmpty) _locationName.text = locality;
      } catch (_) {}
      try {
        final waters = await places.nearbyWaters(fix.latitude, fix.longitude);
        if (mounted) setState(() => draft.waterSuggestions = waters);
      } catch (_) {}
    } on LocationException catch (e) {
      if (mounted) setState(() => _locationError = e.message);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      // Downscaled by the platform before we ever see the bytes, so a 48 MP original
      // never has to be decoded in Dart.
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: PhotoProcessor.maxLongEdge.toDouble(),
        maxHeight: PhotoProcessor.maxLongEdge.toDouble(),
        imageQuality: 85,
      );
      if (file == null || !mounted) return;
      setState(() => _processingPhoto = true);
      final bytes = await file.readAsBytes();
      final processed = await PhotoProcessor.process(bytes);
      if (!mounted) return;
      if (processed == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("That image format isn't supported.")));
      } else {
        setState(() {
          _pendingPhoto = processed;
          _photoSize = Size(processed.width.toDouble(), processed.height.toDouble());
          _draft!
            ..photoBytes = processed.full
            ..photoChanged = true;
          _dirty = true;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't open that photo.")));
      }
    } finally {
      if (mounted) setState(() => _processingPhoto = false);
    }
  }

  void _removePhoto() {
    setState(() {
      _pendingPhoto = null;
      _photoSize = null;
      _draft!
        ..photoBytes = null
        ..photoChanged = true;
      _dirty = true;
    });
  }

  Future<void> _measure() async {
    final draft = _draft!;
    final bytes = draft.photoBytes;
    final size = _photoSize;
    if (bytes == null || size == null || size.isEmpty) return;
    final result = await Navigator.of(context).push<MeasurementResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PhotoMeasurementScreen(
          imageBytes: bytes,
          imageSize: size,
          speciesId: SpeciesCatalog.resolveId(_species.text),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      draft.applyMeasurement(length: result.length, weight: result.weight);
      _length.text = draft.lengthText;
      if (result.weight != null) _weight.text = draft.weightText;
    });
  }

  bool get _canFetchConditions {
    final draft = _draft;
    if (draft == null) return false;
    return DateTime.now().difference(draft.date).abs() < const Duration(hours: 24);
  }

  Future<void> _fetchConditions() async {
    final draft = _draft!;
    if (!draft.hasCoordinate) await _captureLocation();
    if (!mounted || !draft.hasCoordinate) return;

    setState(() => _fetchingConditions = true);
    try {
      final conditions = await ref.read(conditionsProviderProvider).currentConditions(
            latitude: draft.latitude!,
            longitude: draft.longitude!,
            date: draft.date,
          );
      if (!mounted) return;
      if (conditions == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Weather isn't available right now.")));
      } else {
        setState(() {
          draft.applyConditions(conditions);
          _airTemp.text = draft.airTemperatureText;
          _windSpeed.text = draft.windSpeedText;
          _windDir.text = draft.windDirectionText;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Weather isn't available right now.")));
      }
    } finally {
      if (mounted) setState(() => _fetchingConditions = false);
    }
  }

  // ---- UI ----

  static final _decimalFilter = FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]'));
  static const _decimalKeyboard = TextInputType.numberWithOptions(decimal: true, signed: true);

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.catchId != null;
    final draft = _draft;

    if (_notFound) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Catch')),
        body: const EmptyState(icon: Icon(Icons.search_off), title: 'Catch not found', message: 'It may have been deleted.'),
      );
    }
    if (draft == null) {
      return Scaffold(
        appBar: AppBar(title: Text(isEditing ? 'Edit Catch' : 'New Catch')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final trips = ref.watch(tripsProvider).value ?? const [];

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard() && mounted) {
          setState(() => _dirty = false);
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEditing ? 'Edit Catch' : 'New Catch'),
          leading: IconButton(
            tooltip: 'Cancel',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          actions: [
            ListenableBuilder(
              listenable: _species,
              builder: (context, _) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  onPressed: _species.text.trim().isEmpty || _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save'),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: ContentColumn(
              child: Column(
                spacing: Metrics.sectionSpacing,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Section(title: 'Catch', children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _species,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(labelText: 'Species'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(onPressed: _browseSpecies, child: const Text('Browse')),
                      ],
                    ),
                    _DateRow(date: draft.date, onTap: _pickDate),
                    _UnitField<MassUnit>(
                      controller: _weight,
                      label: 'Weight',
                      unit: draft.weightUnit,
                      units: const [MassUnit.pounds, MassUnit.kilograms],
                      onUnit: (u) => setState(() {
                        draft.weightUnit = u;
                        _dirty = true;
                      }),
                      keyboard: _decimalKeyboard,
                      formatter: _decimalFilter,
                    ),
                    _UnitField<LengthUnit>(
                      controller: _length,
                      label: 'Length',
                      unit: draft.lengthUnit,
                      units: const [LengthUnit.inches, LengthUnit.centimeters],
                      onUnit: (u) => setState(() {
                        draft.lengthUnit = u;
                        _dirty = true;
                      }),
                      keyboard: _decimalKeyboard,
                      formatter: _decimalFilter,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Released'),
                      value: draft.wasReleased,
                      onChanged: (v) => setState(() {
                        draft.wasReleased = v;
                        _dirty = true;
                      }),
                    ),
                  ]),
                  if (trips.isNotEmpty)
                    _Section(title: 'Trip', children: [
                      DropdownButtonFormField<String?>(
                        initialValue: trips.any((t) => t.id == draft.tripId) ? draft.tripId : null,
                        decoration: const InputDecoration(labelText: 'Trip'),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('None')),
                          for (final t in trips)
                            DropdownMenuItem<String?>(
                              value: t.id,
                              child: Text(t.title.isEmpty ? formatDate(t.startDate) : t.title),
                            ),
                        ],
                        onChanged: (v) => setState(() {
                          draft.tripId = v;
                          _dirty = true;
                        }),
                      ),
                    ]),
                  _Section(title: 'Location', children: [
                    TextField(
                      controller: _waterBody,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Lake or river'),
                    ),
                    TextField(
                      controller: _locationName,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Location name'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _locating ? null : _captureLocation,
                      icon: _locating
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location),
                      label: const Text('Use Current Location'),
                    ),
                    if (draft.hasCoordinate)
                      Text(
                        '${draft.latitude!.toStringAsFixed(5)}, ${draft.longitude!.toStringAsFixed(5)}',
                        style: context.text.fishCaption.copyWith(color: context.scheme.onSurfaceVariant),
                      ),
                    if (_locationError != null)
                      Text(_locationError!, style: context.text.fishCaption.copyWith(color: context.scheme.error)),
                    _UnitField<LengthUnit>(
                      controller: _depth,
                      label: 'Depth',
                      unit: draft.depthUnit,
                      units: const [LengthUnit.feet, LengthUnit.meters],
                      onUnit: (u) => setState(() {
                        draft.depthUnit = u;
                        _dirty = true;
                      }),
                      keyboard: _decimalKeyboard,
                      formatter: _decimalFilter,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Fishing from a boat'),
                      value: draft.wasFromBoat,
                      onChanged: (v) => setState(() {
                        draft.wasFromBoat = v;
                        _dirty = true;
                      }),
                    ),
                  ]),
                  if (draft.waterSuggestions.isNotEmpty)
                    _Section(title: 'Nearby waters', children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final name in draft.waterSuggestions)
                            ActionChip(
                              avatar: const Icon(Icons.water, size: 18),
                              label: Text(name),
                              onPressed: () => _waterBody.text = name,
                            ),
                        ],
                      ),
                    ]),
                  _Section(title: 'Photo', children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _processingPhoto ? null : () => _pickPhoto(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text(draft.photoBytes == null ? 'Select Photo' : 'Change Photo'),
                        ),
                        if (ImagePicker().supportsImageSource(ImageSource.camera))
                          OutlinedButton.icon(
                            onPressed: _processingPhoto ? null : () => _pickPhoto(ImageSource.camera),
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('Take Photo'),
                          ),
                      ],
                    ),
                    if (_processingPhoto)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (draft.photoBytes case final Uint8List bytes) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(Metrics.controlCornerRadius),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 220),
                          child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _measure,
                            icon: const Icon(Icons.straighten),
                            label: const Text('Measure Fish'),
                          ),
                          TextButton.icon(
                            onPressed: _removePhoto,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Remove Photo'),
                          ),
                        ],
                      ),
                    ],
                  ]),
                  _Section(title: 'Conditions', children: [
                    Row(
                      spacing: 12,
                      children: [
                        Expanded(child: _NumberField(controller: _airTemp, label: 'Air temp (°F)', keyboard: _decimalKeyboard, formatter: _decimalFilter)),
                        Expanded(child: _NumberField(controller: _waterTemp, label: 'Water temp (°F)', keyboard: _decimalKeyboard, formatter: _decimalFilter)),
                      ],
                    ),
                    Row(
                      spacing: 12,
                      children: [
                        Expanded(child: _NumberField(controller: _windSpeed, label: 'Wind (mph)', keyboard: _decimalKeyboard, formatter: _decimalFilter)),
                        Expanded(child: _NumberField(controller: _windDir, label: 'Wind direction (°)', keyboard: _decimalKeyboard, formatter: _decimalFilter)),
                      ],
                    ),
                    TextField(
                      controller: _waterConditions,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Water conditions'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _fetchingConditions || !_canFetchConditions ? null : _fetchConditions,
                      icon: _fetchingConditions
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.cloud_download_outlined),
                      label: const Text('Fill from current weather'),
                    ),
                    if (!_canFetchConditions)
                      Text(
                        'Live weather is only available for catches within the last 24 hours.',
                        style: context.text.fishCaption.copyWith(color: context.scheme.onSurfaceVariant),
                      ),
                    _InfoRow(label: 'Moon phase', value: MoonPhase.fromDate(draft.date).label),
                  ]),
                  _Section(title: 'Gear', children: [
                    for (final field in GearField.values)
                      _GearInput(
                        field: field,
                        controller: _gear[field]!,
                        onBrowse: () => _browseGear(field),
                      ),
                  ]),
                  _Section(title: 'Notes', children: [
                    TextField(
                      controller: _notes,
                      minLines: 3,
                      maxLines: 6,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Notes'),
                    ),
                  ]),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Semantics(
            header: true,
            child: Text(
              title.toUpperCase(),
              style: context.text.labelMedium!.copyWith(
                color: context.scheme.onSurfaceVariant,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        SurfaceCard(
          padding: const EdgeInsets.all(Metrics.cardSpacing + 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Metrics.cardSpacing,
            children: children,
          ),
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.keyboard,
    required this.formatter,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType keyboard;
  final TextInputFormatter formatter;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      inputFormatters: [formatter],
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(labelText: label),
    );
  }
}

/// A number field with a segmented unit switch beside it.
class _UnitField<U extends MeasureUnit> extends StatelessWidget {
  const _UnitField({
    required this.controller,
    required this.label,
    required this.unit,
    required this.units,
    required this.onUnit,
    required this.keyboard,
    required this.formatter,
  });

  final TextEditingController controller;
  final String label;
  final U unit;
  final List<U> units;
  final ValueChanged<U> onUnit;
  final TextInputType keyboard;
  final TextInputFormatter formatter;

  @override
  Widget build(BuildContext context) {
    // An imported entry may carry a unit the form doesn't normally offer (oz, g, ft for
    // length…). Show it rather than silently selecting nothing.
    final shown = units.contains(unit) ? units : [...units, unit];
    return Row(
      spacing: 12,
      children: [
        Expanded(child: _NumberField(controller: controller, label: label, keyboard: keyboard, formatter: formatter)),
        SegmentedButton<U>(
          showSelectedIcon: false,
          segments: [for (final u in shown) ButtonSegment(value: u, label: Text(u.symbol))],
          selected: {unit},
          onSelectionChanged: (s) => onUnit(s.first),
        ),
      ],
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({required this.date, required this.onTap});

  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Metrics.controlCornerRadius),
      child: InputDecorator(
        decoration: const InputDecoration(labelText: 'Date', suffixIcon: Icon(Icons.event)),
        child: Text(formatDateTime(date)),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: context.text.fishBody.copyWith(color: context.scheme.onSurfaceVariant))),
        Text(value, style: context.text.fishBody),
      ],
    );
  }
}

/// A gear text field with Browse and the angler's own most-used values as one-tap chips.
class _GearInput extends ConsumerWidget {
  const _GearInput({required this.field, required this.controller, required this.onBrowse});

  final GearField field;
  final TextEditingController controller;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(gearSuggestionsProvider(field));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: field.fieldLabel),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: onBrowse, child: const Text('Browse')),
          ],
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: suggestions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ActionChip(
                label: Text(suggestions[i]),
                visualDensity: VisualDensity.compact,
                onPressed: () => controller.text = suggestions[i],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
