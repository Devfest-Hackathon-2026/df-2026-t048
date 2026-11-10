#!/bin/bash
# Run the object detection pipeline inside the pinned linux/amd64 container.
#   ml/object_detection/od.sh build
#   ml/object_detection/od.sh synth    --out data/synth_whiteboard_v1
#   ml/object_detection/od.sh split    --dataset data/whiteboard_v1 --out runs/v1/split
#   ml/object_detection/od.sh train    --split runs/v1/split --out runs/v1/model
#   ml/object_detection/od.sh verify   runs/v1/model/model.tflite --expect-labels labels.txt
#   ml/object_detection/od.sh evaluate --model runs/v1/model/model.tflite --split runs/v1/split --out runs/v1/eval
# Paths are relative to ml/object_detection/. Nothing leaves the machine except
# the one-time download of the pretrained EfficientDet-Lite backbone.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
image="postcheck-objdet:0.4.3"
case "${1:-}" in
  build) exec docker build --platform linux/amd64 -t "$image" "$here" ;;
  synth) script=synth_whiteboard.py; extra=() ;;
  sheet) script=contact_sheet.py; extra=() ;;
  split) script=prepare_split.py; extra=(--labels labels.txt) ;;
  train) script=train.py; extra=(--labels labels.txt) ;;
  verify) script=verify_model.py; extra=() ;;
  evaluate) script=evaluate.py; extra=() ;;
  shell) exec docker run --rm -it --platform linux/amd64 -v "$here:/work" -w /work "$image" bash ;;
  *) echo "usage: $0 build|synth|sheet|split|train|verify|evaluate|shell [args]" >&2; exit 2 ;;
esac
shift
# The TF Hub cache keeps the pretrained backbone between runs (Git-ignored).
exec docker run --rm --platform linux/amd64 -v "$here:/work" -w /work \
  -e TFHUB_CACHE_DIR=/work/runs/.tfhub_cache -e PYTHONWARNINGS=ignore::FutureWarning \
  "$image" python "$script" ${extra[@]+"${extra[@]}"} "$@"
