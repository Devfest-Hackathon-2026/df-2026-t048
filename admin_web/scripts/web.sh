#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
task_mode="${1:-run}"
task_config="${2:-config/demo.json}"
python3 scripts/prepare_maps.py "$task_config"
task_flutter="${FLUTTER_BIN:-flutter}"
if [ "$task_mode" = "run" ]; then
  exec "$task_flutter" run -d web-server --web-hostname=127.0.0.1 --web-port=5173 --dart-define-from-file="$task_config"
elif [ "$task_mode" = "build" ]; then
  exec "$task_flutter" build web --dart-define-from-file="$task_config"
else
  printf 'Usage: bash scripts/web.sh run|build config/file.json\n' >&2
  exit 1
fi
