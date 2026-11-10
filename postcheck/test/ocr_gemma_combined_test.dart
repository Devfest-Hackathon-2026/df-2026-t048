import 'package:postcheck_rules/contracts.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:postcheck/adapters/mlkit_perception.dart';
import 'package:postcheck/adapters/ocr_preprocessing.dart';
import 'package:postcheck/adapters/image_processing.dart';
import 'package:postcheck/application/analysis_gate.dart';
import 'package:postcheck/application/ai_contract.dart';
import 'package:postcheck/application/check_draft.dart';
import 'package:postcheck/application/ocr_merge.dart';
import 'package:postcheck/domain/models.dart';
import 'package:postcheck/domain/ports.dart';
import 'package:postcheck/domain/preferences.dart';
import 'package:postcheck/presentation/postcheck_controller.dart';
import 'controller_test.dart' show TestImages, TestExport;

const box = ImageRegion(.1, .2, .4, .05);
OcrReading reading(
  String text, {
  ImageRegion region = box,
  String pass = 'original',
}) => OcrReading(text: text, region: region, pass: pass);
PhotoInput photo() => PhotoInput(bytes: Uint8List(0), width: 100, height: 100);

class CountingContext implements ContextAnalysisPort {
  int calls = 0;
  final started = Completer<void>();
  Observations? received;
  Completer<ContextResult>? pending;
  @override
  Future<ContextResult> analyze(
    DraftInput d,
    Observations o, {
    PublishedVenue? venue,
  }) async {
    calls++;
    if (!started.isCompleted) started.complete();
    received = o;
    return pending == null
        ? const ContextResult(status: 'test')
        : pending!.future;
  }
}

class Engine implements PerceptionEngine {
  final calls = <String>[];
  Completer<List<OcrReading>>? delayed;
  final extraStarted = Completer<void>();
  bool closed = false;
  bool throwOnExtra = false;
  @override
  Future<List<OcrReading>> read(OcrVariant variant, int script) async {
    calls.add('${variant.pass}:$script');
    if (variant.pass != 'original' && !extraStarted.isCompleted) {
      extraStarted.complete();
    }
    if (variant.pass != 'original' && throwOnExtra) throw StateError('fixture');
    if (variant.pass != 'original' && delayed != null) return delayed!.future;
    return [
      reading(
        script == 0 ? 'fixture@example.com' : 'fixture@examp1e.com',
        pass: variant.pass,
      ),
    ];
  }

  @override
  Future<List<ImageRegion>> faces(PhotoInput p) async {
    calls.add('face');
    return [];
  }

