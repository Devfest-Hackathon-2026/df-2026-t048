import '../l10n/app_localizations.dart';
import 'package:postcheck_rules/postcheck_rules.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'apple_components.dart';
import '../domain/input.dart';
import '../domain/models.dart';
import '../domain/preferences.dart';
import '../application/preferences_codec.dart';
import 'postcheck_controller.dart';
import 'photo_preview.dart';
import 'finding_review_list.dart';
import 'mask_editor.dart';
import 'settings_page.dart';
import 'app_theme.dart';
import 'venue_page.dart';
import 'nearby_controller.dart';
import 'nearby_card.dart';
import 'social_share_sheet.dart';
import 'story_share_page.dart';
import '../domain/social_share.dart';
import '../domain/location.dart';

enum _Page { start, draft, review, export }

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.settings,
    required this.library,
    required this.openCamera,
    this.cloudSettings,
    this.chooseVenue,
    this.nearby,
    this.startWithCamera = false,
  });
  final PostCheckController controller;
  final SettingsPort settings;
  final PhotoLibraryPort library;
  final Future<CapturedPhoto?> Function(BuildContext) openCamera;
  final NearbyController? nearby;
  final bool startWithCamera;
  final WidgetBuilder? cloudSettings;
  final Future<PublishedVenue?> Function(BuildContext)? chooseVenue;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  PublishedVenue? _draftCandidate;
  int _catalogRevision = -1;
  _Page _page = _Page.start;
  bool _picking = false, _captionTab = false;
  final _reviewListKey = GlobalKey<FindingReviewListState>();
  final _reviewScroll = ScrollController();
  final _caption = TextEditingController();
  PostCheckController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    widget.nearby?.addListener(_nearbyChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.nearby?.start();
      if (widget.startWithCamera) _input(camera: true);
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _nearbyChanged() {
    if (!mounted) return;
    final n = widget.nearby!;
    if (n.catalogLoaded && n.catalogRevision != _catalogRevision) {
      _catalogRevision = n.catalogRevision;
      c.reconcileVenue(n.rules.venues);
      if (_draftCandidate != null) {
        final id = _draftCandidate!.id;
        _draftCandidate = n.rules.venues.where((v) => v.id == id).firstOrNull;
      }
    }
    c.expireVenue();
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.nearby?.start();
    } else {
      widget.nearby?.stop();
    }
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    widget.nearby?.removeListener(_nearbyChanged);
    widget.nearby?.stop();
    WidgetsBinding.instance.removeObserver(this);
    _caption.dispose();
    _reviewScroll.dispose();
    super.dispose();
  }

  void _draft() {
    if (c.hasChanges && !c.commitEditsForDraft()) return;
    _caption.text = c.caption;
    setState(() => _page = _Page.draft);
  }

  bool get _hasDraft => c.photo != null || c.caption.isNotEmpty;

  void _startOver() {
    c.reset();
    _caption.clear();
  }

  /// Start-screen inputs used to silently reuse the previous photo or caption.
  /// Ask first; true means the caller may start a fresh post. Choosing to
  /// continue reopens the existing draft instead of mixing the two posts.
  Future<bool> _confirmFreshStart() async {
    if (!_hasDraft) return true;
    final fresh = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const AppText('作業中の下書きがあります'),
        content: const AppText('新しく始めると、今の写真と投稿文、修正内容を消去します。元の写真は削除しません。'),
        actions: [
          TextButton(
            key: const ValueKey('continue-draft-button'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const AppText('下書きを続ける'),
          ),
          TextButton(
            key: const ValueKey('start-fresh-button'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const AppText('新しく始める'),
          ),
        ],
      ),
    );
    if (!mounted || fresh == null) return false;
    if (!fresh) {
      _draft();
      return false;
    }
    _startOver();
    return true;
  }

  Future<void> _startInput({bool camera = false, bool sample = false}) async {
    if (await _confirmFreshStart()) {
      await _input(camera: camera, sample: sample);
    }
  }

  Future<void> _startTextOnly() async {
    if (await _confirmFreshStart()) _draft();
  }

  /// Sharing keeps the draft for retries (FR-OUT-03), so a new post is only
  /// started when the person asks for it here.
  Future<void> _newPost() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const AppText('新しい投稿を始めますか？'),
        content: const AppText('今の写真と投稿文、修正内容を消去します。保存・共有したものと元の写真は削除しません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const AppText('戻る'),
          ),
          TextButton(
            key: const ValueKey('confirm-new-post-button'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const AppText('新しく始める'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted || c.busy) return;
    _startOver();
    setState(() => _page = _Page.start);
  }

  Future<void> _input({bool camera = false, bool sample = false}) async {
    if (_picking || c.busy) return;
    setState(() => _picking = true);
    try {
      final venue = widget.nearby?.active;
      if (camera && venue?.policy.photography == RulePermission.forbidden) {
        final outside = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const AppText('この施設には撮影不可の案内があります'),
            content: AppText(
              '${venue!.policy.name}\n施設・対象エリアと原文を確認してください。適用を外す操作は、撮影許可の取得を意味しません。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const AppText('戻る'),
              ),
              TextButton(
                onPressed: () => Navigator.push(
                  ctx,
                  MaterialPageRoute<void>(
                    builder: (_) => VenueRulesPage(
                      venue: venue,
                      applied: true,
                      aiEnabled: widget.settings.aiEnabled,
                      preferences: widget.settings.reviewPreferences,
                    ),
                  ),
                ),
                child: const AppText('原文'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const AppText('この施設にいないためOFF'),
              ),
            ],
          ),
        );
        if (!mounted || outside != true) return;
        if (widget.nearby?.selected?.id == venue!.id) {
          widget.nearby?.toggle(false);
        }
      }
      if (!mounted) return;
      final capture = camera ? await widget.openCamera(context) : null;
      final bytes = camera
          ? capture?.bytes
          : sample
          ? await widget.library.sample()
          : await widget.library.pick();
      if (!mounted || bytes == null) return;
      var applied = capture?.venue;
      final fromLibrary = !camera || capture?.fromLibrary == true;
      final candidate = widget.nearby?.active;
      if (fromLibrary && candidate != null) {
        final yes = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const AppText('この写真にも施設ルールを使いますか？'),
            content: AppText(
              '${candidate.policy.name}\n撮影場所・対象エリア・日時を確認してください。現在地だけでは判断しません。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const AppText('使わない'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const AppText('この施設の写真です'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        applied = yes == true ? candidate : null;
      }
      await c.loadPhoto(bytes);
      if (!mounted) return;
      if (c.error.isNotEmpty) return;
      _draftCandidate = applied;
      c.selectVenue(applied);
      if (widget.nearby?.catalogLoaded == true) {
        c.reconcileVenue(widget.nearby!.rules.venues);
      }
      if (sample) c.setCaption('新しい企画の準備中。連絡先 taro@example.com');
      if (c.photo != null) _draft();
    } catch (_) {
      if (mounted) _message('写真を開けませんでした。権限や空き容量を確認してください。');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _message(String text) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: AppText(text)));
  Future<void> _chooseVenue() async {
    if (widget.chooseVenue == null || c.busy || c.preparingPreview) return;
    final chosen = await widget.chooseVenue!(context);
    if (chosen != null &&
        mounted &&
        (_page != _Page.start || widget.nearby == null)) {
      final n = widget.nearby;
      final verified = n == null ? chosen : n.active;
      if (verified == null) {
        _message('施設ルールが更新されたため、もう一度選んでください。');
        return;
      }
      _draftCandidate = verified;
      c.selectVenue(verified);
    }
  }

  Future<void> _venueDetails() async {
    final v = c.venue;
    if (v == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => _draftVenueRules(v)),
    );
  }

  Widget _draftVenueRules(PublishedVenue v) => ListenableBuilder(
    listenable: c,
    builder: (_, _) => VenueRulesPage(
      venue: c.venue?.id == v.id ? c.venue! : v,
      applied: c.venue?.id == v.id,
      aiEnabled: widget.settings.aiEnabled,
      preferences: widget.settings.reviewPreferences,
    ),
  );

  Widget _venueTile() {
    if (_page == _Page.start && widget.nearby != null) {
      return NearbyCard(
        controller: widget.nearby!,
        onChange: _chooseVenue,
        aiEnabled: widget.settings.aiEnabled,
        preferences: widget.settings.reviewPreferences,
      );
    }
    final v = c.venue ?? _draftCandidate;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            const Icon(CupertinoIcons.location, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: _chooseVenue,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        v?.policy.name ?? '場所のルールを追加',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      AppText(
                        c.venue == null ? '基本チェック' : 'この投稿に適用 · v${v!.version}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: PostCheckPalette.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (v != null) ...[
              Switch.adaptive(
                value: c.venue != null,
                onChanged: c.busy || c.preparingPreview
                    ? null
                    : (on) {
                        if (on && !v.policy.validAt(DateTime.now())) {
                          _message('ルールは期限切れです。施設を選び直してください。');
                          return;
                        }
                        c.selectVenue(on ? v : null);
                        if (widget.nearby?.selected?.id == v.id) {
                          widget.nearby?.toggle(on);
                        }
                      },
              ),
              IconButton(
                tooltip: tr(context, 'ルールと適用状況'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => _draftVenueRules(v)),
                ),
                icon: const Icon(CupertinoIcons.info_circle, size: 20),
              ),
            ] else
              const Icon(CupertinoIcons.chevron_forward, size: 15),
          ],
        ),
      ),
    );
  }

  Future<void> _settings() async {
    final before = encodeBackup(widget.settings);
    final modelBefore = widget.settings.modelName;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(
          settings: widget.settings,
          cloudSettings: widget.cloudSettings,
        ),
      ),
    );
    if (!mounted) return;
    // Settings can change the signed-in account. Do not retain an organization
    // rule across that boundary; require an authorized fetch again.
    if (c.venue?.policy.visibility == 'organization') {
      c.selectVenue(null);
      if (_page != _Page.start) _draft();
    }
    if (encodeBackup(widget.settings) != before ||
        widget.settings.modelName != modelBefore) {
      c.commitEditsForDraft();
      c.invalidateConfiguration();
      if (_page != _Page.start) _draft();
    }
    setState(() {});
  }

  Future<void> _check() async {
    FocusScope.of(context).unfocus();
    setState(() => _page = _Page.review);
    await c.runCheck(widget.settings.privateWords);
    if (mounted) {
      setState(() {
        _captionTab =
            c.photo == null ||
            (c.findings.isNotEmpty &&
                c.findings.every((f) => f.target is CaptionTarget));
      });
    }
  }

  Future<void> _mask(Finding? f) async {
    if (c.photo == null) return;
    final ownMask = f?.target is PhotoTarget ? c.maskFor(f!) : null;
    final region = await Navigator.push<PhotoMask>(
      context,
      MaterialPageRoute(
        builder: (_) => MaskEditor(
          photo: c.photo!,
          images: c.images,
          style: c.effectiveRedactionStyle,
          initial:
              ownMask ??
              (f == null
                  ? PhotoMask(
                      c.manualRegions.expand((m) => m.operations).toList(),
                    )
                  : null),
          baseMasks: [
            for (final finding in c.findings)
              if (finding != f &&
                  (ownMask == null ||
                      c.findings.indexOf(finding) < c.findings.indexOf(f!)) &&
                  finding.target is PhotoTarget &&
                  c.decisions[finding.id] == ReviewDecision.hide)
                c.maskFor(finding),
            if (f != null && ownMask == null) ...c.manualRegions,
          ],
          trailingMasks: ownMask == null
              ? const []
              : [
                  for (final finding in c.findings)
                    if (c.findings.indexOf(finding) > c.findings.indexOf(f!) &&
                        finding.target is PhotoTarget &&
                        c.decisions[finding.id] == ReviewDecision.hide)
                      c.maskFor(finding),
                  ...c.manualRegions,
                ],
          allowEmpty: f == null,
        ),
      ),
    );
    if (!mounted || region == null) return;
    if (f == null) {
      await c.replaceManualMask(region);
    } else {
      await c.adjustMask(f, region);
    }
  }

  Future<void> _editCaption() async {
    final text = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => _CaptionEditor(value: c.outputCaption)),
    );
    if (!mounted || text == null || text == c.outputCaption) return;
    await c.reviseCaption(text);
    await _check();
  }

  Widget _button(
    String text,
    VoidCallback? action, {
    IconData? icon,
    Key? key,
  }) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        key: key,
        onPressed: action,
        icon: Icon(icon ?? CupertinoIcons.chevron_forward),
        label: AppText(text),
      ),
    ),
  );
  Widget _note(String text, {IconData icon = Icons.info_outline}) => Container(
    margin: const EdgeInsets.symmetric(vertical: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: icon == Icons.error_outline
          ? const Color(0xFFFFF1F0)
          : PostCheckPalette.blueSoft,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: PostCheckPalette.border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Expanded(child: AppText(text)),
      ],
    ),
  );
  Widget _photo({bool overlays = false}) {
    if (c.photo == null) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * (overlays ? .32 : .42),
      ),
      child: Center(
        child: PhotoPreview(
          photo: c.photo!,
          preview: c.previewBytes,
          findings: overlays ? c.reviewFindings : const [],
          decisions: c.reviewDecisions,
          selectedId: c.selectedId,
          drawing: false,
          onSelect: (id) {
            c.select(id);
            setState(() => _captionTab = false);
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!mounted || _page != _Page.review) return;
              if (_reviewListKey.currentState == null &&
                  _reviewScroll.hasClients) {
                await _reviewScroll.animateTo(
                  0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                );
              }
              if (!mounted) return;
              _reviewListKey.currentState?.reveal(id);
            });
          },
          onDraw: (_) {},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _page == _Page.start,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: Scaffold(
      appBar: AppleBar(
        leading: _page == _Page.start
            ? null
            : IconButton(
                onPressed: _back,
                icon: const Icon(CupertinoIcons.chevron_back),
                tooltip: tr(context, '戻る'),
              ),
        title: AppText(switch (_page) {
          _Page.start => 'PostCheck',
          _Page.draft => '投稿を準備',
          _Page.review => '確認する',
          _Page.export => '仕上がり',
        }),
        actions: [
          if (_page == _Page.start)
            PopupMenuButton<String>(
              tooltip: tr(context, 'その他'),
              icon: const Icon(CupertinoIcons.ellipsis_circle),
              onSelected: (value) {
                if (value == 'sample') {
                  _startInput(sample: true);
                } else {
                  _about();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'sample', child: AppText('架空のサンプルで試す')),
                PopupMenuItem(value: 'about', child: AppText('PostCheckについて')),
              ],
            ),
          IconButton(
            onPressed: c.busy ? null : _settings,
            icon: const Icon(CupertinoIcons.gear_alt),
            tooltip: tr(context, '設定'),
          ),
        ],
      ),
      bottomNavigationBar: _dock(),
      body: PostCheckBackdrop(
        // Mobile text fields keep focus on outside taps by default, which left
        // people without an obvious way to close the keyboard. Buttons and the
        // text field still win the tap, so only empty areas dismiss it.
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: SafeArea(
            child: Column(
              children: [
                if (_page == _Page.review &&
                    !c.busy &&
                    c.report != null &&
                    c.photo != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _photo(overlays: true),
                  ),
                Expanded(
                  child: ListView(
                    key: ValueKey(_page),
                    controller: _page == _Page.review ? _reviewScroll : null,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                    children: [
                      if (c.error.isNotEmpty)
                        _note(c.error, icon: Icons.error_outline),
                      if (_picking) const LinearProgressIndicator(),
                      ...switch (_page) {
                        _Page.start => _start(),
                        _Page.draft => _draftWidgets(),
                        _Page.review => c.busy ? _checking() : _review(),
                        _Page.export => _export(),
                      },
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  void _back() {
    if (_page == _Page.export && c.busy) return;
    if (c.busy) {
      c.cancelCheck();
      _draft();
      return;
    }
    if (_page == _Page.export) {
      setState(() => _page = _Page.review);
    } else if (_page == _Page.review) {
      _draft();
    } else {
      setState(() => _page = _Page.start);
    }
  }

  void _about() => appleSheet<void>(
    context,
    ListView(
      padding: const EdgeInsets.all(24),
      children: [
        AppText('PostCheck', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 20),
        const AppText('写真や文章の写り込みに気づき、公開する内容を自分で選ぶためのアプリです。'),
        const SizedBox(height: 16),
        const AppText(
          '写真・投稿文の解析は端末内で行います。地図表示などの通信は発生します。検出には限界があり、公開の最終判断は利用者が行います。',
        ),
      ],
    ),
  );

  Widget? _dock() {
    if (_page == _Page.start || (_page == _Page.review && c.busy)) return null;
    final Widget action = switch (_page) {
      _Page.draft => _button(
        'チェックする',
        c.canCheck ? _check : null,
        icon: CupertinoIcons.sparkles,
        key: const ValueKey('check-button'),
      ),
      _Page.review when c.hasChanges => _button(
        '修正して再チェック',
        c.preparingPreview
            ? null
            : () => c.applyAndRecheck(widget.settings.privateWords),
        icon: CupertinoIcons.arrow_clockwise,
        key: const ValueKey('recheck-button'),
      ),
      _Page.review => _button(
        '仕上がりを見る',
        c.canExport ? () => setState(() => _page = _Page.export) : null,
        key: const ValueKey('preview-button'),
      ),
      _Page.export => _button(
        'SNS・その他に共有',
        c.canExport ? _share : null,
        icon: CupertinoIcons.share,
        key: const ValueKey('export-button'),
      ),
      _ => const SizedBox.shrink(),
    };
    // Scaffold keeps bottomNavigationBar behind the keyboard. Lift the dock so
    // the next action stays visible while the caption is being typed.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: GlassSurface(
        radius: 0,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_page == _Page.review && c.pendingCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: AppText(
                      'あと${c.pendingCount}件を確認',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                action,
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _start() => [
    const SizedBox(height: 28),
    GlassSurface(
      radius: 30,
      native: false,
      child: InkWell(
        key: const ValueKey('library-button'),
        borderRadius: BorderRadius.circular(30),
        onTap: _picking ? null : () => _startInput(),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 25),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: .50),
                const Color(0xFFDCEBFF).withValues(alpha: .25),
              ],
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF75B5FF), Color(0xFF276FD6)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3B7DDA).withValues(alpha: .22),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  CupertinoIcons.photo_on_rectangle,
                  size: 31,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              AppText('写真を選ぶ', style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
      ),
    ),
    const SizedBox(height: 12),
    GlassSurface(
      radius: 28,
      native: false,
      child: SizedBox(
        width: double.infinity,
        child: TextButton.icon(
          onPressed: _picking ? null : () => _startInput(camera: true),
          icon: const Icon(CupertinoIcons.camera),
          label: const AppText('カメラで撮影'),
        ),
      ),
    ),
    TextButton(
      key: const ValueKey('text-only-button'),
      onPressed: _picking ? null : _startTextOnly,
      child: const AppText('文章だけチェックする'),
    ),
    const SizedBox(height: 20),
    if (widget.chooseVenue != null) _venueTile(),
    if (c.photo != null || c.caption.isNotEmpty)
      TextButton(onPressed: _draft, child: const AppText('作業中の下書きに戻る')),
  ];
  List<Widget> _draftWidgets() => [
    const SizedBox(height: 12),
    _photo(),
    Wrap(
      spacing: 8,
      children: [
        TextButton.icon(
          onPressed: () => _input(),
          icon: const Icon(CupertinoIcons.photo),
          label: AppText(c.photo == null ? '写真を追加' : '写真を変更'),
        ),
        TextButton.icon(
          onPressed: () => _input(camera: true),
          icon: const Icon(CupertinoIcons.camera),
          label: const AppText('撮影'),
        ),
        if (c.photo != null)
          TextButton(onPressed: c.removePhoto, child: const AppText('写真を外す')),
      ],
    ),
    if (widget.chooseVenue != null) _venueTile(),
    const SizedBox(height: 20),
    const AppText('投稿文（任意）'),
    const SizedBox(height: 8),
    TextField(
      key: const ValueKey('caption-input'),
      controller: _caption,
      minLines: 3,
      maxLines: 8,
      enabled: !c.busy,
      onChanged: c.setCaption,
      decoration: InputDecoration(
        hintText: tr(context, '写真に添える文章を入力…'),
        // There is no save button for the caption; say so to avoid people
        // looking for one and finding only 「下書きを破棄」.
        helperText: tr(context, '入力した文章は自動で保持されます。'),
      ),
    ),
    const SizedBox(height: 12),
    if (c.busy) const LinearProgressIndicator(),
    if (c.canRestoreOriginal)
      TextButton(
        onPressed: () async {
          await c.restoreOriginal();
          _draft();
        },
        child: const AppText('修正前の下書きに戻す'),
      ),
    TextButton(
      onPressed: () async {
        final yes = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const AppText('下書きを破棄しますか？'),
            content: const AppText('この画面の写真と文章、修正内容を消去します。元の写真は削除しません。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const AppText('戻る'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const AppText('破棄'),
              ),
            ],
          ),
        );
        if (yes == true && mounted) {
          c.reset();
          setState(() => _page = _Page.start);
        }
      },
      child: const AppText('下書きを破棄'),
    ),
  ];
  List<Widget> _checking() => [
    _photo(),
    const SizedBox(height: 24),
    const LinearProgressIndicator(),
    const SizedBox(height: 16),
    AppText(
      c.progress,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    ),
    if (c.canFinishCheck)
      OutlinedButton(
        onPressed: c.finishWithCurrentResults,
        child: const AppText('現在の結果で確認する'),
      ),
    TextButton(
      onPressed: () {
        c.cancelCheck();
        _draft();
      },
      child: const AppText('キャンセル'),
    ),
  ];
  List<Widget> _review() {
    if (c.report == null) {
      return [
        const AppText('チェックを完了できませんでした。'),
        _button('もう一度チェック', c.canCheck ? _check : null),
        TextButton(onPressed: _draft, child: const AppText('編集に戻る')),
      ];
    }
    final rows = c.reviewFindings;
    final filtered = rows
        .where(
          (f) => _captionTab
              ? f.target is CaptionTarget
              : f.target is! CaptionTarget,
        )
        .toList();
    return [
      const SizedBox(height: 12),
      CupertinoSlidingSegmentedControl<bool>(
        groupValue: _captionTab,
        children: {
          false: Padding(
            padding: const EdgeInsets.all(10),
            child: AppText(
              '写真 ${rows.where((f) => f.target is! CaptionTarget).length}',
            ),
          ),
          true: Padding(
            padding: const EdgeInsets.all(10),
            child: AppText(
              '文章 ${rows.where((f) => f.target is CaptionTarget).length}',
            ),
          ),
        },
        onValueChanged: (v) {
          if (v != null) setState(() => _captionTab = v);
        },
      ),
      if (_captionTab)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            c.outputCaption.isEmpty
                ? tr(context, '投稿文はありません')
                : c.outputCaption,
          ),
        ),
      if (c.photo != null && !_captionTab) ...[
        const SizedBox(height: 12),
        CupertinoSlidingSegmentedControl<RedactionStyle>(
          groupValue: c.redactionStyle,
          children: const {
            RedactionStyle.blur: Padding(
              padding: EdgeInsets.all(10),
              child: AppText('ぼかし'),
            ),
            RedactionStyle.black: Padding(
              padding: EdgeInsets.all(10),
              child: AppText('黒塗り'),
            ),
          },
          onValueChanged: (value) {
            if (value != null) c.setRedactionStyle(value);
          },
        ),
        if (c.redactionStyle == RedactionStyle.blur && c.masks.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: AppText(
              'ぼかしても判別できる場合があります。仕上がりを確認してください。',
              style: TextStyle(fontSize: 12, color: PostCheckPalette.secondary),
            ),
          ),
      ],
      if (filtered.isNotEmpty) ...[
        const SizedBox(height: 12),
        if (!_captionTab) ...[
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (final choice in [ReviewDecision.hide, ReviewDecision.keep])
                OutlinedButton.icon(
                  key: ValueKey('photo-all-${choice.name}'),
                  onPressed: c.busy || c.preparingPreview
                      ? null
                      : () => c.decideAllPhotos(choice),
                  icon: Icon(
                    choice == ReviewDecision.hide
                        ? CupertinoIcons.eye_slash
                        : CupertinoIcons.eye,
                  ),
                  label: AppText(
                    choice == ReviewDecision.hide ? 'すべて隠す' : 'すべて残す',
                  ),
                ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6, bottom: 10),
            child: AppText(
              '写真の候補をまとめて選択します。後から1件ずつ変更できます。',
              style: TextStyle(fontSize: 12, color: PostCheckPalette.secondary),
            ),
          ),
          if (filtered.any((f) => f.target is WholePhotoTarget))
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: AppText('範囲のない候補は、個別に範囲を指定して隠してください。'),
            ),
        ],
        FindingReviewList(
          key: _reviewListKey,
          controller: c,
          findings: filtered,
          onMask: (finding) => _mask(finding),
          onVenueDetails: _venueDetails,
        ),
      ] else
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: AppText(
            rows.isEmpty ? '今回のチェックで確認候補は見つかりませんでした。' : 'このタブに確認候補はありません。',
          ),
        ),
      if (c.findings.any(
        (f) =>
            c.policy.suggestionFor(f) != null &&
            (c.decisions[f.id] ?? ReviewDecision.pending) ==
                ReviewDecision.pending,
      ))
        OutlinedButton.icon(
          onPressed: c.preparingPreview ? null : c.applySuggestions,
          icon: const Icon(Icons.auto_fix_high_outlined),
          label: const AppText('いつもの選択を適用'),
        ),
      Wrap(
        spacing: 8,
        children: [
          if (c.photo != null)
            TextButton.icon(
              onPressed: c.preparingPreview ? null : () => _mask(null),
              icon: const Icon(CupertinoIcons.crop),
              label: const AppText('範囲を隠す'),
            ),
          TextButton.icon(
            onPressed: c.preparingPreview ? null : _editCaption,
            icon: const Icon(CupertinoIcons.pencil),
            label: const AppText('文章を編集'),
          ),
          if (c.manualRegions.isNotEmpty)
            TextButton(
              onPressed: c.undoManualRegion,
              child: const AppText('手動マスクを戻す'),
            ),
          if (c.hasChanges)
            TextButton(
              onPressed: c.resetEdits,
              child: const AppText('今回の選択を戻す'),
            ),
        ],
      ),
      if (c.preparingPreview) const LinearProgressIndicator(),
      AppleRow(
        title:
            c.report!.aiStatus.contains('できません') ||
                c.report!.aiStatus.contains('ませんでした') ||
                c.report!.aiStatus.startsWith('前のAI処理')
            ? 'AIの確認は未完了'
            : c.report!.notes.isNotEmpty
            ? '確認事項があります'
            : c.report!.aiStatus.startsWith('Gemmaが')
            ? '端末内チェック済み'
            : '基本チェックで確認',
        subtitle: 'チェックの詳細',
        icon: CupertinoIcons.info_circle,
        onTap: () => appleSheet<void>(
          context,
          ListView(
            padding: const EdgeInsets.all(24),
            children: [
              AppText('チェックの詳細', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              for (final note in c.report!.notes) _note(note),
              AppText(c.report!.aiStatus),
              const SizedBox(height: 16),
              const AppText('検出できない写り込みや文脈もあります。最後に写真全体を確認してください。'),
              TextButton(
                onPressed: c.canCheck
                    ? () {
                        Navigator.pop(context);
                        c.applyAndRecheck(widget.settings.privateWords);
                      }
                    : null,
                child: const AppText('もう一度確認する'),
              ),
            ],
          ),
        ),
      ),
      if (c.rechecked)
        const AppText(
          '修正後の内容で確認しました',
          style: TextStyle(fontSize: 13, color: PostCheckPalette.secondary),
        ),
    ];
  }

  Future<void> _share() async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box?.localToGlobal(Offset.zero);
    if (c.socialExporter == null) {
      await c.share(x: origin?.dx, y: origin?.dy);
      return;
    }
    final destination = await chooseShareDestination(
      context,
      hasPhoto: c.photo != null,
      hasCaption: c.caption.trim().isNotEmpty,
    );
    if (!mounted || destination == null || !c.canExport) return;
    if (destination == ShareDestination.instagramStory) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => StorySharePage(controller: c)),
      );
      return;
    }
    String? officialId;
    if (destination == ShareDestination.lineOfficial) {
      officialId = await chooseOfficialLine(context);
      if (!mounted || officialId == null) return;
    }
    final result = await c.shareTo(
      destination,
      officialLineId: officialId,
      x: origin?.dx,
      y: origin?.dy,
    );
    if (mounted && result != null) _message(shareHandoffMessage(result));
  }

  List<Widget> _export() => [
    _photo(),
    const SizedBox(height: 16),
    if (c.caption.isNotEmpty) SelectableText(c.caption),
    if (c.appliedEdits > 0) _note('${c.appliedEdits}か所を修正しました'),
    if (c.busy) const LinearProgressIndicator(),
    if (c.error.isNotEmpty) ...[
      AppText(c.error),
      if (c.photoPermissionDenied)
        TextButton(
          onPressed: () async {
            try {
              await const MethodChannel(
                'postcheck/privacy',
              ).invokeMethod<void>('openSettings');
            } catch (_) {
              if (mounted) _message('iPhoneの設定から写真への追加を許可してください。');
            }
          },
          child: const AppText('写真のアクセス設定を開く'),
        ),
      TextButton(onPressed: c.retryExport, child: const AppText('もう一度保存・共有する')),
    ],
    if (c.photo != null && c.saver != null)
      _button(
        '写真に保存',
        c.canExport
            ? () async {
                if (await c.savePhoto() && mounted) _message('写真に保存しました。');
              }
            : null,
        icon: Icons.save_alt,
        key: const ValueKey('save-photo-button'),
      ),
    if (c.photo != null && c.fileSaver != null) ...[
      const SizedBox(height: 10),
      _button(
        'ファイルに保存',
        c.canExport
            ? () async {
                if (await c.saveFile() && mounted) _message('ファイルに保存しました。');
              }
            : null,
        icon: CupertinoIcons.folder,
        key: const ValueKey('save-file-button'),
      ),
    ],
    if (c.caption.isNotEmpty)
      TextButton.icon(
        onPressed: c.busy
            ? null
            : () async {
                await Clipboard.setData(ClipboardData(text: c.caption));
                if (mounted) _message('投稿文をコピーしました。');
              },
        icon: const Icon(CupertinoIcons.doc_on_doc),
        label: const AppText('投稿文をコピー'),
      ),
    const SizedBox(height: 12),
    const AppText(
      '共有先は次の画面で選べます。投稿は共有先のアプリで行います。',
      style: TextStyle(fontSize: 12, color: PostCheckPalette.secondary),
    ),
    TextButton(
      onPressed: c.busy ? null : () => setState(() => _page = _Page.review),
      child: const AppText('確認・修正に戻る'),
    ),
    TextButton.icon(
      key: const ValueKey('new-post-button'),
      onPressed: c.busy ? null : _newPost,
      icon: const Icon(CupertinoIcons.plus),
      label: const AppText('新しい投稿'),
    ),
  ];
}

class _CaptionEditor extends StatefulWidget {
  const _CaptionEditor({required this.value});
  final String value;
  @override
  State<_CaptionEditor> createState() => _CaptionEditorState();
}

class _CaptionEditorState extends State<_CaptionEditor> {
  late final _text = TextEditingController(text: widget.value);
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const AppleBar(title: AppText('文章を編集')),
    body: PostCheckBackdrop(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _text,
              minLines: 8,
              maxLines: 16,
              decoration: InputDecoration(labelText: tr(context, '投稿文')),
            ),
            TextButton(
              onPressed: () => _text.text = widget.value,
              child: const AppText('編集前に戻す'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, _text.text),
              child: const AppText('反映して再チェック'),
            ),
          ],
        ),
      ),
    ),
  );
}
