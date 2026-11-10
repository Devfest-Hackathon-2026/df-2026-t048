"""Validate a labelled dataset and split it into train / validation / test.

Input (Git-ignored):
  <dataset>/images/*.jpg|png
  <dataset>/annotations/<same stem>.xml   Pascal VOC; may be omitted for negatives
  <dataset>/manifest.csv                  one row per image (see odlib.MANIFEST_COLUMNS)

Output:
  <out>/{train,validation,test}/images/*.jpg
  <out>/{train,validation,test}/annotations/*.xml
  <out>/split_manifest.csv, <out>/split_report.json

Splitting is by group_id (capture location + session), never by image, so
burst shots and the same room cannot appear on both the training and the
evaluation side. A perceptual-hash check flags remaining near-duplicates that
cross split boundaries (for example the same room recorded under two ids).

Images are re-encoded with EXIF orientation applied and all metadata (GPS,
device, timestamps) removed, so the pixels the model sees match the boxes.
"""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
import pathlib
import sys

from PIL import Image, ImageOps

import odlib

SPLITS = ("train", "validation", "test")


def group_bucket(group_id: str, seed: str) -> float:
    digest = hashlib.sha256(f"{seed}:{group_id}".encode()).hexdigest()
    return int(digest[:12], 16) / float(16 ** 12)


