import '../l10n/app_localizations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'nearby_controller.dart';
import 'venue_page.dart';
import 'location_permission.dart';
import 'apple_components.dart';
import 'venue_check_status.dart';
import 'venue_rule_summary.dart';
import '../domain/preferences.dart';

class NearbyCard extends StatelessWidget {
  const NearbyCard({
    super.key,
    required this.controller,
    required this.onChange,
    this.compact = false,
    this.iconOnly = false,
    this.aiEnabled,
    this.preferences = const ReviewPreferences(),
  });
  final NearbyController controller;
  final VoidCallback onChange;
  final bool compact;
  final bool iconOnly;
  final bool? aiEnabled;
  final ReviewPreferences preferences;

  void _details(BuildContext context) => appleSheet<void>(
    context,
    ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final n = controller, v = n.selected;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            AppText(
              '場所のルール',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 20),
            const AppText('現在地から500m以内で最も近い登録施設を自動選択します。手動で選んだ施設を優先します。'),
            const SizedBox(height: 12),
            AppleSection(
              footer: '施設ルールを外しても、利用者がONにした項目はチェックします。OFFは撮影許可を意味しません。',
              children: [
                AppleRow(
                  title: v?.policy.name ?? tr(context, '施設は未選択'),
                  translateTitle: false,
                  subtitle: v == null
                      ? '顔・連絡先の基本チェックは利用できます'
                      : (n.rules.manual ? '手動で選択' : '現在地からの推定'),
                  trailing: v == null
                      ? null
                      : Switch.adaptive(
                          value: n.active != null,
                          onChanged: v.policy.validAt(n.rules.now())
                              ? n.toggle
                              : null,
                        ),
                ),
                AppleRow(
                  title: '施設を変更',
                  icon: CupertinoIcons.map,
                  onTap: () {
                    Navigator.pop(context);
                    onChange();
                  },
                ),
                if (v != null)
                  AppleRow(
                    title: 'ルールの原文',
                    icon: CupertinoIcons.doc_text,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ListenableBuilder(
                          listenable: n,
                          builder: (_, _) => VenueRulesPage(
                            venue: n.selected?.id == v.id ? n.selected! : v,
                            applied: n.active?.id == v.id,
                            aiEnabled: aiEnabled,
                            preferences: preferences,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (v != null) ...[
              VenueCheckStatus(
                venue: v,
                applied: n.active != null,
                aiEnabled: aiEnabled,
                preferences: preferences,
                now: n.rules.now(),
              ),
              VenueRuleSummary(policy: v.policy),
            ],
            AppleSection(
              title: '現在地',
              footer: n.locationMessage.isEmpty ? null : n.locationMessage,
              children: [
                AppleRow(
                  title: n.simulated ? '実際の現在地に戻す' : '現在地を使う',
                  icon: CupertinoIcons.location,
                  onTap: () => useDeviceLocation(context, n),
                ),
                if (n.rules.manual || n.rules.switchedOff || n.simulated)
                  AppleRow(
                    title: '施設の自動選択に戻す',
                    icon: CupertinoIcons.arrow_clockwise,
                    onTap: n.automatic,
                  ),
                AppleRow(
                  title: 'ルールを再取得',
                  icon: CupertinoIcons.arrow_clockwise,
                  onTap: n.loading
                      ? null
                      : () async {
                          await n.refresh();
                          await n.measure();
                        },
                ),
              ],
            ),
            if (n.catalogMessage.isNotEmpty) AppText(n.catalogMessage),
            if (n.catalogStale && n.fetchedAt != null)
              AppText(
                '取得：${n.fetchedAt!.toLocal().toIso8601String().substring(0, 16).replaceFirst('T', ' ')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (n.demo)
              AppleSection(
                title: 'デモ',
                footer: '架空施設の動作デモです。実在施設の案内ではありません。',
                children: [
                  AppleRow(title: '架空の施設に近づく', onTap: () => n.simulate()),
                  if (n.simulated)
                    AppleRow(
                      title: '施設から離れる',
                      onTap: () => n.simulate(outside: true),
                    ),
                ],
              ),
          ],
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final n = controller, v = n.selected;
      final expired = v != null && !v.policy.validAt(n.rules.now());
      final subtitle = n.catalogStale
          ? 'ルールの最新情報を確認できません'
          : expired
          ? '期限切れ · 基本チェック'
          : v != null
          ? '${n.active == null
                ? n.rules.switchedOff
                      ? 'OFF · 基本チェック'
                      : !n.rules.fresh
                      ? '現在地を確認中 · 基本チェック'
                      : '500m圏外 · 基本チェック'
                : n.rules.manual
                ? 'ON · 手動選択'
                : 'ON · 近くの施設（推定）'}${n.demo ? ' · デモ' : ''}'
          : n.loading
          ? '施設を確認中'
          : !n.permitted && !n.simulated
          ? '現在地オフ · 基本チェック${n.demo ? ' · デモ' : ''}'
          : '基本チェック${n.demo ? ' · デモ' : ''}';
      final fg = compact ? Colors.white : const Color(0xFF1C1C1E);
      if (iconOnly) {
        return Tooltip(
          message: tr(context, '場所のルール · $subtitle'),
          child: Semantics(
            label: tr(context, '場所のルール · $subtitle'),
            button: true,
            child: GlassSurface(
              dark: true,
              radius: 22,
              child: IconButton(
                onPressed: () => _details(context),
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                constraints: const BoxConstraints.tightFor(
                  width: 44,
                  height: 44,
                ),
                padding: EdgeInsets.zero,
                icon: Icon(
                  CupertinoIcons.location_solid,
                  size: 18,
                  color: n.catalogStale || expired
                      ? const Color(0xFFFFCC00)
                      : n.active != null
                      ? const Color(0xFF64D2FF)
                      : Colors.white,
                ),
              ),
            ),
          ),
        );
      }
      if (compact) {
        final state = n.catalogStale
            ? '未更新'
            : expired
            ? '期限切れ'
            : v == null
            ? (n.loading ? '確認中' : '基本チェック')
            : n.active == null
            ? n.rules.switchedOff
                  ? 'OFF'
                  : n.rules.fresh
                  ? '圏外'
                  : '確認中'
            : 'ON';
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: GlassSurface(
            dark: true,
            radius: 22,
            child: Semantics(
              label: tr(context, '場所のルール、${v?.policy.name ?? ''}、$subtitle'),
              button: true,
              child: InkWell(
                onTap: () => _details(context),
                child: SizedBox(
                  height: 44,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          CupertinoIcons.location,
                          size: 15,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            v?.policy.name ?? tr(context, '場所のルール'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        AppText(
                          state,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Icon(
                          CupertinoIcons.chevron_forward,
                          size: 10,
                          color: Colors.white70,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
      final row = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _details(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Icon(CupertinoIcons.location, size: 21, color: fg),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              v?.policy.name ?? tr(context, '場所のルール'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: fg,
                              ),
                            ),
                            AppText(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: fg.withValues(alpha: .75),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        CupertinoIcons.chevron_forward,
                        size: 13,
                        color: fg.withValues(alpha: .6),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (v != null)
              Semantics(
                label: tr(context, '施設ルールの適用'),
                child: Switch.adaptive(
                  key: const ValueKey('venue-switch'),
                  value: n.active != null,
                  onChanged: expired ? null : n.toggle,
                ),
              ),
          ],
        ),
      );
      return GlassSurface(
        dark: compact,
        native: compact,
        radius: 24,
        child: row,
      );
    },
  );
}
