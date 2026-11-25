#!/usr/bin/env python3
"""Placeholder art for the building kit (docs/MAP_KIT.md): walls, floors and roofs for premade maps.

Code-drawn in the style palette (tools/style_palette.hex) so premade maps can be built and played before the
paid art batch. Every file here is a tracked stand-in (data/placeholders.json, kind "tiles", from "code:kit"):
the final art drops in at the same path and name, no code change.

    python3 tools/make_map_kit.py            # all kits
    python3 tools/make_map_kit.py timber     # one kit

Each kit folder holds 16 x 16 tiles (scripts/structures.gd reads them):
    cap.png        top of a wall seen from above
    face.png       wall face, middle rows      face_top.png  the row under the cap   face_base.png  the row on the ground
    window.png     wall face with a window
    floor.png, floor_v1.png   interior floor (variants are picked per cell)
    door.png       an open doorway's threshold
    roof.png       roof surface (tiles both ways)   roof_ridge.png  the ridge row   roof_eave.png  the bottom row
"""
import os
import random
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "tiles", "kit")

INK = "12141f"
P = {
    "ink_shadow": "1f2233", "night": "2e3247", "stone_dark": "3d4152", "stone": "575b6b", "stone_light": "7a7d88",
    "stone_hi": "a3a3a6", "wood_darkest": "2a2019", "wood_dark": "3a2a1c", "wood": "5a3e28", "wood_light": "7d5836",
    "wood_hi": "a07a4e", "straw": "c9a97a", "plaster_shadow": "8f8270", "plaster": "b5a68a", "bone": "d6cdba",
    "slate_dark": "2b3448", "slate": "3f4c66", "slate_light": "5b6b85", "clay_dark": "5c2a26", "clay": "85402f",
    "clay_light": "a85d3e", "candle": "f2c25c", "moss": "566b3a",
}


def rgb(h):
    h = P.get(h, h)
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


class Tile:
    def __init__(self, fill):
        self.im = Image.new("RGBA", (16, 16), rgb(fill))

    def px(self, x, y, c):
        if 0 <= x < 16 and 0 <= y < 16:
            self.im.putpixel((x, y), rgb(c))

    def rect(self, x, y, w, h, c):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.px(xx, yy, c)

    def hline(self, y, c, x0=0, x1=16):
        self.rect(x0, y, x1 - x0, 1, c)

    def vline(self, x, c, y0=0, y1=16):
        self.rect(x, y0, 1, y1 - y0, c)

    def save(self, kit, name):
        d = os.path.join(OUT, kit)
        os.makedirs(d, exist_ok=True)
        self.im.save(os.path.join(d, name + ".png"))


def speckle(t, rng, cols, n):
    for _ in range(n):
        t.px(rng.randrange(16), rng.randrange(16), rng.choice(cols))


# ------------------------------------------------------------------ shared pieces

def planks(rng, base, seam, light, dark):
    t = Tile(base)
    for y in (3, 7, 11, 15):
        t.hline(y, seam)
    for row, y0 in enumerate((0, 4, 8, 12)):
        jx = rng.randrange(3, 13)
        t.vline(jx, seam, y0, y0 + 3)
        t.hline(y0, light, 0, 16)
        for _ in range(2):
            t.px(rng.randrange(16), y0 + rng.randrange(1, 3), dark)
    return t


def slate_roof(rng, base, line, light, dark):
    t = Tile(base)
    for i, y in enumerate((3, 7, 11, 15)):
        t.hline(y, line)
        off = 0 if i % 2 == 0 else 4
        for x in range(off, 16, 8):
            t.vline(x, line, y - 3, y)
        t.hline(y - 3, light, 0, 16)
    speckle(t, rng, [dark], 4)
    return t


def bricks(rng, base, mortar, light, dark, rows=(3, 7, 11, 15)):
    t = Tile(base)
    for i, y in enumerate(rows):
        t.hline(y, mortar)
        off = 2 if i % 2 == 0 else 6
        for x in range(off, 16, 8):
            t.vline(x, mortar, y - 3, y)
        t.hline(y - 3, light, 0, 16)
    speckle(t, rng, [dark, light], 5)
    return t


