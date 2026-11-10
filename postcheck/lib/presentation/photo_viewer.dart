import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Inspection only: display the same bytes as the current photo preview.
class PhotoViewer extends StatefulWidget {
  const PhotoViewer({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  final _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: SafeArea(
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                key: const ValueKey('close-photo-viewer'),
                tooltip: tr(context, '写真を閉じる'),
                color: Colors.white,
                icon: const Icon(CupertinoIcons.xmark),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const Spacer(),
              IconButton(
                tooltip: tr(context, '元の倍率に戻す'),
                color: Colors.white,
                icon: const Icon(CupertinoIcons.arrow_counterclockwise),
                onPressed: () => _transform.value = Matrix4.identity(),
              ),
            ],
          ),
          Expanded(
            child: InteractiveViewer(
              key: const ValueKey('fullscreen-photo'),
              transformationController: _transform,
              minScale: 1,
              maxScale: 8,
              child: SizedBox.expand(
                child: Image.memory(
                  widget.bytes,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  semanticLabel: tr(context, '写真の全画面表示'),
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: AppText(
              '2本の指で拡大・縮小、ドラッグで移動',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    ),
  );
}
