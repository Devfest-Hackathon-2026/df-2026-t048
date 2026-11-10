#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_model="$task_root/assets/screen_detector/efficientdet_lite0.tflite"
task_temp="${task_model}.partial"
mkdir -p "$(dirname "$task_model")"
trap 'rm -f "$task_temp"' EXIT
curl -fL 'https://storage.googleapis.com/download.tensorflow.org/models/tflite/task_library/object_detection/rpi/lite-model_efficientdet_lite0_detection_metadata_1.tflite' -o "$task_temp"
printf '%s  %s\n' '2e04c53bfeac0ac2a30c057c7e2a777594ce39baaac35a92f74fb1e8c4fc4e0b' "$task_temp" | shasum -a 256 -c -
mv "$task_temp" "$task_model"
