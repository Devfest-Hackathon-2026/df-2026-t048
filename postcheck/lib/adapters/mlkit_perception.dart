import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    hide TextBlock;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';
import '../application/analysis_gate.dart';
import '../application/ocr_merge.dart';
import '../domain/models.dart';
import '../domain/ports.dart';
import 'screen_device_detector.dart';
import 'ocr_preprocessing.dart';
import 'ocr_scripts.dart';

/// SDK boundary, also injectable for lifecycle/deadline tests without a device.
abstract interface class PerceptionEngine {
  Future<List<OcrReading>> read(OcrVariant variant, int script);
  Future<List<ImageRegion>> faces(PhotoInput photo);
  Future<List<ImageRegion>> devices(PhotoInput photo);
  Future<void> close();
}

final class MlKitPerceptionAdapter implements ProgressivePerceptionPort {
  MlKitPerceptionAdapter({
    this.enhanced = const bool.fromEnvironment(
      'POSTCHECK_OCR_ENHANCED',
      defaultValue: true,
    ),
    this.extraBudget = const Duration(seconds: 10),
    AnalysisGate? gate,
    this.engineFactory,
    this.temporaryRoot,
    this.variantBuilder,
  }) : gate = gate ?? AnalysisGate.shared;
  final bool enhanced;
  final Duration extraBudget;
  final AnalysisGate gate;
  final PerceptionEngine Function(Directory directory)? engineFactory;
  final Future<Directory> Function()? temporaryRoot;
  final Future<OcrVariant> Function(PhotoInput photo, int index)?
  variantBuilder;
  @override
  bool get isRunning => gate.busy;
  @override
  Duration get additionalBudget => extraBudget;

  @override
  Future<Observations> inspect(PhotoInput photo) => inspectProgressively(
    photo,
    budget: const Duration(seconds: 45),
    shouldStop: () => false,
    onPartial: (_, _) {},
  );

  @override
  Future<Observations> inspectProgressively(
    PhotoInput photo, {
    required Duration budget,
    required bool Function() shouldStop,
    required void Function(Observations, bool) onPartial,
    void Function(String)? onProgress,
  }) async {
    if (!gate.acquire()) {
      return const Observations(notes: ['前の端末内処理が終了するまで、写真は目視で確認してください。']);
    }
    final watch = Stopwatch()..start();
    final readings = <OcrReading>[];
    final faces = <ImageRegion>[], devices = <ImageRegion>[];
    final notes = <String>[];
    var basicComplete = false;
    Directory? directory;
    PerceptionEngine? engine;
    bool stopped() => shouldStop() || watch.elapsed >= budget;
    Observations snapshot() => Observations(
      blocks: groupOcrReadings(readings),
      faces: List.unmodifiable(faces),
      devices: List.unmodifiable(devices),
      notes: List.unmodifiable(notes),
    );
    void publish() {
      if (!stopped()) onPartial(snapshot(), basicComplete);
    }

    try {
      final root = await (temporaryRoot?.call() ?? getTemporaryDirectory());
      if (stopped()) return snapshot();
      final scanRoot = await Directory(
        '${root.path}/postcheck-scan',
      ).create(recursive: true);
      directory = await scanRoot.createTemp('scan-');
      if (stopped()) return snapshot();
      engine = engineFactory?.call(directory) ?? _MlKitEngine(directory);
      final original = OcrVariant(
        photo,
        const ImageRegion(0, 0, 1, 1),
        'original',
      );
      for (var script = 0; script < postCheckOcrScripts.length; script++) {
        if (stopped()) return snapshot();
        try {
          readings.addAll(await engine.read(original, script));
        } catch (_) {
          notes.add('一部の文字認識が完了しませんでした。写り込んだ文字を目視で確認してください。');
        }
        publish();
      }
      if (stopped()) return snapshot();
      try {
        faces.addAll(await engine.faces(photo));
      } catch (_) {
        notes.add('人物の検出が完了しませんでした。写っている方を目視で確認してください。');
      }
      publish();
      if (stopped()) return snapshot();
      try {
        devices.addAll(await engine.devices(photo));
      } catch (_) {
        notes.add('パソコン・スマホの自動検出が利用できません。写り込みを目視で確認してください。');
      }
      basicComplete = true;
      publish();
      if (!enhanced || stopped()) return snapshot();
      onProgress?.call('小さい文字や薄暗い文字を追加で確認しています');
      final extraStarted = watch.elapsed;
      bool extraStopped() =>
          stopped() || watch.elapsed - extraStarted >= extraBudget;
      for (var variantIndex = 0; variantIndex < 5; variantIndex++) {
        if (extraStopped()) {
          notes.add('追加の文字認識を途中で終了しました。取得済みの結果を表示しています。');
          break;
        }
        try {
          final variant =
              await (variantBuilder?.call(photo, variantIndex) ??
                  compute(prepareOcrVariant, (photo, variantIndex)));
          for (var script = 0; script < postCheckOcrScripts.length; script++) {
            if (extraStopped()) break;
            readings.addAll(await engine.read(variant, script));
            publish();
          }
        } catch (_) {
          notes.add('追加の文字認識を一部実行できませんでした。基本チェックの結果を表示しています。');
        }
      }
      return snapshot();
    } finally {
      // A caller may already have returned its frozen partial report. This owner
      // retains native resources and files until the outstanding SDK call ends.
      try {
        try {
          await engine?.close();
        } catch (_) {
          /* Best-effort cleanup. */
        }
        if (directory != null && await directory.exists()) {
          await directory.delete(recursive: true);
        }
      } finally {
        gate.release();
      }
    }
  }
}

