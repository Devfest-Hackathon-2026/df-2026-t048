import 'models.dart';
import 'model_preparation.dart';

/// Every item the app can point out. The user turns each on or off on the
/// review settings page (default: all on). Detection still runs for all of
/// them; switched-off items are dropped from the candidates afterwards.
enum CheckTarget {
  contact('連絡先'),
  privateWord('登録ワード'),
  imageText('写り込んだ文字'),
  face('人物'),
  announcement('告知のタイミング'),
  context('内容の確認（AI）'),
  screenDevice('パソコン・スマホ'),
  whiteboard('ホワイトボード'),
  wineGlass('お酒（ワイングラス）'),
  book('本・資料'),
  pictureFrame('額縁'),
  poster('ポスター');

  const CheckTarget(this.label);
  final String label;

  static CheckTarget of(Finding finding) => switch (finding.kind) {
    FindingKind.contact => contact,
    FindingKind.privateWord => privateWord,
    FindingKind.imageText => imageText,
    FindingKind.face => face,
    FindingKind.announcement => announcement,
    FindingKind.context => context,
    FindingKind.screenDevice => switch (finding.detectedLabel) {
      'whiteboard' => whiteboard,
      'wine_glass' => wineGlass,
      'book' => book,
      'picture_frame' => pictureFrame,
      'poster' => poster,
      _ => screenDevice,
    },
  };
}

/// Only aggregate choices are learned. No excerpts, images or identities.
final class ChoiceCount {
  const ChoiceCount({this.hide = 0, this.keep = 0});
  final int hide, keep;
  ReviewDecision? get suggestion {
    if (hide + keep < 3) return null;
    if (hide / (hide + keep) >= .75) return ReviewDecision.hide;
    if (keep / (hide + keep) >= .75) return ReviewDecision.keep;
    return null;
  }

  ChoiceCount record(ReviewDecision decision) => ChoiceCount(
    hide: hide + (decision == ReviewDecision.hide ? 1 : 0),
    keep: keep + (decision == ReviewDecision.keep ? 1 : 0),
  );
}

final class ReviewPreferences {
  const ReviewPreferences({
    this.disabledTargets = const {},
    this.learningEnabled = false,
    this.choices = const {},
  });
  final Set<CheckTarget> disabledTargets;
  final bool learningEnabled;
  final Map<String, ChoiceCount> choices;

  bool isEnabled(CheckTarget target) => !disabledTargets.contains(target);

  /// Shared by the review filter and the UI showing the OR result.
  bool effectiveEnabled(
    CheckTarget target, {
    Iterable<String> venueTargets = const [],
  }) => isEnabled(target) || venueTargets.contains(target.name);

  /// A candidate is shown when any of its evidence is switched on by the user
  /// OR by the applied venue ([venueTargets] = `VenuePolicy.checkTargets`), or
  /// when it comes from the venue rule text/words (always shown).
  bool shows(Finding finding, {Iterable<String> venueTargets = const []}) =>
      finding.evidence.any((f) {
        final target = CheckTarget.of(f);
        return f.ruleEvidence != null ||
            effectiveEnabled(target, venueTargets: venueTargets);
      });

  // Separate photo / caption / overall context. The "personal:" prefix keeps
  // choice counts learned before the enterprise mode was removed.
  String keyFor(Finding finding) =>
      'personal:${finding.kind.name}:${finding.target is CaptionTarget
          ? 'caption'
          : finding.target is PhotoTarget
          ? 'photo'
          : 'whole'}';
  ReviewDecision? suggestionFor(Finding finding) =>
      learningEnabled ? choices[keyFor(finding)]?.suggestion : null;
  ReviewPreferences copyWith({
    Set<CheckTarget>? disabledTargets,
    bool? learningEnabled,
    Map<String, ChoiceCount>? choices,
  }) => ReviewPreferences(
    disabledTargets: disabledTargets ?? this.disabledTargets,
    learningEnabled: learningEnabled ?? this.learningEnabled,
    choices: choices ?? this.choices,
  );
}

abstract interface class SettingsPort {
  List<String> get privateWords;
  bool get aiEnabled;
  String? get modelName;
  ReviewPreferences get reviewPreferences;
  Future<void> saveWords(String words);
  Future<void> setAIEnabled(bool value);
  Future<void> saveReviewPreferences(ReviewPreferences value);
  Future<void> recordChoice(Finding finding, ReviewDecision decision);
  Future<String?> modelPath();
  Future<ModelPreparation> modelPreparation();
  Future<ModelPreparation> prepareModel({bool resume = false});
  Future<ModelPreparation> pauseModelDownload();
  Future<void> replaceSettings({
    required bool aiEnabled,
    required List<String> privateWords,
    required ReviewPreferences review,
  });
}
