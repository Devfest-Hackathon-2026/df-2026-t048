import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postcheck/adapters/local_storage.dart';
import 'package:postcheck/application/check_draft.dart';
import 'package:postcheck/domain/models.dart';
import 'package:postcheck/domain/ports.dart';
import 'package:postcheck/domain/preferences.dart';
import 'package:postcheck/presentation/finding_review_list.dart';
import 'package:postcheck/presentation/photo_preview.dart';
import 'package:postcheck/presentation/postcheck_controller.dart';
import 'localization_test.dart' show englishApp;
import 'controller_test.dart' show TestExport, TestContext;

class ReviewTextPerception implements PerceptionPort {
  @override
  Future<Observations> inspect(PhotoInput photo) async => const Observations(
    blocks: [
      TextBlock(id: 'name', text: '山田 太郎', region: ImageRegion(.1, .1, .3, .1)),
      TextBlock(id: 'word', text: '写真', region: ImageRegion(.1, .4, .3, .1)),
      TextBlock(
        id: 'project',
        text: '企画展2026\n会場案内',
        region: ImageRegion(.1, .7, .3, .1),
      ),
    ],
  );
}

class ReviewImages implements ImageProcessingPort {
  final png = Uint8List.fromList(
    img.encodePng(img.Image(width: 100, height: 100)),
  );
  @override
  Future<PhotoInput> prepare(Uint8List bytes) async =>
      PhotoInput(bytes: png, width: 100, height: 100);
  @override
  Future<Uint8List> redact(
    PhotoInput photo,
    List<PhotoMask> regions, {
    RedactionStyle style = RedactionStyle.black,
  }) async => png;
}

void main() {
  late PostCheckController c;
  late LocalSettings settings;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = LocalSettings(await SharedPreferences.getInstance());
    await settings.saveReviewPreferences(
      const ReviewPreferences(learningEnabled: true),
    );
    c = PostCheckController(
      check: CheckDraft(
        perception: ReviewTextPerception(),
        context: TestContext(),
      ),
      images: ReviewImages(),
      exporter: TestExport(),
      settings: settings,
    );
    await c.loadPhoto(Uint8List.fromList([1]));
    await c.runCheck([]);
  });
  tearDown(() => c.dispose());
  Widget list({GlobalKey<FindingReviewListState>? key}) => AnimatedBuilder(
    animation: c,
    builder: (_, _) => FindingReviewList(
      key: key,
      controller: c,
      findings: c.findings,
      onMask: (_) async {},
      onVenueDetails: () async {},
    ),
  );
  testWidgets(
    'literal OCR titles are stacked vertically and actions affect only that row',
    (tester) async {
      await tester.pumpWidget(
        englishApp(Scaffold(body: SingleChildScrollView(child: list()))),
      );
      expect(find.text('山田 太郎'), findsOneWidget);
      expect(
        find.text('写真'),
        findsOneWidget,
      ); // Do not translate OCR into “Photo”.
      expect(find.text('企画展2026\n会場案内'), findsOneWidget);
      expect(find.text('写り込んだ文字'), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      final first = tester.getTopLeft(
        find.byKey(const ValueKey('finding-row-block-name')),
      );
      final second = tester.getTopLeft(
        find.byKey(const ValueKey('finding-row-block-word')),
      );
      final third = tester.getTopLeft(
        find.byKey(const ValueKey('finding-row-block-project')),
      );
      expect(first.dx, second.dx);
      expect(second.dx, third.dx);
      expect(first.dy, lessThan(second.dy));
      expect(second.dy, lessThan(third.dy));
      final hide = find.byKey(const ValueKey('finding-hide-block-word'));
      await tester.ensureVisible(hide);
      await tester.tap(hide);
      await tester.pumpAndSettle();
      expect(c.selectedId, 'block-word');
      expect(c.decisions['block-word'], ReviewDecision.hide);
      expect(c.decisions['block-name'], isNull);
      expect(c.decisions['block-project'], isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('learning opt-in stays with its own finding', (tester) async {
    await tester.pumpWidget(
      englishApp(Scaffold(body: SingleChildScrollView(child: list()))),
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    final second = find.byKey(const ValueKey('finding-hide-block-word'));
    await tester.ensureVisible(second);
    await tester.pumpAndSettle();
    await tester.tap(second);
    await tester.pumpAndSettle();
    expect(settings.reviewPreferences.choices, isEmpty);
    final first = find.byKey(const ValueKey('finding-hide-block-name'));
    await tester.ensureVisible(first);
    await tester.pumpAndSettle();
    await tester.tap(first);
    await tester.pumpAndSettle();
    expect(settings.reviewPreferences.choices.values.single.hide, 1);
  });
  testWidgets(
    'photo selection scrolls the matching row into view and exposes OCR semantics',
    (tester) async {
      final key = GlobalKey<FindingReviewListState>();
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          englishApp(
            Scaffold(
              body: Column(
                children: [
                  SizedBox(
                    height: 160,
                    child: AnimatedBuilder(
                      animation: c,
                      builder: (_, _) => PhotoPreview(
                        photo: c.photo!,
                        findings: c.findings,
                        decisions: c.decisions,
                        selectedId: c.selectedId,
                        drawing: false,
                        onSelect: (id) {
                          c.select(id);
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => key.currentState?.reveal(id),
                          );
                        },
                        onDraw: (_) {},
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(child: list(key: key)),
                  ),
                ],
              ),
            ),
          ),
        );
        final frame = find.bySemanticsLabel('3 企画展2026\n会場案内');
        expect(frame, findsOneWidget);
        await tester.tap(frame);
        await tester.pumpAndSettle();
        expect(c.selectedId, 'block-project');
        final selected = find.byKey(
          const ValueKey('finding-select-block-project'),
        );
        expect(tester.getTopLeft(selected).dy, greaterThanOrEqualTo(160));
        expect(tester.getBottomLeft(selected).dy, lessThan(600));
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
  testWidgets(
    'choosing a lower row keeps its header visible after other details collapse',
    (tester) async {
      await tester.pumpWidget(
        englishApp(
          Scaffold(
            body: Center(
              child: SizedBox(
                height: 260,
                child: SingleChildScrollView(child: list()),
              ),
            ),
          ),
        ),
      );
      final target = find.byKey(const ValueKey('finding-select-block-project'));
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(c.selectedId, 'block-project');
      expect(tester.getTopLeft(target).dy, greaterThanOrEqualTo(170));
      expect(tester.getBottomLeft(target).dy, lessThan(430));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'small screen with large text keeps both choices available',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        englishApp(Scaffold(body: SingleChildScrollView(child: list()))),
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('finding-keep-block-name')),
            )
            .onPressed,
        isNotNull,
      );
      final hide = find.byKey(const ValueKey('finding-hide-block-name'));
      expect(tester.widget<OutlinedButton>(hide).onPressed, isNotNull);
      await tester.tap(hide);
      await tester.pumpAndSettle();
      expect(c.decisions['block-name'], ReviewDecision.hide);
      expect(tester.takeException(), isNull);
    },
  );
}
