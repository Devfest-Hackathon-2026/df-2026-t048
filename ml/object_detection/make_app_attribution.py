"""Build the in-app Open Images attribution text from make_credits.py lists.

  python3 make_app_attribution.py \
      --model "whiteboard_experiment.tflite (whiteboard)=credits/whiteboard_exp200.csv" \
      --model "docs_experiment.tflite (picture frame, poster)=credits/frame_poster_docs_whole_v1.csv" \
      --out ../../postcheck/assets/licenses/open-images-attribution.txt

One --model per shipped custom model. Standard library only.
"""

from __future__ import annotations

import argparse
import csv
import pathlib
import sys

HEAD = """Open Images Dataset V7 (Google LLC)

The custom on-device detectors in this app are EfficientDet-Lite0 models
fine-tuned on photos and annotations from the Open Images Dataset V7
(https://storage.googleapis.com/openimages/web/index.html).

Annotations: Copyright Google LLC, licensed under the Creative Commons
Attribution 4.0 International License (CC BY 4.0),
https://creativecommons.org/licenses/by/4.0/

Images: published on Flickr by the authors listed below, licensed under the
Creative Commons Attribution 2.0 Generic License (CC BY 2.0),
https://creativecommons.org/licenses/by/2.0/
Google LLC does not own these images. The images are used only to train the
models; no image is included in the app. Changes: the images were resized
(and, where noted in the source repository, cropped and composited) for
training.
"""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", action="append", required=True, metavar="NAME=CSV")
    ap.add_argument("--out", required=True, type=pathlib.Path)
    args = ap.parse_args()
    parts = [HEAD]
    for spec in args.model:
        name, path = spec.split("=", 1)
        rows = list(csv.DictReader(open(path, encoding="utf-8")))
        parts.append(f"\nImages used to train {name} ({len(rows)}): author - source\n")
        parts.extend(f"{r['author']} - {r['url']}\n" for r in rows)
    args.out.write_text("".join(parts), encoding="utf-8")
    print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
