#!/usr/bin/env python3
"""Makes the level 4 and 5 building sprites (issue #189) from each building's level 3 art pass sprite.

    python3 tools/make_building_tiers.py            writes assets/buildings/<look>_4.png and <look>_5.png
    python3 tools/footprints.py                     then retrace the footprints (the lamp posts stand in front)

Level 4 is "warded": two Wardlamp posts with blue Ink flames stand at the front corners. Level 5 is "gilded":
the same lamps on brass posts, and a brass finial with a crimson pennant on the highest point of the roof
(the canvas grows upward for it, so the building stands on the same ground). Everything is drawn in the fixed
style palette (tools/style_palette.hex) with the ink-black outline the art pass uses.

These are tool-made from the level 3 art so every level has its own look in town; a hand-drawn pass for the
late levels belongs with the big matching art pass (see the issue linked in docs/BALANCE.md).
"""
import os

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "buildings")
LOOKS = ["barracks", "forge", "guildhall", "infirmary", "inkworks", "market", "scriptorium"]

INK = (0x12, 0x14, 0x1F, 255)
WOOD_DARKEST = (0x2A, 0x20, 0x19, 255)
WOOD_DARK = (0x3A, 0x2A, 0x1C, 255)
WOOD = (0x5A, 0x3E, 0x28, 255)
BLUE = (0x3A, 0x5F, 0x9E, 255)
GLOW = (0x7F, 0xA8, 0xEC, 255)
BONE = (0xD6, 0xCD, 0xBA, 255)
BRASS = (0xE8, 0xC6, 0x5A, 255)
CANDLE = (0xF2, 0xC2, 0x5C, 255)
BRASS_DARK = (0xA0, 0x7A, 0x4E, 255)
CRIMSON = (0xA3, 0x24, 0x3B, 255)
CLAY_DARK = (0x5C, 0x2A, 0x26, 255)
FINIAL_H = 14  # extra canvas on top for the level 5 pennant


def put(im, x, y, c):
    if 0 <= x < im.width and 0 <= y < im.height:
        im.putpixel((x, y), c)


def rect(im, x, y, w, h, c):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            put(im, xx, yy, c)


def lamp_post(im, x, bottom, gilded):
    """A Wardlamp on a post, 3px wide post, lamp head on top. x = left edge of the post."""
    post_hi, post_lo = (BRASS, BRASS_DARK) if gilded else (WOOD, WOOD_DARK)
    top = bottom - 21
    # post with outline
    rect(im, x - 1, top + 6, 5, bottom - top - 5, INK)
    rect(im, x, top + 7, 1, bottom - top - 8, post_hi)
    rect(im, x + 1, top + 7, 2, bottom - top - 8, post_lo)
    rect(im, x - 2, bottom - 2, 7, 2, INK)  # foot
    rect(im, x - 1, bottom - 2, 5, 1, WOOD_DARKEST if not gilded else BRASS_DARK)
    # lamp head: cap, glass with blue Ink flame, base
    rect(im, x - 2, top - 1, 7, 9, INK)
    rect(im, x - 1, top, 5, 1, post_hi)  # cap
    rect(im, x - 1, top + 1, 5, 5, BLUE)
    rect(im, x, top + 2, 3, 3, GLOW)
    put(im, x + 1, top + 2, BONE)  # hot core
    rect(im, x - 1, top + 6, 5, 1, post_lo)
    put(im, x + 1, top - 2, INK)  # ring
    put(im, x + 1, top - 3, INK)


def finial(im, top_y, cx):
    """Brass finial on the roof's highest point with a crimson pennant blowing east."""
    # pole
    rect(im, cx - 1, top_y - 12, 3, 13, INK)
    rect(im, cx, top_y - 11, 1, 12, BRASS)
    rect(im, cx - 2, top_y - 14, 5, 3, INK)  # knob
    put(im, cx, top_y - 13, CANDLE)
    put(im, cx - 1, top_y - 13, BRASS)
    put(im, cx + 1, top_y - 13, BRASS_DARK)
    # pennant, 9px long, tapering
    for i in range(9):
        h = 5 - (i * 4) // 9
        x = cx + 2 + i
        y0 = top_y - 10 + (1 if i > 5 else 0)
        rect(im, x, y0 - 1, 1, h + 2, INK)
        rect(im, x, y0, 1, h, CRIMSON if i % 4 != 3 else CLAY_DARK)
    rect(im, cx + 2, top_y - 10, 1, 4, CRIMSON)


def highest_point(im):
    """(x, y) of the topmost opaque pixel, the centre of that row's opaque run."""
    for y in range(im.height):
        xs = [x for x in range(im.width) if im.getpixel((x, y))[3] > 0]
        if xs:
            return (xs[0] + xs[-1]) // 2, y
    return im.width // 2, 0


def bottom_row(im):
    for y in range(im.height - 1, -1, -1):
        if any(im.getpixel((x, y))[3] > 0 for x in range(im.width)):
            return y
    return im.height - 1


def make(look):
    base = Image.open(os.path.join(OUT, "%s_3.png" % look)).convert("RGBA")
    w, h = base.size
    bottom = bottom_row(base) + 1
    # level 4: warded
    l4 = base.copy()
    lamp_post(l4, 3, bottom, False)
    lamp_post(l4, w - 6, bottom, False)
    l4.save(os.path.join(OUT, "%s_4.png" % look))
    # level 5: gilded, taller canvas for the finial (bottom-anchored in game, so the ground stays put)
    l5 = Image.new("RGBA", (w, h + FINIAL_H), (0, 0, 0, 0))
    l5.alpha_composite(base, (0, FINIAL_H))
    cx, ty = highest_point(l5)
    finial(l5, ty + 1, cx)
    lamp_post(l5, 3, bottom + FINIAL_H, True)
    lamp_post(l5, w - 6, bottom + FINIAL_H, True)
    l5.save(os.path.join(OUT, "%s_5.png" % look))


if __name__ == "__main__":
    for look in LOOKS:
        make(look)
        print("made %s_4 and %s_5" % (look, look))
