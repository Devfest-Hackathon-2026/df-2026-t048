import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:postcheck/adapters/image_processing.dart';
import 'package:postcheck/application/check_draft.dart';
import 'package:postcheck/domain/models.dart';
import 'package:postcheck/domain/ports.dart';
import 'package:postcheck/presentation/postcheck_controller.dart';
import 'controller_test.dart' show TestContext, TestExport;
import 'freeform_mask_test.dart' show fixture;

class NoFindings implements PerceptionPort {
  @override
  Future<Observations> inspect(PhotoInput photo) async => const Observations();
}

class Destination implements PhotoSavePort, FileSavePort {
  Uint8List? savedPhoto, savedFile;
  bool cancel = false, deny = false;
  @override
  Future<void> savePhoto(Uint8List png) async {
    if (deny) throw PhotoPermissionDenied();
    savedPhoto = png;
  }

  @override
  Future<bool> saveFile(Uint8List png) async {
    if (cancel) return false;
    savedFile = png;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PostCheckController c;
  late Destination destination;
  late TestExport sharing;
  setUp(() {
    destination = Destination();
    sharing = TestExport();
    c = PostCheckController(
      check: CheckDraft(perception: NoFindings(), context: TestContext()),
      images: const RasterImageAdapter(),
      exporter: sharing,
      saver: destination,
      fileSaver: destination,
    );
  });
  tearDown(() => c.dispose());
  test(
    'photos, files and sharing receive the flattened edited image',
    () async {
      await c.loadPhoto(fixture().bytes);
      await c.runCheck([]);
      await c.setRedactionStyle(RedactionStyle.black);
      await c.addManualRegion(const ImageRegion(.2, .2, .5, .5));
      expect(await c.savePhoto(), isFalse);
      expect(await c.saveFile(), isFalse);
      await c.applyAndRecheck([]);
      expect(c.canExport, isTrue);
      expect(await c.savePhoto(), isTrue);
      expect(await c.saveFile(), isTrue);
      await c.share();
      for (final bytes in [
        destination.savedPhoto!,
        destination.savedFile!,
        sharing.artifact!.imageBytes!,
      ]) {
        final image = img.decodePng(bytes)!;
        expect(image.getPixel(40, 40).r, 0);
        expect(image.getPixel(5, 5).r, greaterThan(0));
        expect(image.exif.isEmpty, isTrue);
      }
    },
  );
  test(
    'file cancellation is silent, permission denial can be retried',
    () async {
      await c.loadPhoto(fixture().bytes);
      await c.runCheck([]);
      destination.cancel = true;
      expect(await c.saveFile(), isFalse);
      expect(c.error, isEmpty);
      expect(c.busy, isFalse);
      destination.deny = true;
      expect(await c.savePhoto(), isFalse);
      expect(c.photoPermissionDenied, isTrue);
      c.retryExport();
      destination.deny = false;
      expect(await c.savePhoto(), isTrue);
      expect(c.photoPermissionDenied, isFalse);
    },
  );
}
