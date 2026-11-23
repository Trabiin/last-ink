#!/usr/bin/env python3
"""Turn the raw AI portraits (1024x1536, flat light-grey background) into game portraits.

Usage: python3 tools/cut_portraits.py SRC_DIR [OUT_DIR] [--painted DIR] [--only id,id]
Reads SRC_DIR/<id>-v2.png (or <id>.png), cuts out the grey background (flood fill from the edges,
pockets between hair strands, the pale glow around strands, stray specks), cleans the background
colour out of the edge, and writes:
  - OUT_DIR/<id>.png: the game portrait, hi-res pixel art 224x336 (tools/portrait_style.py pixelate),
    1 canvas pixel per art pixel in the dialogue box;
  - with --painted DIR, also the painted cut-out at 512x768 (kept in project files for reference).
Expression variants follow the same naming: <id>_<expr>-v2.png -> <id>_<expr>.png.
Then run the check: python3 tools/check_portraits.py (tests/test_portraits.gd runs the same check).
"""
import sys, os, glob
from collections import deque
from PIL import Image, ImageFilter
import numpy as np
from pathlib import Path
from scipy import ndimage

TOL = 22  # how far (max channel diff) from the background grey still counts as background
SIZE = (512, 768)  # painted cut-out
PIXEL_H = 336  # game portrait height in art pixels (224x336)
PIXEL_COLOURS = 24  # 24 since the speckle cleanup (2026-11-23): fewer near-duplicate shades, less noise
POCKET = 40  # enclosed background blobs bigger than this (in source pixels) are cleared too
# Characters whose own colours sit close to the background grey (Ilse's pale hair) only lose big pockets.
POCKET_FOR = {"ilse": 1500}
# How far colours are pulled onto the game palette (0.4 default). Hesper's olive coat turns brown at 0.4,
# and her sprite is olive, so hers is pulled less.
PULL_FOR = {"hesper": 0.12}


