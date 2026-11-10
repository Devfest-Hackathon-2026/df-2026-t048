import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:postcheck_rules/postcheck_rules.dart';
import 'app_theme.dart';
import 'access_page.dart';
import 'publish_logo.dart';
import 'pull_refresh_tip.dart';
import 'soft_refresh.dart';
import 'session.dart';
import 'venue_editor.dart';
import 'venue_detail.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final fragment = Uri.base.fragment;
  final raw = fragment.startsWith('access=') ? fragment.substring(7) : null;
  if (raw != null) {
    await SystemNavigator.routeInformationUpdated(
      uri: Uri.base.replace(fragment: ''),
      replace: true,
    );
  }
  runApp(AdminApp(accessToken: raw));
}

/// Webではマウスドラッグが既定でスクロールにならないため、引き下げ更新が動かない。
class AdminScrollBehavior extends MaterialScrollBehavior {
  const AdminScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
  };
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key, this.accessToken});
  final String? accessToken;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PostCheck 管理',
    debugShowCheckedModeBanner: false,
    scrollBehavior: const AdminScrollBehavior(),
    theme: buildPostCheckTheme(),
    locale: const Locale('ja'),
    supportedLocales: const [Locale('ja'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    initialRoute: '/',
    home: accessToken == null
        ? const AdminHome()
        : Builder(
            builder: (context) => AccessLinkPage(
              rawToken: accessToken!,
              onDone: () => Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute<void>(builder: (_) => const AdminHome()),
                (_) => false,
              ),
            ),
          ),
  );
}

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  final session = AdminSession(
    demo: const bool.fromEnvironment('POSTCHECK_DEMO'),
  );
  final refreshKey = GlobalKey<SoftRefreshState>();
  List<ManagedVenue> venues = [];
  bool busy = false;
  bool showPullTip = false;
  String error = '', filter = 'all';

  Future<void> task(Future<void> Function() op) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await op();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is RulesApiException
              ? e.message
              : '接続・ログインを完了できませんでした。設定を確認してください。',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> refresh() async {
    final listed = await session.api.managed();
    // 運営画面には下書きを出さない（API側でも除外するが、表示でも二重に守る）。
    venues = session.operator
        ? listed.where((v) => v.status != 'draft').toList()
        : listed;
  }

  Future<void> pullRefresh() async {
    final tipWasShowing = showPullTip;
    try {
      await refresh();
      if (tipWasShowing) await markPullRefreshTipSeen();
      if (mounted) {
        setState(() {
          error = '';
          if (tipWasShowing) showPullTip = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is RulesApiException
              ? e.message
              : '接続・ログインを完了できませんでした。設定を確認してください。',
        );
      }
      rethrow;
    }
  }

  Future<void> _maybeShowPullTip() async {
    final seen = await hasSeenPullRefreshTip();
    if (!mounted || seen || session.actor == null) return;
    setState(() => showPullTip = true);
  }

  Future<void> login(bool op) => task(() async {
    await session.login(asOperator: op);
    await refresh();
    await _maybeShowPullTip();
  });

  Future<void> edit([ManagedVenue? v]) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => VenueEditor(api: session.api, venue: v),
      ),
    );
    if (mounted) await task(refresh);
  }

  Future<void> detail(ManagedVenue v) async {
    final canEdit = !session.operator && v.status != 'pending';
    final openEditor = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => VenueDetail(
          api: session.api,
          venue: v,
          operator: session.operator,
          canEdit: canEdit,
        ),
      ),
    );
    if (!mounted) return;
    if (openEditor == true) {
      await edit(v);
      return;
    }
    await task(refresh);
  }

  Future<void> _showApplicationModal(ManagedVenue v) async {
    // 下書き・差し戻しは申請者が直して再提出できる。
    final showEdit = !session.operator && v.status != 'pending';
    final actionLabel = showEdit
        ? '編集'
        : session.operator
        ? (v.status == 'published' ? '停止へ' : '承認へ')
        : '詳細';
    final publishLabel = v.suspended
        ? '公開停止'
        : v.published == null
        ? '未公開'
        : '公開中';
    final until = v.draft.validUntil;
    final untilLabel = () {
      if (until == null) return '未設定';
      final j = until.toUtc().add(const Duration(hours: 9));
      return '${j.year}年${j.month}月${j.day}日';
    }();
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
                  '申請の詳細',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _modalStacked('申請名', v.applicationTitle),
                        _modalRow(
                          '申請状態',
                          session.operator && v.status == 'pending'
                              ? '審査前'
                              : v.statusLabel,
                        ),
                        _modalRow('施設名', v.draft.name),
                        _modalRow('公開状態', publishLabel),
                        _modalRow('有効期限', untilLabel),
                        if (v.draft.event.isNotEmpty)
                          _modalRow('イベント', v.draft.event),
                        if (v.draft.address.isNotEmpty)
                          _modalRow('住所', v.draft.address),
                        if (v.draft.website.isNotEmpty)
                          _modalRow('公式サイト', v.draft.website),
                        if (v.draft.sourceText.isNotEmpty)
                          _modalRow('根拠', v.draft.sourceText),
                        if (v.draft.sourceUrl.isNotEmpty)
                          _modalRow('参考URL', v.draft.sourceUrl),
                        if (v.reason.isNotEmpty) _modalRow('理由', v.reason),
                        const SizedBox(height: 8),
                        const Divider(),
                        const SizedBox(height: 8),
                        if (v.draft.hasLegacyRuleDetails) ...[
                          _modalRow('撮影許可', v.draft.photography.label),
                          _modalRow('公開範囲', v.draft.publication.label),
                          _modalRow('商用利用', v.draft.commercial.label),
                        ],
                        _modalRow(
                          '必ず指摘する項目',
                          checkTargetsLabel(v.draft.checkTargets),
                        ),
                        _modalRow(
                          '配信範囲',
                          v.draft.visibility == 'public' ? '一般公開' : '組織内のみ',
                        ),
                        if (v.draft.words.isNotEmpty)
                          _modalRow('確認ワード', v.draft.words.join('、')),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (!session.operator)
                  TextButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => FacilityAccessPage(
                            api: session.api,
                            venueId: v.id,
                          ),
                        ),
                      );
                      if (mounted) await task(refresh);
                    },
                    icon: const Icon(Icons.verified_user_outlined),
                    label: const Text('施設の管理権限'),
                  ),
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          if (showEdit) {
                            edit(v);
                          } else {
                            detail(v);
                          }
                        },
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(actionLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modalRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
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

  /// 長い申請名向けに、ラベルの下へ値を置く。
  Widget _modalStacked(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: PostCheckPalette.secondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(value),
      ],
    ),
  );

  @override
  void dispose() {
    session.api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(session.operator ? 'PostCheck 運営' : 'PostCheck 管理'),
      actions: [
        if (session.demo)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('ローカルデモ・架空データ'),
          ),
        if (session.actor != null)
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => VerificationRequestsPage(
                          api: session.api,
                          operator: session.operator,
                        ),
                      ),
                    );
                    if (mounted) await task(refresh);
                  },
            child: Text(
              session.operator ? '責任者の確認' : '確認依頼',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        if (session.actor != null)
          TextButton(
            onPressed: busy
                ? null
                : () => task(() async {
                    await session.logout();
                    venues = [];
                    showPullTip = false;
                  }),
            child: const Text('ログアウト', style: TextStyle(color: Colors.white)),
          ),
      ],
    ),
    body: Column(
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error.isNotEmpty)
          MaterialBanner(
            content: Text(error),
            actions: [
              TextButton(
                onPressed: () => setState(() => error = ''),
                child: const Text('閉じる'),
              ),
            ],
          ),
        Expanded(child: session.actor != null ? _workspace() : _login()),
      ],
    ),
  );

  Widget _login() => Center(
    child: SingleChildScrollView(
      child: Container(
        width: 640,
        margin: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_city_outlined, size: 44),
                const SizedBox(height: 24),
                Text(
                  '施設のルールを届ける',
                  style: Theme.of(
                    context,
                  ).textTheme.headlineMedium?.copyWith(fontSize: 28),
                ),
                const SizedBox(height: 12),
                const Text('撮影・公開のルールを登録し、利用者へ案内します。'),
                const SizedBox(height: 32),
                if (session.demo) ...[
                  FilledButton(
                    onPressed: busy ? null : () => login(false),
                    child: const Text('組織担当者としてデモを開く'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: busy ? null : () => login(true),
                    child: const Text('運営担当者としてデモを開く'),
                  ),
                ] else
                  FilledButton.icon(
                    onPressed: busy ? null : () => login(false),
                    icon: const Icon(Icons.login),
                    label: const Text('Googleでログイン'),
                  ),
                const SizedBox(height: 24),
                const Text(
                  'ルールは、運営の承認後に公開されます。',
                  style: TextStyle(color: PostCheckPalette.secondary),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _workspace() {
    final effectiveFilter =
        session.operator &&
            filter != 'all' &&
            filter != 'published' &&
            filter != 'pending'
        ? 'all'
        : filter;
    final displayed = venues
        .where(
          (v) =>
              effectiveFilter == 'all' ||
              (effectiveFilter == 'published'
                  ? v.published != null && !v.suspended
                  : v.status == effectiveFilter),
        )
        .toList();
    return Row(
      children: [
        if (MediaQuery.sizeOf(context).width > 850)
          Container(
            width: 200,
            color: PostCheckPalette.soft,
            child: Column(
              children: [
                const SizedBox(height: 20),
                ListTile(
                  selected: true,
                  selectedTileColor: PostCheckPalette.blueSoft,
                  leading: const Icon(Icons.business_outlined),
                  title: const Text('申請一覧'),
                ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('下書きと公開版を分けて管理します。'),
                ),
              ],
            ),
          ),
        Expanded(
          child: SoftRefresh(
            key: refreshKey,
            onRefresh: pullRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: const EdgeInsets.all(28),
              children: [
                if (showPullTip) ...[
                  PullRefreshTipCard(
                    onDismiss: () => setState(() => showPullTip = false),
                    onTryRefresh: () async {
                      final indicator = refreshKey.currentState;
                      if (indicator != null) {
                        await indicator.show();
                      } else {
                        await pullRefresh();
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                ],
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 20,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '申請一覧',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: '公開のしくみ',
                          onPressed: _showPublishInfoSheet,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          icon: const Icon(
                            Icons.info_outline,
                            color: PostCheckPalette.primary,
                            size: 22,
                          ),
                        ),
                      ],
                    ),
                    if (!session.operator)
                      FilledButton.icon(
                        onPressed: busy ? null : () => edit(),
                        icon: const Icon(Icons.add),
                        label: const Text('新規申請'),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                _statusFilters(),
                const SizedBox(height: 24),
                if (displayed.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 48,
                      horizontal: 24,
                    ),
                    child: Center(
                      child: Text(
                        session.operator
                            ? 'この状態の申請はありません。'
                            : 'この状態の申請はありません。\n新規申請してください',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: PostCheckPalette.secondary,
                          height: 1.6,
                        ),
                      ),
                    ),
                  )
                else
                  _ApplicationList(
                    venues: displayed,
                    operator: session.operator,
                    onOpen: _showApplicationModal,
                  ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showPublishInfoSheet() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => GestureDetector(
        // isScrollControlled + Align だと上の透明領域がタップを吸うため、明示的に閉じる。
        onTap: () => Navigator.pop(ctx),
        behavior: HitTestBehavior.opaque,
        child: const _PublishInfoSheet(),
      ),
    );
  }

  Widget _statusFilters() {
    // 運営は審査・公開確認が主作業。下書き・差戻しは組織担当者側のタブに残す。
    final items = session.operator
        ? const <MapEntry<String, String>>[
            MapEntry('all', 'すべて'),
            MapEntry('published', '公開中'),
            MapEntry('pending', '審査前'),
          ]
        : const <MapEntry<String, String>>[
            MapEntry('all', 'すべて'),
            MapEntry('published', '公開中'),
            MapEntry('pending', '審査中'),
            MapEntry('returned', '差戻し'),
            MapEntry('draft', '下書き'),
          ];
    final selected = items.any((e) => e.key == filter) ? filter : 'all';
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _FilterPill(
              label: items[i].value,
              selected: selected == items[i].key,
              onTap: () => setState(() => filter = items[i].key),
            ),
          ),
        ],
      ],
    );
  }
}

class _ApplicationList extends StatelessWidget {
  const _ApplicationList({
    required this.venues,
    required this.operator,
    required this.onOpen,
  });

  final List<ManagedVenue> venues;
  final bool operator;
  final ValueChanged<ManagedVenue> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < venues.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _ApplicationListCard(
            venue: venues[i],
            operator: operator,
            onOpen: onOpen,
          ),
        ],
      ],
    );
  }
}

