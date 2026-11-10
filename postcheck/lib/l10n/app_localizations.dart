import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'english.dart';

/// UI-only translations. Photos, OCR, venue evidence and captions are never sent
/// for translation. Domain messages remain unchanged until rendered here.
class AppStrings {
  const AppStrings(this.locale);
  final Locale locale;
  static const supportedLocales = [Locale('ja'), Locale('en')];
  static const languageNames = {'ja': '日本語', 'en': 'English'};
  static const _catalogs = {'en': english};
  static const delegate = _StringsDelegate();
  static AppStrings of(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings) ??
      const AppStrings(Locale('ja'));
  String text(String source) {
    if (locale.languageCode == 'ja') return source;
    final catalog = _catalogs[locale.languageCode] ?? english;
    final exact = catalog[source];
    if (exact != null) return exact;
    for (final entry in _templates[locale.languageCode] ?? _templates['en']!) {
      final match = entry.pattern.firstMatch(source);
      if (match == null) continue;
      return entry.translation.replaceAllMapped(RegExp(r'\{(\d+)\}'), (m) {
        final index = int.parse(m[1]!);
        final value = match.group(index + 1)!;
        return entry.translatedSlots.contains(index) ? text(value) : value;
      });
    }
    return source;
  }

  // Explicitly translate only slots containing app-authored labels. Facility
  // names, registered words and source excerpts are always literal.
  static const _translatedSlots = <String, Set<int>>{
    '場所のルール · {0}': {0},
    '{0}番 {1}': {1},
    '場所のルール、{0}、{1}': {1},
    '{0} · デモ': {0},
    '過去の選択では「{0}」が多い傾向です。': {0},
    '{0}が写っています。公開する範囲を確認してください。': {0},
    '{0} · 約{1}m{2}': {0, 2},
    '施設のSNS公開条件：{0}。写真の修正だけでは公開条件を満たすとは限りません。': {0},
  };
  static final _templates = {
    for (final catalog in _catalogs.entries)
      catalog.key: [
        for (final entry in catalog.value.entries.where(
          (e) => e.key.contains(RegExp(r'\{\d+\}')),
        ))
          _Template(
            entry.key,
            entry.value,
            _translatedSlots[entry.key] ?? const {},
          ),
      ],
  };
}

class _Template {
  _Template(String source, this.translation, this.translatedSlots)
    : pattern = RegExp(
        '^${source.split(RegExp(r'\{\d+\}')).map(RegExp.escape).join('(.*?)')}\u0024',
        dotAll: true,
      );
  final RegExp pattern;
  final String translation;
  final Set<int> translatedSlots;
}

class _StringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _StringsDelegate();
  @override
  bool isSupported(Locale locale) =>
      AppStrings.languageNames.containsKey(locale.languageCode);
  @override
  Future<AppStrings> load(Locale locale) =>
      SynchronousFuture(AppStrings(locale));
  @override
  bool shouldReload(_StringsDelegate old) => false;
}

String tr(BuildContext context, String source) =>
    AppStrings.of(context).text(source);

/// A const-friendly text leaf. Only authored UI messages belong here; use Text
/// for user content and original venue evidence.
class AppText extends StatelessWidget {
  const AppText(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });
  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;
  @override
  Widget build(BuildContext context) => Text(
    tr(context, data),
    style: style,
    strutStyle: strutStyle,
    textAlign: textAlign,
    textDirection: textDirection,
    locale: locale,
    softWrap: softWrap,
    overflow: overflow,
    textScaler: textScaler,
    maxLines: maxLines,
    semanticsLabel: semanticsLabel == null
        ? null
        : tr(context, semanticsLabel!),
    textWidthBasis: textWidthBasis,
    textHeightBehavior: textHeightBehavior,
    selectionColor: selectionColor,
  );
}

class AppLanguage extends ChangeNotifier {
  AppLanguage({required String? saved, required this.persist})
    : _code = valid(saved);
  final Future<void> Function(String?) persist;
  String? _code;
  String? get code => _code;
  Locale? get locale => _code == null ? null : Locale(_code!);
  static String? valid(String? code) =>
      AppStrings.languageNames.containsKey(code) ? code : null;
  Future<void> select(String? code) async {
    final next = valid(code);
    await persist(next);
    _code = next;
    notifyListeners();
  }
}

class AppLanguageScope extends InheritedNotifier<AppLanguage> {
  const AppLanguageScope({
    super.key,
    required AppLanguage language,
    required super.child,
  }) : super(notifier: language);
  static AppLanguage? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLanguageScope>()?.notifier;
}
