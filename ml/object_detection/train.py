"""Train EfficientDet-Lite with TFLite Model Maker and export a Task Library model.

Run inside the container (see README). The exported model.tflite contains the
TFLite_Detection_PostProcess op (4 outputs) and ObjectDetector metadata with
the label file packed in, which is what TensorFlowLiteTaskVision expects.

Outputs in --out (Git-ignored):
  model.tflite, labels.txt, train_config.json, eval_model_maker.json
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import pathlib
import platform
import sys

import odlib

SPECS = ("efficientdet_lite0", "efficientdet_lite1", "efficientdet_lite2")


def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--split", required=True, type=pathlib.Path,
                    help="output directory of prepare_split.py")
    ap.add_argument("--labels", required=True, type=pathlib.Path)
    ap.add_argument("--out", required=True, type=pathlib.Path)
    ap.add_argument("--spec", choices=SPECS, default="efficientdet_lite0",
                    help="lite0 matches the input size of the current app model (320x320)")
    ap.add_argument("--epochs", type=int, default=50)
    ap.add_argument("--batch-size", type=int, default=8)
    ap.add_argument("--train-whole-model", action="store_true",
                    help="also fine-tune the backbone (more data recommended)")
    ap.add_argument("--quantization", choices=("int8", "float16", "float32"), default="int8",
                    help="int8 = uint8 input like the current app model")
    ap.add_argument("--max-detections", type=int, default=25)
    ap.add_argument("--max-instances", type=int, default=300,
                    help="max boxes per training image (Model Maker default 100; wine racks exceed it)")
    ap.add_argument("--train-limit", type=int, default=0,
                    help="use only N randomly chosen training images (0 = all), for quick experiments")
    ap.add_argument("--val-limit", type=int, default=0,
                    help="use only N randomly chosen validation images (0 = all)")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--skip-eval", action="store_true")
    args = ap.parse_args()

    import tensorflow as tf
    from tflite_model_maker import model_spec, object_detector
    from tflite_model_maker.config import ExportFormat, QuantizationConfig

    labels = odlib.read_labels(args.labels)
    label_map = {i + 1: name for i, name in enumerate(labels)}
    args.out.mkdir(parents=True, exist_ok=True)
    cache = args.out / "tfrecord_cache"

    def load(split: str, limit: int = 0):
        d = args.split / split
        names = None
        prefix = split
        if limit:
            import random
            stems = sorted(p.stem for p in (d / "annotations").glob("*.xml"))
            names = sorted(random.Random(args.seed).sample(stems, min(limit, len(stems))))
            prefix = f"{split}_limit{limit}_seed{args.seed}"
        return object_detector.DataLoader.from_pascal_voc(
            str(d / "images"), str(d / "annotations"), label_map,
            annotation_filenames=names,
            cache_dir=str(cache), cache_prefix_filename=prefix)

    train_data = load("train", args.train_limit)
    val_data = load("validation", args.val_limit)
    test_data = load("test")
    print(f"images: train={len(train_data)} validation={len(val_data)} test={len(test_data)}")

    spec = model_spec.get(args.spec)
    spec.config.tflite_max_detections = args.max_detections
    spec.config.max_instances_per_image = args.max_instances
    model = object_detector.create(
        train_data, model_spec=spec, validation_data=val_data,
        epochs=args.epochs, batch_size=args.batch_size,
        train_whole_model=args.train_whole_model)

    if args.quantization == "int8":
        qconfig = "default"  # full-integer with train_data as representative set
    elif args.quantization == "float16":
        qconfig = QuantizationConfig.for_float16()
    else:
        qconfig = None
    model.export(export_dir=str(args.out), tflite_filename="model.tflite",
                 label_filename="labels.txt",
                 export_format=[ExportFormat.TFLITE, ExportFormat.LABEL],
                 quantization_config=qconfig)

    model_path = args.out / "model.tflite"
    record = {
        "created_utc": datetime.datetime.utcnow().isoformat(timespec="seconds") + "Z",
        "tool": "tflite-model-maker 0.4.3",
        "tensorflow": tf.__version__,
        "python": platform.python_version(),
        "spec": args.spec,
        "pretrained_backbone": spec.uri,
        "labels": labels,
        "epochs": args.epochs,
        "batch_size": args.batch_size,
        "train_whole_model": args.train_whole_model,
        "quantization": args.quantization,
        "max_detections": args.max_detections,
        "split_dir": str(args.split),
        "train_limit": args.train_limit,
        "val_limit": args.val_limit,
        "seed": args.seed,
        "images": {"train": len(train_data), "validation": len(val_data), "test": len(test_data)},
        "model_sha256": sha256(model_path),
        "model_bytes": model_path.stat().st_size,
    }
    (args.out / "train_config.json").write_text(json.dumps(record, indent=2))

    if not args.skip_eval and len(test_data):
        # COCO-style metrics of Model Maker on the exported TFLite file. These are
        # reference numbers only; evaluate.py gives the per-image breakdown.
        metrics = model.evaluate_tflite(str(model_path), test_data)
        metrics = {k: float(v) for k, v in metrics.items()}
        (args.out / "eval_model_maker.json").write_text(json.dumps(metrics, indent=2))
        print(json.dumps(metrics, indent=2))
    print(json.dumps(record, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