def window(t, frame, pane, glow=None):
    t.rect(4, 4, 8, 8, frame)
    t.rect(5, 5, 6, 6, pane)
    t.vline(7, frame, 5, 11)
    t.vline(8, frame, 5, 11)
    t.hline(8, frame, 5, 11)
    t.px(5, 5, P["slate_light"] if glow is None else glow)
    t.hline(12, INK, 3, 13)  # sill shadow
    t.hline(11, frame, 3, 13)


def outline_cap(t, top_col, edge_col):
    t.hline(0, edge_col)
    t.hline(1, top_col)


# ------------------------------------------------------------------ kits

def timber(rng):
    k = "timber"
    cap = Tile("wood_dark")  # the top of a timber wall: a dark beam, plaster showing between the studs
    cap.hline(0, "wood")
    cap.hline(15, "wood_darkest")
    for x in (0, 8):
        cap.vline(x, "wood_darkest", 1, 15)
    cap.rect(2, 5, 4, 6, "plaster_shadow")
    cap.rect(10, 5, 4, 6, "plaster_shadow")
    cap.hline(5, "plaster", 2, 6)
    cap.hline(5, "plaster", 10, 14)
    cap.save(k, "cap")

    def face_base_plaster():
        t = Tile("plaster")
        speckle(t, rng, ["plaster_shadow", "bone"], 6)
        t.vline(0, "wood_dark")
        t.vline(15, "wood_darkest")
        return t

    f = face_base_plaster()
    f.save(k, "face")
    ft = face_base_plaster()
    ft.rect(0, 0, 16, 3, "wood_dark")
    ft.hline(0, "wood_light")
    ft.hline(3, "plaster_shadow")
    for x in range(1, 15):  # a diagonal brace
        if x % 1 == 0 and 3 + (x // 2) < 16:
            ft.px(x, 3 + x // 2 + 1, "wood_dark")
    ft.save(k, "face_top")
    fb = face_base_plaster()
    fb.rect(0, 10, 16, 6, "stone")
    for x in (0, 5, 11):
        fb.vline(x, "stone_dark", 10, 13)
    for x in (3, 8, 13):
        fb.vline(x, "stone_dark", 13, 16)
    fb.hline(10, "stone_light")
    fb.hline(13, "stone_dark")
    fb.hline(9, "wood_dark")
    fb.save(k, "face_base")
    w = face_base_plaster()
    window(w, P["wood_dark"], P["night"], P["candle"])
    w.save(k, "window")
    planks(rng, "wood_light", "wood_dark", "wood_hi", "wood").save(k, "floor")
    planks(rng, "wood_light", "wood_dark", "wood_hi", "wood").save(k, "floor_v1")
    d = planks(rng, "wood", "wood_darkest", "wood_light", "wood_dark")
    d.vline(0, "wood_darkest")
    d.vline(15, "wood_darkest")
    d.save(k, "door")
    roof = slate_roof(rng, "slate", "slate_dark", "slate_light", "ink_shadow")
    roof.save(k, "roof")
    r = slate_roof(rng, "slate", "slate_dark", "slate_light", "ink_shadow")
    r.rect(0, 6, 16, 4, "slate_dark")
    r.hline(6, "slate_light")
    r.hline(9, "ink_shadow")
    r.save(k, "roof_ridge")
    e = slate_roof(rng, "slate", "slate_dark", "slate_light", "ink_shadow")
    e.rect(0, 12, 16, 4, "slate_dark")
    e.hline(15, INK)
    e.save(k, "roof_eave")


def stone(rng):
    k = "stone"
    cap = Tile("stone_light")
    cap.hline(0, "stone_hi")
    cap.hline(15, "stone")
    for x in (0, 8):
        cap.vline(x, "stone", 1, 15)
    speckle(cap, rng, ["stone", "stone_hi"], 5)
    cap.save(k, "cap")
    bricks(rng, "stone", "stone_dark", "stone_light", "night").save(k, "face")
    ft = bricks(rng, "stone", "stone_dark", "stone_light", "night")
    ft.rect(0, 0, 16, 3, "stone_light")
    ft.hline(0, "stone_hi")
    ft.hline(3, "night")
    ft.save(k, "face_top")
    fb = bricks(rng, "stone", "stone_dark", "stone_light", "night")
    fb.rect(0, 12, 16, 4, "stone_dark")
    fb.hline(12, "stone_light")
    for x in range(0, 16, 3):
        fb.px(x, 15, "moss")
    fb.save(k, "face_base")
    w = bricks(rng, "stone", "stone_dark", "stone_light", "night")
    window(w, P["stone_dark"], P["ink_shadow"])
    w.rect(7, 4, 2, 8, "stone_dark")  # iron bars, not panes: Concord windows
    w.save(k, "window")
    for name in ("floor", "floor_v1"):
        t = Tile("stone")
        t.hline(7, "stone_dark")
        t.hline(15, "stone_dark")
        t.vline(rng.randrange(3, 7), "stone_dark", 0, 7)
        t.vline(rng.randrange(9, 14), "stone_dark", 8, 15)
        t.hline(0, "stone_light")
        t.hline(8, "stone_light")
        speckle(t, rng, ["stone_dark", "stone_light"], 6)
        t.save(k, name)
    d = Tile("stone_dark")
    d.hline(0, "stone")
    d.vline(0, INK)
    d.vline(15, INK)
    d.save(k, "door")
    slate_roof(rng, "clay", "clay_dark", "clay_light", "wood_darkest").save(k, "roof")
    r = slate_roof(rng, "clay", "clay_dark", "clay_light", "wood_darkest")
    r.rect(0, 6, 16, 4, "clay_dark")
    r.hline(6, "clay_light")
    r.hline(9, "wood_darkest")
    r.save(k, "roof_ridge")
    e = slate_roof(rng, "clay", "clay_dark", "clay_light", "wood_darkest")
    e.rect(0, 12, 16, 4, "clay_dark")
    e.hline(15, INK)
    e.save(k, "roof_eave")


def palisade(rng):
    k = "palisade"
    cap = Tile("wood")
    for x in range(0, 16, 4):  # log ends seen from above
        cap.rect(x, 4, 4, 8, "wood_light")
        cap.rect(x + 1, 5, 2, 6, "wood_hi")
        cap.vline(x, "wood_darkest", 3, 13)
    cap.hline(3, "wood_darkest")
    cap.hline(12, "wood_darkest")
    cap.rect(0, 0, 16, 3, "wood_dark")
    cap.rect(0, 13, 16, 3, "wood_dark")
    cap.save(k, "cap")

    def logs():
        t = Tile("wood")
        for x in range(0, 16, 4):
            t.vline(x, "wood_darkest")
            t.vline(x + 1, "wood_light")
            t.px(x + 2, rng.randrange(16), "wood_dark")
        return t

    logs().save(k, "face")
    ft = logs()
    for x in range(0, 16, 4):  # sharpened tops
        ft.px(x, 0, INK)
        ft.px(x + 3, 0, INK)
    ft.rect(0, 6, 16, 2, "wood_dark")  # rope binding
    ft.hline(6, "straw")
    ft.save(k, "face_top")
    fb = logs()
    fb.rect(0, 13, 16, 3, "wood_dark")
    for x in range(1, 16, 3):
        fb.px(x, 15, "moss")
    fb.save(k, "face_base")
    w = logs()  # an arrow slit
    w.rect(7, 4, 2, 7, INK)
    w.save(k, "window")
    for name in ("floor", "floor_v1"):  # trodden earth
        t = Tile("wood_dark")
        speckle(t, rng, ["wood", "wood_darkest", "wood_light"], 22)
        t.save(k, name)
    d = Tile("wood")
    speckle(d, rng, ["wood_dark", "wood_light"], 14)
    d.save(k, "door")

    def thatch():
        t = Tile("straw")
        for y in range(0, 16, 3):
            t.hline(y, "wood_hi")
        speckle(t, rng, ["wood_hi", "bone", "wood_light"], 26)
        return t

    thatch().save(k, "roof")
    r = thatch()
    r.rect(0, 6, 16, 4, "wood_light")
    r.hline(9, "wood_dark")
    r.save(k, "roof_ridge")
    e = thatch()
    e.rect(0, 13, 16, 3, "wood_hi")
    e.hline(15, INK)
    e.save(k, "roof_eave")


KITS = {"timber": timber, "stone": stone, "palisade": palisade}


def build(name):
    KITS[name](random.Random(name))
    print("built kit", name)


if __name__ == "__main__":
    for n in (sys.argv[1:] or list(KITS)):
        build(n)
