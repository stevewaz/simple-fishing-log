import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/format/number_format.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/catalog/species_catalog.dart';
import '../../domain/models/units.dart';

class MeasurementResult {
  const MeasurementResult(this.length, this.weight);

  final Measurement<LengthUnit> length;
  final Measurement<MassUnit>? weight;
}

/// Things an angler is likely to already have in a pocket or on the boat — a card isn't
/// something most carry to the water — plus a fully custom length for anything else.
enum ReferenceKind {
  card('Card', 'credit or ID card', 3.37),
  bill('Bill', 'dollar bill', 6.14),
  can('Can', 'drink can', 4.83),
  custom('Custom', 'reference object', null);

  const ReferenceKind(this.shortLabel, this.fullLabel, this.fixedLengthInches);

  final String shortLabel;
  final String fullLabel;

  /// Long edge for card/bill, height for a standard can — whichever edge is easiest to lay
  /// flat next to the fish and tap both ends of.
  final double? fixedLengthInches;
}

enum _Phase { referenceStart, referenceEnd, fishStart, fishEnd, done }

/// A manual two-reference measuring tool. No photo carries real-world scale by itself — a
/// fish held close to the lens looks identical in pixels to a bigger one held farther away.
/// The angler marks two points along something of known size and two more along the fish;
/// because both pairs are measured in the same image, the display scale cancels out of the
/// ratio and only the reference's real length matters.
///
/// Points are stored normalised to the *image* (0…1), not to the screen, so rotating the
/// device or resizing the window can't shift them off the fish.
class PhotoMeasurementScreen extends StatefulWidget {
  const PhotoMeasurementScreen({
    super.key,
    required this.imageBytes,
    required this.imageSize,
    required this.speciesId,
  });

  final Uint8List imageBytes;
  final Size imageSize;
  final String speciesId;

  @override
  State<PhotoMeasurementScreen> createState() => _PhotoMeasurementScreenState();
}

class _PhotoMeasurementScreenState extends State<PhotoMeasurementScreen> {
  Offset? _refStart, _refEnd, _fishStart, _fishEnd; // normalised 0…1 within the image
  ReferenceKind _kind = ReferenceKind.bill;
  final _customLength = TextEditingController();

  @override
  void dispose() {
    _customLength.dispose();
    super.dispose();
  }

  _Phase get _phase {
    if (_refStart == null) return _Phase.referenceStart;
    if (_refEnd == null) return _Phase.referenceEnd;
    if (_fishStart == null) return _Phase.fishStart;
    if (_fishEnd == null) return _Phase.fishEnd;
    return _Phase.done;
  }

  String get _instruction => switch (_phase) {
        _Phase.referenceStart => 'Lay your ${_kind.fullLabel} flat next to the fish, then tap one end of it',
        _Phase.referenceEnd => 'Now tap the other end of the ${_kind.fullLabel}',
        _Phase.fishStart => "Tap the tip of the fish's nose",
        _Phase.fishEnd => "Tap the tip of the fish's tail",
        _Phase.done => 'Drag any point to fine-tune, or use this measurement',
      };

  double? get _referenceInches => _kind.fixedLengthInches ?? parseDecimal(_customLength.text);

  /// Distance between two normalised points, in *image pixels*.
  double _pixels(Offset a, Offset b) {
    final dx = (b.dx - a.dx) * widget.imageSize.width;
    final dy = (b.dy - a.dy) * widget.imageSize.height;
    return math.sqrt(dx * dx + dy * dy);
  }

  double? get _lengthInches {
    final rs = _refStart, re = _refEnd, fs = _fishStart, fe = _fishEnd, ref = _referenceInches;
    if (rs == null || re == null || fs == null || fe == null || ref == null || ref <= 0) return null;
    final referencePixels = _pixels(rs, re);
    if (referencePixels <= 0) return null;
    return _pixels(fs, fe) / (referencePixels / ref);
  }

  double? get _estimatedPounds {
    final length = _lengthInches;
    if (length == null) return null;
    return SpeciesCatalog.estimatedWeightPounds(speciesId: widget.speciesId, lengthInches: length);
  }

  void _reset() => setState(() => _refStart = _refEnd = _fishStart = _fishEnd = null);

  void _use() {
    final length = _lengthInches;
    if (length == null) return;
    final pounds = _estimatedPounds;
    Navigator.pop(
      context,
      MeasurementResult(
        Measurement(double.parse(length.toStringAsFixed(2)), LengthUnit.inches),
        pounds == null ? null : Measurement(double.parse(pounds.toStringAsFixed(2)), MassUnit.pounds),
      ),
    );
  }

  /// The rectangle the contained image actually occupies inside [box].
  Rect _imageRect(Size box) {
    final fitted = applyBoxFit(BoxFit.contain, widget.imageSize, box).destination;
    return Alignment.center.inscribe(fitted, Offset.zero & box);
  }

