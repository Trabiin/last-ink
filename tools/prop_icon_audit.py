#!/usr/bin/env python3
"""Icons and props audit (the icons/props review pass after PRs #216/#217): finds the small faults a person
spots when they look closely at a prop or an icon, so the whole set can be checked with one yardstick.

    python3 tools/prop_icon_audit.py OUT_DIR            # report.json + report.md + contact sheets in OUT_DIR
    python3 tools/prop_icon_audit.py OUT_DIR --only icons|props|buildings

Checks per image (docs/ART_STYLE.md: ink outline, hard alpha, no loose pixels, 38-colour palette):
  outline   share of the silhouette edge that is not dark (the outer outline should be ink black, #12141f).
            Light, glow and FX pixels (fire, Ink glow, magic arcs) are allowed to break it; see LIGHT_OK.
  specks    pixel islands of 1-3 px that float free of the object (stray pixels)
  orphans   lone pixels inside the object whose colour matches none of their 8 neighbours and stands out
            from all of them (the salt-and-pepper noise generated art leaves behind)
  jogs      1 px kinks in an otherwise straight silhouette edge (a post or a roof line that wobbles)
  soft      half-transparent pixels
  palette   share of pixels outside tools/style_palette.hex (reported only)
  dupe      images that are pixel-identical or nearly so to another image of the same size in the set
  fill      icons only: how much of the 32x32 cell the icon fills, against the set's median

Contact sheets: <set>_1x.png (game size, on grass for props and on the UI panel colour for icons),
<set>_zoom[_small|_mid|_big].png (6x / 4x / 3x by size, with every flagged pixel marked: red = orphan/speck, magenta = light outline,
cyan = jog).
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from palette_lock import load_palette  # noqa: E402

PLACEHOLDER = os.path.join(ROOT, "data", "placeholders.json")
DARK = 72          # max(r,g,b) below this counts as outline-dark
ORPHAN_DIST = 70   # colour distance (sum of abs RGB) an orphan must keep from every neighbour

# Icons whose glow or flame is the point: their light edge is not a missing outline.
LIGHT_OK = {"status_burn", "status_stun", "status_poison", "tech_ash", "tech_bran", "tech_gristle", "pike_sweep",
            "long_thrust", "cleave", "trait_ink_sick", "tech_ninefingers", "oil_flask", "ward_candle"}


def placeholders():
    out = set()
    for p in json.load(open(PLACEHOLDER))["placeholders"]:
        if p["kind"] in ("prop", "icon"):
            base = os.path.splitext(os.path.basename(p["path"]))[0]
            out.add(base)
    return out


def base_name(n):
    for k in range(1, 9):
        if n.endswith("_v%d" % k):
            return n[:-3]
    return n


def collect(only=None):
    skip = placeholders()
    sets = {"icons": "assets/icons", "props": "assets/props", "buildings": "assets/buildings"}
    out = {}
    for s, d in sets.items():
        if only and s != only:
            continue
        files = sorted(f for f in os.listdir(os.path.join(ROOT, d)) if f.endswith(".png"))
        out[s] = [(f[:-4], os.path.join(ROOT, d, f)) for f in files if base_name(f[:-4]) not in skip]
    return out


def analyse(path, name, kind, pal):
    a = np.array(Image.open(path).convert("RGBA")).astype(int)
    h, w = a.shape[:2]
    alpha = a[..., 3]
    op = alpha > 0
    rgb = a[..., :3]
    res = {"name": name, "size": [w, h]}
    res["soft"] = int(((alpha > 0) & (alpha < 255)).sum())
    # Edge pixels: opaque with a transparent 4-neighbour (or the canvas edge).
    pad = np.pad(op, 1, constant_values=False)
    nb_clear = ~pad[:-2, 1:-1] | ~pad[2:, 1:-1] | ~pad[1:-1, :-2] | ~pad[1:-1, 2:]
    edge = op & nb_clear
    light = edge & (rgb.max(-1) >= DARK)
    res["edge_px"] = int(edge.sum())
    res["light_edge"] = int(light.sum())
    res["light_share"] = round(float(light.sum()) / max(1, edge.sum()), 3)
    # Components (8-connected).
    lab = np.zeros((h, w), int)
    comps = []
    for y in range(h):
        for x in range(w):
            if op[y, x] and not lab[y, x]:
                stack = [(y, x)]
                lab[y, x] = len(comps) + 1
                pts = []
                while stack:
                    cy, cx = stack.pop()
                    pts.append((cy, cx))
                    for dy in (-1, 0, 1):
                        for dx in (-1, 0, 1):
                            ny, nx = cy + dy, cx + dx
                            if 0 <= ny < h and 0 <= nx < w and op[ny, nx] and not lab[ny, nx]:
                                lab[ny, nx] = len(comps) + 1
                                stack.append((ny, nx))
                comps.append(pts)
    specks = [p for c in comps if len(c) <= 3 for p in c]
    res["specks"] = len(specks)
    res["components"] = len(comps)
    # Orphans: interior pixels unlike every neighbour.
    orph = []
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            if not op[y, x]:
                continue
            c = rgb[y, x]
            nbs = [(y + dy, x + dx) for dy in (-1, 0, 1) for dx in (-1, 0, 1) if (dy or dx)]
            if not all(op[p] for p in nbs):
                continue
            d = [int(np.abs(rgb[p] - c).sum()) for p in nbs]
            if min(d) >= ORPHAN_DIST:
                orph.append((y, x))
    res["orphans"] = len(orph)
    # Jogs: 1 px kinks in straight silhouette runs (left/right profile per row, top/bottom per column).
    jogs = []

    def profile_jogs(prof, along):
        for i in range(2, len(prof) - 2):
            p = prof[i - 2:i + 3]
            if any(v is None for v in p):
                continue
            if p[0] == p[1] == p[3] == p[4] and abs(p[2] - p[0]) == 1:
                jogs.append(along(i, p[2]))

    rows = [np.flatnonzero(op[y]) for y in range(h)]
    cols = [np.flatnonzero(op[:, x]) for x in range(w)]
    profile_jogs([int(r[0]) if len(r) else None for r in rows], lambda i, v: (i, v))
    profile_jogs([int(r[-1]) if len(r) else None for r in rows], lambda i, v: (i, v))
    profile_jogs([int(c[0]) if len(c) else None for c in cols], lambda i, v: (v, i))
    profile_jogs([int(c[-1]) if len(c) else None for c in cols], lambda i, v: (v, i))
    res["jogs"] = len(jogs)
    pset = {tuple(c) for c in pal}
    cols_used = [tuple(v) for v in rgb[op]]
    res["colours"] = len(set(cols_used))
    res["off_palette"] = round(sum(1 for c in cols_used if c not in pset) / max(1, len(cols_used)), 3)
    ys, xs = np.nonzero(op)
    res["bbox"] = [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1] if len(xs) else [0, 0, 0, 0]
    res["fill"] = round(max(res["bbox"][2] - res["bbox"][0], res["bbox"][3] - res["bbox"][1]) / max(w, h), 2)
    marks = {"red": specks + orph, "magenta": [tuple(p) for p in np.argwhere(light)], "cyan": jogs}
    if name in LIGHT_OK:
        marks["magenta"] = []
    return res, a.astype(np.uint8), marks


def dupes(results, arrays):
    out = []
    groups = {}
    for n in arrays:
        groups.setdefault(arrays[n].shape, []).append(n)
    for g, names in groups.items():
        for i in range(len(names)):
            for j in range(i + 1, len(names)):
                A, B = arrays[names[i]], arrays[names[j]]
                if A.shape != B.shape:
                    continue
                diff = int((np.abs(A.astype(int) - B.astype(int)).sum(-1) > 0).sum())
                share = diff / max(1, int((A[..., 3] > 0).sum()))
                if share < 0.03:
                    out.append({"a": names[i], "b": names[j], "diff_px": diff})
    return out


def sheet(items, out, scale, bg, cell_bg, marks=None, cols=None):
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 11 if scale > 1 else 9)
    cw = max(a.shape[1] for _, a in items) * scale + 8
    ch = max(a.shape[0] for _, a in items) * scale + 20
    ncol = cols or max(1, min(len(items), 1900 // cw))
    nrow = (len(items) + ncol - 1) // ncol
    S = Image.new("RGBA", (ncol * cw, nrow * ch), bg)
    d = ImageDraw.Draw(S)
    for k, (n, a) in enumerate(items):
        x, y = (k % ncol) * cw, (k // ncol) * ch
        d.rectangle([x + 2, y + 2, x + cw - 3, y + ch - 17], fill=cell_bg)
        im = Image.fromarray(a).resize((a.shape[1] * scale, a.shape[0] * scale), Image.NEAREST)
        S.alpha_composite(im, (x + 4, y + 4))
        if marks:
            for colour, pts in marks[n].items():
                for (py, px) in pts:
                    X, Y = x + 4 + px * scale, y + 4 + py * scale
                    d.rectangle([X, Y, X + scale - 1, Y + scale - 1], outline=colour)
        d.text((x + 3, y + ch - 16), n[:26], fill=(20, 20, 20), font=font)
    S.save(out)


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    out = argv[0]
    only = argv[argv.index("--only") + 1] if "--only" in argv else None
    os.makedirs(out, exist_ok=True)
    pal = load_palette()
    report = {}
    for s, files in collect(only).items():
        res, arrays, marks = [], {}, {}
        for n, p in files:
            r, a, m = analyse(p, n, s, pal)
            res.append(r)
            arrays[n] = a
            marks[n] = m
        if s == "icons":
            med = float(np.median([r["fill"] for r in res]))
            for r in res:
                r["fill_vs_median"] = round(r["fill"] - med, 2)
        report[s] = {"items": res, "dupes": dupes(res, arrays)}
        items = [(n, arrays[n]) for n, _ in files]
        grass, panel = (86, 120, 70, 255), (58, 52, 60, 255)
        cell = panel if s == "icons" else grass
        sheet(items, os.path.join(out, "%s_1x.png" % s), 1 if s != "icons" else 2, (150, 140, 120, 255), cell)
        if s == "icons":
            buckets = [("", items, 6)]
        else:
            size = lambda a: max(a.shape[:2])  # noqa: E731
            buckets = [("_small", [i for i in items if size(i[1]) <= 40], 6),
                       ("_mid", [i for i in items if 40 < size(i[1]) <= 64], 4),
                       ("_big", [i for i in items if size(i[1]) > 64], 3)]
        for suffix, group, scale in buckets:
            if group:
                sheet(group, os.path.join(out, "%s_zoom%s.png" % (s, suffix)), scale, (150, 140, 120, 255),
                      (120, 150, 100, 255), marks)
    json.dump(report, open(os.path.join(out, "report.json"), "w"), indent=1)
    lines = ["| set | name | size | light edge | specks | orphans | jogs | soft | off-pal | fill |", "|" + "---|" * 10]
    for s, r in report.items():
        for it in r["items"]:
            lines.append("| %s | %s | %dx%d | %.0f%% | %d | %d | %d | %d | %.0f%% | %s |" % (
                s, it["name"], it["size"][0], it["size"][1], 100 * it["light_share"], it["specks"], it["orphans"],
                it["jogs"], it["soft"], 100 * it["off_palette"], it.get("fill_vs_median", "")))
        for dpl in r["dupes"]:
            lines.append("| %s | DUPE %s = %s | | %d px differ | | | | | | |" % (s, dpl["a"], dpl["b"], dpl["diff_px"]))
    open(os.path.join(out, "report.md"), "w").write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
