import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'app_theme.dart';

/// 地図キー未設定時に出す、見た目だけの地図プレビュー（文言なし）。
class FakeMapPreview extends StatelessWidget {
  const FakeMapPreview({
    super.key,
    required this.latitude,
    required this.longitude,
    this.height = 280,
    this.onTap,
  });

  final double latitude;
  final double longitude;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: PostCheckPalette.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CustomPaint(
              painter: _FakeMapPainter(
                seed: (latitude * 1000 + longitude).round(),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

class _FakeMapPainter extends CustomPainter {
  _FakeMapPainter({required this.seed});
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    // 地の色
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFE8EEF2),
    );
    // 公園っぽい緑の塊
    for (var i = 0; i < 4; i++) {
      final r = size.shortestSide * (0.08 + rnd.nextDouble() * 0.1);
      canvas.drawCircle(
        Offset(
          size.width * (0.15 + rnd.nextDouble() * 0.7),
          size.height * (0.2 + rnd.nextDouble() * 0.6),
        ),
        r,
        Paint()..color = const Color(0xFFC8E6C9),
      );
    }
    // 道路
    final road = Paint()
      ..color = Colors.white
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final roadEdge = Paint()
      ..color = const Color(0xFFCFD8DC)
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final paths = <Path>[
      Path()
        ..moveTo(0, size.height * 0.35)
        ..quadraticBezierTo(
          size.width * 0.4,
          size.height * 0.25,
          size.width,
          size.height * 0.4,
        ),
      Path()
        ..moveTo(size.width * 0.2, 0)
        ..quadraticBezierTo(
          size.width * 0.35,
          size.height * 0.5,
          size.width * 0.55,
          size.height,
        ),
      Path()
        ..moveTo(0, size.height * 0.75)
        ..lineTo(size.width, size.height * 0.62),
    ];
    for (final p in paths) {
      canvas.drawPath(p, roadEdge);
      canvas.drawPath(p, road);
    }
    // 街区
    for (var i = 0; i < 10; i++) {
      final w = 28.0 + rnd.nextDouble() * 40;
      final h = 18.0 + rnd.nextDouble() * 28;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * rnd.nextDouble() * 0.85,
          size.height * rnd.nextDouble() * 0.85,
          w,
          h,
        ),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, Paint()..color = const Color(0xFFD5DEE5));
    }
    // 中央ピン
    final c = Offset(size.width / 2, size.height / 2 - 8);
    final pin = Path()
      ..moveTo(c.dx, c.dy + 22)
      ..quadraticBezierTo(c.dx - 16, c.dy + 4, c.dx - 16, c.dy - 6)
      ..arcToPoint(
        Offset(c.dx + 16, c.dy - 6),
        radius: const Radius.circular(16),
        clockwise: true,
      )
      ..quadraticBezierTo(c.dx + 16, c.dy + 4, c.dx, c.dy + 22)
      ..close();
    canvas.drawPath(pin, Paint()..color = PostCheckPalette.primary);
    canvas.drawCircle(
      Offset(c.dx, c.dy - 8),
      6,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _FakeMapPainter oldDelegate) =>
      oldDelegate.seed != seed;
}
