import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Licence entries that Flutter does not collect automatically: bundled
/// models, training-data attribution and native SDKs (CocoaPods / Gradle).
/// Shown on the licence page together with the automatic package notices.
void registerAppLicenses() {
  LicenseRegistry.addLicense(() async* {
    final apache = await rootBundle.loadString(
      'assets/licenses/gemma-4-apache-2.0.txt', // plain Apache 2.0 text
    );
    yield LicenseEntryWithLineBreaks(['Gemma 4 E2B (Google)'], apache);
    yield LicenseEntryWithLineBreaks(
      ['EfficientDet-Lite0 (TensorFlow / Google)'],
      '${await rootBundle.loadString('assets/licenses/efficientdet-modification-notice.txt')}\n$apache',
    );
    // Native SDKs linked through CocoaPods / Gradle are not covered by the
    // automatic Flutter package notices, so they are listed here.
    yield LicenseEntryWithLineBreaks(
      [
        'Native SDKs (Firebase, Google Sign-In, MediaPipe, TensorFlow Lite, LiteRT-LM)',
      ],
      '${await rootBundle.loadString('assets/licenses/native-sdk-notices.txt')}\n\n$apache',
    );
    yield LicenseEntryWithLineBreaks([
      'ML Kit, Google Maps SDK, Google Play services',
    ], await rootBundle.loadString('assets/licenses/google-sdk-terms.txt'));
    yield LicenseEntryWithLineBreaks([
      'nanopb',
    ], await rootBundle.loadString('assets/licenses/nanopb-zlib.txt'));
    yield LicenseEntryWithLineBreaks(
      ['Open Images Dataset V7 (Google LLC)'],
      await rootBundle.loadString(
        'assets/licenses/open-images-attribution.txt',
      ),
    );
  });
}
