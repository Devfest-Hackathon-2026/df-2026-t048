#!/bin/bash
set -euo pipefail

task_source="$(cd "$(dirname "$0")/.." && pwd)"
task_build_number="${1:-1}"
task_signing="${POSTCHECK_ANDROID_KEY_PROPERTIES:-$HOME/Library/Application Support/PostCheck/android-signing/key.properties}"
if [ ! -f "$task_signing" ]; then
  printf 'Upload signing configuration is missing: %s\n' "$task_signing" >&2
  exit 1
fi
export POSTCHECK_ANDROID_KEY_PROPERTIES="$task_signing"
export POSTCHECK_BUILD_ROOT="${POSTCHECK_ANDROID_BUILD_ROOT:-$HOME/Library/Caches/PostCheckAndroidInternal}"
task_staged="$(bash "$task_source/scripts/stage_build.sh")"
# The experimental model remains in source for local experiments only.
rm -f "$task_staged/assets/screen_detector/whiteboard_experiment.tflite" \
  "$task_staged/assets/screen_detector/docs_experiment.tflite"
if [ ! -f "$task_staged/assets/screen_detector/efficientdet_lite0.tflite" ]; then
  printf 'Run scripts/setup_screen_detector.sh before packaging.\n' >&2
  exit 1
fi
cd "$task_staged"
flutter pub get
# Keep the published venue API; do not enable the native Android map until its
# Android-restricted key and Play signing certificate have been configured.
flutter build appbundle --release --build-number="$task_build_number" \
  --dart-define=RULE_API_URL=https://postcheck-admin-0521532178.web.app \
  --dart-define=MAPS_ENABLED=false
python3 - "$task_staged/build/app/outputs/bundle/release/app-release.aab" <<'PY'
import sys
import zipfile
from pathlib import Path

bundle = Path(sys.argv[1])
with zipfile.ZipFile(bundle) as archive:
    names = archive.namelist()
    forbidden = [n for n in names if n.endswith('.litertlm')
                 or 'whiteboard_experiment' in n or 'docs_experiment' in n or n.endswith('.local.json')]
    if forbidden:
        raise SystemExit('Distribution contains excluded assets: ' + ', '.join(forbidden))
    if not any(n.endswith('/efficientdet_lite0.tflite') for n in names):
        raise SystemExit('The standard detector model is missing.')
print(f'Checked distribution assets: {bundle} ({bundle.stat().st_size} bytes)')
PY
