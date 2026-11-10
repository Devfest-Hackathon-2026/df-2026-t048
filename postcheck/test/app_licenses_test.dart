import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postcheck/app_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'bundled models, training data and native SDKs are on the licence page',
    () async {
      registerAppLicenses();
      final entries = await LicenseRegistry.licenses.toList();
      String textOf(String package) => entries
          .where((e) => e.packages.contains(package))
          .expand((e) => e.paragraphs)
          .map((p) => p.text)
          .join('\n');
      final efficientDet = textOf('EfficientDet-Lite0 (TensorFlow / Google)');
      expect(efficientDet, contains('modified versions'));
      expect(efficientDet, contains('Apache License'));
      final native = textOf(
        'Native SDKs (Firebase, Google Sign-In, MediaPipe, TensorFlow Lite, LiteRT-LM)',
      );
      expect(native, contains('MediaPipe Tasks Vision 0.10.26.1'));
    expect(native, contains('removes the GMLImage.o object'));
      expect(native, contains('Apache License'));
      expect(
        textOf('ML Kit, Google Maps SDK, Google Play services'),
        contains('https://developers.google.com/ml-kit/terms'),
      );
      expect(textOf('nanopb'), contains('Petteri Aimonen'));
      final openImages = textOf('Open Images Dataset V7 (Google LLC)');
      expect(
        openImages,
        contains('Images used to train whiteboard_experiment'),
      );
      expect(openImages, contains('Images used to train docs_experiment'));
      expect(textOf('Gemma 4 E2B (Google)'), contains('Apache License'));
    },
  );
}
