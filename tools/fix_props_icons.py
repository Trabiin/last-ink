#!/usr/bin/env python3
"""Free pixel fixes for icons, props and buildings (the icons/props review pass; findings from
tools/prop_icon_audit.py and the eye check). Every fix is listed in tools/prop_icon_fixes.json and is safe to
replay: running it again on an already fixed file changes nothing.

    python3 tools/fix_props_icons.py               # apply every fix in tools/prop_icon_fixes.json
    python3 tools/fix_props_icons.py --only NAME   # just the entries for one file (name without .png)
    python3 tools/fix_props_icons.py --preview OUT # write before/after sheets to OUT instead of saving

Ops (each entry: {"file": "assets/...png", "op": ..., args}):
  outline  {exclude: [[x0,y0,x1,y1],...], only: [...]}  light outer edge pixels get the ink outline the style asks
           for (docs/ART_STYLE.md). Where the object is thick there, the edge pixel itself turns ink; where it is a
           1-2 px line (a chain, a blade, a stalk) ink goes on the outside instead, so the line keeps its colour.
           exclude/only: rects (x1,y1 exclusive) for parts that must stay unoutlined (steam, flame, glow).
  dedither {rect?}  flattens checkerboard dithering (no dithering on objects) to the lighter of its two colours.
  remap    {map: {"#from": "#to"}, rect?, near?: {colours: [...], min: 5}}  swaps palette colours (roof recolours, the
           infirmary cross); with near, only pixels with min+ of 8 neighbours in those colours (stray dither).
  pixels   {set: [[x, y, "#rrggbb" | null], ...]}  hand-placed pixels (null clears one): kinks in straight lines.
"""
import json
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FIXES = os.path.join(HERE, "prop_icon_fixes.json")
INK = (18, 20, 31)
DARK = 72


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def _in(rects, x, y):
    return any(r[0] <= x < r[2] and r[1] <= y < r[3] for r in rects)


