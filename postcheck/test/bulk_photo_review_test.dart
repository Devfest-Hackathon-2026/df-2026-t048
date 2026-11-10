import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postcheck/adapters/local_storage.dart';
import 'package:postcheck/application/check_draft.dart';
import 'package:postcheck/domain/models.dart';
import 'package:postcheck/domain/preferences.dart';
import 'package:postcheck/l10n/app_localizations.dart';
import 'package:postcheck/main.dart';
import 'package:postcheck/presentation/postcheck_controller.dart';

import 'controller_test.dart' show TestContext, TestExport, TestImages;
import 'finding_review_list_test.dart' show ReviewImages, ReviewTextPerception;

void main() {
  test(
    'batch renders once, guards concurrent changes and preserves area-less candidates',
    () async {
      final images = TestImages();
      final c = PostCheckController(
        check: CheckDraft(
          perception: ReviewTextPerception(),
          context: TestContext(
            findings: const [
              Finding(
                id: 'whole',
                kind: FindingKind.context,
                question: 'Review this photo?',
                target: WholePhotoTarget(),
                source: FindingSource.gemma,
              ),
            ],
          ),
        ),
        images: images,
        exporter: TestExport(),
      );
      addTearDown(c.dispose);
      await c.loadPhoto(Uint8List(1));
      await c.runCheck(const []);
      final whole = c.findings.singleWhere((f) => f.target is WholePhotoTarget);
      final gate = Completer<Uint8List>();
      images.pending = gate;
      final batch = c.decideAllPhotos(ReviewDecision.hide);
      expect(c.preparingPreview, isTrue);
      expect(images.rendered, hasLength(1));
      expect(images.rendered.single, hasLength(3));
      expect(c.decisionFor(whole), ReviewDecision.pending);
      await c.decideAllPhotos(ReviewDecision.keep);
      expect(c.masks, hasLength(3));
      gate.complete(Uint8List.fromList([9]));
      await batch;
      await c.decideAllPhotos(ReviewDecision.keep);
      expect(c.masks, isEmpty);
      expect(c.decisionFor(whole), ReviewDecision.keep);
    },
  );

  test(
    'switched-off items leave the candidates and bulk choices do not learn',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = LocalSettings(await SharedPreferences.getInstance());
      await settings.saveReviewPreferences(
        const ReviewPreferences(
          disabledTargets: {CheckTarget.imageText},
          learningEnabled: true,
        ),
      );
      final c = PostCheckController(
        check: CheckDraft(
          perception: ReviewTextPerception(),
          context: TestContext(),
        ),
        images: ReviewImages(),
        exporter: TestExport(),
        settings: settings,
      );
      addTearDown(c.dispose);
      await c.loadPhoto(Uint8List(1));
      await c.runCheck(const []);
      expect(
        c.findings.any(
          (f) => f.evidence.every((e) => e.kind == FindingKind.imageText),
        ),
        isFalse,
      );
      await c.decideAllPhotos(ReviewDecision.hide);
      await c.decideAllPhotos(ReviewDecision.keep);
      expect(settings.reviewPreferences.choices, isEmpty);
    },
  );

  for (final language in ['ja', 'en']) {
    testWidgets(
      'photo bulk buttons allow individual exceptions and leave caption alone ($language)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.4;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        SharedPreferences.setMockInitialValues({'ui.language': language});
        final c = PostCheckController(
          check: CheckDraft(
            perception: ReviewTextPerception(),
            context: TestContext(),
          ),
          images: ReviewImages(),
          exporter: TestExport(),
        );
        addTearDown(c.dispose);
        await c.loadPhoto(Uint8List(1));
        c.setCaption('fixture@example.com');
        await tester.pumpWidget(
          PostCheckApp(
            controller: c,
            settings: LocalSettings(await SharedPreferences.getInstance()),
            startWithCamera: false,
          ),
        );
        await tester.pumpAndSettle();
        final s = AppStrings(Locale(language));
        Future<void> tap(Finder finder, {double scrollDelta = 120}) async {
          if (finder.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              finder,
              scrollDelta,
              scrollable: find.byType(Scrollable).first,
            );
          }
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        await tap(find.text(s.text('作業中の下書きに戻る')));
        await tap(find.byKey(const ValueKey('check-button')));
        expect(find.text(s.text('すべて隠す')), findsOneWidget);
        expect(find.text(s.text('すべて残す')), findsOneWidget);
        await tap(find.byKey(const ValueKey('photo-all-hide')));
        await tap(find.byKey(const ValueKey('finding-keep-block-name')));
        expect(c.decisions['block-name'], ReviewDecision.keep);
        expect(c.decisions['block-word'], ReviewDecision.hide);
        await tap(
          find.byKey(const ValueKey('photo-all-keep')),
          scrollDelta: -120,
        );
        await tap(find.byKey(const ValueKey('finding-hide-block-word')));
        expect(c.decisions['block-name'], ReviewDecision.keep);
        expect(c.decisions['block-word'], ReviewDecision.hide);
        final caption = c.findings.singleWhere(
          (f) => f.target is CaptionTarget,
        );
        expect(c.decisionFor(caption), ReviewDecision.pending);
        await tap(find.text(s.text('文章 1')), scrollDelta: -120);
        expect(find.byKey(const ValueKey('photo-all-hide')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
