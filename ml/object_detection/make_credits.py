"""Write the attribution list (author, licence, source URL) of the images that
trained a model, so a shipped model can credit every CC BY photo.

  python3 make_credits.py --split runs/oi_v1/split --train-limit 200 --val-limit 50 \
      --out credits/whiteboard_exp200.csv

Use the same --train-limit / --val-limit / --seed as train.py (0 = all images of
that subset). Test images are not used for training and are not listed.
Standard library only; the output contains no image data.
"""

from __future__ import annotations

import argparse
import csv
import pathlib
import random
import sys


def chosen(split: pathlib.Path, subset: str, limit: int, seed: int) -> set:
    stems = sorted(p.stem for p in (split / subset / "annotations").glob("*.xml"))
    if limit:
        stems = random.Random(seed).sample(stems, min(limit, len(stems)))
    return set(stems)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--split", required=True, type=pathlib.Path)
    ap.add_argument("--out", required=True, type=pathlib.Path)
    ap.add_argument("--train-limit", type=int, default=0)
    ap.add_argument("--val-limit", type=int, default=0)
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()

    used = {"train": chosen(args.split, "train", args.train_limit, args.seed),
            "validation": chosen(args.split, "validation", args.val_limit, args.seed)}
    rows = []
    for r in csv.DictReader(open(args.split / "split_manifest.csv", encoding="utf-8")):
        if r["split"] in used and pathlib.Path(r["image"]).stem in used[r["split"]]:
            rows.append({"image": r["image"], "subset": r["split"], "author": r["rights_holder"],
                         "license": r["license"], "source": r["source"], "url": r["notes"]})
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with open(args.out, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["image", "subset", "author", "license", "source", "url"])
        w.writeheader()
        w.writerows(sorted(rows, key=lambda x: (x["subset"], x["image"])))
    print(f"{len(rows)} images -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