final class _MlKitEngine implements PerceptionEngine {
  _MlKitEngine(this.directory);
  final Directory directory;
  final recognizers = [
    for (final script in postCheckOcrScripts) TextRecognizer(script: script),
  ];
  final detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: .04,
    ),
  );
  Future<InputImage> _input(PhotoInput photo, String name) async {
    final file = File('${directory.path}/$name.jpg');
    await file.writeAsBytes(photo.bytes, flush: true);
    return InputImage.fromFilePath(file.path);
  }

  @override
  Future<List<OcrReading>> read(OcrVariant variant, int script) async {
    final input = await _input(variant.photo, 'ocr');
    final recognized = await recognizers[script].processImage(input);
    return [
      for (final line in recognized.blocks.expand((b) => b.lines))
        if (variant.mapBox(
              line.boundingBox.left,
              line.boundingBox.top,
              line.boundingBox.width,
              line.boundingBox.height,
            )
            case final region?)
          if (line.text.trim().isNotEmpty)
            OcrReading(
              text: line.text.trim(),
              region: region,
              pass: variant.pass,
              tileId: variant.tileId,
            ),
    ];
  }

  @override
  Future<List<ImageRegion>> faces(PhotoInput photo) async {
    final input = await _input(photo, 'original');
    return [
      for (final face in await detector.processImage(input))
        ?ImageRegion.fromPixels(
          face.boundingBox.left,
          face.boundingBox.top,
          face.boundingBox.width,
          face.boundingBox.height,
          photo.width,
          photo.height,
        ),
    ];
  }

  @override
  Future<List<ImageRegion>> devices(PhotoInput photo) async {
    // iOS and Android each register `postcheck/screen_detector` natively.
    if (!Platform.isIOS && !Platform.isAndroid) {
      throw UnsupportedError('Device detection requires iOS or Android');
    }
    final input = await _input(photo, 'original');
    return const ScreenDeviceDetector(
      timeout: null,
    ).inspectFile(input.filePath!, photo.width, photo.height);
  }

  @override
  Future<void> close() async {
    for (final recognizer in recognizers) {
      try {
        await recognizer.close();
      } catch (_) {
        /* Continue releasing peers. */
      }
    }
    await detector.close();
  }
}
