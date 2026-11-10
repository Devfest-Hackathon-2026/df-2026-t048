import '../l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'apple_components.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:postcheck_rules/postcheck_rules.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_theme.dart';
import '../domain/location.dart';
import '../application/map_follow.dart';
import '../application/nearby_rules.dart';
import 'nearby_controller.dart';
import 'location_permission.dart';
import 'venue_rule_summary.dart';
import 'venue_check_status.dart';
import '../domain/preferences.dart';

class VenuePage extends StatefulWidget {
  const VenuePage({
    super.key,
    required this.repository,
    this.mapEnabled = false,
    this.nearby,
  });
  final bool mapEnabled;
  final NearbyController? nearby;
  final VenueRepositoryPort repository;
  @override
  State<VenuePage> createState() => _VenuePageState();
}

class _VenuePageState extends State<VenuePage> {
  List<PublishedVenue> venues = [];
  bool loading = true;
  String error = '';
  GoogleMapController? map;
  BitmapDescriptor? _locationDot;
  Future<void> _createLocationDot() async {
    // Fixed screen-size dot, separate from the metre-based accuracy circle.
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const center = ui.Offset(48, 48);
    canvas.drawCircle(center, 44, ui.Paint()..color = const Color(0x3348B5FF));
    canvas.drawCircle(center, 24, ui.Paint()..color = Colors.white);
    canvas.drawCircle(center, 19, ui.Paint()..color = const Color(0xFF168BFF));
    final picture = recorder.endRecording();
    final image = await picture.toImage(96, 96);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (!mounted || bytes == null) return;
    setState(
      () => _locationDot = BitmapDescriptor.bytes(
        bytes.buffer.asUint8List(),
        width: 40,
        height: 40,
      ),
    );
  }

  final _follow = MapFollow();
  LocationFix? get _position => widget.nearby?.currentLocation;
  void _locationChanged() {
    if (!mounted) return;
    setState(() {});
    unawaited(_recenter());
  }

  Future<void> _recenter() async {
    final controller = map;
    if (!mounted || controller == null) return;
    final fix = _follow.update(_position, DateTime.now());
    if (fix == null) return;
    try {
      await controller.animateCamera(
        CameraUpdate.newLatLng(LatLng(fix.latitude, fix.longitude)),
      );
    } catch (_) {
      // The map can be disposed while a native animation is finishing.
    }
  }

  @override
  void initState() {
    super.initState();
    widget.nearby?.addListener(_locationChanged);
    unawaited(_createLocationDot());
    load();
  }

