import 'access_page.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:postcheck_rules/postcheck_rules.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_theme.dart';

/// 選択済みの項目を表示順に並べた文字列。空なら「なし」。
String checkTargetsLabel(List<String> targets) {
  final labels = [
    for (final t in venueCheckTargets)
      if (targets.contains(t)) venueCheckTargetLabels[t] ?? t,
  ];
  return labels.isEmpty ? 'なし' : labels.join('、');
}

class InfoBox extends StatelessWidget {
  const InfoBox(this.text, {super.key, this.warning = false});
  final String text;
  final bool warning;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: warning ? const Color(0xfffff3dc) : PostCheckPalette.blueSoft,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(text),
  );
}

class PolicyCard extends StatelessWidget {
  const PolicyCard({
    super.key,
    required this.policy,
    this.forSubmitPreview = false,
  });
  final VenuePolicy policy;

  /// 最終確認用：申請名見出し＋配信範囲・確認ワードを白カードに含める。
  final bool forSubmitPreview;

  String get _applicationTitle {
    final t = policy.applicationName.trim();
    return t.isNotEmpty ? t : policy.name;
  }

  @override
  Widget build(BuildContext context) {
    final showLegacy = !forSubmitPreview && policy.hasLegacyRuleDetails;
    final rows = <MapEntry<String, String>>[
      MapEntry('施設名', policy.name),
      if (forSubmitPreview) MapEntry('住所', policy.address),
      if (forSubmitPreview && policy.website.isNotEmpty)
        MapEntry('公式サイト', policy.website),
      if (showLegacy) ...[
        if (policy.event.isNotEmpty) MapEntry('イベント', policy.event),
        MapEntry('撮影許可', policy.photography.label),
        if (policy.area.isNotEmpty) MapEntry('対象エリア', policy.area),
        MapEntry('公開範囲', policy.publication.label),
        MapEntry('商用利用', policy.commercial.label),
      ],
      MapEntry('必ず指摘する項目', checkTargetsLabel(policy.checkTargets)),
      if (forSubmitPreview)
        MapEntry('配信範囲', policy.visibility == 'public' ? '一般公開' : '組織内のみ'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '申請名　$_applicationTitle',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Divider(height: 28),
            for (final e in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    SizedBox(width: 120, child: Text(e.key)),
                    Expanded(child: Text(e.value)),
                  ],
                ),
              ),
            if (showLegacy) MultilingualPolicyDetails(policy: policy),
            if (showLegacy && policy.releaseAt != null) ...[
              const SizedBox(height: 8),
              InfoBox(
                '名称の公開解禁：${policy.releaseAt!.toUtc().add(const Duration(hours: 9)).toString().substring(0, 16)}（日本時間）',
              ),
            ],
            if (showLegacy && policy.sourceText.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('根拠', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(policy.sourceText),
            ],
            if (showLegacy && policy.sourceUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                '参考URL',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              TextButton(
                onPressed: () => openSource(policy.sourceUrl),
                child: const Text('参考URLを開く'),
              ),
            ],
            if (showLegacy && policy.sourceImage.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('参考画像', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Builder(
                builder: (context) {
                  final raw = policy.sourceImage;
                  final i = raw.indexOf('base64,');
                  if (i < 0) return const Text('画像を表示できません');
                  try {
                    final bytes = base64Decode(raw.substring(i + 7));
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        bytes,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    );
                  } catch (_) {
                    return const Text('画像を表示できません');
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class MultilingualPolicyDetails extends StatelessWidget {
  const MultilingualPolicyDetails({super.key, required this.policy});
  final VenuePolicy policy;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 16),
      Text(
        '原文の言語：${ruleLanguages[policy.sourceLanguage] ?? policy.sourceLanguage}',
      ),
      Text('対象エリアの種類：${policy.areaKind.label}'),
      if (policy.conditionCodes.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text('具体的な条件', style: TextStyle(fontWeight: FontWeight.w600)),
        for (final code in policy.conditionCodes)
          Text(VenueCondition.parse(code)?.label ?? '未対応の条件：$code'),
      ],
      for (final entry in policy.translations.entries)
        ExpansionTile(
          title: Text('${ruleLanguages[entry.key] ?? entry.key}の説明'),
          subtitle: Text(
            policy.reviewedTranslation(entry.key) != null
                ? '施設確認済み・承認後に配信'
                : '未確認／更新後の再確認が必要・配信対象外',
          ),
          childrenPadding: const EdgeInsets.all(12),
          children: [
            if (entry.value.area.isNotEmpty) Text('対象エリア：${entry.value.area}'),
            Text(entry.value.text),
          ],
        ),
    ],
  );
}

Future<void> openSource(String value) async {
  final u = Uri.tryParse(value);
  if (u != null &&
      u.scheme == 'https' &&
      u.userInfo.isEmpty &&
      u.host.isNotEmpty) {
    await launchUrl(u, mode: LaunchMode.externalApplication);
  }
}

class VenueDetail extends StatefulWidget {
  const VenueDetail({
    super.key,
    required this.api,
    required this.venue,
    required this.operator,
    this.canEdit = false,
  });
  final RulesApi api;
  final ManagedVenue venue;
  final bool operator;

  /// 申請者側：下書き・差し戻しを編集画面へ戻す。
  final bool canEdit;
  @override
  State<VenueDetail> createState() => _VenueDetailState();
}

class _VenueDetailState extends State<VenueDetail> {
  late ManagedVenue v = widget.venue;
  final reason = TextEditingController();
  bool verified = false, busy = false;
  String error = '';
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> act(String action) async {
    if (busy) return;
    if (['return', 'suspend'].contains(action) && reason.text.trim().isEmpty) {
      setState(() => error = '理由を入力してください。');
      return;
    }
    final label = {
      'approve': '承認して公開',
      'return': '差し戻す',
      'suspend': '公開停止',
      'withdraw': '申請を取り下げる',
    }[action]!;
    final confirmTitle = {
      'approve': '承認して公開しますか？',
      'return': '差し戻しますか？',
      'suspend': '公開停止しますか？',
      'withdraw': '申請を取り下げますか？',
    }[action]!;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(confirmTitle),
        content: Text(
          '${v.draft.name}\n公開範囲：${v.draft.visibility == 'public' ? '一般公開' : '組織内のみ'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(label),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final next = await widget.api.change(
        v,
        action,
        reason: reason.text.trim(),
      );
      if (!mounted) return;
      // 差し戻し・承認・停止・取り下げ後は一覧へ戻す。
      if (const {'return', 'approve', 'suspend', 'withdraw'}.contains(action)) {
        Navigator.pop(context);
        return;
      }
      setState(() => v = next);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is RulesApiException ? e.message : '操作に失敗しました。',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String get _applicationTitle {
    final t = v.draft.applicationName.trim();
    return t.isNotEmpty ? t : v.draft.name;
  }

  bool get _isApproved => v.status == 'published';

  Widget _approvalStatusPill() {
    final approved = _isApproved;
    final color = approved ? const Color(0xFF1B7F3A) : const Color(0xFFC62828);
    final background = approved
        ? const Color(0xFFE8F5E9)
        : const Color(0xFFFFEBEE);
    return _statusPill(
      label: approved ? '承認済み' : '未承認',
      color: color,
      background: background,
      leading: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }

  Widget _applicantStatusPill() {
    if (v.suspended) {
      return _statusPill(
        label: '公開停止',
        color: const Color(0xFFC62828),
        background: const Color(0xFFFFEBEE),
        leading: const Icon(
          Icons.pause_circle_filled,
          size: 14,
          color: Color(0xFFC62828),
        ),
      );
    }
    return switch (v.status) {
      'returned' => _statusPill(
        label: '差戻し',
        color: const Color(0xFFB45309),
        background: const Color(0xFFFFF4E5),
        leading: const Icon(
          Icons.warning_amber_rounded,
          size: 15,
          color: Color(0xFFB45309),
        ),
      ),
      'pending' => _statusPill(
        label: '審査中',
        color: const Color(0xFF0A6CF1),
        background: const Color(0xFFEFF6FF),
        leading: Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: Color(0xFF0A6CF1),
            shape: BoxShape.circle,
          ),
        ),
      ),
      'published' => _statusPill(
        label: '公開済み',
        color: const Color(0xFF1B7F3A),
        background: const Color(0xFFE8F5E9),
        leading: Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: Color(0xFF1B7F3A),
            shape: BoxShape.circle,
          ),
        ),
      ),
      _ => _statusPill(
        label: '下書き',
        color: PostCheckPalette.secondary,
        background: const Color(0xFFF3F2F0),
        leading: Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: PostCheckPalette.secondary,
            shape: BoxShape.circle,
          ),
        ),
      ),
    };
  }

