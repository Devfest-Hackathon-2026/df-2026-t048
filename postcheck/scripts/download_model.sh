#!/bin/bash
set -euo pipefail
task_directory="${POSTCHECK_BUILD_ROOT:-$HOME/Library/Caches/PostCheckMVP}/models"
task_model="$task_directory/gemma-4-E2B-it.litertlm"
task_hash='181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c'
mkdir -p "$task_directory"
if [ -f "$task_model" ]; then
  printf '%s  %s\n' "$task_hash" "$task_model" | shasum -a 256 --check
  exit 0
fi
curl -L --fail --retry 2 --connect-timeout 30 --max-time 1800 \
  'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm?download=true' \
  -o "$task_model.partial"
printf '%s  %s\n' "$task_hash" "$task_model.partial" | shasum -a 256 --check
mv "$task_model.partial" "$task_model"
