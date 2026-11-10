import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postcheck/adapters/local_storage.dart';
import 'package:postcheck/application/preferences_codec.dart';
import 'package:postcheck/application/restore_settings.dart';
import 'package:postcheck/application/live_frame_gate.dart';
import 'package:postcheck/domain/preferences.dart';
import 'package:postcheck/domain/models.dart';
import 'package:postcheck/application/check_draft.dart';
import 'package:postcheck/presentation/postcheck_controller.dart';
import 'controller_test.dart';

void main() {
  late LocalSettings settings;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = LocalSettings(await SharedPreferences.getInstance());
  });
  test('each detectable item can be switched off; venue rules still apply', () {
    const whiteboard = Finding(
      id: 'device-0',
      kind: FindingKind.screenDevice,
      question: 'q',
      target: PhotoTarget(ImageRegion(.1, .1, .2, .2)),
      source: FindingSource.deviceModel,
      detectedLabel: 'whiteboard',
    );
    const venueWord = Finding(
      id: 'private-x-0',
      kind: FindingKind.privateWord,
      question: 'q',
      target: CaptionTarget(TextSpanRange(0, 1)),
      source: FindingSource.rule,
      ruleEvidence: '架空の施設 / v1',
    );
    expect(CheckTarget.of(whiteboard), CheckTarget.whiteboard);
    const prefs = ReviewPreferences(
      disabledTargets: {CheckTarget.whiteboard, CheckTarget.privateWord},
    );
    expect(prefs.shows(whiteboard), isFalse);
    expect(prefs.shows(venueWord), isTrue);
    expect(const ReviewPreferences().shows(whiteboard), isTrue);
    // OR with the applied venue: the venue's ON wins over the user's OFF, and
    // the venue's OFF (not listed) never hides an item the user keeps on.
    expect(prefs.shows(whiteboard, venueTargets: ['whiteboard']), isTrue);
    expect(prefs.shows(whiteboard, venueTargets: ['poster']), isFalse);
    expect(
      const ReviewPreferences().shows(whiteboard, venueTargets: const []),
      isTrue,
    );
    final decoded = decodePreferences(encodePreferences(prefs));
    expect(decoded.disabledTargets, prefs.disabledTargets);
  });
  test('settings saved with the removed enterprise mode still load', () {
    final decoded = decodePreferences({
      'mode': 'enterprise',
      'requiredKinds': ['contact'],
      'learningEnabled': true,
      'choices': {
        'enterprise:contact:caption': {'hide': 3, 'keep': 0},
        'personal:contact:caption': {'hide': 0, 'keep': 3},
      },
    });
    expect(decoded.disabledTargets, isEmpty);
    expect(decoded.choices.keys, ['personal:contact:caption']);
  });
  test(
    'explicit learning records only aggregates and suggests the usual choice',
    () async {
      final finding = const RuleChecker()
          .check(
            const DraftInput(caption: 'fiction@example.com'),
            const Observations(),
          )
          .single;
      await settings.recordChoice(finding, ReviewDecision.keep);
      expect(settings.reviewPreferences.choices, isEmpty);
      await settings.saveReviewPreferences(
        const ReviewPreferences(learningEnabled: true),
      );
      for (var i = 0; i < 3; i++) {
        await settings.recordChoice(finding, ReviewDecision.keep);
      }
      expect(
        settings.reviewPreferences.suggestionFor(finding),
        ReviewDecision.keep,
      );
      expect(encodeBackup(settings), isNot(contains('fiction@example.com')));
      final subject = PostCheckController(
        check: CheckDraft(perception: TestPerception(), context: TestContext()),
        images: TestImages(),
        exporter: TestExport(),
        settings: settings,
      );
      addTearDown(subject.dispose);
      subject.setCaption('fiction@example.com');
      await subject.runCheck([]);
      expect(subject.pendingCount, 1);
      await subject.applySuggestions();
      expect(
        subject.decisionFor(subject.findings.single),
        ReviewDecision.keep,
      );
      expect(subject.pendingCount, 0);
      expect(subject.outputCaption, 'fiction@example.com');
    },
  );
  test(
    'restore validates before atomic replacement and model stays local',
    () async {
      await settings.saveWords('架空企画');
      await settings.setAIEnabled(false);
      final backup = encodeBackup(settings);
      await settings.saveWords('変更後');
      await RestoreSettings(settings)(backup);
      expect(settings.privateWords, ['架空企画']);
      expect(settings.aiEnabled, isFalse);
      final invalid = jsonDecode(backup) as Map<String, dynamic>;
      invalid['review']['choices'] = {
        'raw-person-name': {'hide': 1, 'keep': 0},
      };
      await expectLater(
        RestoreSettings(settings)(jsonEncode(invalid)),
        throwsFormatException,
      );
      expect(settings.privateWords, ['架空企画']);
      expect(
        jsonDecode(backup).keys,
        unorderedEquals(['schema', 'aiEnabled', 'privateWords', 'review']),
      );
    },
  );
  test(
    'single frame in flight, bounded sampling, old sessions and stale data rejected',
    () {
      final gate = LiveFrameGate();
      final generation = gate.begin(0)!;
      expect(gate.begin(1000), isNull);
      gate.invalidate();
      expect(gate.finish(generation, 0, 1200), isFalse);
      final next = gate.begin(1300)!;
      expect(gate.finish(next, 1300, 3401), isFalse);
      final current = gate.begin(3500)!;
      expect(gate.finish(current, 3500, 3700), isTrue);
      expect(gate.begin(3800), isNull);
      expect(gate.begin(4300), isNotNull);
    },
  );
}