class _ApplicationListCard extends StatelessWidget {
  const _ApplicationListCard({
    required this.venue,
    required this.operator,
    required this.onOpen,
  });

  final ManagedVenue venue;
  final bool operator;
  final ValueChanged<ManagedVenue> onOpen;

  @override
  Widget build(BuildContext context) {
    final status = _listStatus(venue, operator: operator);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onOpen(venue),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
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
                        const Text(
                          '申請名',
                          style: TextStyle(
                            color: PostCheckPalette.secondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          venue.applicationTitle,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                            color: PostCheckPalette.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _ListStatusPill(status: status),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

({String label, Color color, Color background, IconData? icon}) _listStatus(
  ManagedVenue v, {
  required bool operator,
}) {
  if (v.suspended) {
    return (
      label: '公開停止',
      color: const Color(0xFFC62828),
      background: const Color(0xFFFFEBEE),
      icon: Icons.pause_circle_filled,
    );
  }
  return switch (v.status) {
    'returned' => (
      label: '差戻し',
      color: const Color(0xFFB45309),
      background: const Color(0xFFFFF4E5),
      icon: Icons.warning_amber_rounded,
    ),
    'pending' => (
      label: operator ? '審査前' : '審査中',
      color: const Color(0xFF0A6CF1),
      background: const Color(0xFFEFF6FF),
      icon: null,
    ),
    'published' => (
      label: operator ? '承認済み' : '公開済み',
      color: const Color(0xFF1B7F3A),
      background: const Color(0xFFE8F5E9),
      icon: null,
    ),
    _ => (
      label: '下書き',
      color: PostCheckPalette.secondary,
      background: const Color(0xFFF3F2F0),
      icon: null,
    ),
  };
}

class _ListStatusPill extends StatelessWidget {
  const _ListStatusPill({required this.status});

  final ({String label, Color color, Color background, IconData? icon}) status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: status.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status.icon != null) ...[
            Icon(status.icon, size: 15, color: status.color),
            const SizedBox(width: 6),
          ] else ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: status.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            status.label,
            style: TextStyle(
              color: status.color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const blue = PostCheckPalette.primary;
    return Material(
      color: selected ? blue : Colors.white,
      shape: const StadiumBorder(side: BorderSide(color: blue, width: 1.2)),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: SizedBox(
          height: 40,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : blue,
                fontWeight: FontWeight.w600,
                fontSize: 13,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PublishInfoSheet extends StatelessWidget {
  const _PublishInfoSheet();

  static const _bodySize = 15.0;
  static const _bodyHeight = 1.6;

  @override
  Widget build(BuildContext context) {
    final logoHeight = publishLogoHeightForText(
      fontSize: _bodySize,
      height: _bodyHeight,
    );
    return Align(
      alignment: Alignment.bottomCenter,
      child: GestureDetector(
        onTap: () {}, // シート本体のタップでは閉じない
        child: Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 12, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: PostCheckPalette.borderStrong,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '公開について',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '閉じる',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text.rich(
                      TextSpan(
                        style: const TextStyle(
                          color: PostCheckPalette.charcoal,
                          height: _bodyHeight,
                          fontSize: _bodySize,
                        ),
                        children: const [
                          TextSpan(text: '変更を申請しても、'),
                          TextSpan(
                            text: '承認までは',
                            style: TextStyle(
                              color: PostCheckPalette.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(text: '公開中のルールが維持されます。'),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: logoHeight * 0.12),
                  Center(child: PublishLogo(height: logoHeight)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
