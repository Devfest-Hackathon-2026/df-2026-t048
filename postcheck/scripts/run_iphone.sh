#!/bin/bash
set -euo pipefail
task_staged="$(bash "$(dirname "$0")/stage_build.sh")"
cd "$task_staged"
flutter pub get
if [ "$#" -gt 0 ]; then
  task_device="$1"
  shift
  flutter run --release -d "$task_device" "$@"
else
  flutter run --release
fi