  @override
  Future<List<ImageRegion>> devices(PhotoInput p) async {
    calls.add('device');
    return [];
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

MlKitPerceptionAdapter adapter(
  Engine engine,
  Directory root, {
  bool enhanced = true,
  Duration extraBudget = const Duration(seconds: 10),
  AnalysisGate? gate,
}) => MlKitPerceptionAdapter(
  enhanced: enhanced,
  gate: gate ?? AnalysisGate(),
  extraBudget: extraBudget,
  engineFactory: (_) => engine,
  temporaryRoot: () async => root,
  variantBuilder: (p, i) async => OcrVariant(
    p,
    const ImageRegion(0, 0, 1, 1),
    i == 0 ? 'gamma' : 'tile',
    tileId: i == 0 ? null : i - 1,
  ),
);

class BrokenPerception implements PerceptionPort {
  @override
  Future<Observations> inspect(PhotoInput p) async =>
      throw StateError('fixture');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'same-line alternatives retain contact and registered word evidence in one decision',
    () {
      final grouped = groupOcrReadings([
        reading('internal@example.com'),
        reading('internal@examp1e.com', pass: 'gamma'),
        reading(
          'example.com',
          region: const ImageRegion(.26, .2, .24, .05),
          pass: 'tile',
        ),
      ]);
      expect(grouped, lengthHas(1));
      final items = const RuleChecker(
        privateWords: ['internal'],
      ).check(const DraftInput(caption: ''), Observations(blocks: grouped));
      expect(items, lengthHas(1));
      expect(items.single.kind, FindingKind.contact);
      expect(
        items.single.evidence.any((f) => f.kind == FindingKind.privateWord),
        isTrue,
      );
      expect(
        items.single.evidence.map((f) => f.excerpt),
        contains('internal@examp1e.com'),
      );
      // A merged row stays while any of its evidence is switched on.
      expect(
        const ReviewPreferences(
          disabledTargets: {CheckTarget.contact},
        ).shows(items.single),
        isTrue,
      );
      expect(
        ReviewPreferences(
          disabledTargets: {
            for (final e in items.single.evidence) CheckTarget.of(e),
          },
        ).shows(items.single),
        isFalse,
      );
    },
  );
  test(
    'repeated lines, separate words and neighboring lines do not collapse',
    () {
      final grouped = groupOcrReadings([
        reading('same'),
        reading('same', region: const ImageRegion(.1, .3, .4, .05)),
        reading('same', region: const ImageRegion(.6, .2, .3, .05)),
        reading('same', region: const ImageRegion(.1, .2, .4, .05)),
      ]);
      expect(grouped, lengthHas(3));
    },
  );
  test('ambiguous partial overlaps never concatenate a new contact', () {
    final grouped = groupOcrReadings([
      reading('abc@', region: const ImageRegion(.1, .2, .25, .05)),
      reading(
        'example.com',
        region: const ImageRegion(.3, .2, .3, .05),
        pass: 'tile',
      ),
    ]);
    expect(grouped, lengthHas(2));
    expect(
      grouped.every((b) => b.texts.every((t) => t != 'abc@example.com')),
      isTrue,
    );
  });
  test('mask covers all slightly shifted readings in a group', () {
    final readings = [
      reading('abc'),
      reading(
        'abc',
        region: const ImageRegion(.105, .201, .4, .05),
        pass: 'gamma',
      ),
    ];
    final group = groupOcrReadings(readings).single;
    for (final r in readings) {
      expect(group.region.x, lessThanOrEqualTo(r.region.x));
      expect(group.region.y, lessThanOrEqualTo(r.region.y));
      expect(
        group.region.x + group.region.width,
        greaterThanOrEqualTo(r.region.x + r.region.width),
      );
      expect(
        group.region.y + group.region.height,
        greaterThanOrEqualTo(r.region.y + r.region.height),
      );
    }
  });
  test(
    'Gemma reason joins only its explicit OCR group and preserves sources',
    () {
      final basic = const RuleChecker().check(
        const DraftInput(caption: ''),
        const Observations(
          blocks: [TextBlock(id: 'b0', text: 'a@example.com', region: box)],
        ),
      );
      final ai = parseContextFindings(
        '{"findings":[{"question":"資料を公開しますか？","blockId":"b0"}]}',
        DraftInput(caption: '', photo: photo()),
        const Observations(
          blocks: [TextBlock(id: 'b0', text: 'a@example.com', region: box)],
        ),
      );
      final merged = mergeReviewFindings([...basic, ...ai]);
      expect(merged, lengthHas(1));
      expect(merged.single.sources, {FindingSource.mlKit, FindingSource.gemma});
      expect(merged.single.related.single.question, '資料を公開しますか？');
      expect(merged.single.id, 'block-b0');
    },
  );
  test(
    'Gemma whole-photo suggestions stay separate from measured OCR targets',
    () {
      final input = DraftInput(caption: '', photo: photo());
      final ai = parseContextFindings(
        '{"findings":[{"question":"背景の名札を確認しましたか？"}]}',
        input,
        const Observations(),
      );
      expect(ai.single.target, isA<WholePhotoTarget>());
      final basic = const RuleChecker().check(
        input,
        const Observations(
          blocks: [TextBlock(id: 'b0', text: '名札', region: box)],
        ),
      );
      expect(mergeReviewFindings([...basic, ...ai]), lengthHas(2));
    },
  );
  test(
    'bounded AI input rejects omitted IDs, unknown fields, mixed refs and ambiguous quotes',
    () {
      final draft = DraftInput(caption: 'repeat repeat', photo: photo());
      final all = Observations(
        blocks: [
          for (var i = 0; i < 40; i++)
            TextBlock(id: 'b$i', text: 'hello', region: box),
        ],
      );
      final input = buildContextInput(draft, all);
      expect(input.omitted, isTrue);
      final items = [
        {'question': 'q', 'blockId': 'b39'},
        {'question': 'q', 'blockId': 'b0', 'captionQuote': 'repeat'},
        {'question': 'q', 'captionQuote': 'repeat'},
        {'question': 'q', 'blockId': 1},
        {'question': 'q', 'blockId': 'b0', 'x': .3},
        {'question': 'q', 'blockId': 'b0'},
      ];
      expect(
        parseContextFindings(
          jsonEncode({'findings': items.take(5).toList()}),
          input.draft,
          input.observations,
        ),
        isEmpty,
      );
      expect(
        parseContextFindings(
          jsonEncode({
            'findings': [items.last],
          }),
          input.draft,
          input.observations,
        ),
        lengthHas(1),
      );
    },
  );
  test(
    'quotes beyond the sent prefix and repeated in the original are rejected',
    () {
      final draft = DraftInput(
        caption: 'hello${'x' * 3000}hello',
        photo: photo(),
      );
      final input = buildContextInput(draft, const Observations());
      expect(
        parseContextFindings(
          '{"findings":[{"question":"q","captionQuote":"hello"}]}',
          input.draft,
          input.observations,
          originalDraft: draft,
        ),
        isEmpty,
      );
    },
  );
  test(
    'AI input budgets alternatives and reports omission without damaging surrogate pairs',
    () {
      final text = '😀' * 200;
      final input = buildContextInput(
        DraftInput(caption: '😀' * 1700),
        Observations(
          blocks: [
            for (var i = 0; i < 32; i++)
              TextBlock(id: 'b$i', text: text, region: box),
          ],
        ),
      );
      final payload = jsonDecode(input.prompt) as Map;
      expect(payload['inputOmitted'], isTrue);
      final rows = payload['ocrBlocks'] as List;
      expect(
        rows.fold<int>(0, (n, row) => n + (row['text'] as String).length),
        lessThanOrEqualTo(1600),
      );
      for (final row in rows) {
        expect(
          (row['text'] as String).runes.every((c) => c == 0x1f600),
          isTrue,
        );
      }
    },
  );
  test(
    'prompt versions share output contract but v2 independently inspects photos',
    () {
      expect(contextSystemPromptFor('ja'), contains('画像自体も確認'));
      expect(contextSystemPromptFor('en'), contains('英語の短い質問'));
      expect(
        contextSystemPromptFor('ja', tuned: false),
        legacyContextSystemPrompt,
      );
    },
  );
  group('raster variants', () {
    for (final (w, h) in [(1009, 607), (607, 1009)]) {
      test(
        'tile mapping accounts for overlap, rounded size and clipping $w x $h',
        () {
          final image = img.Image(width: w, height: h);
          final p = PhotoInput(
            bytes: img.encodePng(image),
            width: w,
            height: h,
          );
          final tiles = [
            for (var i = 1; i <= 4; i++) prepareOcrVariant((p, i)),
          ];
          expect(tiles[0].source.x, 0);
          expect(
            tiles[0].source.x + tiles[0].source.width,
            greaterThan(tiles[1].source.x),
          );
          expect(
            tiles.last.source.x + tiles.last.source.width,
            closeTo(1, 1e-9),
          );
          expect(
            tiles.last.source.y + tiles.last.source.height,
            closeTo(1, 1e-9),
          );
          for (final v in tiles) {
            final mapped = v.mapBox(
              0,
              0,
              v.photo.width.toDouble(),
              v.photo.height.toDouble(),
            )!;
            expect(mapped.x, closeTo(v.source.x, 1e-9));
            expect(mapped.width, closeTo(v.source.width, 1e-9));
            expect(v.mapBox(-10, -10, 20, 20)!.isValid, isTrue);
            expect(v.mapBox(double.nan, 0, 2, 2), isNull);
            expect(
              v.photo.width,
              lessThanOrEqualTo((v.source.width * w * 2).ceil()),
            );
          }
        },
      );
    }
    test('gamma lightens a dark fixture and strips metadata', () {
      final image = img.Image(width: 20, height: 20);
      img.fill(image, color: img.ColorRgb8(40, 40, 40));
      image.exif.imageIfd['Artist'] = 'fictional fixture';
      final p = PhotoInput(bytes: img.encodeJpg(image), width: 20, height: 20);
      final v = prepareOcrVariant((p, 0));
      final decoded = img.decodeJpg(v.photo.bytes)!;
      expect(decoded.getPixel(10, 10).r, greaterThan(40));
      expect(decoded.exif.isEmpty, isTrue);
      expect(v.mapBox(0, 0, 20, 20)!.width, 1);
    });
    test('EXIF orientation is baked before tile coordinates are assigned', () {
      final image = img.Image(width: 80, height: 40);
      image.exif.imageIfd['Orientation'] = 6;
      final prepared = prepareRaster(Uint8List.fromList(img.encodeJpg(image)));
      expect(prepared.width, 40);
      expect(prepared.height, 80);
      final tile = prepareOcrVariant((prepared, 4));
      expect(tile.source.x + tile.source.width, closeTo(1, 1e-9));
      expect(tile.source.y + tile.source.height, closeTo(1, 1e-9));
    });
  });
  group('progressive lifecycle', () {
    late Directory root;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('postcheck-unit-');
    });
    tearDown(() async {
      await root.delete(recursive: true);
    });
    test(
      'base detectors run once and extra OCR is sequential with a 12-call cap',
      () async {
        final engine = Engine();
        final perception = adapter(engine, root);
        final states = <bool>[];
        final result = await perception.inspectProgressively(
          photo(),
          budget: const Duration(seconds: 2),
          shouldStop: () => false,
          onPartial: (o, ready) => states.add(ready),
        );
        expect(engine.calls.where((c) => c.contains(':')), lengthHas(12));
        expect(engine.calls.where((c) => c == 'face'), lengthHas(1));
        expect(engine.calls.where((c) => c == 'device'), lengthHas(1));
        expect(
          engine.calls.indexOf('device'),
          lessThan(engine.calls.indexOf('gamma:0')),
        );
        expect(states, containsAll([false, true]));
        expect(result.blocks.single.texts, contains('fixture@example.com'));
        expect(engine.closed, isTrue);
        expect(perception.isRunning, isFalse);
      },
    );
    test('extra failures preserve base readings', () async {
      final engine = Engine()..throwOnExtra = true;
      final result = await adapter(engine, root).inspect(photo());
      expect(result.blocks.single.texts, contains('fixture@example.com'));
      expect(result.notes, isNotEmpty);
    });
    test(
      'additional deadline returns partial result and holds resources until SDK ends',
      () async {
        final gate = AnalysisGate();
        final engine = Engine()..delayed = Completer<List<OcrReading>>();
        final perception = adapter(
          engine,
          root,
          gate: gate,
          extraBudget: const Duration(milliseconds: 30),
        );
        final context = CountingContext();
        final report = await CheckDraft(
          perception: perception,
          context: context,
          perceptionBudget: const Duration(seconds: 2),
        )(DraftInput(caption: '', photo: photo()));
        expect(report.findings.single.kind, FindingKind.contact);
        expect(report.notes, isNotEmpty);
        expect(context.calls, 0);
        expect(engine.closed, isFalse);
        expect(gate.busy, isTrue);
        final other = await perception.inspect(photo());
        expect(other.blocks, isEmpty);
        expect(other.notes, isNotEmpty);
        engine.delayed!.complete([reading('late@example.com')]);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(engine.closed, isTrue);
        expect(gate.busy, isFalse);
        expect(report.findings.single.excerpt, 'fixture@example.com');
        expect(engine.calls.where((c) => c.startsWith('tile')), isEmpty);
      },
    );
    test(
      'user finishes during extra OCR without waiting for native completion',
      () async {
        final engine = Engine()..delayed = Completer<List<OcrReading>>();
        final context = CountingContext();
        final c = PostCheckController(
          check: CheckDraft(
            perception: adapter(engine, root),
            context: context,
          ),
          images: TestImages(),
          exporter: TestExport(),
        );
        addTearDown(c.dispose);
        await c.loadPhoto(Uint8List(1));
        final work = c.runCheck([]);
        await engine.extraStarted.future;
        expect(c.canFinishCheck, isTrue);
        c.finishWithCurrentResults();
        await work;
        expect(c.report, isNotNull);
        expect(c.findings.single.kind, FindingKind.contact);
        expect(context.calls, 0);
        expect(c.busy, isFalse);
        engine.delayed!.completeError(StateError('late SDK failure'));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(engine.closed, isTrue);
        expect(c.findings.single.kind, FindingKind.contact);
      },
    );
    test(
      'OCR-only mode avoids extra work and cancellation avoids new calls',
      () async {
        final engine = Engine();
        final result = await adapter(
          engine,
          root,
          enhanced: false,
        ).inspect(photo());
        expect(engine.calls.where((c) => c.contains(':')), lengthHas(2));
        expect(result.blocks, isNotEmpty);
        final cancelled = Engine();
        await adapter(cancelled, root).inspectProgressively(
          photo(),
          budget: const Duration(seconds: 1),
          shouldStop: () => true,
          onPartial: (_, _) {},
        );
        expect(cancelled.calls, isEmpty);
      },
    );
    test('a failed perception still returns caption checks', () async {
      final report = await CheckDraft(
        perception: BrokenPerception(),
        context: CountingContext(),
      )(DraftInput(caption: 'contact@example.com', photo: photo()));
      expect(report.findings.single.kind, FindingKind.contact);
      expect(report.notes, isNotEmpty);
    });
    test(
      'finish during Gemma freezes basic findings and late errors are handled',
      () async {
        final context = CountingContext()..pending = Completer<ContextResult>();
        final c = PostCheckController(
          check: CheckDraft(perception: BrokenPerception(), context: context),
          images: TestImages(),
          exporter: TestExport(),
        );
        addTearDown(c.dispose);
        c.setCaption('a@example.com');
        final work = c.runCheck([]);
        await context.started.future;
        c.finishWithCurrentResults();
        await work;
        expect(c.findings.single.kind, FindingKind.contact);
        expect(c.report!.aiStatus, contains('完了しませんでした'));
        context.pending!.completeError(StateError('late'));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(c.findings.single.kind, FindingKind.contact);
      },
    );
    test(
      'actionable OCR after the 32nd line is prioritized for Gemma',
      () async {
        final context = CountingContext();
        // CheckDraft also supports simple pre-existing ports.
        final perception = _ManyBlocks();
        await CheckDraft(perception: perception, context: context)(
          DraftInput(caption: '', photo: photo()),
        );
        final input = buildContextInput(
          DraftInput(caption: '', photo: photo()),
          context.received!,
        );
        expect(input.observations.blocks.first.id, 'important');
      },
    );
  });
}

Matcher lengthHas(int n) => hasLength(n);

class _ManyBlocks implements PerceptionPort {
  @override
  Future<Observations> inspect(PhotoInput p) async => Observations(
    blocks: [
      for (var i = 0; i < 40; i++)
        TextBlock(
          id: 'plain$i',
          text: 'plain',
          region: ImageRegion(.1, i / 100, .3, .005),
        ),
      const TextBlock(
        id: 'important',
        text: 'fixture@example.com',
        region: ImageRegion(.1, .9, .3, .01),
      ),
    ],
  );
}
