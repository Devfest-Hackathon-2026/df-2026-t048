import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import '../domain/models.dart';
import '../domain/social_share.dart';

/// Renders the same PNG for preview and sharing. Original caption stays local;
/// no caption is silently truncated and no original photo metadata is copied.
final class StoryImageComposer {
  const StoryImageComposer();
  Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1080);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  Future<Uint8List> compose(ExportArtifact artifact, StoryLayout layout) async {
    if (layout != StoryLayout.photoOnly && artifact.caption.length > 6000) {
      throw StoryCaptionTooLong();
    }
    if (layout == StoryLayout.photoOnly && artifact.imageBytes == null) {
      throw ArgumentError('photo_required');
    }
    const width = 1080.0, height = 1920.0;
    final image = artifact.imageBytes == null
        ? null
        : await _decode(artifact.imageBytes!);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(const Color(0xff121214), BlendMode.src);
    final caption = layout == StoryLayout.photoOnly ? '' : artifact.caption;
    final hasCaption = caption.trim().isNotEmpty;
    // Keep top/bottom room for Instagram's own controls.
    final photoRect = layout == StoryLayout.card && hasCaption
        ? const Rect.fromLTWH(48, 200, 984, 1000)
        : const Rect.fromLTWH(0, 160, width, 1600);
    if (image != null) {
      canvas.save();
      canvas.clipRRect(
        RRect.fromRectAndRadius(photoRect, const Radius.circular(28)),
      );
      paintImage(
        canvas: canvas,
        rect: photoRect,
        image: image,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      );
      canvas.restore();
    }
    if (hasCaption) {
      final rect = image == null
          ? const Rect.fromLTWH(80, 300, 920, 1300)
          : layout == StoryLayout.card
          ? const Rect.fromLTWH(80, 1270, 920, 450)
          : const Rect.fromLTWH(80, 1100, 920, 590);
      if (layout == StoryLayout.overlay && image != null) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(24), const Radius.circular(24)),
          Paint()..color = const Color(0xd9121214),
        );
      }
      TextPainter? text;
      for (double size = 58; size >= 30; size -= 2) {
        final candidate = TextPainter(
          text: TextSpan(
            text: caption,
            style: TextStyle(
              color: const Color(0xffffffff),
              fontFamily: '.SF Pro Text',
              fontSize: size,
              height: 1.4,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: rect.width);
        text?.dispose();
        text = candidate;
        if (candidate.height <= rect.height) break;
      }
      if (text!.height > rect.height) {
        text.dispose();
        image?.dispose();
        recorder.endRecording().dispose();
        throw StoryCaptionTooLong();
      }
      text.paint(
        canvas,
        Offset(
          rect.left,
          rect.top + (image == null ? (rect.height - text.height) / 2 : 0),
        ),
      );
      text.dispose();
    }
    final picture = recorder.endRecording();
    final output = await picture.toImage(width.toInt(), height.toInt());
    try {
      return (await output.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();
    } finally {
      output.dispose();
      picture.dispose();
      image?.dispose();
    }
  }
}
