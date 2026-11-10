"""Build a whiteboard dataset from Open Images (human-drawn boxes, CC BY images).

Standard library only, so it runs natively on the host:

  python3 -I fetch_openimages.py --raw data/openimages_raw --out data/openimages_whiteboard_v1

--raw must contain the pre-filtered rows produced by the commands in
docs/custom-object-detection.md (wb_bbox.csv, wb_labels.csv, *_header.csv).
This script then:
  1. picks positives: images with a human-drawn box of --mid (default
     Whiteboard /m/02d9qx)
  2. picks negatives: images where annotators verified that the class is
     absent (image label Confidence=0), preferring look-alike scenes
     (LOOKALIKES below is tuned for whiteboards; edit it for other classes)
  3. keeps only CC BY 2.0 images without a rotation flag
  4. downloads the images from the public Open Images bucket
  5. writes Pascal VOC files and manifest.csv with author/license/URL per image

group_id is the Flickr author, so one photographer's series never spans the
train and test sides. IsGroupOf / IsDepiction / tiny boxes are marked
difficult (excluded from scoring, still used for training).

Licences: annotations CC BY 4.0 (Google); images as listed per row (CC BY 2.0
here, attribution required). Nothing is sent anywhere; images are only fetched.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import csv
import io
import pathlib
import random
import struct
import sys
import urllib.request

import odlib

WHITEBOARD = "/m/02d9qx"
LOOKALIKES = {  # Open Images label -> negative_kind
    "/m/0d4v4": "window", "/m/02522": "monitor_off", "/m/07c52": "monitor_off",
    "/m/01n5jq": "whiteboard_like_paper", "/m/06z37_": "whiteboard_like_paper",
    "/m/02dgv": "white_wall",
}
CC_BY_20 = "https://creativecommons.org/licenses/by/2.0/"
BASE = "https://storage.googleapis.com/openimages/"
IMAGE_INFO = {
    "train": "2018_04/train/train-images-boxable-with-rotation.csv",
    "validation": "2018_04/validation/validation-images-with-rotation.csv",
    "test": "2018_04/test/test-images-with-rotation.csv",
}
LABELS = {
    "train": "v5/train-annotations-human-imagelabels-boxable.csv",
    "validation": "v5/validation-annotations-human-imagelabels-boxable.csv",
    "test": "v5/test-annotations-human-imagelabels-boxable.csv",
}
S3 = "https://open-images-dataset.s3.amazonaws.com/{subset}/{image_id}.jpg"


def stream_csv(url):
    with urllib.request.urlopen(url, timeout=120) as r:
        yield from csv.reader(io.TextIOWrapper(r, encoding="utf-8"))


def jpeg_size(data: bytes):
    """(width, height) from the SOF marker, without Pillow."""
    i = 2
    while i < len(data) - 9:
        if data[i] != 0xFF:
            i += 1
            continue
        marker = data[i + 1]
        if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
            h, w = struct.unpack(">HH", data[i + 5:i + 9])
            return w, h
        if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
            i += 2
            continue
        i += 2 + struct.unpack(">H", data[i + 2:i + 4])[0]
    raise ValueError("no SOF marker")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--raw", required=True, type=pathlib.Path)
    ap.add_argument("--out", required=True, type=pathlib.Path)
    ap.add_argument("--mid", default=WHITEBOARD,
                    help="Open Images class MID (see classes.csv), e.g. /m/06z37_ for Picture frame")
    ap.add_argument("--label", default="whiteboard", help="label written to VOC; must be in labels.txt")
    ap.add_argument("--class", dest="classes", action="append", default=[],
                    metavar="MID:LABEL",
                    help="repeatable; several classes make one multi-class dataset, "
                         "e.g. --class /m/06z37_:picture_frame --class /m/01n5jq:poster "
                         "(overrides --mid/--label)")
    ap.add_argument("--positives", type=int, default=1000,
                    help="positive images per class")
    ap.add_argument("--negatives", type=int, default=500)
    ap.add_argument("--min-box-frac", type=float, default=0.02,
                    help="boxes narrower/shorter than this fraction are marked difficult")
    ap.add_argument("--seed", type=int, default=20261109)
    ap.add_argument("--workers", type=int, default=16)
    args = ap.parse_args()
    classes = dict(c.split(":", 1) for c in args.classes) or {args.mid: args.label}
    # Look-alike scene tags are tuned for whiteboards; other classes skip the
    # extra 400MB label scan and tag negatives as "other".
    use_lookalikes = WHITEBOARD in classes

    if args.out.exists() and any(args.out.iterdir()):
        print(f"{args.out} is not empty; choose a new directory", file=sys.stderr)
        return 1

    # ---- 1. positives (boxes) and verified negatives (image labels)
    bbox_cols = ["split"] + (args.raw / "bbox_header.csv").read_text().strip().split(",")
    boxes = {}
    subset_of = {}
    with (args.raw / "wb_bbox.csv").open(newline="") as f:
        for row in csv.reader(f):
            r = dict(zip(bbox_cols, row))
            if r["LabelName"] not in classes:
                continue
            boxes.setdefault(r["ImageID"], []).append(r)
            subset_of[r["ImageID"]] = r["split"]
    negatives = set()
    with (args.raw / "wb_labels.csv").open(newline="") as f:
        for split, image_id, _src, label, conf in csv.reader(f):
            if label in classes and conf == "0":
                negatives.add(image_id)
                subset_of.setdefault(image_id, split)
    negatives -= set(boxes)  # an image with any target box is never a negative
    for mid, label in classes.items():
        n = sum(1 for v in boxes.values() if any(b["LabelName"] == mid for b in v))
        print(f"candidates {label}: {n} images with boxes")
    print(f"candidates: {len(negatives)} images verified without a target class")

    # ---- 2. image metadata (licence, author, rotation) for all candidates
    wanted = set(boxes) | negatives
    info = {}
    for subset, path in IMAGE_INFO.items():
        reader = stream_csv(BASE + path)
        header = next(reader)
        for row in reader:
            if row and row[0] in wanted:
                info[row[0]] = dict(zip(header, row))
        print(f"metadata {subset}: {sum(1 for v in info.values() if v.get('Subset') == subset)} rows")

    def usable(image_id):
        meta = info.get(image_id)
        return (meta is not None and meta["License"] == CC_BY_20
                and meta.get("Rotation", "") in ("", "0", "0.0"))

    rng = random.Random(args.seed)
    pos_ids = []
    for mid in classes:
        pool = sorted(i for i, v in boxes.items()
                      if usable(i) and i not in pos_ids and any(b["LabelName"] == mid for b in v))
        rng.shuffle(pool)
        pos_ids += pool[:args.positives]

    # ---- 3. look-alike scenes among negatives (verified present labels)
    neg_pool = sorted(i for i in negatives if usable(i))
    neg_kind = {}
    pool_set = set(neg_pool)
    for subset in sorted({subset_of[i] for i in pool_set}) if use_lookalikes else []:
        for row in stream_csv(BASE + LABELS[subset]):
            if len(row) == 4 and row[0] in pool_set and row[3] == "1" and row[2] in LOOKALIKES:
                neg_kind.setdefault(row[0], LOOKALIKES[row[2]])
    rng.shuffle(neg_pool)
    hard = [i for i in neg_pool if i in neg_kind]
    other = [i for i in neg_pool if i not in neg_kind]
    neg_ids = (hard + other)[:args.negatives]
    print(f"selected: {len(pos_ids)} positives, {len(neg_ids)} negatives "
          f"({sum(1 for i in neg_ids if i in neg_kind)} look-alike scenes)")

    # ---- 4. download + 5. VOC / manifest
    (args.out / "images").mkdir(parents=True, exist_ok=True)
    (args.out / "annotations").mkdir(parents=True, exist_ok=True)

    def fetch(image_id):
        url = S3.format(subset=subset_of[image_id], image_id=image_id)
        with urllib.request.urlopen(url, timeout=60) as r:
            data = r.read()
        return image_id, data

    rows, failed = [], []
    ids = [(i, "positive") for i in pos_ids] + [(i, "negative") for i in neg_ids]
    kind_of = dict(ids)
    with concurrent.futures.ThreadPoolExecutor(args.workers) as pool:
        futures = [pool.submit(fetch, i) for i, _ in ids]
        for n, fut in enumerate(concurrent.futures.as_completed(futures), 1):
            try:
                image_id, data = fut.result()
                width, height = jpeg_size(data)
            except Exception as e:  # network or corrupt file: skip, report
                failed.append(repr(e))
                continue
            name = f"oi_{image_id}.jpg"
            (args.out / "images" / name).write_bytes(data)
            vboxes = []
            for b in boxes.get(image_id, []):
                x0, x1 = float(b["XMin"]) * width, float(b["XMax"]) * width
                y0, y1 = float(b["YMin"]) * height, float(b["YMax"]) * height
                small = min(x1 - x0, y1 - y0) < args.min_box_frac * min(width, height)
                vboxes.append(odlib.Box(classes[b["LabelName"]], x0, y0, x1, y1,
                                        difficult=b["IsGroupOf"] == "1" or b["IsDepiction"] == "1"
                                        or small))
            odlib.write_voc(args.out / "annotations" / f"oi_{image_id}.xml",
                            odlib.Annotation(name, width, height, vboxes))
            meta = info[image_id]
            rows.append({
                "image": name,
                "group_id": "flickr:" + (meta.get("AuthorProfileURL") or image_id),
                "kind": kind_of[image_id],
                "negative_kind": neg_kind.get(image_id, "other") if kind_of[image_id] == "negative" else "none",
                "source": f"open_images_v7:{subset_of[image_id]}:{image_id}",
                "license": "CC-BY-2.0 (image); CC-BY-4.0 (Open Images annotations)",
                "rights_holder": meta.get("Author", ""),
                "consent": "public_cc_license",
                "notes": meta.get("OriginalLandingURL", ""),
            })
            if n % 100 == 0:
                print(f"downloaded {n}/{len(ids)}")
    rows.sort(key=lambda r: r["image"])
    odlib.write_csv(args.out / "manifest.csv", rows, list(odlib.MANIFEST_COLUMNS))
    pos = sum(r["kind"] == "positive" for r in rows)
    print(f"wrote {len(rows)} images ({pos} positive, {len(rows) - pos} negative) to {args.out}; "
          f"{len(failed)} failed")
    for e in failed[:10]:
        print("  failed:", e)
    return 0


if __name__ == "__main__":
    sys.exit(main())
