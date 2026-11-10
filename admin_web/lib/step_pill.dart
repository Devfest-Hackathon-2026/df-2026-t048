import 'package:flutter/material.dart';
import 'app_theme.dart';

/// 新規申請の現在ステップだけを出す青いピル。
class StepPill extends StatelessWidget {
  const StepPill({super.key, required this.step});

  /// 0: 施設登録 / 1: ルール / 2: 最終確認
  final int step;

  static const titles = ['施設登録', 'ルール', '最終確認'];
  static const _assets = [
    'assets/steps/step_facility_ai_20261110.png',
    'assets/steps/step_rules_ai_20261110.png',
    'assets/steps/step_confirm_ai_20261110.png',
  ];

  @override
  Widget build(BuildContext context) {
    final i = step.clamp(0, 2);
    return Center(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 20, 10),
        decoration: const ShapeDecoration(
          color: PostCheckPalette.primary,
          shape: StadiumBorder(),
          shadows: [
            BoxShadow(
              color: Color(0x220A6CF1),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 正方形ボックス + contain で縦横比を維持（潰れ防止）
            SizedBox.square(
              dimension: 36,
              child: Image.asset(
                _assets[i],
                color: Colors.white,
                colorBlendMode: BlendMode.srcIn,
                fit: BoxFit.contain,
                alignment: Alignment.center,
                filterQuality: FilterQuality.high,
                isAntiAlias: true,
                gaplessPlayback: true,
                excludeFromSemantics: true,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Step ${i + 1}　${titles[i]}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                height: 1.25,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
