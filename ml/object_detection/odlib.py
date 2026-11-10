"""Shared helpers for the PostCheck object detection pipeline.

Only the Python standard library and Pillow are used here, so the dataset
checks can run either inside the training container or on any host Python.
"""

from __future__ import annotations

import csv
import dataclasses
import pathlib
import xml.etree.ElementTree as ET
from typing import Dict, Iterable, List, Optional

IMAGE_SUFFIXES = (".jpg", ".jpeg", ".png")

# manifest.csv columns. Rights/provenance columns are mandatory so that every
# image used for training has a recorded origin.
MANIFEST_COLUMNS = (
    "image",          # file name inside images/
    "group_id",       # capture location + session; never split across sets
    "kind",           # positive | negative
    "negative_kind",  # none | white_wall | projector_screen | window | ...
    "source",         # team_capture | public_dataset:<name> | ...
    "license",        # e.g. internal-consent, CC-BY-4.0
    "rights_holder",  # who may grant use of the image
    "consent",        # yes | not_required (no people/private info) | ...
    "notes",
)


@dataclasses.dataclass
class Box:
    label: str
    xmin: float
    ymin: float
    xmax: float
    ymax: float
    difficult: bool = False

    def iou(self, other: "Box") -> float:
        ix = max(0.0, min(self.xmax, other.xmax) - max(self.xmin, other.xmin))
        iy = max(0.0, min(self.ymax, other.ymax) - max(self.ymin, other.ymin))
        inter = ix * iy
        union = self.area() + other.area() - inter
        return inter / union if union > 0 else 0.0

    def area(self) -> float:
        return max(0.0, self.xmax - self.xmin) * max(0.0, self.ymax - self.ymin)


@dataclasses.dataclass
class Annotation:
    filename: str
    width: int
    height: int
    boxes: List[Box]


def read_labels(path: pathlib.Path) -> List[str]:
    labels = [l.strip() for l in path.read_text(encoding="utf-8").splitlines()]
    labels = [l for l in labels if l and not l.startswith("#")]
    if not labels or len(set(labels)) != len(labels):
        raise SystemExit(f"{path}: labels must be non-empty and unique")
    if "background" in labels:
        raise SystemExit(f"{path}: 'background' is reserved by Model Maker")
    return labels


def read_voc(path: pathlib.Path) -> Annotation:
    root = ET.parse(path).getroot()
    size = root.find("size")
    if size is None:
        raise ValueError(f"{path}: <size> missing")
    width = int(float(size.findtext("width", "0")))
    height = int(float(size.findtext("height", "0")))
    boxes = []
    for obj in root.findall("object"):
        bnd = obj.find("bndbox")
        if bnd is None:
            raise ValueError(f"{path}: <object> without <bndbox>")
        boxes.append(Box(
            label=(obj.findtext("name") or "").strip(),
            xmin=float(bnd.findtext("xmin")),
            ymin=float(bnd.findtext("ymin")),
            xmax=float(bnd.findtext("xmax")),
            ymax=float(bnd.findtext("ymax")),
            difficult=(obj.findtext("difficult") or "0").strip() == "1",
        ))
    return Annotation(root.findtext("filename") or path.stem, width, height, boxes)


def write_voc(path: pathlib.Path, ann: Annotation) -> None:
    root = ET.Element("annotation")
    ET.SubElement(root, "filename").text = ann.filename
    size = ET.SubElement(root, "size")
    ET.SubElement(size, "width").text = str(ann.width)
    ET.SubElement(size, "height").text = str(ann.height)
    ET.SubElement(size, "depth").text = "3"
    for b in ann.boxes:
        obj = ET.SubElement(root, "object")
        ET.SubElement(obj, "name").text = b.label
        ET.SubElement(obj, "pose").text = "Unspecified"
        ET.SubElement(obj, "truncated").text = "0"
        ET.SubElement(obj, "difficult").text = "1" if b.difficult else "0"
        bnd = ET.SubElement(obj, "bndbox")
        for key in ("xmin", "ymin", "xmax", "ymax"):
            ET.SubElement(bnd, key).text = str(int(round(getattr(b, key))))
    ET.indent(root)
    path.write_text(ET.tostring(root, encoding="unicode"), encoding="utf-8")


def read_manifest(path: pathlib.Path) -> List[Dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        missing = [c for c in MANIFEST_COLUMNS if c not in (reader.fieldnames or [])]
        if missing:
            raise SystemExit(f"{path}: missing columns {missing}")
        return [{k: (v or "").strip() for k, v in row.items()} for row in reader]


def write_csv(path: pathlib.Path, rows: Iterable[Dict[str, object]],
              columns: Optional[List[str]] = None) -> None:
    rows = list(rows)
    columns = columns or (list(rows[0].keys()) if rows else [])
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def dhash(image, size: int = 8) -> int:
    """64-bit difference hash, used to flag near-duplicate frames across splits."""
    gray = image.convert("L").resize((size + 1, size))
    px = list(gray.getdata())
    bits = 0
    for row in range(size):
        for col in range(size):
            left = px[row * (size + 1) + col]
            right = px[row * (size + 1) + col + 1]
            bits = (bits << 1) | (1 if left > right else 0)
    return bits
