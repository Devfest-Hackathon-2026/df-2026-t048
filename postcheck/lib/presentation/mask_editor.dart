import '../l10n/app_localizations.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'apple_components.dart';
import '../domain/models.dart';
import '../domain/ports.dart';

enum _Tool { vertices, brush, erase, move }

/// Local transaction. Nothing is committed until Done; undo includes erasing.
class MaskEditor extends StatefulWidget {
  const MaskEditor({
    super.key,
    required this.photo,
    required this.images,
    required this.style,
    this.initial,
    this.baseMasks = const [],
    this.trailingMasks = const [],
    this.allowEmpty = true,
  });
  final PhotoInput photo;
  final ImageProcessingPort images;
  final RedactionStyle style;
  final PhotoMask? initial;
  final List<PhotoMask> baseMasks;
  final List<PhotoMask> trailingMasks;
  final bool allowEmpty;
  @override
  State<MaskEditor> createState() => _MaskEditorState();
}

class _MaskEditorState extends State<MaskEditor> {
  late List<MaskOperation> _ops;
  final _history = <List<MaskOperation>>[];
  final _redo = <List<MaskOperation>>[];
  final _transform = TransformationController();
  _Tool _tool = _Tool.vertices;
  double _diameter = .055;
  int? _selected, _vertex;
  Offset? _last;
  bool _dragging = false, _rendering = true;
  ui.Image? _effect;
  Uint8List? _preview;
  String? _error;
  @override
  void initState() {
    super.initState();
    _ops = [...?widget.initial?.operations];
    _selected = _ops.indexWhere((o) => o.kind == MaskOperationKind.polygon);
    if (_selected == -1) _selected = null;
    if (_ops.isEmpty) _tool = _Tool.brush;
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      final codec = await ui.instantiateImageCodec(
        widget.photo.bytes,
        targetWidth:
            (widget.photo.width *
                    math.min(
                      1.0,
                      1000 / math.max(widget.photo.width, widget.photo.height),
                    ))
                .round(),
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      final photo = PhotoInput(
        bytes: data!.buffer.asUint8List(),
        width: frame.image.width,
        height: frame.image.height,
      );
      frame.image.dispose();
      codec.dispose();
      if (!mounted) return;
      if (widget.style == RedactionStyle.blur) {
        final blurred = await widget.images.redact(photo, [
          PhotoMask.region(const ImageRegion(0, 0, 1, 1)),
        ], style: RedactionStyle.blur);
        final effectCodec = await ui.instantiateImageCodec(blurred);
        final effectFrame = await effectCodec.getNextFrame();
        effectCodec.dispose();
        if (!mounted) {
          effectFrame.image.dispose();
          return;
        }
        _effect = effectFrame.image;
      }
      if (mounted) {
        setState(() {
          _preview = photo.bytes;
          _rendering = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'プレビューを作れませんでした';
          _rendering = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _effect?.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _saveHistory() {
    _history.add(List.of(_ops));
    _redo.clear();
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(
        () => _error = PhotoMask(_ops).isValid ? null : '頂点や範囲を確認してください',
      );
    }
  }

  void _changed() {
    setState(() {});
    unawaited(_refresh());
  }

  void _addShape(int count) {
    _saveHistory();
    _ops.add(
      PhotoMask.regularPolygon(count, const ImageRegion(.2, .2, .6, .6)),
    );
    _selected = _ops.length - 1;
    _vertex = null;
    _tool = _Tool.vertices;
    _transform.value = Matrix4.identity();
    _changed();
  }

  void _shapeMenu() => showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Wrap(
        children: [
          for (final count in [3, 4, 5, 6, 8])
            ListTile(
              title: AppText(
                count == 3
                    ? '三角形'
                    : count == 4
                    ? '四角形・台形'
                    : '$count角形',
              ),
              onTap: () {
                Navigator.pop(ctx);
                _addShape(count);
              },
            ),
        ],
      ),
    ),
  );
  MaskPoint _point(Offset p, Size size) => MaskPoint(
    (p.dx / size.width).clamp(0, 1),
    (p.dy / size.height).clamp(0, 1),
  );
  Path _path(MaskOperation op, Size size) {
    final p = Path()
      ..moveTo(op.points.first.x * size.width, op.points.first.y * size.height);
    for (final v in op.points.skip(1)) {
      p.lineTo(v.x * size.width, v.y * size.height);
    }
    return p..close();
  }

  void _select(Offset p, Size size) {
    _vertex = null;
    final hitRadius = 26 / _transform.value.getMaxScaleOnAxis();
    if (_selected != null) {
      final points = _ops[_selected!].points;
      for (var i = 0; i < points.length; i++) {
        if ((p - Offset(points[i].x * size.width, points[i].y * size.height))
                .distance <
            hitRadius) {
          _vertex = i;
          return;
        }
      }
    }
    _selected = null;
    for (var i = _ops.length - 1; i >= 0; i--) {
      if (_ops[i].kind == MaskOperationKind.polygon &&
          _path(_ops[i], size).contains(p)) {
        _selected = i;
        return;
      }
    }
  }

  void _start(Offset p, Size size) {
    if (_tool == _Tool.vertices) {
      _select(p, size);
      if (_selected == null) {
        setState(() {});
        return;
      }
    }
    _saveHistory();
    _last = p;
    _dragging = true;
    if (_tool == _Tool.brush || _tool == _Tool.erase) {
      _ops.add(
        MaskOperation(
          _tool == _Tool.erase
              ? MaskOperationKind.erase
              : MaskOperationKind.brush,
          [_point(p, size)],
          diameter: _diameter,
        ),
      );
    }
    setState(() {});
  }

  void _update(Offset p, Size size) {
    if (!_dragging) return;
    if (_tool == _Tool.brush || _tool == _Tool.erase) {
      final op = _ops.last;
      final next = _point(p, size);
      final last = op.points.last;
      if (math.pow((next.x - last.x) * size.width, 2) +
              math.pow((next.y - last.y) * size.height, 2) <
          1) {
        return;
      }
      _ops[_ops.length - 1] = MaskOperation(op.kind, [
        ...op.points,
        next,
      ], diameter: op.diameter);
    } else if (_selected != null) {
      final op = _ops[_selected!];
      final points = List<MaskPoint>.of(op.points);
      if (_vertex != null) {
        points[_vertex!] = _point(p, size);
      } else {
        var dx = (p.dx - _last!.dx) / size.width,
            dy = (p.dy - _last!.dy) / size.height;
        dx = dx.clamp(
          -points.map((p) => p.x).reduce(math.min),
          1 - points.map((p) => p.x).reduce(math.max),
        );
        dy = dy.clamp(
          -points.map((p) => p.y).reduce(math.min),
          1 - points.map((p) => p.y).reduce(math.max),
        );
        for (var i = 0; i < points.length; i++) {
          points[i] = MaskPoint(points[i].x + dx, points[i].y + dy);
        }
      }
      _ops[_selected!] = MaskOperation(MaskOperationKind.polygon, points);
    }
    _last = p;
    setState(() {});
  }

  void _end() {
    if (!_dragging) return;
    _dragging = false;
    if (!PhotoMask(_ops).isValid) {
      _ops = _history.removeLast();
    }
    _changed();
  }

  void _undo(bool redo) {
    final from = redo ? _redo : _history, to = redo ? _history : _redo;
    if (from.isEmpty) return;
    to.add(List.of(_ops));
    _ops = from.removeLast();
    _selected = null;
    _changed();
  }

  void _addVertex() {
    if (_selected == null) return;
    final op = _ops[_selected!];
    if (op.points.length >= 16) return;
    _saveHistory();
    final points = List<MaskPoint>.of(op.points);
    final at = _vertex ?? 0,
        a = points[at],
        b = points[(at + 1) % points.length];
    points.insert(at + 1, MaskPoint((a.x + b.x) / 2, (a.y + b.y) / 2));
    _ops[_selected!] = MaskOperation(MaskOperationKind.polygon, points);
    _vertex = at + 1;
    _changed();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF101012),
    appBar: AppBar(
      centerTitle: true,
      backgroundColor: const Color(0xFF101012),
      foregroundColor: Colors.white,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      flexibleSpace: const GlassSurface(
        dark: true,
        radius: 0,
        child: SizedBox.expand(),
      ),
      title: AppText(
        widget.style == RedactionStyle.blur ? 'ぼかしを編集' : '黒塗りを編集',
        style: const TextStyle(fontSize: 17, color: Colors.white),
      ),
      actions: [
        TextButton(
          onPressed:
              _rendering ||
                  _dragging ||
                  _preview == null ||
                  _error != null ||
                  (!widget.allowEmpty && _ops.isEmpty)
              ? null
              : () => Navigator.pop(context, PhotoMask(_ops)),
          child: const AppText('完了'),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (_rendering) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            AppText(_error!, style: const TextStyle(color: Colors.orange)),
          Expanded(
            child: Center(
              child: InteractiveViewer(
                transformationController: _transform,
                panEnabled: _tool == _Tool.move,
                scaleEnabled: _tool == _Tool.move,
                minScale: 1,
                maxScale: 8,
                child: AspectRatio(
                  aspectRatio: widget.photo.width / widget.photo.height,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = constraints.biggest;
                      return GestureDetector(
                        dragStartBehavior: DragStartBehavior.down,
                        behavior: HitTestBehavior.opaque,
                        onTapDown: _tool == _Tool.vertices
                            ? (d) {
                                _select(d.localPosition, size);
                                setState(() {});
                              }
                            : null,
                        onTapUp: _tool == _Tool.brush || _tool == _Tool.erase
                            ? (d) {
                                _start(d.localPosition, size);
                                _end();
                              }
                            : null,
                        onPanStart: _tool == _Tool.move
                            ? null
                            : (d) => _start(d.localPosition, size),
                        onPanUpdate: _tool == _Tool.move
                            ? null
                            : (d) => _update(d.localPosition, size),
                        onPanEnd: _tool == _Tool.move ? null : (_) => _end(),
                        onPanCancel: _tool == _Tool.move ? null : _end,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(
                              _preview ?? widget.photo.bytes,
                              fit: BoxFit.fill,
                              gaplessPlayback: true,
                            ),
                            IgnorePointer(
                              child: CustomPaint(
                                painter: _LiveMaskPainter(
                                  [
                                    ...widget.baseMasks.expand(
                                      (m) => m.operations,
                                    ),
                                    ..._ops,
                                    ...widget.trailingMasks.expand(
                                      (m) => m.operations,
                                    ),
                                  ],
                                  widget.style,
                                  _effect,
                                ),
                              ),
                            ),
                            IgnorePointer(
                              child: CustomPaint(
                                painter: _MaskOverlay(
                                  _ops,
                                  _tool == _Tool.vertices ? _selected : null,
                                  _dragging,
                                  _transform.value.getMaxScaleOnAxis(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          Container(
            color: const Color(0xFF202024),
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_tool == _Tool.brush || _tool == _Tool.erase)
                  Row(
                    children: [
                      const Icon(Icons.circle, color: Colors.white, size: 8),
                      Expanded(
                        child: Slider(
                          value: _diameter,
                          min: .008,
                          max: .25,
                          semanticFormatterCallback: (v) =>
                              tr(context, 'ブラシの太さ ${(v * 100).round()}'),
                          onChanged: (v) => setState(() => _diameter = v),
                        ),
                      ),
                      const Icon(Icons.circle, color: Colors.white, size: 28),
                    ],
                  ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _button('図形を追加', CupertinoIcons.plus, _shapeMenu),
                      for (final item in [
                        (_Tool.vertices, '頂点', CupertinoIcons.crop),
                        (_Tool.brush, 'ブラシ', CupertinoIcons.paintbrush),
                        (_Tool.erase, '消しゴム', Icons.auto_fix_normal),
                        (_Tool.move, '拡大・移動', CupertinoIcons.hand_draw),
                      ])
                        _button(
                          item.$2,
                          item.$3,
                          () => setState(() => _tool = item.$1),
                          selected: _tool == item.$1,
                        ),
                    ],
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    IconButton(
                      tooltip: tr(context, '元に戻す'),
                      onPressed: _history.isEmpty ? null : () => _undo(false),
                      icon: const Icon(Icons.undo),
                      color: Colors.white,
                    ),
                    IconButton(
                      tooltip: tr(context, 'やり直す'),
                      onPressed: _redo.isEmpty ? null : () => _undo(true),
                      icon: const Icon(Icons.redo),
                      color: Colors.white,
                    ),
                    if (_tool == _Tool.vertices && _selected != null) ...[
                      TextButton(
                        onPressed: _addVertex,
                        child: const AppText('頂点を追加'),
                      ),
                      IconButton(
                        tooltip: tr(context, '選択した図形を削除'),
                        color: Colors.white,
                        icon: const Icon(CupertinoIcons.trash),
                        onPressed: () {
                          _saveHistory();
                          _ops.removeAt(_selected!);
                          _selected = null;
                          _changed();
                        },
                      ),
                    ],
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const AppText('キャンセル'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Widget _button(
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool selected = false,
  }) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      foregroundColor: selected ? Colors.lightBlueAccent : Colors.white70,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22),
        const SizedBox(height: 4),
        AppText(label, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );
}

class _MaskOverlay extends CustomPainter {
  const _MaskOverlay(this.ops, this.selected, this.dragging, this.scale);
  final List<MaskOperation> ops;
  final int? selected;
  final bool dragging;
  final double scale;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    for (var index = 0; index < ops.length; index++) {
      final op = ops[index];
      if (!dragging && index != selected) continue;
      final points = op.points
          .map((p) => Offset(p.x * size.width, p.y * size.height))
          .toList();
      if (op.kind == MaskOperationKind.polygon) {
        final path = Path()..addPolygon(points, true);

        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.lightBlueAccent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 / scale,
        );
        if (index == selected) {
          for (final point in points) {
            canvas.drawCircle(point, 7 / scale, Paint()..color = Colors.white);
            canvas.drawCircle(point, 4 / scale, Paint()..color = Colors.blue);
          }
        }
      } else if (dragging && index == ops.length - 1) {
        canvas.drawCircle(
          points.last,
          op.diameter * math.min(size.width, size.height) / 2,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 / scale,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MaskOverlay old) => true;
}

/// Alpha-mask layers make erasing subtract coverage while the finger moves.
class _LiveMaskPainter extends CustomPainter {
  const _LiveMaskPainter(this.operations, this.style, this.effect);
  final List<MaskOperation> operations;
  final RedactionStyle style;
  final ui.Image? effect;
  @override
  void paint(Canvas canvas, Size size) {
    if (style == RedactionStyle.blur && effect == null) return;
    final bounds = Offset.zero & size;
    canvas.saveLayer(bounds, Paint());
    if (effect != null && style == RedactionStyle.blur) {
      canvas.drawImageRect(
        effect!,
        Rect.fromLTWH(
          0,
          0,
          effect!.width.toDouble(),
          effect!.height.toDouble(),
        ),
        bounds,
        Paint()..filterQuality = FilterQuality.low,
      );
    } else {
      canvas.drawRect(bounds, Paint()..color = Colors.black);
    }
    canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.dstIn);
    for (final op in operations) {
      if (op.points.isEmpty) continue;
      final points = op.points
          .map((p) => Offset(p.x * size.width, p.y * size.height))
          .toList();
      final paint = Paint()
        ..color = Colors.black
        ..blendMode = op.kind == MaskOperationKind.erase
            ? BlendMode.clear
            : BlendMode.srcOver;
      if (op.kind == MaskOperationKind.polygon) {
        canvas.drawPath(
          Path()
            ..fillType = PathFillType.evenOdd
            ..addPolygon(points, true),
          paint,
        );
      } else {
        final width = op.diameter * math.min(size.width, size.height);
        if (points.length == 1) {
          canvas.drawCircle(points.first, width / 2, paint);
        } else {
          final path = Path()..moveTo(points.first.dx, points.first.dy);
          for (final p in points.skip(1)) {
            path.lineTo(p.dx, p.dy);
          }
          canvas.drawPath(
            path,
            paint
              ..style = PaintingStyle.stroke
              ..strokeWidth = width
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round,
          );
        }
      }
    }
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LiveMaskPainter oldDelegate) => true;
}
