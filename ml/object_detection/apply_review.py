"""Merge review results into review_exclusions.csv for prepare_split.py --exclude.

Each result file is JSON written by a reviewer (person or agent):
  {"reviewed_sheets": [0, 1, ...], "exclude": [{"id": "P0003", "reason": "paper"}, ...]}

  python3 apply_review.py --index runs/review_v1/index.json \
      --results runs/review_v1/result_*.json \
      --out data/openimages_whiteboard_v1/review_exclusions.csv

Standard library only. Fails if an ID is unknown or listed twice.
"""

from __future__ import annotations

import argparse
import collections
import csv
import json
import pathlib
import sys


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--index", required=True, type=pathlib.Path)
    ap.add_argument("--results", required=True, nargs="+", type=pathlib.Path)
    ap.add_argument("--out", required=True, type=pathlib.Path)
    args = ap.parse_args()

    index = json.loads(args.index.read_text())
    rows, seen, counts = [], set(), collections.Counter()
    for path in args.results:
        data = json.loads(path.read_text())
        for e in data["exclude"]:
            tile = e["id"]
            if tile not in index:
                raise SystemExit(f"{path}: unknown id {tile}")
            if tile in seen:
                raise SystemExit(f"{path}: {tile} listed twice")
            seen.add(tile)
            kind = "positive" if tile.startswith("P") else "negative"
            rows.append({"image": index[tile], "review_id": tile, "kind": kind, "reason": e["reason"]})
            counts[(kind, e["reason"])] += 1
    with args.out.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, ["image", "review_id", "kind", "reason"])
        w.writeheader()
        w.writerows(rows)
    print(f"{len(rows)} exclusions -> {args.out}")
    for (kind, reason), n in sorted(counts.items()):
        print(f"  {kind:8s} {reason:20s} {n}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
