"""Generate a synthetic whiteboard dataset (images + Pascal VOC boxes + manifest).

Everything is drawn procedurally on this machine (Pillow + numpy); no external
image generator or API is used, so the boxes are exact by construction.

  python synth_whiteboard.py --out data/synth_whiteboard_v1

Each group is one synthetic room; several "shots" per group vary the camera
crop, lighting and blur, which mimics burst photos of the same place and lets
prepare_split.py exercise its group-based split.

Positives: whiteboard (wall-mounted or on a stand, with writing, glare,
perspective, partial occlusion) among room clutter. The box covers the
writing surface and frame, not the tray or legs.
Negatives: rooms whose dominant element is a look-alike: white_wall,
projector_screen, window, whiteboard_like_paper (flip chart), monitor_off.

Synthetic images are for building and smoke-testing the pipeline. Scores on
them do not describe accuracy on real photos.
"""

from __future__ import annotations

import argparse
import csv
import pathlib
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

import odlib

SCENE = (1600, 1200)
NEG_KINDS = ("white_wall", "projector_screen", "window", "whiteboard_like_paper", "monitor_off")
INK = [(20, 20, 25), (25, 50, 160), (180, 30, 30), (20, 120, 50)]


# ---------------------------------------------------------------- geometry
def homography(src, dst):
    """3x3 matrix mapping src points to dst points (4 correspondences)."""
    a, b = [], []
    for (x, y), (u, v) in zip(src, dst):
        a.append([x, y, 1, 0, 0, 0, -u * x, -u * y]); b.append(u)
        a.append([0, 0, 0, x, y, 1, -v * x, -v * y]); b.append(v)
    h = np.linalg.solve(np.array(a, float), np.array(b, float))
    return np.append(h, 1).reshape(3, 3)


def apply_h(h, pts):
    out = []
    for x, y in pts:
        u, v, w = h @ np.array([x, y, 1.0])
        out.append((u / w, v / w))
    return out


def paste_warped(canvas: Image.Image, tex: Image.Image, quad):
    """Alpha-composite RGBA texture onto canvas so its corners land on quad."""
    w, h = tex.size
    src = [(0, 0), (w, 0), (w, h), (0, h)]
    inv = homography(quad, src)  # PIL wants output->input coefficients
    coeffs = (inv / inv[2, 2]).flatten()[:8]
    warped = tex.transform(canvas.size, Image.PERSPECTIVE, tuple(coeffs), Image.BICUBIC)
    canvas.alpha_composite(warped)
    return homography(src, quad)


