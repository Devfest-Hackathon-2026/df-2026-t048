import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../domain/social_share.dart';
import '../l10n/app_localizations.dart';
import 'apple_components.dart';

Future<ShareDestination?> chooseShareDestination(
  BuildContext context, {
  required bool hasPhoto,
  bool hasCaption = true,
}) => appleSheet<ShareDestination>(
  context,
  SocialShareSheet(hasPhoto: hasPhoto, hasCaption: hasCaption),
);

class SocialShareSheet extends StatelessWidget {
  const SocialShareSheet({
    super.key,
    required this.hasPhoto,
    this.hasCaption = true,
  });
  final bool hasPhoto, hasCaption;
  @override
  Widget build(BuildContext context) {
    Widget row(
      ShareDestination destination,
      String title,
      String subtitle,
      IconData icon, {
      bool enabled = true,
    }) => ListTile(
      key: ValueKey('share-${destination.name}'),
      leading: Icon(icon),
      title: AppText(title),
      subtitle: AppText(subtitle),
      trailing: const Icon(CupertinoIcons.chevron_forward, size: 16),
      enabled: enabled,
      onTap: enabled ? () => Navigator.pop(context, destination) : null,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: AppText('共有先', style: Theme.of(context).textTheme.titleLarge),
        ),
        row(
          ShareDestination.x,
          'X',
          hasPhoto ? '写真と文章 · 次の画面でXを選択' : '文章入りの投稿画面を開く',
          CupertinoIcons.bubble_left,
        ),
        row(
          ShareDestination.line,
          'LINE',
          hasPhoto ? '写真と文章 · 次の画面でLINEを選択' : '友だち・グループを選んで送る',
          CupertinoIcons.chat_bubble_2,
        ),
        row(
          ShareDestination.instagramStory,
          'Instagram ストーリーズ',
          '9:16の画像を作成',
          CupertinoIcons.rectangle,
        ),
        row(
          ShareDestination.instagramPost,
          'Instagram 投稿',
          hasPhoto ? '写真を共有・文章をコピー' : '写真を追加すると使えます',
          CupertinoIcons.square_grid_2x2,
          enabled: hasPhoto,
        ),
        row(
          ShareDestination.threads,
          'Threads',
          hasPhoto ? '写真と文章 · 次の画面でThreadsを選択' : '文章入りの投稿画面を開く',
          CupertinoIcons.at,
        ),
        row(
          ShareDestination.lineOfficial,
          '公式LINEに送る',
          hasCaption ? '文章入りのトークを開く · 写真は別途追加' : '投稿文を追加すると使えます',
          CupertinoIcons.building_2_fill,
          enabled: hasCaption,
        ),
        row(ShareDestination.other, 'その他', '共有シートから選ぶ', CupertinoIcons.share),
        const Padding(
          padding: EdgeInsets.all(12),
          child: AppText(
            '投稿・送信は共有先で確定します。',
            style: TextStyle(
              fontSize: 12,
              color: CupertinoColors.secondaryLabel,
            ),
          ),
        ),
      ],
    );
  }
}

Future<String?> chooseOfficialLine(BuildContext context) => showDialog<String>(
  context: context,
  builder: (_) => const _OfficialLineDialog(),
);

class _OfficialLineDialog extends StatefulWidget {
  const _OfficialLineDialog();
  @override
  State<_OfficialLineDialog> createState() => _OfficialLineDialogState();
}

class _OfficialLineDialogState extends State<_OfficialLineDialog> {
  final input = TextEditingController();
  String get accountId {
    final text = input.text.trim();
    return text.startsWith('@') ? text : '@$text';
  }

  bool get valid => RegExp(r'^@[A-Za-z0-9._-]{1,100}$').hasMatch(accountId);
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const AppText('公式LINEに送る'),
    content: TextField(
      key: const ValueKey('official-line-id'),
      controller: input,
      autofocus: true,
      maxLength: 101,
      autocorrect: false,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: tr(context, '公式アカウントのID'),
        hintText: '@example',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const AppText('キャンセル'),
      ),
      TextButton(
        onPressed: valid ? () => Navigator.pop(context, accountId) : null,
        child: const AppText('トークを開く'),
      ),
    ],
  );
}

String shareHandoffMessage(ShareHandoff result) => switch (result) {
  ShareHandoff.composer => '投稿画面を開きました。投稿は共有先で確定してください。',
  ShareHandoff.sheet => '共有先で内容を確認してください。',
  ShareHandoff.captionCopiedSheet => '投稿文をコピーしました。反映されない場合は共有先で貼り付けてください。',
  ShareHandoff.storySheet => '9:16画像を用意しました。共有先でストーリーズを選択してください。',
  ShareHandoff.instagramStory => 'ストーリーズの編集画面を開きました。',
  ShareHandoff.officialLineText => '文章入りのトークを開きました。写真は保存してから別途追加してください。',
};