def outline(a, exclude=(), only=None):
    h, w = a.shape[:2]
    op = a[..., 3] > 0
    out = a.copy()

    def opaque(x, y):
        return 0 <= x < w and 0 <= y < h and op[y, x]

    for y in range(h):
        for x in range(w):
            if not op[y, x] or max(a[y, x, :3]) < DARK:
                continue
            if _in(exclude, x, y) or (only and not _in(only, x, y)):
                continue
            dirs = [(dx, dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if not opaque(x + dx, y + dy)]
            if not dirs:
                continue
            thick = all(opaque(x - dx, y - dy) and opaque(x - 2 * dx, y - 2 * dy) for dx, dy in dirs)
            if thick:
                out[y, x] = INK + (255,)
                continue
            for dx, dy in dirs:
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h:
                    out[ny, nx] = INK + (255,)
                else:
                    out[y, x] = INK + (255,)
    return out


def dedither(a, rect=None):
    h, w = a.shape[:2]
    c = a[..., 0].astype(int) * 65536 + a[..., 1].astype(int) * 256 + a[..., 2]
    op = a[..., 3] > 0
    x0, y0, x1, y1 = rect or (0, 0, w, h)
    mark = np.zeros((h, w), bool)
    for y in range(max(1, y0), min(h - 1, y1)):
        for x in range(max(1, x0), min(w - 1, x1)):
            if not op[y - 1:y + 2, x - 1:x + 2].all():
                continue
            A = c[y, x]
            # A checkerboard cell: 3+ edge neighbours share one other colour, 2+ corner neighbours share its own.
            n4 = [c[y, x - 1], c[y, x + 1], c[y - 1, x], c[y + 1, x]]
            d4 = [c[y - 1, x - 1], c[y - 1, x + 1], c[y + 1, x - 1], c[y + 1, x + 1]]
            B = max(set(n4), key=n4.count)
            if B != A and n4.count(B) >= 3 and d4.count(A) >= 2:
                mark[y, x] = True
    out = a.copy()
    # The dark cells of the checker take their neighbours' lighter colour, so the patch reads as the flat thatch
    # the dither was speckling.
    for y, x in zip(*np.nonzero(mark)):
        n4 = [tuple(a[y + dy, x + dx, :3]) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
        nb = np.array(max(set(n4), key=n4.count))
        if int(nb.astype(int).sum()) > int(a[y, x, :3].astype(int).sum()):
            out[y, x, :3] = nb
    return out


def remap(a, cmap, rect=None, near=None):
    out = a.copy()
    h, w = a.shape[:2]
    x0, y0, x1, y1 = rect or (0, 0, w, h)
    region = np.zeros((h, w), bool)
    region[y0:y1, x0:x1] = True
    if near:  # only pixels mostly surrounded by these colours (the target colours count too)
        cols = [hexc(c) for c in near["colours"]] + [hexc(t) for t in cmap.values()]
        hit = np.zeros((h, w), int)
        pad = np.pad(a[..., :3], ((1, 1), (1, 1), (0, 0)))
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dy or dx:
                    sh = pad[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
                    hit += np.any([(sh == c).all(-1) for c in cols], axis=0)
        region &= hit >= near.get("min", 5)
    for f, t in cmap.items():
        m = (a[..., :3] == hexc(f)).all(-1) & (a[..., 3] > 0) & region
        out[m, :3] = hexc(t)
    return out


def pixels(a, items):
    out = a.copy()
    for x, y, col in items:
        out[y, x] = (0, 0, 0, 0) if col is None else hexc(col) + (255,)
    return out


def apply(a, fix):
    op = fix["op"]
    if op == "outline":
        return outline(a, fix.get("exclude", []), fix.get("only"))
    if op == "dedither":
        while True:  # filling a patch can expose its rim as a new checker cell: repeat until stable
            b = dedither(a, fix.get("rect"))
            if (b == a).all():
                return b
            a = b
    if op == "remap":
        for _ in range(50):  # spreads through a patch from its edge inwards
            b = remap(a, fix["map"], fix.get("rect"), fix.get("near"))
            if (b == a).all():
                break
            a = b
        return a
    if op == "pixels":
        return pixels(a, fix["set"])
    raise ValueError("unknown op " + op)


def main(argv):
    fixes = json.load(open(FIXES))["fixes"]
    only = argv[argv.index("--only") + 1] if "--only" in argv else None
    preview = argv[argv.index("--preview") + 1] if "--preview" in argv else None
    by_file = {}
    for f in fixes:
        if only and os.path.basename(f["file"])[:-4] != only:
            continue
        by_file.setdefault(f["file"], []).append(f)
    pairs = []
    for path, fl in by_file.items():
        full = os.path.join(ROOT, path)
        a = np.array(Image.open(full).convert("RGBA"))
        b = a
        for _ in range(6):  # a file's fixes can feed each other (a remap exposes new dither): run to a fixed point
            prev = b
            for f in fl:
                b = apply(b, f)
            if (b == prev).all():
                break
        changed = int((b != a).any(-1).sum())
        print("%-40s %4d px changed" % (path, changed))
        if preview:
            pairs.append((os.path.basename(path)[:-4], a, b))
        elif changed:
            Image.fromarray(b).save(full)
    if preview:
        os.makedirs(preview, exist_ok=True)
        sys.path.insert(0, HERE)
        from prop_icon_audit import sheet  # noqa: E402
        items = []
        for n, a, b in pairs:
            items += [(n + " before", a), (n + " after", b)]
        small = [i for i in items if max(i[1].shape[:2]) <= 40]
        big = [i for i in items if max(i[1].shape[:2]) > 40]
        if small:
            sheet(small, os.path.join(preview, "fixes_small.png"), 6, (150, 140, 120, 255), (86, 120, 70, 255),
                  cols=8)
        if big:
            sheet(big, os.path.join(preview, "fixes_big.png"), 3, (150, 140, 120, 255), (86, 120, 70, 255), cols=6)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
