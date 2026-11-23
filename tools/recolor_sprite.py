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


def hue_set(lo, hi, min_s, min_l, hue, s_mul, l_mul):
    """Colours in the hue window (and not outline-dark) move to one hue, keeping their shading."""
    def f(c):
        h, l, s = _hls(c)
        if lo <= h <= hi and s >= min_s and l >= min_l:
            r, g, b = colorsys.hls_to_rgb(hue / 360.0, l * l_mul, s * s_mul)
            return (round(r * 255), round(g * 255), round(b * 255))
        return None
    return f


ROW_LIMIT = {("abeyance", "hood"): 34}  # frame rows at or below this are left alone

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
}


def apply(sid, material):
    fn = FIXES[(sid, material)]
    limit = ROW_LIMIT.get((sid, material), 10 ** 6)
    for path in sorted(glob.glob(os.path.join(ROOT, "assets", "sprites", sid, "*.png"))):
        im = Image.open(path).convert("RGBA")
        px = im.load()
        cache = {}
        for y in range(im.size[1]):
            for x in range(im.size[0]):
                p = px[x, y]
                if not p[3] or y % im.size[1] >= limit:
                    continue
                if p[:3] not in cache:
                    cache[p[:3]] = fn(p)
                new = cache[p[:3]]
                if new:
                    px[x, y] = new + (p[3],)
        im.save(path)


if __name__ == "__main__":
    if len(sys.argv) != 3 or tuple(sys.argv[1:]) not in FIXES:
        print(__doc__)
        print("known:", ", ".join("%s %s" % k for k in FIXES))
        sys.exit(1)
    apply(sys.argv[1], sys.argv[2])