def jitter_quad(rng, x, y, w, h, persp):
    """Rectangle with perspective-like distortion (one side shorter)."""
    dx, dy = w * persp * rng.uniform(-1, 1), h * persp * rng.uniform(-0.6, 0.6)
    q = [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
    if dx > 0:  # right side farther away
        q[1] = (q[1][0], q[1][1] + dx * 0.5 + dy); q[2] = (q[2][0], q[2][1] - dx * 0.5 + dy)
    else:
        q[0] = (q[0][0], q[0][1] - dx * 0.5 + dy); q[3] = (q[3][0], q[3][1] + dx * 0.5 + dy)
    return [(px + rng.uniform(-4, 4), py + rng.uniform(-4, 4)) for px, py in q]


# ---------------------------------------------------------------- textures
def vgradient(size, top, bottom):
    w, h = size
    t = np.linspace(0, 1, h)[:, None, None]
    arr = np.array(top, float) * (1 - t) + np.array(bottom, float) * t
    return Image.fromarray(np.repeat(arr, w, axis=1).astype(np.uint8))


def scribble(draw, rng, box, density):
    """Handwriting-like strokes, boxes and arrows inside box."""
    x0, y0, x1, y1 = box
    color = rng.choice(INK)
    width = rng.randint(2, 5)
    line_h = rng.randint(24, 48)
    y = y0 + rng.randint(10, 40)
    while y < y1 - line_h and rng.random() < density:
        x = x0 + rng.randint(10, 60)
        if rng.random() < 0.3:
            color = rng.choice(INK)
        end = rng.uniform(x + 80, x1 - 20)
        while x < end:  # one "word"
            word = rng.randint(30, 120)
            pts, px = [], x
            while px < min(x + word, end):
                pts.append((px, y + rng.uniform(-line_h * 0.35, line_h * 0.35)))
                px += rng.uniform(5, 12)
            if len(pts) > 1:
                draw.line(pts, fill=color, width=width, joint="curve")
            x += word + rng.randint(15, 35)
        y += line_h + rng.randint(4, 20)
    for _ in range(rng.randint(0, 3)):
        bx, by = rng.uniform(x0, x1 - 60), rng.uniform(y0, y1 - 40)
        if rng.random() < 0.5:
            draw.rectangle([bx, by, bx + rng.uniform(40, 180), by + rng.uniform(30, 120)],
                           outline=rng.choice(INK), width=width)
        else:
            ex, ey = bx + rng.uniform(-150, 150), by + rng.uniform(-80, 80)
            draw.line([(bx, by), (ex, ey)], fill=rng.choice(INK), width=width)


def whiteboard_texture(rng, w, h):
    """RGBA texture: frame + surface (+ tray strip below). Returns (tex, board_h)."""
    tray = rng.randint(14, 28) if rng.random() < 0.8 else 0
    tex = Image.new("RGBA", (w, h + tray), (0, 0, 0, 0))
    frame_c = rng.choice([(170, 172, 175), (140, 142, 146), (200, 200, 205), (60, 60, 65)])
    t = max(6, int(min(w, h) * rng.uniform(0.012, 0.03)))
    d = ImageDraw.Draw(tex)
    d.rectangle([0, 0, w - 1, h - 1], fill=frame_c + (255,))
    base = rng.randint(236, 252)
    tint = rng.choice([(0, 0, 0), (0, 2, 6), (4, 2, 0)])
    surf = vgradient((w - 2 * t, h - 2 * t),
                     tuple(min(255, base + c) for c in tint),
                     tuple(max(0, base - rng.randint(4, 18) + c) for c in tint)).convert("RGBA")
    sd = ImageDraw.Draw(surf, "RGBA")
    # faint ghosting from earlier erased writing
    for _ in range(rng.randint(0, 6)):
        gx, gy = rng.uniform(0, surf.width), rng.uniform(0, surf.height)
        sd.ellipse([gx, gy, gx + rng.uniform(60, 300), gy + rng.uniform(20, 90)],
                   fill=(150, 150, 160, rng.randint(8, 25)))
    if rng.random() < 0.85:
        scribble(sd, rng, (0, 0, surf.width, surf.height), rng.uniform(0.4, 0.95))
    # glossy glare band
    if rng.random() < 0.7:
        glare = Image.new("L", surf.size, 0)
        gd = ImageDraw.Draw(glare)
        gx = rng.uniform(-0.2, 0.9) * surf.width
        gw = rng.uniform(0.08, 0.3) * surf.width
        gd.polygon([(gx, 0), (gx + gw, 0), (gx + gw - surf.width * 0.15, surf.height),
                    (gx - surf.width * 0.15, surf.height)], fill=rng.randint(40, 110))
        glare = glare.filter(ImageFilter.GaussianBlur(25))
        surf = Image.composite(Image.new("RGBA", surf.size, (255, 255, 255, 255)), surf, glare)
    for _ in range(rng.randint(0, 4)):  # magnets
        mx, my = rng.uniform(10, surf.width - 30), rng.uniform(10, surf.height - 30)
        ImageDraw.Draw(surf).ellipse([mx, my, mx + 18, my + 18],
                                     fill=rng.choice([(200, 40, 40), (40, 80, 200), (30, 30, 30)]))
    tex.paste(surf, (t, t))
    if tray:
        d.rectangle([w * 0.05, h, w * 0.95, h + tray - 1], fill=frame_c + (255,))
    return tex, h


def flipchart_texture(rng, w, h):
    tex = Image.new("RGBA", (w, h), (248, 247, 240, 255))
    d = ImageDraw.Draw(tex)
    d.rectangle([0, 0, w - 1, 18], fill=(60, 60, 60, 255))
    if rng.random() < 0.8:
        scribble(d, rng, (5, 25, w - 5, h - 5), 0.8)
    return tex


# ---------------------------------------------------------------- scene
def room(rng):
    """Room style shared by all shots in a group."""
    wall = rng.choice([(226, 218, 200), (205, 205, 200), (190, 205, 215), (235, 232, 225),
                       (215, 200, 185), (175, 180, 170), (240, 240, 238)])
    return {"wall": wall, "floor": rng.choice([(120, 90, 60), (90, 90, 95), (150, 120, 90),
                                               (70, 75, 85)]),
            "horizon": rng.uniform(0.68, 0.85), "seed": rng.random()}


def draw_room(rng, style, extras):
    w, h = SCENE
    hz = int(h * style["horizon"])
    top = tuple(min(255, c + 12) for c in style["wall"])
    bottom = tuple(max(0, c - 18) for c in style["wall"])
    img = vgradient((w, hz), top, bottom).convert("RGBA")
    canvas = Image.new("RGBA", SCENE)
    canvas.paste(img, (0, 0))
    floor = vgradient((w, h - hz), style["floor"], tuple(max(0, c - 30) for c in style["floor"]))
    canvas.paste(floor.convert("RGBA"), (0, hz))
    d = ImageDraw.Draw(canvas)
    d.rectangle([0, hz - 6, w, hz], fill=tuple(max(0, c - 50) for c in style["wall"]))
    for kind in extras:
        place_distractor(rng, canvas, kind, hz)
    return canvas, hz


def free_rect(rng, hz, wr, hr):
    w, h = SCENE
    bw, bh = w * rng.uniform(*wr), hz * rng.uniform(*hr)
    x = rng.uniform(0, w - bw)
    y = rng.uniform(hz * 0.05, max(hz * 0.06, hz - bh - 10))
    return x, y, bw, bh


def place_distractor(rng, canvas, kind, hz):
    d = ImageDraw.Draw(canvas)
    if kind == "window":
        x, y, bw, bh = free_rect(rng, hz, (0.15, 0.4), (0.35, 0.75))
        sky = vgradient((int(bw), int(bh)), (200, 225, 245), (245, 248, 250))
        canvas.paste(sky.convert("RGBA"), (int(x), int(y)))
        n = rng.randint(1, 3)
        for i in range(1, n + 1):
            d.line([(x + bw * i / (n + 1), y), (x + bw * i / (n + 1), y + bh)], fill=(235, 235, 235), width=10)
        d.line([(x, y + bh / 2), (x + bw, y + bh / 2)], fill=(235, 235, 235), width=8)
        d.rectangle([x, y, x + bw, y + bh], outline=(225, 225, 222), width=14)
    elif kind == "projector_screen":
        x, y, bw, bh = free_rect(rng, hz, (0.3, 0.55), (0.45, 0.8))
        d.rectangle([x - 10, y - 26, x + bw + 10, y], fill=(40, 40, 42))
        d.rectangle([x, y, x + bw, y + bh], fill=tuple([rng.randint(232, 250)] * 3),
                    outline=(30, 30, 30), width=rng.choice([0, 6, 12]))
    elif kind == "white_wall":
        x, y, bw, bh = free_rect(rng, hz, (0.4, 0.8), (0.6, 0.95))
        v = rng.randint(238, 252)
        d.rectangle([x, y, x + bw, y + bh], fill=(v, v, v - 2))
        if rng.random() < 0.5:
            d.line([(x, y + bh), (x + bw, y + bh)], fill=(200, 200, 200), width=6)
    elif kind == "whiteboard_like_paper":
        bw, bh = SCENE[0] * rng.uniform(0.12, 0.22), hz * rng.uniform(0.35, 0.55)
        x, y = rng.uniform(0, SCENE[0] - bw), hz - bh - rng.uniform(80, 200)
        canvas.alpha_composite(flipchart_texture(rng, int(bw), int(bh)), (int(x), int(y)))
        for lx in (x + bw * 0.15, x + bw * 0.85):
            d.line([(lx, y + bh), (lx + rng.uniform(-40, 40), hz + 60)], fill=(70, 70, 70), width=8)
    elif kind == "monitor_off":
        x, y, bw, bh = free_rect(rng, hz, (0.15, 0.35), (0.2, 0.4))
        d.rectangle([x, y, x + bw, y + bh], fill=(25, 25, 28), outline=(55, 55, 58), width=10)
        d.rectangle([x + bw / 2 - 15, y + bh, x + bw / 2 + 15, y + bh + 40], fill=(50, 50, 52))
    elif kind == "poster":
        x, y, bw, bh = free_rect(rng, hz, (0.06, 0.15), (0.15, 0.3))
        d.rectangle([x, y, x + bw, y + bh], fill=tuple(rng.randint(40, 230) for _ in range(3)))
        for _ in range(4):
            px, py = rng.uniform(x, x + bw * 0.8), rng.uniform(y, y + bh * 0.8)
            d.rectangle([px, py, px + bw * 0.2, py + bh * 0.1], fill=tuple(rng.randint(0, 255) for _ in range(3)))
    elif kind == "door":
        x, y, bw, bh = rng.uniform(0, SCENE[0] - 260), hz * 0.25, rng.uniform(180, 260), hz * 0.75
        d.rectangle([x, y, x + bw, y + bh], fill=rng.choice([(130, 95, 60), (180, 180, 180), (90, 70, 50)]))
        d.ellipse([x + bw - 40, y + bh * 0.5, x + bw - 22, y + bh * 0.5 + 18], fill=(200, 200, 200))


def draw_foreground(rng, canvas, hz):
    d = ImageDraw.Draw(canvas)
    w, h = SCENE
    for _ in range(rng.randint(0, 3)):  # tables / chairs in front
        tx, ty = rng.uniform(-100, w - 200), rng.uniform(hz - 40, h - 150)
        tw, th = rng.uniform(250, 700), rng.uniform(40, 90)
        c = rng.choice([(150, 110, 70), (200, 200, 200), (90, 90, 95), (40, 60, 120)])
        d.polygon([(tx, ty), (tx + tw, ty), (tx + tw + 40, ty + th), (tx - 40, ty + th)], fill=c)
        for lx in (tx, tx + tw):
            d.rectangle([lx - 6, ty + th, lx + 6, ty + th + rng.uniform(80, 200)], fill=(60, 60, 60))
    if rng.random() < 0.3:  # person-like silhouette
        px, py = rng.uniform(0, w - 200), rng.uniform(hz * 0.45, hz * 0.7)
        c = tuple(rng.randint(20, 120) for _ in range(3))
        d.ellipse([px + 45, py, px + 125, py + 90], fill=(190, 150, 120))
        d.rounded_rectangle([px, py + 85, px + 170, py + 600], 40, fill=c)


def add_whiteboard(rng, canvas, hz):
    w, h = SCENE
    bw = w * rng.uniform(0.2, 0.6)
    bh = bw * rng.uniform(0.45, 0.75)
    stand = rng.random() < 0.3
    x = rng.uniform(20, w - bw - 20)
    y = (hz - bh - rng.uniform(150, 260)) if stand else rng.uniform(hz * 0.08, max(hz * 0.1, hz - bh - 40))
    quad = jitter_quad(rng, x, y, bw, bh, rng.uniform(0, 0.25))
    tex, board_h = whiteboard_texture(rng, int(bw), int(bh))
    fwd = paste_warped(canvas, tex, quad)
    board = apply_h(fwd, [(0, 0), (tex.width, 0), (tex.width, board_h), (0, board_h)])
    if stand:
        d = ImageDraw.Draw(canvas)
        for fx in (0.12, 0.88):
            bx, by = apply_h(fwd, [(tex.width * fx, tex.height)])[0]
            d.line([(bx, by), (bx + rng.uniform(-30, 30), hz + rng.uniform(80, 160))], fill=(90, 90, 95), width=10)
    xs, ys = [p[0] for p in board], [p[1] for p in board]
    return [min(xs), min(ys), max(xs), max(ys)]


def shoot(rng, scene: Image.Image, boxes, out_long):
    """Random camera crop + photometric changes. Returns image and boxes in it."""
    w, h = SCENE
    for _ in range(50):
        aspect = rng.choice([4 / 3, 3 / 4, 16 / 9])
        cw = w * rng.uniform(0.55, 0.95)
        ch = cw / aspect
        if ch > h:
            ch = h * rng.uniform(0.7, 1.0); cw = ch * aspect
        if cw > w:
            continue
        cx, cy = rng.uniform(0, w - cw), rng.uniform(0, h - ch)
        kept = []
        ok = True
        for b in boxes:
            ix0, iy0 = max(b[0], cx), max(b[1], cy)
            ix1, iy1 = min(b[2], cx + cw), min(b[3], cy + ch)
            inter = max(0, ix1 - ix0) * max(0, iy1 - iy0)
            area = (b[2] - b[0]) * (b[3] - b[1])
            if inter / area >= 0.6:
                kept.append([ix0 - cx, iy0 - cy, ix1 - cx, iy1 - cy])
            elif inter > 0:
                ok = False  # ambiguous partial board; re-crop
        if ok and len(kept) == len(boxes):
            break
    else:
        return None, None
    img = scene.crop((int(cx), int(cy), int(cx + cw), int(cy + ch))).convert("RGB")
    s = out_long / max(img.size)
    img = img.resize((round(img.width * s), round(img.height * s)), Image.BILINEAR)
    iw, ih = img.size
    kept = [[max(0.0, b[0] * s), max(0.0, b[1] * s), min(iw - 1.0, b[2] * s), min(ih - 1.0, b[3] * s)]
            for b in kept]
    img = ImageEnhance.Brightness(img).enhance(rng.uniform(0.6, 1.25))
    img = ImageEnhance.Contrast(img).enhance(rng.uniform(0.75, 1.2))
    arr = np.asarray(img).astype(float)
    arr *= np.array([rng.uniform(0.9, 1.08), 1.0, rng.uniform(0.88, 1.1)])  # color temperature
    # vignetting / uneven light
    yy, xx = np.mgrid[0:arr.shape[0], 0:arr.shape[1]]
    lx, ly = rng.uniform(0, arr.shape[1]), rng.uniform(0, arr.shape[0])
    dist = np.sqrt((xx - lx) ** 2 + (yy - ly) ** 2) / max(arr.shape)
    arr *= (1 - rng.uniform(0, 0.35) * dist)[..., None]
    arr += np.random.default_rng(rng.randint(0, 2 ** 31)).normal(0, rng.uniform(1, 7), arr.shape)
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    if rng.random() < 0.4:
        img = img.filter(ImageFilter.GaussianBlur(rng.uniform(0.5, 1.8)))
    return img, kept


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True, type=pathlib.Path)
    ap.add_argument("--positive-groups", type=int, default=40)
    ap.add_argument("--negative-groups", type=int, default=25)
    ap.add_argument("--shots", type=int, default=5, help="images per group (same room)")
    ap.add_argument("--long-side", type=int, default=960)
    ap.add_argument("--seed", type=int, default=20261109)
    args = ap.parse_args()

    if args.out.exists() and any(args.out.iterdir()):
        print(f"{args.out} is not empty; choose a new directory", file=sys.stderr)
        return 1
    (args.out / "images").mkdir(parents=True, exist_ok=True)
    (args.out / "annotations").mkdir(parents=True, exist_ok=True)
    master = random.Random(args.seed)
    rows = []
    plan = [("positive", i) for i in range(args.positive_groups)] + \
           [("negative", i) for i in range(args.negative_groups)]
    for kind, gi in plan:
        rng = random.Random(master.random())
        style = room(rng)
        neg_kind = NEG_KINDS[gi % len(NEG_KINDS)] if kind == "negative" else "none"
        extras = [k for k in ("poster", "door", "window", "monitor_off", "projector_screen",
                              "whiteboard_like_paper") if rng.random() < 0.25]
        if kind == "negative":
            extras = [neg_kind] + [e for e in extras if e != neg_kind]
        group = f"synth-{kind[:3]}-{gi:03d}"
        scene, hz = draw_room(rng, style, extras)
        boxes = []
        if kind == "positive":
            boxes.append(add_whiteboard(rng, scene, hz))
            if rng.random() < 0.15:  # a second board in some rooms
                b2 = add_whiteboard(rng, scene, hz)
                if all(odlib.Box("", *b2).iou(odlib.Box("", *b)) == 0 for b in boxes):
                    boxes.append(b2)
        draw_foreground(rng, scene, hz)
        written = 0
        for si in range(args.shots * 3):
            if written == args.shots:
                break
            img, kept = shoot(rng, scene, boxes, args.long_side)
            if img is None or any(min(b[2] - b[0], b[3] - b[1]) < 12 for b in kept):
                continue
            name = f"{group}_{written:02d}.jpg"
            img.save(args.out / "images" / name, "JPEG", quality=rng.randint(70, 95))
            odlib.write_voc(args.out / "annotations" / f"{pathlib.Path(name).stem}.xml",
                            odlib.Annotation(name, img.width, img.height,
                                             [odlib.Box("whiteboard", *b) for b in kept]))
            rows.append({"image": name, "group_id": group, "kind": kind, "negative_kind": neg_kind,
                         "source": f"synthetic:synth_whiteboard.py seed={args.seed}",
                         "license": "generated-in-house (no third-party content)",
                         "rights_holder": "PostCheck team", "consent": "not_required",
                         "notes": "synthetic; not evidence of accuracy on real photos"})
            written += 1
    odlib.write_csv(args.out / "manifest.csv", rows, list(odlib.MANIFEST_COLUMNS))
    pos = sum(r["kind"] == "positive" for r in rows)
    print(f"wrote {len(rows)} images ({pos} positive, {len(rows) - pos} negative) to {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
