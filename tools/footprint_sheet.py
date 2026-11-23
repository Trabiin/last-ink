#!/usr/bin/env python3
"""Review sheet for data/footprints.json: every prop and building sprite with its collision footprint drawn on
the ground, and Ash standing as close as the footprint lets him get from behind (north), beside (west) and in
front (south), drawn in Y order like the game does. Use it whenever art lands or a footprint changes:

    python3 tools/footprint_sheet.py out.png [kind ...]

A good footprint: Ash behind the building is hidden (or only his hair shows over a low roof), Ash beside it
touches the wall instead of standing inside it, and Ash in front stands on the doorstep, not in the wall.
"""
import json
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SCALE = 3
RADIUS = 5  # Hero radius (scripts/hero.gd)


def load_ash(anim_dir):
    im = Image.open(os.path.join(ROOT, "assets/sprites/ash/idle_%s.png" % anim_dir)).convert("RGBA")
    return im.crop((0, 0, 44, 44))


ASH = {"north": load_ash("north"), "east": load_ash("east"), "south": load_ash("south")}
FEET = (22, 35)


def sprite_for(key, section):
    if section == "buildings":
        p = os.path.join(ROOT, "assets/buildings/%s.png" % key)
    else:
        p = os.path.join(ROOT, "assets/props/%s.png" % key)
    return Image.open(p).convert("RGBA") if os.path.exists(p) else None


def poly_of(entry):
    return entry.get("poly", []) if isinstance(entry, dict) and not entry.get("walk") else []


def cell(key, entry, section):
    spr = sprite_for(key, section)
    if spr is None:
        return None
    pad = 26
    w = max(spr.width, 60) + pad * 2
    h = spr.height + pad * 2 + 10
    img = Image.new("RGBA", (w, h), (58, 84, 52, 255))
    ox, oy = w // 2, h - pad  # the prop's origin; the sprite's bottom sits 3px below it
    sprite_pos = (ox - spr.width // 2, oy + 3 - spr.height)
    poly = [(ox + x, oy + y) for x, y in poly_of(entry)]
    boxes = []
    if poly:
        xs = [p[0] for p in poly]
        ys = [p[1] for p in poly]
        boxes.append((min(xs), min(ys), max(xs), max(ys)))
    layer = []  # (sort y, image, pos)
    layer.append((oy, spr, sprite_pos))
    if boxes:
        main = boxes[0]
        cx = (main[0] + main[2]) / 2.0
        midy = (main[1] + main[3]) / 2.0
        left = min(x for x, y in poly if y >= midy - 2) if any(y >= midy - 2 for x, y in poly) else main[0]
        front = max(y for x, y in poly if abs(x - cx) < 3) if any(abs(x - cx) < 3 for x, y in poly) else main[3]
        for anim, feet in (("north", (cx, main[1] - RADIUS - 1)), ("east", (left - RADIUS - 1, midy)),
                           ("south", (cx, oy + RADIUS + 1))):
            a = ASH[anim]
            layer.append((feet[1], a, (int(feet[0] - FEET[0]), int(feet[1] - FEET[1]))))
    ground = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ground)
    if len(poly) >= 3:
        d.polygon(poly, fill=(255, 40, 40, 90), outline=(255, 80, 80, 255))
    img.alpha_composite(ground)
    for _, im, pos in sorted(layer, key=lambda t: t[0]):
        img.alpha_composite(im, (max(pos[0], 0), max(pos[1], 0)))
    over = ImageDraw.Draw(img)
    for (x, y) in poly:  # the footprint's corners on top, so they show through the art
        over.rectangle((x - 1, y - 1, x + 1, y + 1), fill=(255, 230, 80, 255))
    over.line((ox - 3, oy, ox + 3, oy), fill=(255, 255, 255, 255))
    label = key if boxes else key + " (walk)"
    over.text((3, 2), label, fill=(255, 255, 255, 255))
    return img.resize((img.width * SCALE, img.height * SCALE), Image.NEAREST)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/footprints.png"
    only = set(sys.argv[2:])
    data = json.load(open(os.path.join(ROOT, "data/footprints.json")))
    cells = []
    for section in ("props", "buildings"):
        for key, entry in data[section].items():
            if key.startswith("_") or (only and key not in only):
                continue
            c = cell(key, entry, section)
            if c is not None:
                cells.append(c)
    if not cells:
        print("nothing to draw")
        return
    cols = 6
    rows = [cells[i:i + cols] for i in range(0, len(cells), cols)]
    W = max(sum(c.width for c in r) for r in rows)
    H = sum(max(c.height for c in r) for r in rows)
    sheet = Image.new("RGBA", (W, H), (20, 20, 24, 255))
    y = 0
    for r in rows:
        x = 0
        for c in r:
            sheet.paste(c, (x, y))
            x += c.width
        y += max(c.height for c in r)
    sheet.save(out)
    print("saved", out, sheet.size)


if __name__ == "__main__":
    main()
