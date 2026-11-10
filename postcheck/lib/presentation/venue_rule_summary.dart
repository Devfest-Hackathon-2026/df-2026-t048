import 'package:flutter/material.dart';
import 'package:postcheck_rules/postcheck_rules.dart';
import '../l10n/app_localizations.dart';
import 'apple_components.dart';

/// Renders only fixed labels and facility-confirmed text in the selected
/// language. Unreviewed/stale drafts never become guidance through fallback.
class VenueRuleSummary extends StatelessWidget {
  const VenueRuleSummary({super.key, required this.policy});
  final VenuePolicy policy;

  @override
  Widget build(BuildContext context) {
    final checkItems = AppleSection(
      title: 'この施設で必ず指摘する項目',
      children: [
        if (policy.checkTargets.isEmpty)
          const AppleRow(title: '必ず指摘する項目', value: 'なし'),
        for (final target in venueCheckTargets)
          if (policy.checkTargets.contains(target))
            AppleRow(title: venueCheckTargetLabels[target]!, value: 'ON'),
      ],
    );
    if (!policy.hasLegacyRuleDetails) return checkItems;
    final code = AppStrings.of(context).locale.languageCode;
    final original = code == policy.sourceLanguage;
    final translated = policy.reviewedTranslation(code);
    final missing = !original && translated == null;
    final areaDetail = original ? policy.area : translated?.area ?? policy.area;
    final areaLabel = policy.areaKind == VenueArea.custom
        ? ''
        : tr(context, policy.areaKind.label);
    final area = [areaLabel, areaDetail].where((s) => s.isNotEmpty).join('\n');
    final explanation = original ? policy.sourceText : translated?.text;
    final permissions = [
      ('photography', '撮影', policy.photography),
      ('publication', 'SNS公開', policy.publication),
      ('commercial', '商用利用', policy.commercial),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (policy.checkTargets.isNotEmpty) checkItems,
        AppleSection(
          children: [
            for (final (aspect, title, permission) in permissions)
              AppleRow(
                title: title,
                value: permission.label,
                subtitle: policy.conditionCodes
                    .map(VenueCondition.parse)
                    .whereType<VenueCondition>()
                    .where((c) => c.aspect == aspect)
                    .map((c) => tr(context, c.label))
                    .join('\n'),
                translateSubtitle: false,
              ),
            AppleRow(
              title: '対象エリア',
              subtitle: area.isEmpty ? tr(context, '未指定') : area,
              translateSubtitle: false,
            ),
          ],
        ),
        if (permissions.any((p) => p.$3 == RulePermission.conditional))
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: AppText('定型条件に加え、施設の説明・原文も確認してください。'),
          ),
        if (policy.hasUnknownConditions)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: AppText('このバージョンでは表示できない条件があります。施設の原文・現場の案内を確認してください。'),
          ),
        if (missing)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: AppText('この言語の確認済み説明はありません。対象エリアの詳細とルールは原文・現場の案内で確認してください。'),
          ),
        if (explanation != null && explanation.isNotEmpty)
          AppleSection(
            title: original ? '施設の説明（原文）' : '施設が確認した説明',
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(explanation),
              ),
            ],
          ),
      ],
    );
  }
}