  @override
  void dispose() {
    widget.nearby?.removeListener(_locationChanged);
    map?.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = '';
      venues = [];
    });
    try {
      final result = await widget.repository.list();
      if (mounted) setState(() => venues = result);
    } catch (_) {
      if (mounted) {
        setState(() => error = '施設ルールを取得できませんでした。再試行するか、戻って基本チェックを利用できます。');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> locate() async {
    final n = widget.nearby;
    if (n == null) return;
    _follow.resume();
    setState(() {});
    await useDeviceLocation(context, n);
    if (mounted) await _recenter();
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: AppText(text)));
    }
  }

  Future<void> select(PublishedVenue venue) async {
    final applied = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => VenueRulesPage(venue: venue, canApply: true),
      ),
    );
    if (applied == true && mounted) Navigator.pop(context, venue);
  }

  Future<void> scan() async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const VenueScanner()),
    );
    if (id == null || !mounted) return;
    final found = venues.where((v) => v.id == id).firstOrNull;
    if (found == null) {
      message('この施設の公開ルールは取得できません。未登録・非公開・公開停止の可能性があります。');
      return;
    }
    await select(found);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.mapEnabled;
    final position = _position;
    final simulated = widget.nearby?.simulated == true;
    final now = widget.nearby?.rules.now() ?? DateTime.now();
    final automaticVenues = venues
        .where((v) => v.policy.visibility == 'public' && v.policy.validAt(now))
        .toList();
    final activeId = widget.nearby?.active?.id;
    final withinRange =
        position != null &&
        automaticVenues.any(
          (v) =>
              NearbyRules.distance(position, v) <=
              NearbyRules.automaticRadiusMeters,
        );
    final panelHeight = (MediaQuery.sizeOf(context).height * .32).clamp(
      200.0,
      300.0,
    );
    Widget list() => ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      children: [
        if (error.isNotEmpty)
          Padding(padding: const EdgeInsets.all(12), child: AppText(error)),
        for (final v in venues)
          AppleRow(
            title: v.policy.name,
            translateTitle: false,
            translateSubtitle: v.demo,
            subtitle: v.demo ? 'デモ・架空の施設' : v.policy.event,
            icon: CupertinoIcons.map_pin_ellipse,
            onTap: () => select(v),
          ),
        if (!loading && venues.isEmpty && error.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: AppText('登録施設はありません。基本チェックは使えます。'),
          ),
      ],
    );
    return Scaffold(
      extendBodyBehindAppBar: enabled,
      appBar: AppleBar(
        title: const AppText('場所を選ぶ'),
        actions: [
          IconButton(
            onPressed: scan,
            tooltip: tr(context, '施設のQRを読み取る'),
            icon: const Icon(CupertinoIcons.qrcode_viewfinder),
          ),
          IconButton(
            onPressed: loading ? null : load,
            tooltip: tr(context, '再読込'),
            icon: const Icon(CupertinoIcons.arrow_clockwise),
          ),
        ],
      ),
      body: enabled
          ? Stack(
              children: [
                Positioned.fill(
                  child: Listener(
                    onPointerMove: (event) {
                      if (event.delta.distance > 2 && _follow.following) {
                        setState(_follow.pause);
                      }
                    },
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(
                          position?.latitude ??
                              venues.firstOrNull?.policy.latitude ??
                              35.681236,
                          position?.longitude ??
                              venues.firstOrNull?.policy.longitude ??
                              139.767125,
                        ),
                        // Show the 500 m coverage around the current location.
                        zoom: 14,
                      ),
                      onMapCreated: (c) {
                        map = c;
                        unawaited(_recenter());
                      },
                      padding: EdgeInsets.only(
                        top: MediaQuery.paddingOf(context).top + 168,
                        bottom: panelHeight + 12,
                      ),
                      myLocationEnabled: false,
                      myLocationButtonEnabled: false,
                      circles: {
                        for (final v in automaticVenues)
                          Circle(
                            circleId: CircleId('venue-range-${v.id}'),
                            center: LatLng(
                              v.policy.latitude,
                              v.policy.longitude,
                            ),
                            radius: NearbyRules.automaticRadiusMeters,
                            fillColor: v.id == activeId
                                ? const Color(0x3348B5FF)
                                : const Color(0x1F48B5FF),
                            strokeColor: v.id == activeId
                                ? const Color(0xFF249DDB)
                                : const Color(0x9948B5FF),
                            strokeWidth: v.id == activeId ? 3 : 2,
                            zIndex: v.id == activeId ? 1 : 0,
                          ),
                        if (position != null)
                          Circle(
                            circleId: const CircleId('location-accuracy'),
                            center: LatLng(
                              position.latitude,
                              position.longitude,
                            ),
                            radius: position.accuracy,
                            fillColor: const Color(0x1948B5FF),
                            strokeColor: const Color(0x5548B5FF),
                            strokeWidth: 1,
                            zIndex: 2,
                          ),
                      },
                      markers: {
                        if (position != null && _locationDot != null)
                          Marker(
                            markerId: const MarkerId('current-location'),
                            position: LatLng(
                              position.latitude,
                              position.longitude,
                            ),
                            icon: _locationDot!,
                            anchor: const Offset(.5, .5),
                            flat: true,
                            infoWindow: InfoWindow(
                              title: tr(
                                context,
                                simulated ? 'デモの架空位置' : '現在地（推定）',
                              ),
                              snippet: tr(
                                context,
                                '精度の目安：約${position.accuracy.round()}m',
                              ),
                            ),
                            zIndexInt: 1,
                          ),
                        for (final v in venues)
                          Marker(
                            markerId: MarkerId(v.id),
                            position: LatLng(
                              v.policy.latitude,
                              v.policy.longitude,
                            ),
                            infoWindow: InfoWindow(
                              title: v.policy.name,
                              snippet: automaticVenues.contains(v)
                                  ? tr(context, '自動選択の範囲：半径500m')
                                  : null,
                            ),
                            onTap: () => select(v),
                          ),
                      },
                    ),
                  ),
                ),
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 68,
                  left: 16,
                  right: 76,
                  child: GlassSurface(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppText(
                            position == null
                                ? '現在地を未取得'
                                : '${simulated
                                      ? 'デモの位置'
                                      : _follow.following
                                      ? '現在地に追従中'
                                      : '地図を閲覧中'} · 約${position.accuracy.round()}m${position.accuracy > 50 ? '（低精度）' : ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                          if (position != null) ...[
                            const SizedBox(height: 4),
                            AppText(
                              !position.usableAt(now)
                                  ? '精度不足のため範囲判定を保留中'
                                  : withinRange
                                  ? '自動選択の範囲内（推定）'
                                  : '自動選択の範囲外（推定）',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 64,
                  right: 16,
                  child: AppleIconButton(
                    icon: _follow.following
                        ? CupertinoIcons.location_fill
                        : CupertinoIcons.location,
                    label: '現在地に戻る・追従する',
                    onPressed: widget.nearby == null ? null : locate,
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    height: panelHeight,
                    child: Material(
                      color: PostCheckPalette.surface,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          const SizedBox(height: 16),
                          AppText(
                            '登録施設',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  margin: const EdgeInsets.only(
                                    top: 2,
                                    right: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0x3348B5FF),
                                    border: Border.all(
                                      color: const Color(0xFF249DDB),
                                    ),
                                  ),
                                ),
                                const Expanded(
                                  child: AppText(
                                    '水色の円：自動選択の範囲（半径500m）',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (loading) const LinearProgressIndicator(),
                          Expanded(child: list()),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            )
          : SafeArea(
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: AppText('地図は未接続です。登録施設の一覧から選べます。'),
                  ),
                  if (loading) const LinearProgressIndicator(),
                  Expanded(child: list()),
                ],
              ),
            ),
    );
  }
}

class VenueRulesPage extends StatelessWidget {
  const VenueRulesPage({
    super.key,
    required this.venue,
    this.canApply = false,
    this.applied,
    this.aiEnabled,
    this.preferences = const ReviewPreferences(),
  });
  final PublishedVenue venue;
  final bool canApply;
  final bool? applied, aiEnabled;
  final ReviewPreferences preferences;
  @override
  Widget build(BuildContext context) {
    final p = venue.policy;
    final valid = p.validAt(DateTime.now());
    return Scaffold(
      appBar: const AppleBar(title: AppText('施設のルール')),
      bottomNavigationBar: !canApply
          ? null
          : GlassSurface(
              radius: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: FilledButton(
                    onPressed: valid
                        ? () => Navigator.pop(context, true)
                        : null,
                    child: const AppText('この施設のルールを使う'),
                  ),
                ),
              ),
            ),
      body: PostCheckBackdrop(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(p.name, style: Theme.of(context).textTheme.headlineMedium),
              if (p.event.isNotEmpty)
                Text(p.event, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              AppText(
                venue.demo ? 'デモ・架空のルール' : '公開された施設ルール',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              if (applied != null)
                VenueCheckStatus(
                  venue: venue,
                  applied: applied!,
                  aiEnabled: aiEnabled,
                  preferences: preferences,
                ),
              VenueRuleSummary(policy: p),
              if (!valid)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: AppText(
                    '期限切れ · 施設の案内を確認してください',
                    style: TextStyle(color: CupertinoColors.systemRed),
                  ),
                ),
              if (p.releaseAt != null)
                AppleSection(
                  children: [
                    AppleRow(
                      title: '名称の公開解禁',
                      subtitle:
                          '${p.releaseAt!.toUtc().add(const Duration(hours: 9)).toString().substring(0, 16)}（日本時間）',
                    ),
                  ],
                ),
              if (p.hasLegacyRuleDetails)
                AppleSection(
                  title: '根拠',
                  footer:
                      '更新 ${venue.updatedAt.toLocal().toString().substring(0, 16)} · v${venue.version}',
                  children: [
                    ExpansionTile(
                      title: const AppText('ルールの原文'),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [Text(p.sourceText)],
                    ),
                    if (p.words.isNotEmpty)
                      ExpansionTile(
                        title: const AppText('確認するワード'),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          16,
                        ),
                        children: [Text(p.words.join('、'))],
                      ),
                    if (p.sourceUrl.isNotEmpty)
                      AppleRow(
                        title: venue.demo ? '架空の出典' : '出典を開く',
                        icon: CupertinoIcons.arrow_up_right_square,
                        onTap: venue.demo
                            ? null
                            : () async {
                                final u = Uri.tryParse(p.sourceUrl);
                                if (u != null &&
                                    u.scheme == 'https' &&
                                    u.userInfo.isEmpty) {
                                  await launchUrl(
                                    u,
                                    mode: LaunchMode.externalApplication,
                                  );
                                }
                              },
                      ),
                  ],
                ),
              const AppText(
                '未確認は許可を意味しません。現場の掲示と対象エリアも確認してください。',
                style: TextStyle(
                  fontSize: 13,
                  color: PostCheckPalette.secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VenueScanner extends StatefulWidget {
  const VenueScanner({super.key});
  @override
  State<VenueScanner> createState() => _VenueScannerState();
}

class _VenueScannerState extends State<VenueScanner> {
  bool handled = false;
  String error = '';
  final scanner = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  @override
  void dispose() {
    scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const AppleBar(title: AppText('QRを読み取る')),
    body: Stack(
      children: [
        MobileScanner(
          controller: scanner,
          onDetect: (capture) {
            if (handled) return;
            for (final code in capture.barcodes) {
              final id = venueIdFromQR(code.rawValue ?? '');
              if (id != null) {
                handled = true;
                Navigator.pop(context, id);
                return;
              }
            }
            setState(() => error = 'PostCheckの施設QRを読み取ってください。外部リンクは開きません。');
          },
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(24),
            child: AppText(
              error.isEmpty ? '施設に設置されたPostCheckのQRを枠内に合わせてください。' : error,
            ),
          ),
        ),
      ],
    ),
  );
}