def assign_groups(groups, fractions, seed):
    """Deterministic group assignment aiming at image-count fractions.

    Positive and negative groups are assigned separately so that each split
    receives negatives (white walls, projector screens, windows, ...).
    """
    assignment = {}
    for kind in ("positive", "negative"):
        ids = sorted((g for g, info in groups.items() if info["kind"] == kind),
                     key=lambda g: group_bucket(g, seed))
        total = sum(groups[g]["count"] for g in ids)
        counts = dict.fromkeys(SPLITS, 0)
        # Fill the evaluation splits first so small datasets still get test data.
        order = ("test", "validation", "train")
        for g in ids:
            target = next((s for s in order
                           if counts[s] < fractions[s] * total and s != "train"), "train")
            assignment[g] = target
            counts[target] += groups[g]["count"]
    return assignment


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dataset", required=True, type=pathlib.Path)
    ap.add_argument("--labels", required=True, type=pathlib.Path)
    ap.add_argument("--out", required=True, type=pathlib.Path)
    ap.add_argument("--val", type=float, default=0.15)
    ap.add_argument("--test", type=float, default=0.15)
    ap.add_argument("--seed", default="postcheck-v1")
    ap.add_argument("--min-box-px", type=int, default=8,
                    help="reject boxes narrower/shorter than this")
    ap.add_argument("--dup-distance", type=int, default=6,
                    help="dHash Hamming distance treated as near-duplicate")
    ap.add_argument("--exclude", type=pathlib.Path,
                    help="CSV with an 'image' column (e.g. review_exclusions.csv); "
                         "listed images are left out of every split")
    ap.add_argument("--max-side", type=int, default=1280,
                    help="downscale long side (model input is 320-640 px)")
    args = ap.parse_args()

    labels = odlib.read_labels(args.labels)
    rows = odlib.read_manifest(args.dataset / "manifest.csv")
    excluded = set()
    if args.exclude:
        import csv
        with args.exclude.open(newline="", encoding="utf-8") as f:
            excluded = {r["image"].strip() for r in csv.DictReader(f)}
        rows = [r for r in rows if r["image"] not in excluded]
        print(f"excluded {len(excluded)} images listed in {args.exclude}")
    errors, warnings = [], []
    seen = set()
    groups = collections.defaultdict(lambda: {"count": 0, "kinds": set()})

    for row in rows:
        name = row["image"]
        if name in seen:
            errors.append(f"{name}: duplicated in manifest")
        seen.add(name)
        if row["kind"] not in ("positive", "negative"):
            errors.append(f"{name}: kind must be positive|negative")
        if not row["group_id"]:
            errors.append(f"{name}: group_id is required")
        for col in ("source", "license", "rights_holder", "consent"):
            if not row[col]:
                errors.append(f"{name}: {col} is required (provenance)")
        g = groups[row["group_id"]]
        g["count"] += 1
        g["kinds"].add(row["kind"])

    for gid, info in groups.items():
        if len(info["kinds"]) > 1:
            # Mixed groups are allowed; balanced as positive groups.
            warnings.append(f"group {gid}: mixes positive and negative images")
        info["kind"] = "positive" if "positive" in info["kinds"] else "negative"

    on_disk = {p.name for p in (args.dataset / "images").iterdir()
               if p.suffix.lower() in odlib.IMAGE_SUFFIXES}
    for extra in sorted(on_disk - seen - excluded):
        errors.append(f"{extra}: image not listed in manifest.csv")

    if errors:
        print("\n".join(f"ERROR {e}" for e in errors[:200]), file=sys.stderr)
        return 1

    fractions = {"train": 1 - args.val - args.test, "validation": args.val, "test": args.test}
    assignment = assign_groups(groups, fractions, args.seed)

    if args.out.exists() and any(args.out.iterdir()):
        print(f"ERROR {args.out} is not empty; choose a new output directory", file=sys.stderr)
        return 1
    for s in SPLITS:
        (args.out / s / "images").mkdir(parents=True, exist_ok=True)
        (args.out / s / "annotations").mkdir(parents=True, exist_ok=True)

    out_rows, hashes = [], []
    stats_tiny = [0]
    stats = {s: collections.Counter() for s in SPLITS}
    for row in rows:
        name = row["image"]
        split = assignment[row["group_id"]]
        src = args.dataset / "images" / name
        with Image.open(src) as im:
            im = ImageOps.exif_transpose(im).convert("RGB")
        width, height = im.size
        xml = args.dataset / "annotations" / (pathlib.Path(name).stem + ".xml")
        boxes = []
        if xml.exists():
            ann = odlib.read_voc(xml)
            if (ann.width, ann.height) != (width, height):
                errors.append(f"{name}: annotation size {ann.width}x{ann.height} != "
                              f"image {width}x{height} after EXIF orientation")
                continue
            boxes = ann.boxes
        for b in boxes:
            if b.label not in labels:
                errors.append(f"{name}: unknown label '{b.label}'")
            if not (0 <= b.xmin < b.xmax <= width and 0 <= b.ymin < b.ymax <= height):
                errors.append(f"{name}: box out of bounds {b}")
            elif min(b.xmax - b.xmin, b.ymax - b.ymin) < args.min_box_px and not b.difficult:
                # Tiny boxes (e.g. single books on a shelf) are kept but not scored.
                b.difficult = True
                stats_tiny[0] += 1
        if row["kind"] == "positive" and not boxes:
            errors.append(f"{name}: positive image without boxes")
        if row["kind"] == "negative" and boxes:
            errors.append(f"{name}: negative image has boxes (mark it positive)")

        scale = min(1.0, args.max_side / max(width, height))
        if scale < 1.0:
            im = im.resize((round(width * scale), round(height * scale)), Image.BILINEAR)
            boxes = [odlib.Box(b.label, b.xmin * scale, b.ymin * scale,
                               b.xmax * scale, b.ymax * scale, b.difficult) for b in boxes]
        out_name = pathlib.Path(name).stem + ".jpg"
        # Saving without exif= drops all EXIF/GPS metadata.
        im.save(args.out / split / "images" / out_name, "JPEG", quality=95)
        odlib.write_voc(args.out / split / "annotations" / (pathlib.Path(name).stem + ".xml"),
                        odlib.Annotation(out_name, im.size[0], im.size[1], boxes))
        hashes.append((odlib.dhash(im), split, row["group_id"], name))
        stats[split]["images"] += 1
        stats[split][row["kind"]] += 1
        stats[split]["boxes"] += len(boxes)
        if row["kind"] == "negative":
            stats[split][f"negative:{row['negative_kind'] or 'unspecified'}"] += 1
        out_rows.append({**row, "split": split, "image": out_name, "source_image": name,
                         "boxes": len(boxes)})

    if errors:
        print("\n".join(f"ERROR {e}" for e in errors[:200]), file=sys.stderr)
        print(f"{args.out} is incomplete; delete it, fix the data and rerun.", file=sys.stderr)
        return 1

    leaks = []
    for i in range(len(hashes)):
        for j in range(i + 1, len(hashes)):
            a, b = hashes[i], hashes[j]
            if a[1] != b[1] and bin(a[0] ^ b[0]).count("1") <= args.dup_distance:
                leaks.append({"a": a[3], "a_split": a[1], "a_group": a[2],
                              "b": b[3], "b_split": b[1], "b_group": b[2]})
    for s in ("validation", "test"):
        if stats[s]["positive"] == 0:
            warnings.append(f"{s}: no positive images")
        if stats[s]["negative"] == 0:
            warnings.append(f"{s}: no negative images (white walls, screens, windows ...)")
    if stats_tiny[0]:
        warnings.append(f"{stats_tiny[0]} boxes smaller than {args.min_box_px}px marked difficult")
    if leaks:
        warnings.append(f"{len(leaks)} near-duplicate pairs cross split boundaries; "
                        "merge their group_id or remove them (see split_report.json)")

    odlib.write_csv(args.out / "split_manifest.csv", out_rows,
                    ["image", "source_image", "split", "group_id", "kind", "negative_kind",
                     "boxes", "source", "license", "rights_holder", "consent", "notes"])
    report = {"labels": labels, "seed": args.seed, "fractions": fractions,
              "groups": {s: sorted(g for g, v in assignment.items() if v == s) for s in SPLITS},
              "stats": {s: dict(c) for s, c in stats.items()},
              "near_duplicates_across_splits": leaks, "warnings": warnings}
    (args.out / "split_report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False))
    print(json.dumps(report["stats"], indent=2, ensure_ascii=False))
    for w in warnings:
        print(f"WARNING {w}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
