#!/usr/bin/env python3
"""Tracked placeholder art (Ojon 2026-11-23, issue #28): builds every stand-in listed in data/placeholders.json.

Chapter 2 is written before the paid art batch, so its new sprites, portraits, props, ground tiles, icons and
music start life as recoloured copies of art the game already has. Each one lives at the path the final art will
use, under the same id, so the swap is "drop the new file in": no code or data changes. data/placeholders.json is
the list; tests/test_placeholders.gd prints it on every run and the release check (tools/release_check.sh, #118)
fails while it is not empty. GitHub issue #205 (Chapter 2 art swap) tracks the same list.

    python3 tools/make_placeholders.py            # (re)build every stand-in whose final art has not landed
    python3 tools/make_placeholders.py copyist    # only entries whose id contains "copyist"

Kinds and what "from" names:
    sprite    a sprite set folder in assets/sprites/<from>/; also copies its data/sprites.json entry to <id>
    portrait  assets/portraits/<from>.png
    prop      assets/props/<from>.png and its _v<n> variants
    tiles     a ground set folder in assets/tiles/<from>/
    icon      assets/icons/<from>.png
    music     assets/audio/music/<from>.ogg (copied as is)
    cg        nothing: the scene plays without its CG until the art lands ("from" is empty)

recolor: applied to every pixel in order. Each step may limit itself to a hue window ("hues": [lo, hi] in
degrees, wrapping) and a minimum saturation ("min_s"), or to greys ("greys": max saturation), and to a lightness
band ("min_l", "max_l"):
    {"hue": degrees to turn}  {"sat": multiply}  {"light": multiply}  {"add": lightness to add (-1..1)}
    {"tint": "rrggbb", "amount": 0-1}  blend towards a colour, keeping each pixel's lightness
Outline ink (lightness under 0.12) is never touched, so stand-ins keep the shared line weight.

When the final file lands, delete the entry from data/placeholders.json; this script never overwrites a path that
is not listed there.
"""
import colorsys
import glob
import json
import os
import shutil
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data", "placeholders.json")
SPRITES_JSON = os.path.join(ROOT, "data", "sprites.json")
OUTLINE_L = 0.12


def _in_window(h, s, step):
    if "greys" in step:
        return s <= float(step["greys"])
    if "hues" in step:
        lo, hi = step["hues"]
        inside = lo <= h <= hi if lo <= hi else (h >= lo or h <= hi)
        if not inside:
            return False
    return s >= float(step.get("min_s", 0.0))


def _in_light(l, step):
    return float(step.get("min_l", 0.0)) <= l <= float(step.get("max_l", 1.0))


def recolor_pixel(rgba, steps):
    r, g, b, a = rgba
    if a == 0:
        return rgba
    h, l, s = colorsys.rgb_to_hls(r / 255.0, g / 255.0, b / 255.0)
    if l < OUTLINE_L:
        return rgba
    h *= 360.0
    for step in steps:
        if not _in_window(h, s, step) or not _in_light(l, step):
            continue
        if "hue" in step:
            h = (h + float(step["hue"])) % 360.0
        if "sat" in step:
            s = max(0.0, min(1.0, s * float(step["sat"])))
        if "light" in step:
            l = max(0.0, min(1.0, l * float(step["light"])))
        if "add" in step:
            l = max(0.0, min(1.0, l + float(step["add"])))
        if "tint" in step:
            tr, tg, tb = (int(step["tint"][i:i + 2], 16) / 255.0 for i in (0, 2, 4))
            th, tl, ts = colorsys.rgb_to_hls(tr, tg, tb)
            k = float(step.get("amount", 0.5))
            # Move hue the short way round, saturation straight; lightness stays the pixel's own.
            dh = ((th * 360.0 - h + 180.0) % 360.0) - 180.0
            h = (h + dh * k) % 360.0
            s = s + (ts - s) * k
    nr, ng, nb = colorsys.hls_to_rgb(h / 360.0, l, s)
    return (round(nr * 255), round(ng * 255), round(nb * 255), a)


def recolor_png(src, dst, steps):
    im = Image.open(src).convert("RGBA")
    if steps:
        cache = {}
        px = im.load()
        for y in range(im.height):
            for x in range(im.width):
                c = px[x, y]
                if c not in cache:
                    cache[c] = recolor_pixel(c, steps)
                px[x, y] = cache[c]
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    im.save(dst)


def build(entry, sprites):
    kind, pid, src, steps = entry["kind"], entry["id"], entry.get("from", ""), entry.get("recolor", [])
    name = pid.split(":", 1)[1]
    if kind == "sprite":
        sdir = os.path.join(ROOT, "assets", "sprites", src)
        ddir = os.path.join(ROOT, entry["path"])
        for f in sorted(glob.glob(os.path.join(sdir, "*.png"))):
            recolor_png(f, os.path.join(ddir, os.path.basename(f)), steps)
        e = json.loads(json.dumps(sprites[src]))
        e.pop("folder", None)
        sprites[name] = e
    elif kind in ("portrait", "icon"):
        sub = "portraits" if kind == "portrait" else "icons"
        recolor_png(os.path.join(ROOT, "assets", sub, src + ".png"), os.path.join(ROOT, entry["path"]), steps)
    elif kind == "prop":
        pdir = os.path.join(ROOT, "assets", "props")
        recolor_png(os.path.join(pdir, src + ".png"), os.path.join(ROOT, entry["path"]), steps)
        n = 1
        while os.path.exists(os.path.join(pdir, "%s_v%d.png" % (src, n))) and n <= int(entry.get("variants", 0)):
            recolor_png(os.path.join(pdir, "%s_v%d.png" % (src, n)), os.path.join(pdir, "%s_v%d.png" % (name, n)), steps)
            n += 1
    elif kind == "tiles" and src.startswith("code:"):  # drawn by a tool, not recoloured (the building kit)
        sys.path.insert(0, os.path.join(ROOT, "tools"))
        import make_map_kit
        make_map_kit.build(os.path.basename(entry["path"].rstrip("/")))
    elif kind == "tiles":
        sdir = os.path.join(ROOT, "assets", "tiles", src)
        for f in sorted(glob.glob(os.path.join(sdir, "*.png"))):
            recolor_png(f, os.path.join(ROOT, entry["path"], os.path.basename(f)), steps)
    elif kind == "music":
        shutil.copyfile(os.path.join(ROOT, "assets", "audio", "music", src + ".ogg"), os.path.join(ROOT, entry["path"]))
    elif kind == "cg":
        return
    else:
        raise SystemExit("unknown kind %s in %s" % (kind, pid))
    print("built", pid, "->", entry["path"])


def main():
    only = sys.argv[1:]
    data = json.load(open(DATA))
    sj = json.load(open(SPRITES_JSON))
    for entry in data["placeholders"]:
        if only and not any(o in entry["id"] for o in only):
            continue
        build(entry, sj["sprites"])
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import import_sprites  # same one-line-per-animation layout, so diffs stay readable
    with open(SPRITES_JSON, "w") as f:
        f.write(import_sprites.dump(sj))


if __name__ == "__main__":
    main()
