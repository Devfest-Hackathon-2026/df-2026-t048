import 'app_licenses.dart';
import 'l10n/app_localizations.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postcheck_rules/postcheck_rules.dart';
import 'adapters/image_processing.dart';
import 'adapters/local_gemma.dart';
import 'adapters/local_storage.dart';
import 'adapters/mlkit_perception.dart';
import 'adapters/share_export.dart';
import 'adapters/social_share.dart';
import 'adapters/photo_library.dart';
import 'adapters/live_camera_page.dart';
import 'presentation/app_theme.dart';
import 'presentation/venue_page.dart';
import 'presentation/nearby_controller.dart';
import 'adapters/device_location.dart';
import 'domain/location.dart';
import 'application/check_draft.dart';
import 'presentation/home_page.dart';
import 'presentation/postcheck_controller.dart';
import 'diagnostics/device_smoke.dart';
import 'diagnostics/device_detector_smoke.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  registerAppLicenses();
  final settings = LocalSettings(await SharedPreferences.getInstance());
  var mapsReady = false;
  if (const bool.fromEnvironment('MAPS_ENABLED')) {
    try {
      mapsReady = defaultTargetPlatform == TargetPlatform.iOS
          ? await const MethodChannel('postcheck/privacy').invokeMethod<bool>(
                  'configureMaps',
                  const String.fromEnvironment('GOOGLE_MAPS_API_KEY'),
                ) ??
                false
          : true;
    } catch (_) {
      mapsReady = false;
    }
  }
  String? preparationError;
  try {
    await prepareLocalPrivacy();
  } catch (_) {
    preparationError = '一時ファイルの準備を完了できませんでした。アプリを再起動してください。';
  }
  String currentLanguageCode() =>
      AppLanguage.valid(settings.preferences.getString('ui.language')) ??
      WidgetsBinding.instance.platformDispatcher.locales
          .where(
            (l) => AppStrings.supportedLocales.any(
              (s) => s.languageCode == l.languageCode,
            ),
          )
          .firstOrNull
          ?.languageCode ??
      'en';
  final controller = PostCheckController(
    languageCode: currentLanguageCode,
    check: CheckDraft(
      perception: MlKitPerceptionAdapter(),
      context: ConfiguredGemmaAdapter(
        settings,
        languageCode: currentLanguageCode,
      ),
    ),
    images: const RasterImageAdapter(),
    exporter: ShareExportAdapter(),
    socialExporter: SocialShareAdapter(),
    saver: ShareExportAdapter(),
    fileSaver: ShareExportAdapter(),
    settings: settings,
  );
  final nearby = NearbyController(
    repository: const String.fromEnvironment('RULE_API_URL').isEmpty
        ? const DemoVenueRepository()
        : RulesApi(baseUrl: const String.fromEnvironment('RULE_API_URL')),
    location: const DeviceLocation(),
    demo: const String.fromEnvironment('RULE_API_URL').isEmpty,
  );
  void showApp() => runApp(
    PostCheckApp(
      controller: controller,
      settings: settings,
      preparationError: preparationError,
      mapsReady: mapsReady,
      nearby: nearby,
    ),
  );
  if (const bool.fromEnvironment('POSTCHECK_DETECTOR_SMOKE')) {
    await runDetectorInitializationSmokeTest();
  }
  if (const bool.fromEnvironment('POSTCHECK_SELF_TEST')) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                Text(
                  '実機で動作を確認しています…\n完了するとPostCheckが開きます。',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await runDeviceSmokeTest();
      showApp();
    });
  } else {
    showApp();
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (settings.aiEnabled) unawaited(settings.prepareModel());
  });
}

class PostCheckApp extends StatefulWidget {
  const PostCheckApp({
    super.key,
    required this.controller,
    required this.settings,
    this.preparationError,
    this.mapsReady = false,
    this.nearby,
    this.startWithCamera = true,
  });
  final PostCheckController controller;
  final LocalSettings settings;
  final String? preparationError;
  final bool mapsReady;
  final NearbyController? nearby;
  final bool startWithCamera;
  @override
  State<PostCheckApp> createState() => _PostCheckAppState();
}

class _PostCheckAppState extends State<PostCheckApp> {
  late final language = AppLanguage(
    saved: widget.settings.preferences.getString('ui.language'),
    persist: (code) async {
      final ok = code == null
          ? await widget.settings.preferences.remove('ui.language')
          : await widget.settings.preferences.setString('ui.language', code);
      if (!ok) throw StateError('Language persistence failed');
    },
  );
  PostCheckController get controller => widget.controller;
  LocalSettings get settings => widget.settings;
  NearbyController? get nearby => widget.nearby;
  bool get mapsReady => widget.mapsReady;
  bool get startWithCamera => widget.startWithCamera;
  String? get preparationError => widget.preparationError;
  @override
  void dispose() {
    language.dispose();
    super.dispose();
  }

  Future<PublishedVenue?> chooseVenue(BuildContext context) async {
    final repository = nearby?.repository ?? const DemoVenueRepository();
    final chosen = await Navigator.push<PublishedVenue>(
      context,
      MaterialPageRoute(
        builder: (_) => VenuePage(
          mapEnabled: mapsReady,
          repository: repository,
          nearby: nearby,
        ),
      ),
    );
    if (chosen != null && nearby != null) {
      // Revalidate the selected version before activating it.
      await nearby!.refresh();
      nearby!.choose(chosen);
      if (nearby!.active?.id != chosen.id ||
          nearby!.active?.version != chosen.version) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: AppText('ルールが更新されたため、もう一度施設を選んでください。')),
          );
        }
        return null;
      }
    }
    return chosen;
  }

  @override
  Widget build(BuildContext context) => AppLanguageScope(
    language: language,
    child: ListenableBuilder(
      listenable: language,
      builder: (context, _) => MaterialApp(
        title: 'PostCheck',
        debugShowCheckedModeBanner: false,
        locale: language.locale,
        supportedLocales: AppStrings.supportedLocales,
        localeListResolutionCallback: (preferred, supported) =>
            preferred
                ?.where(
                  (l) => supported.any((s) => s.languageCode == l.languageCode),
                )
                .firstOrNull ??
            const Locale('en'),
        localizationsDelegates: const [
          AppStrings.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: buildPostCheckTheme(),
        home: preparationError == null
            ? HomePage(
                controller: controller,
                settings: settings,
                library: PhotoLibraryAdapter(),
                startWithCamera: startWithCamera,
                nearby: nearby,
                chooseVenue: chooseVenue,
                openCamera: (context) => Navigator.push<CapturedPhoto>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LiveCameraPage(
                      aiEnabled: settings.aiEnabled,
                      privateWords: settings.privateWords,
                      preferences: settings.reviewPreferences,
                      nearby: nearby,
                      chooseVenue: chooseVenue,
                      library: PhotoLibraryAdapter(),
                    ),
                  ),
                ),
              )
            : Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: AppText(preparationError!),
                  ),
                ),
              ),
      ),
    ),
  );
}
