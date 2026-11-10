import 'package:flutter/material.dart';
import 'package:postcheck_rules/postcheck_rules.dart';
import '../domain/preferences.dart';
import '../l10n/app_localizations.dart';
import 'apple_components.dart';

/// Shows the same OR operation used by the checker. ON is configuration,
/// not a claim that detection or model inference has completed.
class VenueCheckStatus extends StatelessWidget {
  const VenueCheckStatus({
    super.key,
    required this.venue,
    required this.applied,
    this.aiEnabled,
    this.preferences = const ReviewPreferences(),
    this.now,
  });
  final PublishedVenue venue;
  final bool applied;
  final bool? aiEnabled;
  final ReviewPreferences preferences;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final time = now ?? DateTime.now();
    final active = applied && venue.policy.validAt(time);
    final facility = active ? venue.policy.checkTargets : const <String>[];
    String state(bool value) => tr(context, value ? 'オン' : 'オフ');
    return AppleSection(
      title: '適用されるチェック（OR）',
      footer:
          '利用者・施設のどちらかがONなら最終適用もONです。既存の施設原文・登録ワードに該当する候補は別途表示します。ONは実行完了や施設の許可を意味しません。',
      children: [
        AppleRow(
          key: const ValueKey('venue-application-status'),
          title: '施設ルールの適用',
          value: active ? 'オン' : 'オフ',
          subtitle: active
              ? 'この施設のルールをチェックに使います。'
              : '施設ルールは未適用です。利用者の設定でチェックします。',
        ),
        for (final item in CheckTarget.values)
          AppleRow(
            key: ValueKey('effective-check-${item.name}'),
            title: item.label,
            value: preferences.effectiveEnabled(item, venueTargets: facility)
                ? 'オン'
                : 'オフ',
            subtitle:
                '${tr(context, '利用者')} ${state(preferences.isEnabled(item))} ／ ${tr(context, '施設')} ${state(facility.contains(item.name))}',
            translateSubtitle: false,
          ),
        if (preferences.effectiveEnabled(
          CheckTarget.context,
          venueTargets: facility,
        ))
          AppleRow(
            title: '端末内AI',
            value: aiEnabled == null
                ? '未確認'
                : aiEnabled!
                ? 'オン'
                : 'オフ',
            subtitle: aiEnabled == false
                ? 'AIの利用がオフのため、内容のAI確認は実行しません。'
                : 'AIの利用がONでモデルの準備ができた場合に実行します。実行状況・結果はレビューで確認してください。',
          ),
      ],
    );
  }
}
