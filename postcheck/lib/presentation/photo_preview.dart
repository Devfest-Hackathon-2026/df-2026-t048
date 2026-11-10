import '../l10n/app_localizations.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../domain/models.dart';
import 'app_theme.dart';
import 'photo_viewer.dart';

class PhotoPreview extends StatefulWidget {
  const PhotoPreview({
    super.key,
    required this.photo,
    this.preview,
    required this.findings,
    required this.decisions,
    required this.selectedId,
    required this.drawing,
    required this.onSelect,
    required this.onDraw,
  });
  final PhotoInput photo;
  final Uint8List? preview;
  final List<Finding> findings;
  final Map<String, ReviewDecision> decisions;
  final String? selectedId;
  final bool drawing;
  final ValueChanged<String> onSelect;
  final ValueChanged<ImageRegion> onDraw;

  @override
  State<PhotoPreview> createState() => _PhotoPreviewState();
}

class _PhotoPreviewState extends State<PhotoPreview> {
  Offset? _start, _end;

  void _openPhoto() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            PhotoViewer(bytes: widget.preview ?? widget.photo.bytes),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant PhotoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.drawing) {
      _start = _end = null;
    }
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: AspectRatio(
      aspectRatio: widget.photo.width / widget.photo.height,
      child: LayoutBuilder(
        builder: (context, size) {
          Offset local(Offset p) => Offset(
            p.dx.clamp(0, size.maxWidth),
            p.dy.clamp(0, size.maxHeight),
          );
          return GestureDetector(
            key: const ValueKey('photo-canvas'),
            behavior: HitTestBehavior.opaque,
            onTap: widget.drawing ? null : _openPhoto,
            onPanStart: !widget.drawing
                ? null
                : (d) => setState(() {
                    _start = local(d.localPosition);
                    _end = _start;
                  }),
            onPanUpdate: !widget.drawing
                ? null
                : (d) => setState(() {
                    _end = local(d.localPosition);
                  }),
            onPanEnd: !widget.drawing
                ? null
                : (_) {
                    if (_start != null && _end != null) {
                      final rect = Rect.fromPoints(_start!, _end!);
                      if (rect.width >= 8 && rect.height >= 8) {
                        widget.onDraw(
                          ImageRegion(
                            rect.left / size.maxWidth,
                            rect.top / size.maxHeight,
                            rect.width / size.maxWidth,
                            rect.height / size.maxHeight,
                          ),
                        );
                      }
                    }
                    setState(() {
                      _start = _end = null;
                    });
                  },
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  widget.preview ?? widget.photo.bytes,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                  excludeFromSemantics: true,
                ),
                for (final (index, finding) in widget.findings.indexed)
                  if (finding.target case PhotoTarget(:final region))
                    if (widget.decisions[finding.id] != ReviewDecision.hide)
                      Positioned(
                        left: region.x * size.maxWidth,
                        top: region.y * size.maxHeight,
                        width: region.width * size.maxWidth,
                        height: region.height * size.maxHeight,
                        child: GestureDetector(
                          onTap: widget.drawing
                              ? null
                              : () => widget.onSelect(finding.id),
                          child: Semantics(
                            excludeSemantics: true,
                            label: finding.excerpt.trim().isNotEmpty
                                ? '${index + 1} ${finding.excerpt.trim()}'
                                : tr(
                                    context,
                                    '${index + 1}番 ${finding.displayLabel}',
                                  ),
                            button: true,
                            child: Container(
                              decoration: BoxDecoration(
                                color: widget.selectedId == finding.id
                                    ? const Color(0x220075DE)
                                    : Colors.transparent,
                                border: Border.all(
                                  width: widget.selectedId == finding.id
                                      ? 3
                                      : 1.5,
                                  color:
                                      widget.decisions[finding.id] ==
                                          ReviewDecision.keep
                                      ? PostCheckPalette.tertiary
                                      : PostCheckPalette.link,
                                ),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              alignment: Alignment.topLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: PostCheckPalette.link,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                if (!widget.drawing)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton.filledTonal(
                      key: const ValueKey('open-photo-viewer'),
                      tooltip: tr(context, '写真を全画面表示'),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.fullscreen),
                      onPressed: _openPhoto,
                    ),
                  ),
                if (widget.drawing)
                  const Positioned(
                    top: 10,
                    left: 10,
                    right: 10,
                    child: IgnorePointer(
                      child: Chip(label: AppText('隠す範囲を指でドラッグしてください')),
                    ),
                  ),
                if (_start != null && _end != null)
                  Positioned.fromRect(
                    rect: Rect.fromPoints(_start!, _end!),
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
