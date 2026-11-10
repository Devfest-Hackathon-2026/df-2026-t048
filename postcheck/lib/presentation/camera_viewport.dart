import 'dart:math' as math;
import 'package:flutter/widgets.dart';

/// Covers the viewport without distorting the camera image. Put detection
/// overlays inside [child] so they share the image's crop and coordinates.
class CameraViewport extends StatelessWidget {
  const CameraViewport({
    super.key,
    required this.aspectRatio,
    required this.child,
  });

  final double aspectRatio;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = math.max(
        constraints.maxWidth,
        constraints.maxHeight * aspectRatio,
      );
      final height = width / aspectRatio;
      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.center,
          minWidth: width,
          maxWidth: width,
          minHeight: height,
          maxHeight: height,
          child: child,
        ),
      );
    },
  );
}