  Widget _statusPill({
    required String label,
    required Color color,
    required Color background,
    required Widget leading,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        leading,
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
      ],
    ),
  );

  Widget _softLabel(String text) => Text(
    text,
    style: const TextStyle(
      color: PostCheckPalette.secondary,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
  );

  Widget _stackedField(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _softLabel(label),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: PostCheckPalette.ink,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
      ],
    ),
  );

  (Color, Color, IconData) _permissionTone(RulePermission permission) =>
      switch (permission) {
        RulePermission.forbidden => (
          const Color(0xFFFFEBEE),
          const Color(0xFFC62828),
          Icons.cancel,
        ),
        RulePermission.allowed => (
          const Color(0xFFE8F5E9),
          const Color(0xFF1B7F3A),
          Icons.check_circle,
        ),
        RulePermission.conditional => (
          const Color(0xFFFFF8E1),
          const Color(0xFFEF6C00),
          Icons.info,
        ),
        RulePermission.unknown => (
          const Color(0xFFF3F2F0),
          PostCheckPalette.secondary,
          Icons.help_outline,
        ),
      };

  Widget _permissionTile(String label, RulePermission permission) {
    final tone = _permissionTone(permission);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        decoration: BoxDecoration(
          color: tone.$1,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: PostCheckPalette.secondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            // アイコンと文言を縦に置き、「条件付き」などの途中改行を防ぐ。
            Icon(tone.$3, size: 16, color: tone.$2),
            const SizedBox(height: 4),
            Text(
              permission.label,
              style: TextStyle(
                color: tone.$2,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: const TextStyle(
              color: PostCheckPalette.secondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );

  Widget _sectionLabel(String text, {bool required = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: PostCheckPalette.ink,
          ),
        ),
        if (required) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: PostCheckPalette.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              '差し戻し・停止時は必須',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: PostCheckPalette.primary,
              ),
            ),
          ),
        ],
      ],
    ),
  );

  Future<void> _showFacilityInfoModal() async {
    final p = v.draft;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 640),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '施設情報',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _kv('施設名', p.name),
                        if (p.address.isNotEmpty) _kv('住所', p.address),
                        if (p.website.isNotEmpty) _kv('公式サイト', p.website),
                        if (p.event.isNotEmpty) _kv('イベント', p.event),
                        if (p.area.isNotEmpty) _kv('対象エリア', p.area),
                        _kv(
                          '配信範囲',
                          p.visibility == 'public' ? '一般公開' : '組織内のみ',
                        ),
                        if (p.words.isNotEmpty) _kv('確認ワード', p.words.join('、')),
                        const SizedBox(height: 4),
                        const Text(
                          '施設の住所・公式サイトは公開対象です。担当者の氏名・電話・メールは収集しません。',
                          style: TextStyle(
                            color: PostCheckPalette.secondary,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('閉じる'),
                      ),
                    ),
                    if (p.website.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => openSource(p.website),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('公式サイト'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _operatorReviewCard() {
    final p = v.draft;
    Uint8List? imageBytes;
    if (p.sourceImage.startsWith('data:image')) {
      final i = p.sourceImage.indexOf('base64,');
      if (i >= 0) {
        try {
          imageBytes = base64Decode(p.sourceImage.substring(i + 7));
        } catch (_) {}
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _softLabel('申請名'),
                      const SizedBox(height: 6),
                      Text(
                        _applicationTitle,
                        style: const TextStyle(
                          color: PostCheckPalette.ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _approvalStatusPill(),
              ],
            ),
            const SizedBox(height: 24),
            _stackedField('施設名', p.name),
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _softLabel('許可内容'),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _permissionTile('撮影許可', p.photography),
                      const SizedBox(width: 8),
                      _permissionTile('公開範囲', p.publication),
                      const SizedBox(width: 8),
                      _permissionTile('商用利用', p.commercial),
                    ],
                  ),
                ],
              ),
            ),
            _stackedField('この施設で必ず指摘する項目', checkTargetsLabel(p.checkTargets)),
            _softLabel('根拠'),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F2F0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                p.sourceText.isEmpty ? '（未入力）' : p.sourceText,
                style: const TextStyle(
                  color: PostCheckPalette.ink,
                  height: 1.5,
                ),
              ),
            ),
            if (p.sourceUrl.isNotEmpty) ...[
              const SizedBox(height: 20),
              _softLabel('参考URL'),
              TextButton(
                onPressed: () => openSource(p.sourceUrl),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 0),
                ),
                child: const Text('参考URLを開く'),
              ),
            ],
            if (imageBytes != null) ...[
              const SizedBox(height: 12),
              _softLabel('参考画像'),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  imageBytes,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _applicantReviewCard() {
    final p = v.draft;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _softLabel('申請名'),
                      const SizedBox(height: 6),
                      Text(
                        _applicationTitle,
                        style: const TextStyle(
                          color: PostCheckPalette.ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _applicantStatusPill(),
              ],
            ),
            if (v.reason.isNotEmpty) ...[
              const Divider(height: 28),
              _softLabel('理由'),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Text(
                  v.reason,
                  style: const TextStyle(
                    color: PostCheckPalette.ink,
                    height: 1.5,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            _stackedField('施設名', p.name),
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _softLabel('許可内容'),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _permissionTile('撮影許可', p.photography),
                      const SizedBox(width: 8),
                      _permissionTile('公開範囲', p.publication),
                      const SizedBox(width: 8),
                      _permissionTile('商用利用', p.commercial),
                    ],
                  ),
                ],
              ),
            ),
            _stackedField('この施設で必ず指摘する項目', checkTargetsLabel(p.checkTargets)),
            _softLabel('根拠'),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F2F0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                p.sourceText.isEmpty ? '（未入力）' : p.sourceText,
                style: const TextStyle(
                  color: PostCheckPalette.ink,
                  height: 1.5,
                ),
              ),
            ),
            if (p.address.isNotEmpty) ...[
              const SizedBox(height: 20),
              _softLabel('施設の住所（公開対象）'),
              const SizedBox(height: 8),
              _kv('住所', p.address),
            ],
            if (p.website.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => openSource(p.website),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 0),
                ),
                child: const Text('施設の公式サイトを確認'),
              ),
            ],
            if (v.published != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              _softLabel('公開中の内容'),
              const SizedBox(height: 8),
              PolicyCard(policy: v.published!),
            ],
          ],
        ),
      ),
    );
  }

  String get _detailTitle {
    if (!widget.operator) return '施設・申請の詳細';
    return _isApproved ? '停止へ' : '承認へ';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_detailTitle)),
    body: ListView(
      padding: const EdgeInsets.all(28),
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error.isNotEmpty) InfoBox(error, warning: true),
        if (!widget.operator)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: busy
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            FacilityAccessPage(api: widget.api, venueId: v.id),
                      ),
                    ),
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('施設の管理権限'),
            ),
          ),
        if (widget.operator) ...[
          _operatorReviewCard(),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: MultilingualPolicyDetails(policy: v.draft),
            ),
          ),
          if (v.reason.isNotEmpty) ...[
            const SizedBox(height: 16),
            InfoBox(v.reason, warning: true),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: busy ? null : _showFacilityInfoModal,
              icon: const Icon(Icons.info_outline, size: 18),
              label: const Text('施設情報'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          CheckboxListTile(
            value: verified,
            onChanged: busy
                ? null
                : (x) => setState(() => verified = x ?? false),
            title: const Text('申請内容・根拠・参考資料を確認しました'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          _sectionLabel('差し戻し・公開停止の理由', required: true),
          TextField(
            controller: reason,
            enabled: !busy,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: '担当者に表示する理由を入力',
              floatingLabelBehavior: FloatingLabelBehavior.never,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '承認時は不要です。差し戻し・公開停止のときだけ使います。',
            style: TextStyle(color: PostCheckPalette.secondary, height: 1.5),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              if (v.status == 'pending') ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : () => act('return'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('差し戻す'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: busy || !verified ? null : () => act('approve'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('承認して公開'),
                  ),
                ),
              ],
            ],
          ),
          if (v.published != null && !v.suspended) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: busy ? null : () => act('suspend'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('公開停止'),
              ),
            ),
          ],
        ] else ...[
          _applicantReviewCard(),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: MultilingualPolicyDetails(policy: v.draft),
            ),
          ),
          if (widget.canEdit) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('編集する'),
              ),
            ),
          ],
          if (v.status == 'pending') ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: busy ? null : () => act('withdraw'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('申請を取り下げる'),
              ),
            ),
          ],
        ],
        if (v.published != null && !v.suspended) ...[
          const Divider(),
          const Text('施設選択用QR（管理権限は付与しません）'),
          Align(
            alignment: Alignment.centerLeft,
            child: QrImageView(data: 'postcheck://venue/${v.id}', size: 180),
          ),
          SelectableText('postcheck://venue/${v.id}'),
        ],
      ],
    ),
  );
}
