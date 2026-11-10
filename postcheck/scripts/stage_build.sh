#!/bin/bash
set -euo pipefail
task_source="$(cd "$(dirname "$0")/.." && pwd)"
task_cache="${POSTCHECK_BUILD_ROOT:-$HOME/Library/Caches/PostCheckMVP}"
task_staged="$task_cache/source"
mkdir -p "$task_staged"
mkdir -p "$task_cache/packages/postcheck_rules/lib"
rsync -rlt --delete --exclude='.dart_tool' --exclude='build' --exclude='test' \
  "$task_source/../packages/postcheck_rules/" "$task_cache/packages/postcheck_rules/"
# Build outside synced Documents: File Provider metadata can break Apple codesign.
rsync -rlt --delete --exclude='.git' --exclude='.research' --exclude='build' \
  --exclude='.dart_tool' --exclude='*.log' --exclude='*.litertlm' \
  --exclude='ios/Pods' --exclude='ios/.symlinks' --exclude='ios/Flutter/ephemeral' \
  --exclude='ios/Flutter/Generated.xcconfig' --exclude='ios/Flutter/flutter_export_environment.sh' \
  --exclude='android/.gradle' --exclude='android/local.properties' \
  "$task_source/" "$task_staged/"
if [ ! -e "$task_staged/build" ]; then
  mkdir -p "$task_cache/build"
  ln -s "$task_cache/build" "$task_staged/build"
fi
printf '%s\n' "$task_staged"
