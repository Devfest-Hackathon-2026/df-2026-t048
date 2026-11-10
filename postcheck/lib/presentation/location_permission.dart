import '../l10n/app_localizations.dart';
import 'package:flutter/cupertino.dart';
import 'nearby_controller.dart';

Future<void> useDeviceLocation(BuildContext context, NearbyController n) async {
  if (!n.permitted) {
    final yes = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const AppText('現在地を使う'),
        content: const AppText(
          '利用中の現在地から、近くの施設ルールを確認します。位置履歴は保存しません。地図の表示領域はGoogleへ送られます。許可せず使うこともできます。',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const AppText('今は使わない'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, true),
            child: const AppText('現在地を使う'),
          ),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
  }
  await n.useCurrentLocation();
}
