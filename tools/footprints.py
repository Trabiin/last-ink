#!/usr/bin/env python3
"""Builds the collision footprints in data/footprints.json from the sprites (scripts/footprints.gd reads them).

A footprint is the ground a building or prop stands on, as a convex polygon in pixels around its origin (the
bottom-centre the sprite stands on). It is traced from the art, so new or redrawn art inherits a matching
footprint by rerunning this script:

    python3 tools/footprints.py            regenerate every entry (keeps the hand-set fields below)
    python3 tools/footprints.py --check    exit 1 if any entry is stale (tests/test_footprints.gd runs the same check)

How a footprint is traced:
  * Front: for each column, the lowest opaque pixel of the sprite is where its wall (or trunk, or crate) meets
    the ground. That profile is the front edge, angled walls included, so an angled building is solid along
    both of its visible sides, not just along a flat rectangle.
  * Back: the far edge sits `d` pixels above the origin. For buildings (sprites 64px or taller) `d` is the
    deepest spot behind the building where Ash (28px tall) is still hidden by the roof, less a 4px margin:
    from behind you walk up to the back wall and vanish behind the roof, but you can't walk "into" the roof
    and stand pressed against the front wall. Small props get about a third of their height.
  * Columns whose lowest pixel is above the back edge (eaves, roof overhangs, a tree's canopy) are not ground
    and are left out. The result is the convex hull, simplified to a few points.

Hand-set fields per entry (kept when regenerating):
  "walk": true        no collision (grass, reeds, planks you walk over, flat bones)
  "d": 12             depth override in pixels
  "clip": [-20, 30]   only trace columns between these x offsets (leave out a hanging sign, a gate arm)
  "inset": 2          pull the sides in by this many pixels (default 1)
  "manual": true      keep "poly" exactly as written (a code-drawn object with no sprite)
Recoloured variants (<kind>_v1.png ...) share their base's footprint when they are the same size. A variant of
another size (a differently shaped tree) gets its own entry, "<kind>_vN": {"of": "<kind>"}, added here
automatically and traced with its base's hand-set fields.
Generated fields: "poly" [[x, y], ...] and "src" [width, height] of the sprite it was traced from (the test
flags a footprint whose art changed size since).
"""
import json
import os
import sys

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DATA = os.path.join(ROOT, "data", "footprints.json")
BODY = (14, 28)  # the part of Ash that has to stay hidden behind a roof (width, height)
HIDDEN = 0.92  # share of that body the roof must cover
BUILDING_H = 64  # sprites at least this tall are buildings: depth from the roof, not from the height


def sprite_path(section, key):
    sub = "buildings" if section == "buildings" else "props"
    return os.path.join(ROOT, "assets", sub, key + ".png")


def alpha(path):
    im = Image.open(path).convert("RGBA")
    return im.size, im.split()[3].load()


