#!/bin/bash
set -euo pipefail

# GitHub Releases向け。キーはGradleプロパティ、署名はGit外で管理する。
task_source="$(cd "$(dirname "$0")/.." && pwd)"
task_build_number="${1:-1}"
task_signing="${POSTCHECK_ANDROID_KEY_PROPERTIES:-$HOME/Library/Application Support/PostCheck/android-signing/key.properties}"
if [ ! -f "$task_signing" ]; then
  printf 'Release signing configuration is missing: %s\n' "$task_signing" >&2
  exit 1
fi
export POSTCHECK_ANDROID_KEY_PROPERTIES="$task_signing"
export POSTCHECK_BUILD_ROOT="${POSTCHECK_ANDROID_APK_BUILD_ROOT:-$HOME/Library/Caches/PostCheckAndroidApk}"
task_staged="$(bash "$task_source/scripts/stage_build.sh")"
rm -f "$task_staged/assets/screen_detector/whiteboard_experiment.tflite" \
  "$task_staged/assets/screen_detector/docs_experiment.tflite"
if [ ! -f "$task_staged/assets/screen_detector/efficientdet_lite0.tflite" ]; then
  printf 'Run scripts/setup_screen_detector.sh before packaging.\n' >&2
  exit 1
fi
cd "$task_staged"
flutter pub get
flutter build apk --release --build-number="$task_build_number" \
  --dart-define=RULE_API_URL=https://postcheck-admin-0521532178.web.app \
  --dart-define=MAPS_ENABLED=true
python3 - "$task_staged/build/app/outputs/flutter-apk/app-release.apk" <<'PY'
import sys
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

apk = Path(sys.argv[1])
manifest = Path('build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml')
android = '{http://schemas.android.com/apk/res/android}'
root = ET.parse(manifest).getroot()
if not any(node.get(android + 'name') == 'com.google.android.geo.API_KEY'
           and node.get(android + 'value', '').strip()
           for node in root.findall('./application/meta-data')):
    raise SystemExit('Set POSTCHECK_MAPS_API_KEY in Gradle properties before distributing this APK.')
with zipfile.ZipFile(apk) as archive:
    names = archive.namelist()
    forbidden = [n for n in names if n.endswith(('.litertlm', '.local.json', '.jks', '.keystore'))
                 or 'whiteboard_experiment' in n or 'docs_experiment' in n or n.endswith('key.properties')]
    if forbidden:
        raise SystemExit('Distribution contains excluded assets: ' + ', '.join(forbidden))
    if not any(n.endswith('/efficientdet_lite0.tflite') for n in names):
        raise SystemExit('The standard detector model is missing.')
print(f'Checked distribution assets: {apk} ({apk.stat().st_size} bytes)')
PY
