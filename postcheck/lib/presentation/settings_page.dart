import 'dart:async';
import '../l10n/app_localizations.dart';
import '../domain/model_preparation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../domain/preferences.dart';
import 'apple_components.dart';

enum _Panel { policy, learning, ai, words, privacy }

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.settings, this.cloudSettings});
  final SettingsPort settings;
  final WidgetBuilder? cloudSettings;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  ModelPreparation? _model;
  Timer? _modelTimer;
  int _modelRequest = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshModel());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshModel());
  }

  void _showModel(ModelPreparation value) {
    if (!mounted) return;
    setState(() => _model = value);
    _modelTimer?.cancel();
    if (widget.settings.aiEnabled && value.isActive) {
      _modelTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        unawaited(_refreshModel());
      });
    }
  }

  Future<void> _refreshModel() async {
    final request = ++_modelRequest;
    final value = await widget.settings.modelPreparation();
    if (mounted && request == _modelRequest) _showModel(value);
  }

  Future<void> _modelAction({required bool resume}) async {
    final request = ++_modelRequest;
    _modelTimer?.cancel();
    final value = resume
        ? await widget.settings.prepareModel(resume: true)
        : await widget.settings.pauseModelDownload();
    if (mounted && request == _modelRequest) _showModel(value);
  }

  final _newWord = TextEditingController();
  int _wordInputRevision = 0;
  bool _working = false;
  String _status = '';
  _Panel? _panel;
  ReviewPreferences get policy => widget.settings.reviewPreferences;
  static const titles = {
    _Panel.policy: '確認ルール',
    _Panel.learning: '自分に合わせる',
    _Panel.ai: '端末内AI',
    _Panel.words: '登録ワード',
    _Panel.privacy: 'プライバシー',
  };
  @override
  void dispose() {
    _modelRequest++;
    _modelTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _newWord.dispose();
    super.dispose();
  }

  void _open(_Panel value) => setState(() {
    _panel = value;
    _status = '';
  });
  Future<void> _back() async {
    if (_working) return;
    if (_panel != null) {
      setState(() {
        _panel = null;
        _status = '';
      });
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_working && _panel == null,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: Scaffold(
      appBar: AppleBar(
        title: AppText(titles[_panel] ?? '設定'),
        leading: IconButton(
          onPressed: _working ? null : _back,
          tooltip: tr(context, '戻る'),
          icon: const Icon(CupertinoIcons.chevron_back),
        ),
      ),
      body: PostCheckBackdrop(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            children: [
              if (_working) const LinearProgressIndicator(),
              if (_status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: AppText(_status),
                ),
              ...switch (_panel) {
                null => _overview(),
                _Panel.policy => _policy(),
                _Panel.learning => _learning(),
                _Panel.ai => _ai(),
                _Panel.words => _wordEditor(),
                _Panel.privacy => _privacy(),
              },
            ],
          ),
        ),
      ),
    ),
  );
  Future<void> _language() async {
    final language = AppLanguageScope.maybeOf(context);
    if (language == null) return;
    final selected = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const AppText('言語'),
        actions: [
          for (final entry in const {
            'system': '端末に合わせる',
            ...AppStrings.languageNames,
          }.entries)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, entry.key),
              child: AppText(entry.value),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const AppText('キャンセル'),
        ),
      ),
    );
    if (selected == null) return;
    try {
      await language.select(selected == 'system' ? null : selected);
    } catch (_) {
      if (mounted) setState(() => _status = '設定を保存できませんでした');
    }
  }

  List<Widget> _overview() => [
    if (AppLanguageScope.maybeOf(context) case final language?)
      AppleSection(
        children: [
          AppleRow(
            title: '言語',
            icon: CupertinoIcons.globe,
            value: AppStrings.languageNames[language.code] ?? '端末に合わせる',
            onTap: _language,
          ),
        ],
      ),
    AppleSection(
      title: 'チェック',
      children: [
        AppleRow(
          title: '確認ルール',
          icon: CupertinoIcons.slider_horizontal_3,
          value: policy.disabledTargets.isEmpty
              ? 'すべてオン'
              : '${CheckTarget.values.length - policy.disabledTargets.length}/${CheckTarget.values.length}件オン',
          onTap: () => _open(_Panel.policy),
        ),
        AppleRow(
          title: '登録ワード',
          icon: CupertinoIcons.textformat_abc,
          value: '${widget.settings.privateWords.length}件',
          onTap: () => _open(_Panel.words),
        ),
        AppleRow(
          title: '自分に合わせる',
          icon: CupertinoIcons.sparkles,
          value: policy.learningEnabled ? 'オン' : 'オフ',
          onTap: () => _open(_Panel.learning),
        ),
        AppleRow(
          title: '端末内AI',
          icon: CupertinoIcons.device_phone_portrait,
          subtitle: widget.settings.aiEnabled && _showModelProgress
              ? '$_modelProgressText · $_modelCapacityText'
              : null,
          value: !widget.settings.aiEnabled
              ? 'オフ'
              : _model?.phase == ModelPreparationPhase.ready
              ? 'オン'
              : '準備中',
          onTap: () => _open(_Panel.ai),
        ),
      ],
    ),
    if (widget.cloudSettings != null)
      AppleSection(
        children: [
          AppleRow(
            title: 'クラウド保存・復元',
            icon: CupertinoIcons.cloud,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(builder: widget.cloudSettings!),
              );
              // A restore may replace the words, so refresh the count.
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
    AppleSection(
      title: 'このアプリについて',
      children: [
        AppleRow(
          title: 'プライバシー',
          icon: CupertinoIcons.lock_shield,
          onTap: () => _open(_Panel.privacy),
        ),
        AppleRow(
          title: 'ライセンス',
          icon: CupertinoIcons.doc_text,
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'PostCheck',
            applicationVersion: '0.1.0',
          ),
        ),
      ],
    ),
  ];
  List<Widget> _policy() => [
    AppleSection(
      title: '指摘する項目',
      footer:
          'オンの項目は、撮影中と撮影後の確認で指摘します。オフの項目も検出は行い、候補から外します。適用中の施設がオンにしている項目と、施設ルールに該当する候補は、オフでも指摘します。',
      children: [
        for (final target in CheckTarget.values)
          SwitchListTile.adaptive(
            title: AppText(target.label),
            value: policy.isEnabled(target),
            onChanged: _working
                ? null
                : (v) {
                    final disabled = {...policy.disabledTargets};
                    v ? disabled.remove(target) : disabled.add(target);
                    _savePolicy(policy.copyWith(disabledTargets: disabled));
                  },
          ),
      ],
    ),
  ];
  List<Widget> _learning() => [
    AppleSection(
      footer: '記憶を選んだ操作だけを集計します。写真や文章は記憶しません。',
      children: [
        SwitchListTile.adaptive(
          title: const AppText('選択から提案する'),
          value: policy.learningEnabled,
          onChanged: _working
              ? null
              : (v) => _savePolicy(policy.copyWith(learningEnabled: v)),
        ),
      ],
    ),
    AppleSection(
      footer: '同じ選択が3回以上で提案します。自動で修正・公開はしません。',
      children: [
        AppleRow(title: '記憶した傾向', value: '${policy.choices.length}種類'),
        AppleRow(
          title: '傾向をリセット',
          destructive: true,
          onTap: _working
              ? null
              : () async {
                  if (await _confirm(
                    '傾向をリセットしますか？',
                    '選択回数を消去します。登録ワードと指摘する項目の設定は残ります。',
                    action: 'リセット',
                  )) {
                    await _savePolicy(policy.copyWith(choices: {}));
                  }
                },
        ),
      ],
    ),
  ];
  String get _modelMessage =>
      !widget.settings.aiEnabled && _model?.phase != ModelPreparationPhase.ready
      ? 'AI補助はオフです。取得は停止しています。'
      : switch (_model?.phase) {
          ModelPreparationPhase.ready => '準備できました。端末内でAI補助を使えます。',
          ModelPreparationPhase.downloading => 'Wi-Fiで取得中です。基本チェックを使えます。',
          ModelPreparationPhase.verifying => '取得したモデルを確認しています。',
          ModelPreparationPhase.paused => '取得を停止しています。基本チェックを使えます。',
          ModelPreparationPhase.failed =>
            '準備できませんでした。Wi-Fiと空き容量を確認して再試行してください。',
          ModelPreparationPhase.unavailable =>
            'この端末ではAIの準備を利用できません。基本チェックを使えます。',
          _ => 'Wi-Fiで自動取得します。基本チェックはすぐに使えます。',
        };
  bool get _showModelProgress =>
      _model != null &&
      _model!.totalBytes > 0 &&
      _model!.phase != ModelPreparationPhase.unavailable &&
      _model!.phase != ModelPreparationPhase.ready;

  String get _modelProgressText {
    // Do not round an incomplete transfer up to 100%.
    final percent = (((_model?.progress ?? 0) * 1000).floor() / 10)
        .toStringAsFixed(1);
    return 'モデル取得 $percent%';
  }

  String get _modelCapacityText {
    final model = _model!;
    final received = model.receivedBytes.clamp(0, model.totalBytes);
    final receivedMB = (received / 1000000).toStringAsFixed(1);
    final totalMB = (model.totalBytes / 1000000).toStringAsFixed(1);
    return '取得済み $receivedMB MB / $totalMB MB';
  }

  List<Widget> _ai() => [
    AppleSection(
      footer: '写真と文章の文脈を端末内で確認します。オフでも文字・顔・登録ワードはチェックできます。',
      children: [
        SwitchListTile.adaptive(
          title: const AppText('AIで確認を補助'),
          value: widget.settings.aiEnabled,
          onChanged: _working
              ? null
              : (v) async {
                  try {
                    await widget.settings.setAIEnabled(v);
                    if (mounted) {
                      setState(() {});
                      await _refreshModel();
                    }
                  } catch (_) {
                    if (mounted) setState(() => _status = '設定を保存できませんでした');
                  }
                },
        ),
      ],
    ),
    AppleSection(
      title: '端末内AIの準備',
      footer: 'モデル約2.59GBをWi-Fiで自動取得します。準備中も基本チェックを使えます。再開時に取得し直す場合があります。',
      children: [
        AppleRow(title: 'Gemma 4 E2B', subtitle: _modelMessage),
        if (_showModelProgress)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  _modelProgressText,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                AppText(_modelCapacityText),
              ],
            ),
          ),
        if (widget.settings.aiEnabled && _model?.isActive == true) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: LinearProgressIndicator(
              value: _model?.phase == ModelPreparationPhase.downloading
                  ? _model?.progress
                  : null,
            ),
          ),
        ],
        if (widget.settings.aiEnabled &&
            const {
              ModelPreparationPhase.waiting,
              ModelPreparationPhase.downloading,
            }.contains(_model?.phase))
          AppleRow(title: '取得を止める', onTap: () => _modelAction(resume: false)),
        if (widget.settings.aiEnabled &&
            const {
              ModelPreparationPhase.paused,
              ModelPreparationPhase.failed,
            }.contains(_model?.phase))
          AppleRow(title: '取得を再開', onTap: () => _modelAction(resume: true)),
        AppleRow(
          title: '公式モデルと利用条件',
          icon: CupertinoIcons.arrow_up_right_square,
          onTap: () => launchUrl(
            Uri.parse(
              'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm',
            ),
            mode: LaunchMode.externalApplication,
          ),
        ),
      ],
    ),
    const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: AppText(
        'iPhoneでは、ホームに戻る・画面ロック後もWi-Fiで取得を続けます。アプリを上に払って強制終了すると取得が止まるため、もう一度開いてください。回線やOSの状態により待機する場合があります。',
      ),
    ),
  ];
  List<Widget> _wordEditor() {
    final words = widget.settings.privateWords;
    return [
      const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: AppText('企画名など、公開前に確認したい言葉を1件ずつ追加します。'),
      ),
      Row(
        children: [
          Expanded(
            // Stays enabled while saving so the keyboard remains open for
            // consecutive additions; _addWord ignores input while working.
            child: TextField(
              key: const ValueKey('private-word-input'),
              controller: _newWord,
              onChanged: (_) => _wordInputRevision++,
              textInputAction: TextInputAction.done,
              // Supplying onEditingComplete keeps focus after "done", so
              // several words can be entered without reopening the keyboard.
              onEditingComplete: _addWord,
              decoration: InputDecoration(
                hintText: tr(context, '例：Project Sakura'),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const ValueKey('private-word-add'),
            onPressed: _working ? null : _addWord,
            child: const AppText('追加'),
          ),
        ],
      ),
      const SizedBox(height: 24),
      AppleSection(
        title: '登録済みのワード',
        footer: '登録したワードはこの端末内に保存され、クラウドAIへは送信しません。',
        children: [
          if (words.isEmpty) const AppleRow(title: 'まだ登録されていません'),
          for (final word in words)
            AppleRow(
              key: ValueKey('private-word-$word'),
              title: word,
              // Registered words are user content and must stay literal.
              translateTitle: false,
              trailing: IconButton(
                tooltip: tr(context, '「$word」を削除'),
                onPressed: _working ? null : () => _deleteWord(word),
                icon: const Icon(
                  CupertinoIcons.minus_circle_fill,
                  color: CupertinoColors.systemRed,
                ),
              ),
            ),
        ],
      ),
    ];
  }

  // Word results go to a SnackBar rather than _status: the top of the list
  // scrolls out of view behind the keyboard, and replacing the previous
  // message makes consecutive operations distinguishable.
  void _wordFeedback(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: AppText(message)));
  }

  Future<void> _addWord() async {
    if (_working) return;
    final inputRevision = _wordInputRevision;
    final input = _newWord.text.trim();
    if (input.isEmpty) {
      _wordFeedback('追加するワードを入力してください');
      return;
    }
    final before = widget.settings.privateWords;
    if (before.contains(input)) {
      _wordFeedback('「$input」はすでに登録されています');
      return;
    }
    // Reuse saveWords so normalisation, limits and on-device storage stay
    // identical to every other path that writes the word list.
    final saved = await _saveWordList(
      [...before, input].join('\n'),
      failure: '追加できませんでした',
    );
    if (!saved || !mounted) return;
    final added = widget.settings.privateWords
        .where((w) => !before.contains(w))
        .toList();
    // A newer entry may have been typed while saving. Count edits rather than
    // comparing text so editing away and back also preserves the newer input.
    if (_wordInputRevision == inputRevision) _newWord.clear();
    _wordFeedback(switch (added.length) {
      0 => '「$input」はすでに登録されています',
      1 => '「${added.single}」を追加しました',
      // saveWords also splits on commas, so one entry can add several words.
      _ => '${added.length}件追加しました',
    });
  }

  Future<void> _deleteWord(String word) async {
    if (_working) return;
    final remaining = [...widget.settings.privateWords]..remove(word);
    final saved = await _saveWordList(
      remaining.join('\n'),
      failure: '削除できませんでした',
    );
    if (saved && mounted) _wordFeedback('「$word」を削除しました');
  }

  Future<bool> _saveWordList(String words, {required String failure}) async {
    setState(() => _working = true);
    try {
      await widget.settings.saveWords(words);
      return true;
    } on FormatException catch (e) {
      if (mounted) _wordFeedback(e.message);
    } catch (_) {
      if (mounted) _wordFeedback(failure);
    } finally {
      if (mounted) setState(() => _working = false);
    }
    return false;
  }

  List<Widget> _privacy() => [
    const AppleSection(
      title: '端末内で処理',
      children: [
        AppleRow(
          title: '写真・文章・OCR',
          subtitle: 'クラウドAIへ送信しません。下書きはメモリ上に保持し、再起動で消去。検査用の一時画像は処理後に削除します。',
        ),
        AppleRow(
          title: '現在地',
          subtitle: 'アプリ利用中のみ。位置履歴は保存しません。施設との距離は端末で照合します。',
        ),
      ],
    ),
    const AppleSection(
      title: '通信が発生する場面',
      children: [
        AppleRow(
          title: 'AIモデルの取得',
          subtitle: '初回起動後、公開モデル配布元から約2.59GBをWi-Fiで取得します。写真や投稿文は送信しません。',
        ),
        AppleRow(
          title: '地図と施設ルール',
          subtitle: '地図の表示領域などをGoogleへ送信し、施設ルールは公開APIから取得します。',
        ),
        AppleRow(
          title: '保存・共有',
          subtitle: '選んだ保存先やアプリに内容を渡します。元写真のクラウド同期は端末の設定に従います。',
        ),
        AppleRow(
          title: 'SDKの診断情報',
          subtitle:
              'ML Kitは入力と結果をGoogleへ送りませんが、利用・性能の診断情報を送る場合があります。通信ゼロを保証するものではありません。',
        ),
      ],
    ),
    TextButton(
      onPressed: () => launchUrl(
        Uri.parse('https://developers.google.com/ml-kit/terms'),
        mode: LaunchMode.externalApplication,
      ),
      child: const AppText('ML Kitの説明'),
    ),
  ];
  Future<bool> _confirm(
    String title,
    String message, {
    required String action,
  }) async =>
      await showCupertinoDialog<bool>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: AppText(title),
          content: AppText(message),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, false),
              child: const AppText('キャンセル'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: AppText(action),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _savePolicy(ReviewPreferences value) async {
    setState(() => _working = true);
    try {
      await widget.settings.saveReviewPreferences(value);
    } catch (_) {
      if (mounted) setState(() => _status = '設定を保存できませんでした');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}