def hidden_depth(size, a):
    """Deepest depth behind the origin where Ash at the sprite's centre column stays covered."""
    W, H = size
    oy = H - 3
    cx = W // 2
    best = 0
    for D in range(0, H):
        feet = oy - D
        tot = cov = 0
        for y in range(feet - BODY[1], feet):
            for x in range(cx - BODY[0] // 2, cx + BODY[0] // 2):
                tot += 1
                cov += 1 if (0 <= x < W and 0 <= y < H and a[x, y] > 100) else 0
        if cov / tot >= HIDDEN:
            best = D
        elif D > 8:
            break
    return best


def hull(points):
    pts = sorted(set(points))
    if len(pts) < 3:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def simplify(poly, tol=1.5, max_pts=8):
    """Drops hull points that sit within `tol` px of the line through their neighbours, then the least
    important ones until at most max_pts remain. Removing a hull point keeps the polygon convex."""
    poly = list(poly)

    def dev(i):
        a, b, c = poly[i - 1], poly[i], poly[(i + 1) % len(poly)]
        ln = ((c[0] - a[0]) ** 2 + (c[1] - a[1]) ** 2) ** 0.5 or 1.0
        return abs((c[0] - a[0]) * (a[1] - b[1]) - (a[0] - b[0]) * (c[1] - a[1])) / ln

    while len(poly) > 3:
        i = min(range(len(poly)), key=dev)
        if dev(i) > tol and len(poly) <= max_pts:
            break
        poly.pop(i)
    return poly


def trace(size, a, entry, building):
    W, H = size
    oy = H - 3
    if "d" in entry:
        d = int(entry["d"])
    elif building:
        d = max(hidden_depth(size, a) - 4, 20)
    else:
        d = max(4, round(H * 0.32))
    clip = entry.get("clip")
    inset = float(entry.get("inset", 1))
    front = []
    for x in range(W):
        rx = x - W / 2.0
        if clip and not (clip[0] <= rx <= clip[1]):
            continue
        low = None
        for y in range(H - 1, -1, -1):
            if a[x, y] > 100:
                low = y
                break
        if low is None:
            continue
        fy = min(low + 1 - oy, 0)  # the ground line under that column, never below the origin (Y-sort)
        if fy < -d + 2:
            continue  # eave, overhang or canopy: not standing on the ground here
        front.append((rx, fy))
    if not front:
        return None
    x0 = min(p[0] for p in front) + inset
    x1 = max(p[0] for p in front) + 1 - inset
    pts = [(min(max(p[0], x0), x1), p[1]) for p in front] + [(x1, front[-1][1]), (x0, -d), (x1, -d)]
    poly = simplify(hull(pts))
    return [[round(p[0], 1), round(p[1], 1)] for p in poly]


HAND = ("walk", "d", "clip", "inset", "manual")


def add_variants(data, stale):
    """Own entries for variants whose art is not the same size as their base's."""
    props = data["props"]
    for key in list(props.keys()):
        entry = props[key]
        if entry.get("of") or entry.get("walk") or entry.get("manual"):
            continue
        base = sprite_path("props", key)
        if not os.path.exists(base):
            continue
        size = Image.open(base).size
        i = 1
        while os.path.exists(sprite_path("props", "%s_v%d" % (key, i))):
            vk = "%s_v%d" % (key, i)
            vsize = Image.open(sprite_path("props", vk)).size
            if vsize != size:
                want = {"of": key}
                want.update({h: entry[h] for h in HAND if h in entry})
                have = props.get(vk, {})
                if {k: v for k, v in have.items() if k not in ("poly", "src")} != want:
                    props[vk] = dict(want, **{k: have[k] for k in ("poly", "src") if k in have})
                    stale.append(vk)
            elif vk in props:
                del props[vk]
                stale.append(vk)
            i += 1
    data["props"] = dict(sorted(props.items()))


def build(data, check=False):
    stale = []
    add_variants(data, stale)
    for section in ("props", "buildings"):
        for key, entry in data[section].items():
            if key.startswith("_") or entry.get("walk") or entry.get("manual"):
                continue
            path = sprite_path(section, key)
            if not os.path.exists(path):
                stale.append("%s: no sprite at %s" % (key, os.path.relpath(path, ROOT)))
                continue
            size, a = alpha(path)
            poly = trace(size, a, entry, section == "buildings" or size[1] >= BUILDING_H)
            if poly is None:
                stale.append("%s: nothing opaque to trace" % key)
                continue
            if entry.get("poly") != poly or entry.get("src") != list(size):
                if key not in stale:
                    stale.append(key)
                entry["poly"] = poly
                entry["src"] = list(size)
    return stale


def dump(data):
    """One entry per line, so a diff shows exactly which footprint moved."""
    lines = ["{", '\t"_comment": %s,' % json.dumps(data["_comment"])]
    secs = ["props", "buildings"]
    for si, section in enumerate(secs):
        lines.append('\t"%s": {' % section)
        keys = list(data[section].keys())
        for i, k in enumerate(keys):
            comma = "," if i < len(keys) - 1 else ""
            lines.append("\t\t%s: %s%s" % (json.dumps(k), json.dumps(data[section][k], separators=(", ", ": ")), comma))
        lines.append("\t}" + ("," if si < len(secs) - 1 else ""))
    lines.append("}")
    return "\n".join(lines) + "\n"


def main():
    check = "--check" in sys.argv
    data = json.load(open(DATA))
    stale = build(data, check)
    if check:
        if stale:
            print("Stale footprints (run python3 tools/footprints.py):", ", ".join(stale))
            sys.exit(1)
        print("Footprints up to date.")
        return
    open(DATA, "w").write(dump(data))
    print("Wrote %s (%d updated)" % (os.path.relpath(DATA, ROOT), len(stale)))


if __name__ == "__main__":
    main()
