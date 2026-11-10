"""Check that a .tflite file is usable by the TFLite Task Library ObjectDetector.

This mirrors what the iOS app does (TensorFlowLiteTaskVision 0.4.3,
ObjectDetectorOptions with scoreThreshold 0.35, maxResults 10, and a label
allow-list) using the Python build of the same Task Library
(tflite-support 0.4.4). Checks:

  1. one input [1, H, W, 3], uint8 or float32 (float32 needs NormalizationOptions)
  2. exactly 4 outputs produced by TFLite_Detection_PostProcess
  3. metadata: BoundingBoxProperties type=BOUNDARIES on the locations output,
     a TENSOR_VALUE_LABELS label file, and (optionally) the expected labels
  4. ObjectDetector actually loads the model and runs on sample images

Exit status is non-zero if any required check fails. A JSON report is written
next to the model unless --report is given.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

import odlib

POSTPROCESS_OP = "TFLite_Detection_PostProcess"


def check(report, name, ok, detail=""):
    report["checks"].append({"name": name, "ok": bool(ok), "detail": detail})
    print(f"[{'OK' if ok else 'NG'}] {name}{': ' + detail if detail else ''}")
    return ok


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("model", type=pathlib.Path)
    ap.add_argument("--expect-labels", type=pathlib.Path,
                    help="labels.txt that the packed label file must contain")
    ap.add_argument("--allow", default="",
                    help="comma-separated label allow-list, as the app passes it")
    ap.add_argument("--score-threshold", type=float, default=0.35)
    ap.add_argument("--max-results", type=int, default=10)
    ap.add_argument("--images", nargs="*", type=pathlib.Path, default=[],
                    help="sample images to run through ObjectDetector")
    ap.add_argument("--report", type=pathlib.Path)
    args = ap.parse_args()

    import numpy as np
    import tensorflow as tf
    from tflite_support import metadata as md
    from tflite_support.task import core, processor, vision

    report = {"model": str(args.model), "checks": [], "detections": []}
    ok = True

    interp = tf.lite.Interpreter(model_path=str(args.model))
    interp.allocate_tensors()
    inputs = interp.get_input_details()
    outputs = interp.get_output_details()
    report["inputs"] = [{"name": d["name"], "shape": d["shape"].tolist(),
                         "dtype": np.dtype(d["dtype"]).name,
                         "quantization": list(d["quantization"])} for d in inputs]
    report["outputs"] = [{"name": d["name"], "shape": d["shape"].tolist(),
                          "dtype": np.dtype(d["dtype"]).name} for d in outputs]

    in_ok = (len(inputs) == 1 and len(inputs[0]["shape"]) == 4
             and inputs[0]["shape"][0] == 1 and inputs[0]["shape"][3] == 3
             and inputs[0]["dtype"] in (np.uint8, np.float32))
    ok &= check(report, "input [1,H,W,3] uint8/float32", in_ok, str(report["inputs"]))

    raw = args.model.read_bytes()
    op_names = set()
    try:
        op_names = {op["op_name"] for op in interp._get_ops_details()}
    except Exception:  # private API; fall back to the flatbuffer string table
        pass
    has_pp = POSTPROCESS_OP in op_names or POSTPROCESS_OP.encode() in raw
    ok &= check(report, f"contains {POSTPROCESS_OP}", has_pp)
    out_ok = len(outputs) == 4 and all(np.dtype(d["dtype"]) == np.float32 for d in outputs)
    ok &= check(report, "exactly 4 float32 outputs", out_ok,
                str([(d["name"], d["shape"].tolist()) for d in outputs]))

    try:
        displayer = md.MetadataDisplayer.with_model_file(str(args.model))
        meta = json.loads(displayer.get_metadata_json())
        packed = displayer.get_packed_associated_file_list()
    except Exception as e:  # no metadata at all
        check(report, "TFLite metadata present", False, repr(e))
        meta, packed = None, []
        ok = False
    labels_in_model = []
    if meta is not None:
        report["metadata_name"] = meta.get("name")
        sub = meta["subgraph_metadata"][0]
        in_meta = sub.get("input_tensor_metadata", [{}])[0]
        norm = [p for p in in_meta.get("process_units", [])
                if p.get("options_type") == "NormalizationOptions"]
        if in_ok and inputs[0]["dtype"] == np.float32:
            ok &= check(report, "float32 input has NormalizationOptions", bool(norm))
        out_meta = sub.get("output_tensor_metadata", [])
        names = [m.get("name") for m in out_meta]
        report["output_metadata_names"] = names
        bbox = [m for m in out_meta
                if m.get("content", {}).get("content_properties_type") == "BoundingBoxProperties"]
        bb_ok = bool(bbox) and bbox[0]["content"]["content_properties"].get("type") == "BOUNDARIES"
        ok &= check(report, "BoundingBoxProperties type=BOUNDARIES",
                    bb_ok, json.dumps(bbox[0]["content"]["content_properties"]) if bbox else "")
        label_files = [f for m in out_meta for f in m.get("associated_files", [])
                       if f.get("type") == "TENSOR_VALUE_LABELS"]
        ok &= check(report, "TENSOR_VALUE_LABELS file attached", bool(label_files),
                    ", ".join(f["name"] for f in label_files))
        if label_files and label_files[0]["name"] in packed:
            data = md.MetadataDisplayer.with_model_file(str(args.model)) \
                .get_associated_file_buffer(label_files[0]["name"]).decode("utf-8")
            labels_in_model = [l.strip() for l in data.splitlines() if l.strip()]
        report["labels_in_model"] = labels_in_model
        print(f"     labels in model ({len(labels_in_model)}): {labels_in_model[:12]}"
              f"{' ...' if len(labels_in_model) > 12 else ''}")

    if args.expect_labels:
        expected = odlib.read_labels(args.expect_labels)
        ok &= check(report, "packed labels match --expect-labels",
                    [l for l in labels_in_model if l not in ("background", "???")] == expected,
                    f"expected {expected}")

    allow = [a.strip() for a in args.allow.split(",") if a.strip()]
    if allow:
        missing = [a for a in allow if a not in labels_in_model]
        ok &= check(report, "allow-list labels exist in model", not missing,
                    f"missing {missing}: those detections would always be filtered out"
                    if missing else str(allow))

    try:
        det_opts = processor.DetectionOptions(
            score_threshold=args.score_threshold, max_results=args.max_results,
            category_name_allowlist=allow or None)
        options = vision.ObjectDetectorOptions(
            base_options=core.BaseOptions(file_name=str(args.model)),
            detection_options=det_opts)
        detector = vision.ObjectDetector.create_from_options(options)
        ok &= check(report, "Task Library ObjectDetector loads model", True)
    except Exception as e:
        check(report, "Task Library ObjectDetector loads model", False, repr(e))
        detector, ok = None, False

    if detector is not None:
        for img in args.images:
            image = vision.TensorImage.create_from_file(str(img))
            result = detector.detect(image)
            dets = [{"label": d.categories[0].category_name,
                     "score": round(d.categories[0].score, 3),
                     "box_xywh": [d.bounding_box.origin_x, d.bounding_box.origin_y,
                                  d.bounding_box.width, d.bounding_box.height]}
                    for d in result.detections]
            report["detections"].append({"image": img.name, "detections": dets})
            print(f"     {img.name}: {len(dets)} detection(s) {dets[:5]}")

    report["compatible"] = bool(ok)
    out = args.report or args.model.with_suffix(".verify.json")
    out.write_text(json.dumps(report, indent=2, ensure_ascii=False))
    print(f"compatible={ok}  report={out}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
