"""Contact sheets for human/agent review (run inside the container).

review   numbered sheets of every image in a dataset, with boxes drawn, plus
         index.json mapping tile IDs (P0001 = positive, N0001 = negative) to
         file names. Used to find wrong labels before training.

  python contact_sheet.py review --dataset data/openimages_whiteboard_v1 --out runs/review_v1

overview one sheet per outcome folder written by `evaluate.py --draw`.

  python contact_sheet.py overview --dir runs/oi_v1/exp_200/eval/review

Red = labelled box, yellow = difficult box. Sheets are local review aids only;
they contain third-party images, so never commit or publish them.
"""

from __future__ import annotations

import argparse
import csv
import json
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

import odlib


def font(size):
    for name in ("DejaVuSans-Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def review(args) -> int:
    d = args.dataset
    rows = list(csv.DictReader(open(d / "manifest.csv", encoding="utf-8")))
    args.out.mkdir(parents=True, exist_ok=True)
    tw, th, cols, per = 480, 360, 4, 16
    label_font = font(30)
    index = {}
    for kind in ("positive", "negative"):
        items = [r["image"] for r in rows if r["kind"] == kind]
        for start in range(0, len(items), per):
            sheet = Image.new("RGB", (tw * cols, th * (per // cols)), (40, 40, 40))
            draw_sheet = ImageDraw.Draw(sheet)
            for k, name in enumerate(items[start:start + per]):
                tile_id = f"{kind[0].upper()}{start + k:04d}"
                index[tile_id] = name
                im = Image.open(d / "images" / name).convert("RGB")
                draw = ImageDraw.Draw(im)
                width = max(3, im.width // 150)
                xml = d / "annotations" / (pathlib.Path(name).stem + ".xml")
                if xml.exists():
                    for b in odlib.read_voc(xml).boxes:
                        color = (255, 220, 0) if b.difficult else (255, 0, 0)
                        draw.rectangle([b.xmin, b.ymin, b.xmax, b.ymax], outline=color, width=width)
                im.thumbnail((tw - 6, th - 6))
                x, y = (k % cols) * tw, (k // cols) * th
                sheet.paste(im, (x + 3, y + 3))
                draw_sheet.rectangle([x + 3, y + 3, x + 150, y + 45], fill=(0, 0, 0))
                draw_sheet.text((x + 8, y + 6), tile_id, fill=(0, 255, 255), font=label_font)
            sheet.save(args.out / f"{kind}_{start // per:03d}.jpg", quality=82)
    (args.out / "index.json").write_text(json.dumps(index, indent=0))
    print(f"{len(index)} tiles -> {args.out}")
    return 0


def overview(args) -> int:
    for cat in sorted(p for p in args.dir.iterdir() if p.is_dir()):
        imgs = sorted(cat.glob("*.jpg"))[:args.limit]
        if not imgs:
            continue
        tw, th, cols = 400, 300, 6
        rows = (len(imgs) + cols - 1) // cols
        sheet = Image.new("RGB", (tw * cols, th * rows), (30, 30, 30))
        for i, p in enumerate(imgs):
            im = Image.open(p).convert("RGB")
            im.thumbnail((tw - 6, th - 6))
            sheet.paste(im, ((i % cols) * tw + 3, (i // cols) * th + 3))
        out = args.dir / f"_{cat.name}_overview.jpg"
        sheet.save(out, quality=85)
        print(out)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="mode", required=True)
    r = sub.add_parser("review")
    r.add_argument("--dataset", required=True, type=pathlib.Path)
    r.add_argument("--out", required=True, type=pathlib.Path)
    o = sub.add_parser("overview")
    o.add_argument("--dir", required=True, type=pathlib.Path)
    o.add_argument("--limit", type=int, default=24)
    args = ap.parse_args()
    return review(args) if args.mode == "review" else overview(args)


if __name__ == "__main__":
    sys.exit(main())
