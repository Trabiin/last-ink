#!/usr/bin/env python3
"""Recolour one material of a character's field sprite so it matches the canon portrait (issue #166).

    python3 tools/recolor_sprite.py velvette hair
    python3 tools/recolor_sprite.py abeyance hood

Each fix in FIXES picks the pixels of one material by colour (hue/lightness/saturation window) across every
strip of the sprite, and either turns the hue or maps the ramp by lightness onto a new ramp. Outline ink
and every other material are left alone. Fixes are listed in tools/ai_fixes.json ("recolor" entries).
"""
import colorsys
import glob
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _hls(c):
    h, l, s = colorsys.rgb_to_hls(*(v / 255.0 for v in c[:3]))
    return h * 360, l, s


def hue_turn(lo, hi, min_s, turn):
    def f(c):
        h, l, s = _hls(c)
        if lo <= h <= hi and s >= min_s:
            r, g, b = colorsys.hls_to_rgb(((h + turn) % 360) / 360.0, l, s)
            return (round(r * 255), round(g * 255), round(b * 255))
        return None
    return f


def ramp_map(max_s, l_lo, l_hi, ramp):
    """Greys with lightness in [l_lo, l_hi] go onto ramp (dark to light) by their place in that window."""
    def f(c, y=0):
        h, l, s = _hls(c)
        if s <= max_s and l_lo <= l <= l_hi:
            t = (l - l_lo) / (l_hi - l_lo)
            return ramp[min(len(ramp) - 1, int(t * len(ramp)))]
        return None
    return f


def hue_set(lo, hi, min_s, min_l, hue, s_mul, l_mul, max_l=1.0, max_s=1.0, s_add=0.0):
    """Colours in the hue window (and not outline-dark) move to one hue, keeping their shading."""
    def f(c):
        h, l, s = _hls(c)
        if lo <= h <= hi and min_s <= s <= max_s and min_l <= l <= max_l:
            s = min(1.0, s * s_mul + s_add)
            r, g, b = colorsys.hls_to_rgb(hue / 360.0, min(1.0, l * l_mul), s)
            return (round(r * 255), round(g * 255), round(b * 255))
        return None
    return f


def hue_ramp(lo, hi, min_s, min_l, ramp):
    """Colours in the hue window go onto ramp (dark to light) by their lightness (e.g. gold to bone white)."""
    def f(c):
        h, l, s = _hls(c)
        if lo <= h <= hi and s >= min_s and l >= min_l:
            t = min(0.999, max(0.0, (l - min_l) / (0.85 - min_l)))
            return ramp[int(t * len(ramp))]
        return None
    return f


def vest_split(path, fw):
    """Ottoline: the sprite had magenta sleeves over a black-and-magenta checked vest; the portrait has a
    dark shirt under a crimson vest. Magenta in blobs of 5+ pixels (4-connected: the sleeves) and anything
    below the waist (frame row 29 down) goes charcoal; the checked magenta goes crimson, and the dark checks between them
    deep crimson, so the vest reads as one crimson piece."""
    import numpy as np

    def is_mag(c):
        h, l, s = _hls(c)
        return 300 <= h <= 335 and s >= 0.8 and l >= 0.1

    im = Image.open(path).convert("RGBA")
    a = np.asarray(im).copy()
    H, W = a.shape[:2]
    mag = np.zeros((H, W), bool)
    for y in range(H):
        for x in range(W):
            if a[y, x, 3] and is_mag(a[y, x]):
                mag[y, x] = True
    from scipy import ndimage
    lab, nl = ndimage.label(mag)  # the vest's checks are single pixels or short runs; sleeves are solid
    sizes = ndimage.sum(mag, lab, range(1, nl + 1))
    big = np.isin(lab, np.nonzero(sizes >= 5)[0] + 1)
    rows = (np.arange(H) % fw)[:, None]
    sleeve = mag & (big | (rows >= 29))
    vest = mag & ~sleeve
    out = a.copy()
    for y, x in zip(*np.nonzero(sleeve)):
        h, l, s_ = _hls(a[y, x])
        v = max(24, min(70, int(20 + (l - 0.2) * 90)))
        out[y, x, :3] = (v, v - 2, v + 2)
    for y, x in zip(*np.nonzero(vest)):
        h, l, s_ = _hls(a[y, x])
        r, g, b = colorsys.hls_to_rgb(352 / 360.0, l * 0.9, s_ * 0.72)
        out[y, x, :3] = (round(r * 255), round(g * 255), round(b * 255))
    vp = np.pad(vest, 1)
    vn = sum(np.roll(np.roll(vp, dy, 0), dx, 1) for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)))[1:-1, 1:-1]
    dark = (a[..., 3] > 0) & (a[..., :3].max(-1) < 60) & ~mag & (vn >= 3) & (rows < 29)
    out[dark, :3] = (92, 14, 30)
    Image.fromarray(out).save(path)