def cut(path: str, pocket: int = POCKET) -> Image.Image:
    im = Image.open(path).convert("RGB")
    w, h = im.size
    px = im.load()
    corners = [px[2, 2], px[w - 3, 2], px[2, h // 2], px[w - 3, h // 2], px[w // 2, 2]]
    bg = tuple(sorted(c[i] for c in corners)[len(corners) // 2] for i in range(3))

    def is_bg(p):
        # the grey itself, or the paper-white "erased" flecks that touch it (they read as holes in the
        # art, so on a dark background they should be see-through too)
        if max(p) - min(p) >= 16:
            return False
        if min(p) >= bg[0] - TOL // 2 and max(p) > bg[0]:
            return True
        return max(abs(p[0] - bg[0]), abs(p[1] - bg[1]), abs(p[2] - bg[2])) <= TOL

    def near(p):
        return max(abs(p[0] - bg[0]), abs(p[1] - bg[1]), abs(p[2] - bg[2])) <= 9

    mask = Image.new("L", (w, h), 255)
    m = mask.load()
    q = deque()
    for x in range(w):
        q.append((x, 0)); q.append((x, h - 1))
    for y in range(h):
        q.append((0, y)); q.append((w - 1, y))
    while q:
        x, y = q.popleft()
        if m[x, y] == 0 or not is_bg(px[x, y]):
            continue
        m[x, y] = 0
        if x > 0: q.append((x - 1, y))
        if x < w - 1: q.append((x + 1, y))
        if y > 0: q.append((x, y - 1))
        if y < h - 1: q.append((x, y + 1))
    # Pockets of background enclosed by the figure (between an axe and a head, say): clear any
    # big blob that is almost exactly the background grey.
    seen = bytearray(w * h)
    for sy in range(0, h, 2):
        for sx in range(0, w, 2):
            if seen[sy * w + sx] or m[sx, sy] == 0 or not near(px[sx, sy]):
                continue
            blob, q2 = [], deque([(sx, sy)])
            seen[sy * w + sx] = 1
            while q2:
                x, y = q2.popleft()
                blob.append((x, y))
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and m[nx, ny] and near(px[nx, ny]):
                        seen[ny * w + nx] = 1
                        q2.append((nx, ny))
            if len(blob) > pocket:
                for x, y in blob:
                    m[x, y] = 0
    mask = clear_halo_pockets(np.asarray(im), mask, bg)
    mask = drop_specks(mask)
    # shave the grey fringe and soften the edge
    mask = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1.2))
    out = Image.fromarray(np.dstack([decontaminate(np.asarray(im), np.asarray(mask), bg), np.asarray(mask)]), "RGBA")
    return out.resize(SIZE, Image.LANCZOS)


def clear_halo_pockets(rgb: np.ndarray, mask: Image.Image, bg, reach: int = 28, biggest: int = 3000) -> Image.Image:
    """Fine hair traps small pockets of background between strands, and the generator paints a pale glow
    around strands. Those pockets are not reached by the edge flood fill. Any background-like pixel blob
    (the grey, or the paler glow) that lies close to the outside and is not too big is cleared too.
    Big pale areas (shirts, paper, Ilse's hair) are left alone."""
    rgb = rgb.astype(np.int16)
    m = np.asarray(mask) > 0
    lo, hi = rgb.min(-1), rgb.max(-1)
    bgl = int(np.mean(bg))
    like = (hi - lo < 16) & (lo >= bgl - TOL) & m
    near_out = ndimage.distance_transform_edt(m) < reach
    lab, n = ndimage.label(like)
    if n == 0:
        return mask
    idx = np.arange(1, n + 1)
    sizes = ndimage.sum(like, lab, idx)
    close = ndimage.mean(near_out, lab, idx)
    kill = idx[(sizes < biggest) & (close > 0.85) & (sizes > 3)]
    out = np.asarray(mask).copy()
    out[np.isin(lab, kill)] = 0
    return Image.fromarray(out, "L")


def drop_specks(mask: Image.Image, keep: int = 400) -> Image.Image:
    """Opaque islands smaller than `keep` source pixels that float free of the figure (stray flecks of
    art or background noise) are removed."""
    m = np.asarray(mask) > 0
    lab, n = ndimage.label(m)
    if n <= 1:
        return mask
    sizes = ndimage.sum(m, lab, range(1, n + 1))
    small = np.isin(lab, np.nonzero(sizes < keep)[0] + 1)
    return Image.fromarray(np.where(small, 0, np.asarray(mask)).astype(np.uint8), "L")


def decontaminate(rgb: np.ndarray, alpha: np.ndarray, bg, band: int = 8, near: int = 46) -> np.ndarray:
    """The grey background bleeds into the figure's edge (between hair strands, along frayed cloth), which
    shows as a pale halo on dark scenes and as white specks once pixelated. Within `band` source pixels of
    the edge, every pixel still close to the background grey takes the colour of the nearest clean pixel
    of the figure instead."""
    rgb = rgb.astype(np.int16)
    solid = alpha > 0
    dist_bg = np.abs(rgb - np.array(bg, np.int16)).max(-1)
    neutral = (rgb.max(-1) - rgb.min(-1)) < 20
    inner = ndimage.binary_erosion(solid, iterations=band)
    band_px = solid & ~inner
    dirty = band_px & (dist_bg < near) & neutral
    dirty |= (alpha < 255) & (dist_bg < near) & neutral
    dirty |= ~solid
    clean = solid & ~dirty
    if not clean.any():
        return rgb.astype(np.uint8)
    _, (iy, ix) = ndimage.distance_transform_edt(~clean, return_indices=True)
    out = rgb[iy, ix]
    out[clean] = rgb[clean]
    return out.astype(np.uint8)


def main():
    import argparse
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import portrait_style
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst", nargs="?", default=os.path.join(os.path.dirname(__file__), "..", "assets", "portraits"))
    ap.add_argument("--painted", default="")
    ap.add_argument("--only", default="")
    args = ap.parse_args()
    only = set(x for x in args.only.split(",") if x)
    os.makedirs(args.dst, exist_ok=True)
    pal = portrait_style.palette()
    for f in sorted(glob.glob(os.path.join(args.src, "*.png"))):
        name = os.path.basename(f)[:-4]
        if name.endswith("-test1"):
            continue
        pid = name[:-3] if name.endswith("-v2") else name
        if only and pid not in only:
            continue
        painted = cut(f, POCKET_FOR.get(pid.split("_")[0], POCKET))
        if args.painted:
            os.makedirs(args.painted, exist_ok=True)
            painted.save(os.path.join(args.painted, pid + ".png"), optimize=True)
        a = np.asarray(painted, np.float32) / 255.0
        rgb, alpha = portrait_style.pixelate(a[..., :3], a[..., 3], pal, PIXEL_H, PIXEL_COLOURS, PULL_FOR.get(pid, 0.4))
        portrait_style.save(rgb, alpha, Path(args.dst) / (pid + ".png"))
        print("wrote", pid)


if __name__ == "__main__":
    main()