  Offset _toNormalised(Offset local, Rect rect) => Offset(
        ((local.dx - rect.left) / rect.width).clamp(0.0, 1.0),
        ((local.dy - rect.top) / rect.height).clamp(0.0, 1.0),
      );

  Offset _toLocal(Offset normalised, Rect rect) =>
      Offset(rect.left + normalised.dx * rect.width, rect.top + normalised.dy * rect.height);

  void _place(Offset local, Rect rect) {
    if (!rect.inflate(8).contains(local)) return; // a tap in the letterbox isn't a point
    final p = _toNormalised(local, rect);
    setState(() {
      switch (_phase) {
        case _Phase.referenceStart:
          _refStart = p;
        case _Phase.referenceEnd:
          _refEnd = p;
        case _Phase.fishStart:
          _fishStart = p;
        case _Phase.fishEnd:
          _fishEnd = p;
        case _Phase.done:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final length = _lengthInches;
    final pounds = _estimatedPounds;
    final fish = context.fish;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Measure Fish'),
        leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Cancel', onPressed: () => Navigator.pop(context)),
        actions: [
          TextButton(onPressed: _reset, child: const Text('Reset')),
          TextButton(onPressed: length == null ? null : _use, child: const Text('Use')),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ReferenceKind>(
                      showSelectedIcon: false,
                      segments: [
                        for (final k in ReferenceKind.values) ButtonSegment(value: k, label: Text(k.shortLabel)),
                      ],
                      selected: {_kind},
                      onSelectionChanged: (s) => setState(() => _kind = s.first),
                    ),
                  ),
                  if (_kind == ReferenceKind.custom) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _customLength,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Known length',
                        hintText: 'e.g. 8.5',
                        suffixText: 'in',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final box = Size(constraints.maxWidth, constraints.maxHeight);
                  final rect = _imageRect(box);
                  // Null until the point is placed. Must not return a placeholder widget: a
                  // non-positioned child would make the Stack size to its content instead of
                  // filling the area, collapsing the whole measuring surface.
                  Widget? handle(Offset? p, Color color, void Function(Offset) set, String label) {
                    if (p == null) return null;
                    final c = _toLocal(p, rect);
                    // 44 px touch target around an 18 px dot: a fingertip is far bigger than
                    // the point it is trying to place.
                    return Positioned(
                      left: c.dx - 22,
                      top: c.dy - 22,
                      width: 44,
                      height: 44,
                      child: Semantics(
                        label: label,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanUpdate: (d) => setState(() => set(_toNormalised(c + d.delta, rect))),
                          child: Center(
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  return GestureDetector(
                    key: const Key('measureArea'),
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => _place(d.localPosition, rect),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned.fill(
                          child: Image.memory(widget.imageBytes, fit: BoxFit.contain, gaplessPlayback: true),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _LinesPainter(
                                rect: rect,
                                reference: (_refStart, _refEnd),
                                fish: (_fishStart, _fishEnd),
                              ),
                            ),
                          ),
                        ),
                        ?handle(_refStart, Colors.yellow, (p) => _refStart = p, 'Reference start'),
                        ?handle(_refEnd, Colors.yellow, (p) => _refEnd = p, 'Reference end'),
                        ?handle(_fishStart, Colors.cyanAccent, (p) => _fishStart = p, 'Fish nose'),
                        ?handle(_fishEnd, Colors.cyanAccent, (p) => _fishEnd = p, 'Fish tail'),
                      ],
                    ),
                  );
                },
              ),
            ),
            Container(
              width: double.infinity,
              color: context.scheme.surfaceContainer,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(_instruction, style: context.text.fishHeadline, textAlign: TextAlign.center),
                  if (length != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      formatMeasurement(Measurement(length, LengthUnit.inches)),
                      style: context.text.fishTitle.copyWith(color: fish.currentWater),
                    ),
                    if (pounds != null)
                      Text(
                        '~${formatMeasurement(Measurement(pounds, MassUnit.pounds))} estimated',
                        style: context.text.fishCaption.copyWith(color: context.scheme.onSurfaceVariant),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinesPainter extends CustomPainter {
  const _LinesPainter({required this.rect, required this.reference, required this.fish});

  final Rect rect;
  final (Offset?, Offset?) reference;
  final (Offset?, Offset?) fish;

  Offset _local(Offset n) => Offset(rect.left + n.dx * rect.width, rect.top + n.dy * rect.height);

  @override
  void paint(Canvas canvas, Size size) {
    void line((Offset?, Offset?) pair, Color color) {
      final (a, b) = pair;
      if (a == null || b == null) return;
      canvas.drawLine(
        _local(a),
        _local(b),
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }

    line(reference, Colors.yellow);
    line(fish, Colors.cyanAccent);
  }

  @override
  bool shouldRepaint(_LinesPainter old) => old.rect != rect || old.reference != reference || old.fish != fish;
}
