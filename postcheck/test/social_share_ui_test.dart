import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postcheck/domain/social_share.dart';
import 'package:postcheck/presentation/social_share_sheet.dart';
import 'package:postcheck/presentation/story_share_page.dart';
import 'package:postcheck/presentation/postcheck_controller.dart';
import 'package:postcheck/application/check_draft.dart';
import 'localization_test.dart' show englishApp;
import 'controller_test.dart'
    show TestImages, TestExport, TestPerception, TestContext;
import 'social_share_test.dart' show SocialRecorder;

void main() {
  testWidgets(
    'small English share menu disables unavailable photo/official options',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        englishApp(
          const Scaffold(
            body: SocialShareSheet(hasPhoto: false, hasCaption: false),
          ),
        ),
      );
      expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('share-instagramPost')))
            .onTap,
        isNull,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('share-lineOfficial')),
        180,
      );
      expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('share-lineOfficial')))
            .onTap,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'official LINE dialog validates ID and returns normalized account',
    (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await chooseOfficialLine(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'トークを開く'))
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const ValueKey('official-line-id')),
        'museum',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('トークを開く'));
      await tester.pumpAndSettle();
      expect(result, '@museum');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('story preview on small English screen shares selected layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final social = SocialRecorder();
    final c = PostCheckController(
      check: CheckDraft(perception: TestPerception(), context: TestContext()),
      images: TestImages(),
      exporter: TestExport(),
      socialExporter: social,
    );
    addTearDown(c.dispose);
    c.setCaption('Museum day');
    await c.runCheck([]);
    await tester.pumpWidget(englishApp(StorySharePage(controller: c)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text overlay'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('share-story-button')));
    await tester.pumpAndSettle();
    expect(social.destination, ShareDestination.instagramStory);
    expect(social.layout, StoryLayout.overlay);
    expect(tester.takeException(), isNull);
  });
}
