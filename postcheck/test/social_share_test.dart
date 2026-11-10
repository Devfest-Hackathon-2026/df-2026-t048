import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:postcheck/adapters/social_share.dart';
import 'package:postcheck/adapters/story_image.dart';
import 'package:postcheck/application/check_draft.dart';
import 'package:postcheck/domain/models.dart';
import 'package:postcheck/domain/social_share.dart';
import 'package:postcheck/presentation/postcheck_controller.dart';
import 'controller_test.dart'
    show TestExport, TestImages, TestContext, TestPerception;

class SocialRecorder implements SocialExportPort {
  int calls = 0;
  ExportArtifact? artifact;
  ShareDestination? destination;
  StoryLayout? layout;
  @override
  Future<ShareHandoff> shareTo(
    ExportArtifact value,
    ShareDestination target, {
    StoryLayout storyLayout = StoryLayout.card,
    String? officialLineId,
    double? anchorX,
    double? anchorY,
  }) async {
    calls++;
    artifact = value;
    destination = target;
    layout = storyLayout;
    return ShareHandoff.sheet;
  }

  @override
  Future<Uint8List> previewStory(
    ExportArtifact artifact,
    StoryLayout layout,
  ) async => Uint8List.fromList(img.encodePng(img.Image(width: 9, height: 16)));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const caption = '展示の感想 🎨\nA&B + #art / 日本語';
  for (final target in [
    ShareDestination.x,
    ShareDestination.line,
    ShareDestination.threads,
  ]) {
    test(
      '$target text intent preserves unicode and reserved characters',
      () async {
        Uri? opened;
        final output = TestExport();
        final adapter = SocialShareAdapter(
          exporter: output,
          openUrl: (url) async {
            opened = url;
            return true;
          },
        );
        final result = await adapter.shareTo(
          const ExportArtifact(caption: caption),
          target,
        );
        expect(result, ShareHandoff.composer);
        expect(opened!.scheme, 'https');
        expect(opened!.queryParameters['text'], caption);
        expect(opened!.host, switch (target) {
          ShareDestination.x => 'x.com',
          ShareDestination.line => 'line.me',
          _ => 'www.threads.com',
        });
        expect(output.artifact, isNull);
      },
    );
  }
  for (final target in [
    ShareDestination.x,
    ShareDestination.line,
    ShareDestination.threads,
    ShareDestination.instagramPost,
  ]) {
    test(
      '$target photo handoff preserves local attachment and copies caption',
      () async {
        final output = TestExport();
        String? copied;
        final png = Uint8List.fromList([1, 2, 3]);
        final adapter = SocialShareAdapter(
          exporter: output,
          openUrl: (_) async => throw StateError('no URL for local photo'),
          copyText: (text) async {
            copied = text;
          },
        );
        final result = await adapter.shareTo(
          ExportArtifact(caption: caption, imageBytes: png),
          target,
        );
        expect(result, ShareHandoff.captionCopiedSheet);
        expect(copied, caption);
        expect(output.artifact!.imageBytes, same(png));
        expect(output.artifact!.caption, caption);
      },
    );
  }
  test('failed intent falls back to sharing without dropping text', () async {
    for (final throws in [false, true]) {
      final output = TestExport();
      final adapter = SocialShareAdapter(
        exporter: output,
        copyText: (_) async {},
        openUrl: (_) async {
          if (throws) throw PlatformException(code: 'unavailable');
          return false;
        },
      );
      await adapter.shareTo(
        const ExportArtifact(caption: caption),
        ShareDestination.x,
      );
      expect(output.artifact!.caption, caption);
    }
  });
  test('long intent uses share sheet; no caption truncation', () async {
    final text = '日本語' * 1000;
    final output = TestExport();
    final adapter = SocialShareAdapter(
      exporter: output,
      copyText: (_) async {},
      openUrl: (_) async => throw StateError('intent too long'),
    );
    await adapter.shareTo(ExportArtifact(caption: text), ShareDestination.line);
    expect(output.artifact!.caption, text);
  });
  test(
    'story fallback shares rendered PNG only; original photo is not attached',
    () async {
      final output = TestExport();
      final rendered = Uint8List.fromList([7, 8, 9]);
      String? copied;
      final original = ExportArtifact(
        caption: caption,
        imageBytes: Uint8List.fromList([1]),
      );
      final adapter = SocialShareAdapter(
        exporter: output,
        copyText: (text) async {
          copied = text;
        },
        instagramAppId: '',
        openInstagramStory: (_, _) async => throw StateError('no Meta ID'),
        renderStory: (value, layout) async {
          expect(value, same(original));
          expect(layout, StoryLayout.overlay);
          return rendered;
        },
      );
      expect(
        await adapter.shareTo(
          original,
          ShareDestination.instagramStory,
          storyLayout: StoryLayout.overlay,
        ),
        ShareHandoff.storySheet,
      );
      expect(output.artifact!.imageBytes, same(rendered));
      expect(output.artifact!.caption, isEmpty);
      expect(copied, caption);
    },
  );
  test(
    'configured story integration opens composer; failed open uses OS fallback',
    () async {
      for (final opened in [true, false]) {
        final output = TestExport();
        final adapter = SocialShareAdapter(
          exporter: output,
          instagramAppId: '123',
          copyText: (_) async {},
          renderStory: (_, _) async => Uint8List.fromList([8]),
          openInstagramStory: (png, id) async {
            expect(id, '123');
            expect(png, [8]);
            return opened;
          },
        );
        final result = await adapter.shareTo(
          const ExportArtifact(caption: caption),
          ShareDestination.instagramStory,
        );
        expect(
          result,
          opened ? ShareHandoff.instagramStory : ShareHandoff.storySheet,
        );
        expect(output.artifact == null, opened);
      }
    },
  );
  test(
    'official LINE accepts only account IDs and safely encodes message',
    () async {
      Uri? opened;
      final adapter = SocialShareAdapter(
        openUrl: (url) async {
          opened = url;
          return true;
        },
      );
      await adapter.shareTo(
        const ExportArtifact(caption: caption),
        ShareDestination.lineOfficial,
        officialLineId: '@museum',
      );
      expect(opened!.pathSegments, ['R', 'oaMessage', '@museum', '']);
      expect(Uri.decodeComponent(opened!.query), caption);
      for (final id in ['https://example.com', '@a/?text=other', '', '@']) {
        await expectLater(
          adapter.shareTo(
            const ExportArtifact(caption: caption),
            ShareDestination.lineOfficial,
            officialLineId: id,
          ),
          throwsA(isA<InvalidLineAccount>()),
        );
      }
    },
  );
  test('unreviewed or changed content cannot reach social adapters', () async {
    final social = SocialRecorder();
    final c = PostCheckController(
      check: CheckDraft(perception: TestPerception(), context: TestContext()),
      images: TestImages(),
      exporter: TestExport(),
      socialExporter: social,
    );
    addTearDown(c.dispose);
    c.setCaption('連絡先 taro@example.com');
    await c.runCheck([]);
    await c.shareTo(ShareDestination.x);
    expect(social.calls, 0);
    for (final finding in c.findings) {
      c.decide(finding, ReviewDecision.hide);
    }
    await c.applyAndRecheck([]);
    await c.shareTo(ShareDestination.x);
    expect(social.calls, 1);
    expect(social.artifact!.caption, isNot(contains('taro@example.com')));
    c.setCaption('changed after checking');
    await c.shareTo(ShareDestination.line);
    expect(social.calls, 1);
  });
  testWidgets(
    'story rendering yields metadata-free 1080x1920 without silently cropping text',
    (tester) async {
      await tester.runAsync(() async {
        final source = img.Image(width: 120, height: 160);
        img.fill(source, color: img.ColorRgb8(220, 30, 40));
        final artifact = ExportArtifact(
          caption: 'Museum day\nTest caption',
          imageBytes: Uint8List.fromList(img.encodePng(source)),
        );
        for (final layout in StoryLayout.values) {
          final png = await const StoryImageComposer().compose(
            artifact,
            layout,
          );
          final decoded = img.decodePng(png)!;
          expect((decoded.width, decoded.height), (1080, 1920));
          expect(decoded.exif.isEmpty, isTrue);
          expect(decoded.getPixel(540, 700).r, greaterThan(150));
        }
        await expectLater(
          const StoryImageComposer().compose(
            ExportArtifact(
              caption: 'line\n' * 100,
              imageBytes: artifact.imageBytes,
            ),
            StoryLayout.card,
          ),
          throwsA(isA<StoryCaptionTooLong>()),
        );
        final png = await const StoryImageComposer().compose(
          const ExportArtifact(caption: 'Text-only story'),
          StoryLayout.card,
        );
        expect(img.decodePng(png)!.height, 1920);
      });
    },
  );
}
