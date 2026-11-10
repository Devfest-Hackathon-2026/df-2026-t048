import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postcheck/adapters/local_storage.dart';
import 'package:postcheck/application/check_draft.dart';
import 'package:postcheck/domain/models.dart';
import 'package:postcheck/l10n/app_localizations.dart';
import 'package:postcheck/main.dart';
import 'package:postcheck/presentation/finding_review_list.dart';
import 'package:postcheck/presentation/postcheck_controller.dart';
import 'controller_test.dart'
    show TestPerception, TestContext, TestImages, TestExport;

const _caption = '連絡先 a@example.com と b@example.com';

PostCheckController _controller() => PostCheckController(
  languageCode: () => 'ja',
  check: CheckDraft(perception: TestPerception(), context: TestContext()),
  images: TestImages(),
  exporter: TestExport(),
);

Finding _byExcerpt(PostCheckController c, String text) =>
    c.findings.firstWhere((f) => f.excerpt.contains(text));

void main() {
  test(
    'a hidden candidate can be changed back to keep after recheck',
    () async {
      final c = _controller();
      addTearDown(c.dispose);
      c.setCaption(_caption);
      await c.runCheck(const []);
      expect(c.findings, hasLength(2));
      await c.decide(_byExcerpt(c, 'a@'), ReviewDecision.hide);
      await c.decide(_byExcerpt(c, 'b@'), ReviewDecision.keep);
      await c.applyAndRecheck(const []);

      // The burned-in address is gone, so it cannot be reselected from here.
      expect(c.caption, isNot(contains('a@example.com')));
      expect(c.findings.where((f) => f.excerpt.contains('a@')), isEmpty);
      expect(c.canReselectHidden, isTrue);

      await c.decide(c.hiddenFindings.single, ReviewDecision.keep);
      expect(c.caption, _caption);
      expect(c.findings, hasLength(2));
      final a = _byExcerpt(c, 'a@');
      final b = _byExcerpt(c, 'b@');
      expect(c.decisions[a.id], ReviewDecision.keep);
      expect(c.decisions[b.id], ReviewDecision.keep);
      expect(c.hasChanges, isFalse);
      expect(c.canExport, isTrue);
      expect(c.outputCaption, _caption);
    },
  );

  test('candidates without an exact earlier match stay unconfirmed', () async {
    final c = _controller();
    addTearDown(c.dispose);
    c.setCaption(_caption);
    await c.runCheck(const []);
    await c.decide(_byExcerpt(c, 'a@'), ReviewDecision.hide);
    // b is left undecided before the recheck.
    await c.applyAndRecheck(const []);
    await c.decide(c.hiddenFindings.single, ReviewDecision.keep);
    expect(c.decisions[_byExcerpt(c, 'a@').id], ReviewDecision.keep);
    expect(
      c.decisions[_byExcerpt(c, 'b@').id] ?? ReviewDecision.pending,
      ReviewDecision.pending,
    );
  });

  test('a new post forgets earlier decisions', () async {
    final c = _controller();
    addTearDown(c.dispose);
    c.setCaption(_caption);
    await c.runCheck(const []);
    await c.decide(_byExcerpt(c, 'a@'), ReviewDecision.hide);
    await c.applyAndRecheck(const []);
    c.reset();
    expect(c.canReselectHidden, isFalse);
    c.setCaption(_caption);
    await c.runCheck(const []);
    expect(
      c.decisions.values.where((d) => d != ReviewDecision.pending),
      isEmpty,
    );
  });

  test(
    'resetting current decisions prevents an older keep from returning',
    () async {
      final c = _controller();
      addTearDown(c.dispose);
      // B precedes A, so restoring A cannot change B's evidence or position.
      c.setCaption('b@example.com a@example.com');
      await c.runCheck(const []);
      await c.decide(_byExcerpt(c, 'b@'), ReviewDecision.keep);
      await c.decide(_byExcerpt(c, 'a@'), ReviewDecision.hide);
      await c.applyAndRecheck(const []);
      await c.decide(_byExcerpt(c, 'b@'), ReviewDecision.hide);
      await c.resetEdits();
      expect(c.decisionFor(_byExcerpt(c, 'b@')), ReviewDecision.pending);

      await c.decide(c.hiddenFindings.single, ReviewDecision.keep);

      expect(c.decisionFor(_byExcerpt(c, 'a@')), ReviewDecision.keep);
      expect(c.decisionFor(_byExcerpt(c, 'b@')), ReviewDecision.pending);
      expect(c.pendingCount, 1);
      expect(c.canExport, isFalse);
    },
  );

  test('a hidden row stays listed with 隠す and 残す reopens it', () async {
    final c = _controller();
    addTearDown(c.dispose);
    c.setCaption(_caption);
    await c.runCheck(const []);
    await c.decide(_byExcerpt(c, 'a@'), ReviewDecision.hide);
    await c.decide(_byExcerpt(c, 'b@'), ReviewDecision.keep);
    await c.applyAndRecheck(const []);

    final hidden = c.hiddenFindings.single;
    expect(hidden.excerpt, contains('a@'));
    // Rows keep the order of the first check; the hidden one does not jump
    // behind the kept one.
    expect(c.reviewFindings.map((f) => f.excerpt), [
      contains('a@'),
      contains('b@'),
    ]);
    expect(c.reviewDecisions[hidden.id], ReviewDecision.hide);
    expect(c.decisionFor(hidden), ReviewDecision.hide);
    // Hidden rows do not block sharing; only the kept one needs a decision.
    expect(c.pendingCount, 1);

    await c.decide(hidden, ReviewDecision.hide);
    expect(c.caption, isNot(contains('a@example.com')), reason: 'no-op');

    await c.decide(hidden, ReviewDecision.keep);
    expect(c.caption, _caption);
    expect(c.hiddenFindings, isEmpty);
    expect(c.decisions[_byExcerpt(c, 'a@').id], ReviewDecision.keep);
    expect(c.decisions[_byExcerpt(c, 'b@').id], ReviewDecision.keep);
    expect(c.selectedId, _byExcerpt(c, 'a@').id);
    expect(c.canExport, isTrue);
  });

  test(
    'a committed mask can be removed when the same candidate is redetected',
    () async {
      final c = _controller();
      addTearDown(c.dispose);
      await c.loadPhoto(Uint8List.fromList([1]));
      await c.runCheck(const []);
      await c.decide(c.findings.single, ReviewDecision.hide);
      await c.applyAndRecheck(const []);
      expect(c.photo!.bytes, [9]);
      expect(
        c.findings,
        hasLength(1),
        reason: 'The fake OCR redetects the masked item',
      );
      await c.decide(c.findings.single, ReviewDecision.keep);
      expect(c.photo!.bytes, [
        1,
      ], reason: 'The selected committed mask is removed');
      expect(c.decisions[c.findings.single.id], ReviewDecision.keep);
      expect(c.canExport, isTrue);
    },
  );

  for (final language in ['ja', 'en']) {
    testWidgets(
      'ambiguous hidden text cannot be restored individually ($language)',
      (tester) async {
        const explanation = '非表示部分が文章編集で変わったため、この候補だけは戻せません。現在の文章は保持しています。';
        final s = AppStrings(Locale(language));
        final c = PostCheckController(
          languageCode: () => language,
          check: CheckDraft(
            perception: TestPerception(),
            context: TestContext(),
          ),
          images: TestImages(),
          exporter: TestExport(),
        );
        addTearDown(c.dispose);
        c.setCaption('a@example.com b@example.com');
        await c.runCheck(const []);
        for (final finding in c.findings.toList()) {
          await c.decide(finding, ReviewDecision.hide);
        }
        await c.applyAndRecheck(const []);
        final marker = language == 'en' ? '[Hidden]' : '［非表示］';
        expect(c.caption, '$marker $marker');
        // Either identical replacement may have been deleted. Neither owner is
        // safe to associate with the one remaining marker.
        await c.reviseCaption(marker);
        await c.runCheck(const []);
        expect(c.hiddenFindings, hasLength(2));
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            supportedLocales: AppStrings.supportedLocales,
            localizationsDelegates: const [
              AppStrings.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: Scaffold(
              body: SingleChildScrollView(
                child: FindingReviewList(
                  controller: c,
                  findings: c.reviewFindings,
                  onMask: (_) async {},
                  onVenueDetails: () async {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(s.text(explanation)), findsNWidgets(2));
        if (language == 'en') expect(find.text(explanation), findsNothing);
        for (final hidden in c.hiddenFindings) {
          expect(c.canReselect(hidden), isFalse);
          final button = find.byKey(ValueKey('finding-keep-${hidden.id}'));
          expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
          await c.decide(hidden, ReviewDecision.keep);
        }
        expect(c.caption, marker);
        expect(c.hiddenFindings, hasLength(2));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('finished screen can reopen hidden items ($language)', (
      tester,
    ) async {
      final s = AppStrings(Locale(language));
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({'ui.language': language});
      final c = PostCheckController(
        languageCode: () => language,
        check: CheckDraft(perception: TestPerception(), context: TestContext()),
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
      await tester.pumpAndSettle();
      Future<void> tapVisible(Finder finder) async {
        await tester.scrollUntilVisible(
          finder,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await tapVisible(find.byKey(const ValueKey('text-only-button')));
      await tester.enterText(
        find.byKey(const ValueKey('caption-input')),
        '連絡先 a@example.com',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('check-button')));
      await tester.pumpAndSettle();
      await tapVisible(find.text(s.text('隠す')).hitTestable());
      await tester.tap(find.byKey(const ValueKey('recheck-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('preview-button')));
      await tester.pumpAndSettle();
      expect(c.findings, isEmpty);

      // Back from the finished screen: the hidden item is still listed with
      // 隠す selected, like kept items are listed with 残す.
      await tester.tap(find.byTooltip(s.text('戻る')));
      await tester.pumpAndSettle();
      expect(find.text(s.text('文章 1')), findsOneWidget);
      await tapVisible(find.text(s.text('残す')).hitTestable());
      expect(c.findings, hasLength(1));
      expect(c.decisions[c.findings.single.id], ReviewDecision.keep);
      expect(c.caption, '連絡先 a@example.com');
      expect(c.canExport, isTrue);
    });
  }
}
