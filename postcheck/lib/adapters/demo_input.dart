import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// A fictional, locally rendered fixture. It goes through the real OCR path.
Future<ByteData?> createDemoPhoto({String? fontFamily}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 1200, 800),
    Paint()..color = const Color(0xFFE8EFF9),
  );
  void rect(Rect rect, Color color, double radius) => canvas.drawRRect(
    RRect.fromRectAndRadius(rect, Radius.circular(radius)),
    Paint()..color = color,
  );
  void text(String value, Offset at, double size, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 1000);
    painter.paint(canvas, at);
  }

  text('EVENT DAY', const Offset(65, 50), 36, const Color(0xFF2563EB));
  rect(const Rect.fromLTWH(65, 145, 680, 420), const Color(0xFF172441), 18);
  rect(const Rect.fromLTWH(85, 165, 640, 365), Colors.white, 6);
  text('新企画の資料', const Offset(130, 200), 42, const Color(0xFF172441));
  text('Project Sakura', const Offset(130, 265), 34, const Color(0xFF2563EB));
  for (var i = 0; i < 5; i++) {
    rect(
      Rect.fromLTWH(140 + i * 105.0, 445 - i * 24, 50, 50 + i * 24),
      const Color(0xFF9DC4FF),
      5,
    );
  }
  rect(const Rect.fromLTWH(790, 275, 335, 265), Colors.white, 16);
  rect(const Rect.fromLTWH(910, 160, 30, 125), const Color(0xFF2563EB), 8);
  text('山田 太郎', const Offset(820, 325), 40, const Color(0xFF172441));
  text('taro@example.com', const Offset(810, 405), 26, const Color(0xFF34435B));
  text('サンプル画像・すべて架空の情報です', const Offset(65, 680), 28, const Color(0xFF63718A));
  final image = await recorder.endRecording().toImage(1200, 800);
  try {
    return await image.toByteData(format: ui.ImageByteFormat.png);
  } finally {
    image.dispose();
  }
}
