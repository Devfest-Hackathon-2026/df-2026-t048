"""Emit white-on-transparent step icons for the blue pill (no runtime tint)."""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1] / "assets" / "steps"
FILES = ["step_facility.png", "step_rules.png", "step_confirm.png"]


def main() -> None:
    for name in FILES:
        path = ROOT / name
        im = Image.open(path).convert("RGBA")
        px = im.load()
        w, h = im.size
        for y in range(h):
            for x in range(w):
                r, g, b, a = px[x, y]
                if a == 0:
                    continue
                # keep alpha, force RGB white
                px[x, y] = (255, 255, 255, a)
        im.save(path)
        print("whitened", name)


if __name__ == "__main__":
    main()
