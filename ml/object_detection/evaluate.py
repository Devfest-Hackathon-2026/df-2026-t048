"""Evaluate an exported .tflite with the Task Library ObjectDetector on a split.

Uses the same inference path as the app (Task Library, score threshold,
max results) rather than the training framework, so the numbers describe the
converted file. Each image is classified into:

  success         every ground-truth box matched (IoU >= --iou), no false alarm
  true_negative   negative image with no detection
  false_positive  detection on a negative image (white wall, screen, window ...)
                  or an unmatched / duplicate detection on a positive image
  missed          at least one ground-truth box not detected

Writes per-image results (file names and boxes only, no pixels) to --out.
Ratios are only printed as "reference" when the counts are below
--min-count, because a handful of images cannot support accuracy claims.
"""

from __future__ import annotations

import argparse
import collections
import json
import pathlib
import sys

import odlib


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", required=True, type=pathlib.Path)
    ap.add_argument("--split", required=True, type=pathlib.Path,
                    help="prepare_split.py output directory")
    ap.add_argument("--subset", default="test", choices=("train", "validation", "test"))
    ap.add_argument("--out", required=True, type=pathlib.Path)
    ap.add_argument("--thresholds", default="0.25,0.35,0.5",
                    help="score thresholds; 0.35 is the current app setting")
    ap.add_argument("--max-results", type=int, default=10)
    ap.add_argument("--iou", type=float, default=0.5)
    ap.add_argument("--min-count", type=int, default=100,
                    help="below this many GT boxes / negative images, ratios are reference only")
    ap.add_argument("--draw", action="store_true",
                    help="save annotated images for manual review (Git-ignored)")
    args = ap.parse_args()

    from tflite_support.task import core, processor, vision

    thresholds = sorted(float(t) for t in args.thresholds.split(","))
    lowest = thresholds[0]
    detector = vision.ObjectDetector.create_from_options(vision.ObjectDetectorOptions(
        base_options=core.BaseOptions(file_name=str(args.model)),
        detection_options=processor.DetectionOptions(
            score_threshold=lowest, max_results=args.max_results)))

    manifest = {r["image"]: r for r in
                odlib.read_manifest(args.split / "split_manifest.csv")}
    base = args.split / args.subset
    images = sorted(p for p in (base / "images").iterdir()
                    if p.suffix.lower() in odlib.IMAGE_SUFFIXES)
    if not images:
        print(f"no images in {base}", file=sys.stderr)
        return 1
    args.out.mkdir(parents=True, exist_ok=True)

    raw = []
    for img in images:
        gt = odlib.read_voc(base / "annotations" / (img.stem + ".xml")).boxes
        result = detector.detect(vision.TensorImage.create_from_file(str(img)))
        dets = []
        for d in result.detections:
            bb, cat = d.bounding_box, d.categories[0]
            dets.append((cat.score, odlib.Box(cat.category_name, bb.origin_x, bb.origin_y,
                                              bb.origin_x + bb.width, bb.origin_y + bb.height)))
        raw.append((img, gt, dets))

    summary = {}
    per_image_rows = []
    for t in thresholds:
        c = collections.Counter()
        fp_by_kind = collections.Counter()
        for img, gt, all_dets in raw:
            row = manifest.get(img.name, {})
            neg_kind = row.get("negative_kind") or ("none" if gt else "unspecified")
            dets = sorted((d for d in all_dets if d[0] >= t), key=lambda d: -d[0])
            # Difficult GT boxes neither count as misses nor make detections false.
            used = [False] * len(gt)
            tp = fp = 0
            for score, box in dets:
                best, best_iou = -1, args.iou
                for i, g in enumerate(gt):
                    if not used[i] and g.label == box.label:
                        v = box.iou(g)
                        if v >= best_iou:
                            best, best_iou = i, v
                if best >= 0:
                    used[best] = True
                    if not gt[best].difficult:
                        tp += 1
                else:
                    fp += 1
            fn = sum(1 for i, g in enumerate(gt) if not used[i] and not g.difficult)
            scored = [g for g in gt if not g.difficult]
            if not gt:
                outcome = "false_positive" if fp else "true_negative"
                c["negative_images"] += 1
                if fp:
                    fp_by_kind[neg_kind] += 1
            elif fn:
                outcome = "missed"
            elif fp:
                outcome = "false_positive"
            else:
                outcome = "success"
            c[outcome] += 1
            c["tp"] += tp
            c["fp"] += fp
            c["fn"] += fn
            c["gt"] += len(scored)
            if t == min(thresholds, key=lambda x: abs(x - 0.35)):
                per_image_rows.append({
                    "threshold": t, "image": img.name, "group_id": row.get("group_id", ""),
                    "negative_kind": neg_kind, "outcome": outcome, "gt": len(scored),
                    "tp": tp, "fp": fp, "fn": fn,
                    "detections": json.dumps([[d[1].label, round(d[0], 3),
                                               [round(d[1].xmin), round(d[1].ymin),
                                                round(d[1].xmax), round(d[1].ymax)]]
                                              for d in dets])})
        enough = c["gt"] >= args.min_count and c["negative_images"] >= args.min_count
        entry = dict(c)
        entry["false_positive_negatives_by_kind"] = dict(fp_by_kind)
        entry["ratios_are_reference_only"] = not enough
        if c["tp"] + c["fp"]:
            entry["precision"] = round(c["tp"] / (c["tp"] + c["fp"]), 3)
        if c["gt"]:
            entry["recall"] = round(c["tp"] / c["gt"], 3)
        summary[str(t)] = entry

    report = {"model": str(args.model), "subset": args.subset, "images": len(raw),
              "iou": args.iou, "max_results": args.max_results, "by_threshold": summary}
    (args.out / "evaluation.json").write_text(json.dumps(report, indent=2, ensure_ascii=False))
    odlib.write_csv(args.out / "per_image.csv", per_image_rows)
    print(json.dumps(report, indent=2, ensure_ascii=False))
    if any(v["ratios_are_reference_only"] for v in summary.values()):
        print(f"NOTE: fewer than {args.min_count} GT boxes or negative images; "
              "precision/recall are reference values, not performance claims.")

    if args.draw:
        from PIL import Image, ImageDraw
        t_draw = min(thresholds, key=lambda x: abs(x - 0.35))
        outcomes = {r["image"]: r["outcome"] for r in per_image_rows}
        for img, gt, dets in raw:
            folder = args.out / "review" / outcomes[img.name]
            folder.mkdir(parents=True, exist_ok=True)
            with Image.open(img) as im:
                im = im.convert("RGB")
                draw = ImageDraw.Draw(im)
                for g in gt:
                    draw.rectangle([g.xmin, g.ymin, g.xmax, g.ymax], outline=(0, 200, 0), width=3)
                for score, b in dets:
                    if score >= t_draw:
                        draw.rectangle([b.xmin, b.ymin, b.xmax, b.ymax], outline=(230, 0, 0), width=3)
                        draw.text((b.xmin + 4, b.ymin + 4), f"{b.label} {score:.2f}", fill=(230, 0, 0))
                im.save(folder / img.name, quality=85)
        print(f"review images: {args.out / 'review'} (green=ground truth, red=detection)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
