"""Convert a COCO detection export (CVAT, Label Studio, ...) to Pascal VOC files.

  python coco_to_voc.py --coco export/labels.json --images export/images \
      --out data/whiteboard_v1/annotations

COCO bbox is [x, y, width, height] in pixels. Images listed in the JSON with
no annotation are written as VOC files without <object> (negatives).
Category names are written as-is; they must match labels.txt.
The VOC <size> is the EXIF-oriented size, matching what annotation tools show;
prepare_split.py rejects files whose size disagrees with the oriented image.
"""

from __future__ import annotations

import argparse
import collections
import json
import pathlib
import sys

from PIL import Image, ImageOps

import odlib


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--coco", required=True, type=pathlib.Path)
    ap.add_argument("--images", required=True, type=pathlib.Path)
    ap.add_argument("--out", required=True, type=pathlib.Path)
    args = ap.parse_args()

    data = json.loads(args.coco.read_text(encoding="utf-8"))
    cats = {c["id"]: c["name"] for c in data["categories"]}
    by_image = collections.defaultdict(list)
    for a in data["annotations"]:
        by_image[a["image_id"]].append(a)
    args.out.mkdir(parents=True, exist_ok=True)
    rotated = 0
    for img in data["images"]:
        name = pathlib.Path(img["file_name"]).name
        with Image.open(args.images / name) as im:
            raw_size = im.size
            size = ImageOps.exif_transpose(im).size
        rotated += size != raw_size
        boxes = []
        for a in by_image.get(img["id"], []):
            x, y, w, h = a["bbox"]
            boxes.append(odlib.Box(cats[a["category_id"]], x, y, x + w, y + h,
                                   bool(a.get("iscrowd", 0))))
        odlib.write_voc(args.out / (pathlib.Path(name).stem + ".xml"),
                        odlib.Annotation(name, size[0], size[1], boxes))
    print(f"wrote {len(data['images'])} files to {args.out} "
          f"({rotated} images carry an EXIF rotation; check boxes in the review output)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
