import 'package:flutter/material.dart';

/// 出典を記録した新規生成のメガホン画像。
class PublishLogo extends StatelessWidget {
  const PublishLogo({super.key, this.height = 168});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: height * 1.15,
      child: Image.asset(
        'assets/megaphone_mark_ai_20261110.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        excludeFromSemantics: true,
      ),
    );
  }
}

/// 文章高さの約3倍のロゴ領域。
double publishLogoHeightForText({
  required double fontSize,
  required double height,
  int lines = 2,
}) => fontSize * height * lines * 3;
