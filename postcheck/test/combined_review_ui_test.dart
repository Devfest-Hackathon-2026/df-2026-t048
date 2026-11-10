import 'package:postcheck_rules/contracts.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postcheck/adapters/local_storage.dart';
import 'package:postcheck/application/check_draft.dart';
import 'package:postcheck/application/ocr_merge.dart';
import 'package:postcheck/domain/models.dart';
import 'package:postcheck/domain/ports.dart';
import 'package:postcheck/l10n/app_localizations.dart';
import 'package:postcheck/main.dart';
import 'package:postcheck/presentation/finding_review_list.dart';
import 'package:postcheck/presentation/postcheck_controller.dart';
import 'controller_test.dart' show TestImages, TestExport, TestPerception;
import 'localization_test.dart' show localizedApp;

class WaitingAi implements ContextAnalysisPort {
  final pending = Completer<ContextResult>();
  @override
  Future<ContextResult> analyze(
    DraftInput d,
    Observations o, {
    PublishedVenue? venue,
  }) => pending.future;
}

void main() {
  for (final code in ['ja', 'en']) {
    final strings = AppStrings(Locale(code));
    testWidgets(
      'merged evidence shares a decision and whole-photo hide needs an area ($code)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.4;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final c = PostCheckController(
          check: CheckDraft(perception: TestPerception(), context: WaitingAi()),
          images: TestImages(),
          exporter: TestExport(),
        );
        addTearDown(c.dispose);
        c.photo = PhotoInput(bytes: Uint8List(1), width: 100, height: 100);
        final items = mergeReviewFindings([
          const Finding(
            id: 'ocr',
            kind: FindingKind.contact,
            question: 'contact',
            target: PhotoTarget(ImageRegion(.1, .2, .3, .1)),
            source: FindingSource.mlKit,
            excerpt: '架空@example.com',
            targetKey: 'ocr:b0',
          ),
          const Finding(
            id: 'ai',
            kind: FindingKind.context,
            question: 'Review the document?',
            target: PhotoTarget(ImageRegion(.1, .2, .3, .1)),
            source: FindingSource.gemma,
            targetKey: 'ocr:b0',
          ),
          const Finding(
            id: 'whole',
            kind: FindingKind.context,
            question: 'Review the badge?',
            target: WholePhotoTarget(),
            source: FindingSource.gemma,
          ),
        ]);
        c.report = CheckReport(
          findings: items,
          notes: [],
          aiStatus: 'test',
          elapsed: Duration.zero,
          completedAt: DateTime.now(),
        );
        c.selectedId = 'ocr';
        var areaRequests = 0;
        await tester.pumpWidget(
          localizedApp(
            Scaffold(
              body: SingleChildScrollView(
                child: AnimatedBuilder(
                  animation: c,
                  builder: (_, _) => FindingReviewList(
                    controller: c,
                    findings: c.findings,
                    onVenueDetails: () async {},
                    onMask: (f) async {
                      areaRequests++;
                      await c.adjustRegion(
                        f,
                        const ImageRegion(.2, .2, .2, .2),
                      );
                    },
                  ),
                ),
              ),
            ),
            code,
          ),
        );
        expect(find.text('架空@example.com'), findsOneWidget);
        expect(find.text('Review the document?'), findsOneWidget);
        final hide = find.byKey(const ValueKey('finding-hide-ocr'));
        await tester.ensureVisible(hide);
        await tester.tap(hide);
        await tester.pumpAndSettle();
        expect(c.decisions, {'ocr': ReviewDecision.hide});
        expect(c.masks, hasLength(1));
        final whole = find.byKey(const ValueKey('finding-hide-whole'));
        await tester.ensureVisible(whole);
        await tester.tap(whole);
        await tester.pumpAndSettle();
        expect(areaRequests, 1);
        expect(c.manualRegions, hasLength(1));
        expect(c.decisions['whole'], ReviewDecision.hide);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'current results button finishes AI wait and keeps basic findings ($code)',
      (tester) async {
        SharedPreferences.setMockInitialValues({'ui.language': code});
        final ai = WaitingAi();
        final c = PostCheckController(
          check: CheckDraft(perception: TestPerception(), context: ai),
          images: TestImages(),
          exporter: TestExport(),
        );
        addTearDown(c.dispose);
        await tester.pumpWidget(
          PostCheckApp(
            controller: c,
            settings: LocalSettings(await SharedPreferences.getInstance()),
            startWithCamera: false,
          ),
        );
        final captionOnly = find.text(strings.text('文章だけチェックする'));
        await tester.ensureVisible(captionOnly);
        await tester.tap(captionOnly);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('caption-input')),
          'fixture@example.com',
        );
        final check = find.byKey(const ValueKey('check-button'));
        await tester.ensureVisible(check);
        await tester.pumpAndSettle();
        await tester.tap(check);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final finish = find.text(strings.text('現在の結果で確認する'));
        expect(finish, findsOneWidget);
        await tester.ensureVisible(finish);
        await tester.tap(finish);
        await tester.pump(const Duration(milliseconds: 30));
        await tester.pumpAndSettle();
        expect(c.busy, isFalse);
        expect(c.findings.single.kind, FindingKind.contact);
        expect(c.report!.aiStatus, contains('基本チェック'));
        ai.pending.completeError(StateError('late native fixture'));
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
