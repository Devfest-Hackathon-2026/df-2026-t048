import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../domain/social_share.dart';
import '../l10n/app_localizations.dart';
import 'postcheck_controller.dart';
import 'social_share_sheet.dart';

class StorySharePage extends StatefulWidget {
  const StorySharePage({super.key, required this.controller});
  final PostCheckController controller;
  @override
  State<StorySharePage> createState() => _StorySharePageState();
}

class _StorySharePageState extends State<StorySharePage> {
  StoryLayout layout = StoryLayout.card;
  late Future<Uint8List> preview;
  @override
  void initState() {
    super.initState();
    preview = widget.controller.previewStory(layout);
  }

  void change(StoryLayout value) {
    if (value == layout) return;
    setState(() {
      layout = value;
      preview = widget.controller.previewStory(value);
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      return PopScope(
        canPop: !c.busy,
        child: Scaffold(
          appBar: AppBar(
            title: const AppText('ストーリーズ'),
            automaticallyImplyLeading: !c.busy,
          ),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final entry in {
                        StoryLayout.card: '写真＋文章',
                        StoryLayout.overlay: '写真に重ねる',
                        StoryLayout.photoOnly: '写真のみ',
                      }.entries)
                        if (entry.key != StoryLayout.photoOnly ||
                            c.photo != null)
                          ChoiceChip(
                            label: AppText(entry.value),
                            selected: layout == entry.key,
                            onSelected: c.canExport
                                ? (_) => change(entry.key)
                                : null,
                          ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FutureBuilder<Uint8List>(
                      future: preview,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: AppText(
                              snapshot.error is StoryCaptionTooLong
                                  ? '文章が長く、ストーリーズ画像に収まりません。写真のみを選ぶか、文章を短くして再確認してください。'
                                  : 'プレビューを作成できませんでした。確認画面へ戻って再確認してください。',
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CupertinoActivityIndicator(),
                          );
                        }
                        return Center(
                          child: AspectRatio(
                            aspectRatio: 9 / 16,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Image.memory(
                                snapshot.data!,
                                fit: BoxFit.contain,
                                gaplessPlayback: false,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                if (c.error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: AppText(c.error),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: FutureBuilder<Uint8List>(
                    future: preview,
                    builder: (context, snapshot) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AppText(
                          '文字は画像に含まれます。共有先でストーリーズを選んでください。',
                          style: TextStyle(
                            fontSize: 12,
                            color: CupertinoColors.secondaryLabel,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            key: const ValueKey('share-story-button'),
                            onPressed:
                                c.canExport &&
                                    snapshot.hasData &&
                                    snapshot.connectionState ==
                                        ConnectionState.done
                                ? () async {
                                    final result = await c.shareTo(
                                      ShareDestination.instagramStory,
                                      layout: layout,
                                    );
                                    if (!context.mounted || result == null) {
                                      return;
                                    }
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: AppText(
                                          shareHandoffMessage(result),
                                        ),
                                      ),
                                    );
                                  }
                                : null,
                            icon: c.busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CupertinoActivityIndicator(),
                                  )
                                : const Icon(CupertinoIcons.share),
                            label: const AppText('9:16画像を共有'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
