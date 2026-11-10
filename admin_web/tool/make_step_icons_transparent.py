"""Rebuild step icons as sharp black glyphs on transparent square canvas.

Requires original-looking source. If already converted, this still works on
near-black glyphs with soft alpha by thresholding alpha/luminance.
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1] / "assets" / "steps"
FILES = ["step_facility.png", "step_rules.png", "step_confirm.png"]
SIZE = 256
WHITE = 200


def to_mask(im: Image.Image) -> Image.Image:
    rgba = im.convert("RGBA")
    w, h = rgba.size
    px = rgba.load()
    out = Image.new("L", (w, h), 0)
    op = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 16:
                continue
            # Treat dark / opaque ink as glyph.
            lum = (r + g + b) / 3
            if lum <= WHITE and a >= 16:
                # binary-ish with soft edge kept
                strength = min(255, int((WHITE - lum) * (a / 255.0) * (255 / max(1, WHITE))))
                if strength < 40 and a > 200 and lum < 40:
                    strength = 255
                if strength >= 40:
                    op[x, y] = 255 if strength > 120 else strength
    return out


def convert(path: Path) -> None:
    src = Image.open(path)
    mask = to_mask(src)
    # bbox from mask
    bbox = mask.getbbox()
    if bbox is None:
        raise SystemExit(f"no ink found in {path.name}")
    mask = mask.crop(bbox)
    tw, th = mask.size
    side = int(max(tw, th) * 1.12)  # small padding
    canvas_mask = Image.new("L", (side, side), 0)
    canvas_mask.paste(mask, ((side - tw) // 2, (side - th) // 2))
    canvas_mask = canvas_mask.resize((SIZE, SIZE), Image.Resampling.LANCZOS)

    # black RGB + mask alpha
    rgba = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    black = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 255))
    rgba = Image.composite(black, rgba, canvas_mask)
    rgba.save(path)
    hist = canvas_mask.histogram()
    print(f"{path.name}: ink={sum(hist[1:])} transparent={hist[0]}")


def main() -> None:
    for name in FILES:
        convert(ROOT / name)


if __name__ == "__main__":
    main()