REGION = {("ottoline", "vest"): vest_split}  # fixes that need the pixel's neighbours, not only its colour

ROW_LIMIT = {("abeyance", "hood"): 34}  # frame rows at or below this are left alone
ROW_FROM = {("auditor", "cravat"): 34}  # frame rows above this are left alone (the Auditor's mask)

FIXES = {
    # Portrait: crimson red bob. Sprite was magenta-maroon.
    ("velvette", "hair"): hue_turn(315, 345, 0.40, 26),
    # Portrait: bone-white hood and robe. Sprite hood and back were slate grey.
    # Rows from 34 down in each 44px frame are the baked ground shadow, which stays dark.
    ("abeyance", "hood"): ramp_map(0.12, 0.11, 0.40, [(104, 98, 92), (138, 130, 118), (168, 160, 144),
                                                     (192, 184, 166), (214, 205, 186)]),
    # Portrait: dark warm brown-black hood and coat. Sprite hood and coat were slate blue (Ojon, round 3).
    # Outline ink (lightness under 0.08) stays as it is.
    ("jessamy", "cloak"): hue_set(212, 262, 0.10, 0.08, 16, 0.8, 0.84),
    # Portrait: dark brown-black leather coat. Sprite coat was grey-blue (Ojon, 2026-11-23).
    # Light greys (the pike's blade) and outline ink stay.
    ("ninefingers", "coat"): hue_set(195, 215, 0.06, 0.12, 24, 1.0, 0.58, max_l=0.52, max_s=0.2, s_add=0.12),
    # Portrait: brown leather coat. Sprite coat was black-navy; outline ink and the grey sword stay.
    ("velvette", "coat"): hue_set(225, 265, 0.06, 0.12, 22, 1.0, 1.25, max_l=0.30, max_s=0.35, s_add=0.22),
    # Portrait: bone-white cravat on the black coat (Ojon, 2026-11-23). Sprite's gold chest detail goes
    # bone white (from row 34 down, so the mask above keeps its colour).
    ("auditor", "cravat"): hue_ramp(28, 58, 0.30, 0.15, [(120, 112, 100), (160, 151, 135), (196, 188, 170), (222, 214, 196)]),
}


def apply(sid, material):
    if (sid, material) in REGION:
        import json as _json
        fw = _json.load(open(os.path.join(ROOT, "data", "sprites.json")))["sprites"][sid]["size"][0]
        for path in sorted(glob.glob(os.path.join(ROOT, "assets", "sprites", sid, "*.png"))):
            REGION[(sid, material)](path, fw)
        return
    fn = FIXES[(sid, material)]
    limit = ROW_LIMIT.get((sid, material), 10 ** 6)
    start = ROW_FROM.get((sid, material), 0)
    for path in sorted(glob.glob(os.path.join(ROOT, "assets", "sprites", sid, "*.png"))):
        im = Image.open(path).convert("RGBA")
        px = im.load()
        cache = {}
        for y in range(im.size[1]):
            for x in range(im.size[0]):
                p = px[x, y]
                if not p[3] or y % im.size[1] >= limit or y % im.size[1] < start:
                    continue
                if p[:3] not in cache:
                    cache[p[:3]] = fn(p)
                new = cache[p[:3]]
                if new:
                    px[x, y] = new + (p[3],)
        im.save(path)


if __name__ == "__main__":
    if len(sys.argv) != 3 or (tuple(sys.argv[1:]) not in FIXES and tuple(sys.argv[1:]) not in REGION):
        print(__doc__)
        print("known:", ", ".join("%s %s" % k for k in list(FIXES) + list(REGION)))
        sys.exit(1)
    apply(sys.argv[1], sys.argv[2])
