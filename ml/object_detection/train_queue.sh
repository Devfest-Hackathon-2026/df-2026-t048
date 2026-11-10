#!/bin/bash
# Unattended sequential training queue (survives the chat/IDE session ending).
#   nohup caffeinate -i bash ml/object_detection/train_queue.sh > ml/object_detection/runs/queue.log 2>&1 &
# Jobs are read from runs/queue.txt, one per line:
#   name|split_dir|labels_file|allow_list|epochs
# A job waits until <split_dir>/split_report.json exists, then trains, verifies
# and evaluates into runs/<name>/. Finished jobs get runs/<name>/DONE and are
# skipped; append lines to queue.txt while the queue runs. Stop: touch runs/queue.stop
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
image="postcheck-objdet:0.4.3"
run() {
  docker run --rm --platform linux/amd64 -v "$here:/work" -w /work \
    -e TFHUB_CACHE_DIR=/work/runs/.tfhub_cache -e PYTHONWARNINGS=ignore::FutureWarning \
    "$image" python "$@"
}
log() { echo "[$(date '+%F %T')] $*"; }
while [ ! -e runs/queue.stop ]; do
  job=""
  while IFS='|' read -r name split labels allow epochs; do
    [ -z "${name:-}" ] || [ "${name:0:1}" = "#" ] && continue
    [ -e "runs/$name/DONE" ] || [ -e "runs/$name/FAILED" ] && continue
    job="$name|$split|$labels|$allow|$epochs"; break
  done < runs/queue.txt
  if [ -z "$job" ]; then log "queue empty; waiting"; sleep 60; continue; fi
  IFS='|' read -r name split labels allow epochs <<< "$job"
  if [ ! -e "$split/split_report.json" ]; then log "$name: waiting for $split"; sleep 60; continue; fi
  mkdir -p "runs/$name"
  log "$name: train start (epochs=$epochs)"
  if run train.py --split "$split" --labels "$labels" --out "runs/$name/model" --epochs "$epochs" \
       > "runs/$name/train.log" 2>&1 \
     && run verify_model.py "runs/$name/model/model.tflite" --expect-labels "$labels" --allow "$allow" \
       > "runs/$name/verify.log" 2>&1 \
     && run evaluate.py --model "runs/$name/model/model.tflite" --split "$split" --out "runs/$name/eval" --draw \
       > "runs/$name/eval.log" 2>&1; then
    touch "runs/$name/DONE"; log "$name: done"
  else
    touch "runs/$name/FAILED"; log "$name: FAILED (see runs/$name/*.log)"
  fi
done
log "stop file found; exiting"
