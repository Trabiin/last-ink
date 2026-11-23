#!/usr/bin/env python3
"""Animation checker: the measurable half of Ojon's review rules (docs/ANIMATION_RULES.md).

It flags; it never fixes. Every flag still gets a look by eye, and the rules it can't measure (natural motion,
feet crossing, cross-direction item colours) are done by eye on the contact sheet.

    python3 tools/anim_check.py bran                 # every animation of one sprite
    python3 tools/anim_check.py bran walk idle       # only these animations
    python3 tools/anim_check.py --all --json out.json

Checks, per animation and direction (bands are cut from the rotation frame: head = top 30%, body = 30-70%,
legs = the rest down to the feet line):
  legs-still   walk: the legs move much less than in the character's liveliest walk direction
  idle-walks   idle: the feet move as much as in the walk (it is walking, not idling)
  frozen       idle: the body barely moves while the head does (arms stay put)
  detail-pops  a colour patch in the head comes and goes between frames (eyes vanish, mouth changes colour)
  new-colour   a colour patch appears in the head that the rotation frame doesn't have (a face on the back
               of the head, a red patch)
  outline      the black outline turns lighter on some frames (the outline takes the cloak colour)
  drift        walk: the head swings sideways (facing south or north, 1.5+ px on a 44 px canvas) instead of moving forward;
               the diagonals get 2+ px, east is skipped because sideways is forward there
"""
import json
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPRITES = json.load(open(os.path.join(ROOT, "data", "sprites.json")))["sprites"]
DIRS = ["south", "south-east", "east", "north-east", "north"]


def load(sid, name):
    p = os.path.join(ROOT, "assets", "sprites", sid, name + ".png")
    return np.array(Image.open(p).convert("RGBA")).astype(int) if os.path.exists(p) else None


def frames(sid, anim, d):
    a = load(sid, "%s_%s" % (anim, d))
    if a is None:
        return None
    fw = SPRITES[sid]["size"][0]
    return [a[:, i * fw:(i + 1) * fw] for i in range(a.shape[1] // fw)]


def bands(sid, d):
    rot = load(sid, "rot_" + d)
    fw, fh = SPRITES[sid]["size"]
    rot = rot[:fh, :fw] if rot is not None else None
    ys = np.nonzero(rot[:, :, 3])[0] if rot is not None else np.array([0, fh - 1])
    top, feet = int(ys.min()), int(SPRITES[sid]["feet"][1])
    h = feet - top
    return rot, {"head": (top, top + int(h * 0.30)), "body": (top + int(h * 0.30), top + int(h * 0.70)),
                 "legs": (top + int(h * 0.70), feet + 2), "feet": (feet - 3, feet + 2)}


def motion(fr, band):
    y0, y1 = band
    n = len(fr)
    if n < 2:
        return 0.0
    return sum(int((np.abs(fr[k][y0:y1] - fr[(k + 1) % n][y0:y1]).sum(2) > 0).sum()) for k in range(n)) / n


def luma(px):
    return 0.299 * px[..., 0] + 0.587 * px[..., 1] + 0.114 * px[..., 2]


def edge_darkness(f):
    """Share of silhouette edge pixels that are dark (outline)."""
    a = f[:, :, 3] > 0
    pad = np.pad(a, 1)
    inner = pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:]
    edge = a & ~inner
    if not edge.any():
        return 1.0
    return float((luma(f[edge]) < 70).mean())


def head_flicker(fr, band):
    """Groups the head's colours (within 24 of each other) and counts them per frame. A group that is there on
    most frames (2+ px) but gone on some = a detail vanishing (eyes, mouth). A group of 4+ px that shows up on at
    most a third of the frames = a patch popping in. Dark outline colours are ignored."""
    y0, y1 = band
    per = [f[y0:y1][f[y0:y1, :, 3] > 0][:, :3] for f in fr]
    allpx = np.concatenate([p for p in per if len(p)]) if any(len(p) for p in per) else np.zeros((0, 3), int)
    cols = [c for c in np.unique(allpx, axis=0) if luma(c[None])[0] > 30]
    groups = []
    for c in cols:
        for g in groups:
            if np.abs(g[0] - c).sum() <= 24:
                g.append(c)
                break
        else:
            groups.append([c])
    pops = patches = None
    n = len(fr)
    for g in groups:
        g = np.array(g)
        cnt = np.array([int((np.abs(p[:, None, :] - g[None]).sum(2) == 0).any(1).sum()) if len(p) else 0 for p in per])
        if np.median(cnt) >= 2 and cnt.min() == 0 and not pops:
            pops = (sorted(int(k) + 1 for k in np.nonzero(cnt == 0)[0]),) + tuple(int(v) for v in g[0])
        if cnt.max() >= 4 and (cnt > 0).sum() <= max(1, n // 3) and not patches:
            patches = (int(cnt.max()), sorted(int(k) + 1 for k in np.nonzero(cnt > 0)[0])) + tuple(int(v) for v in g[0])
    return pops, patches


def head_x(fr, band):
    """Mean x of the head pixels per frame."""
    y0, y1 = band
    out = []
    for f in fr:
        xs = np.nonzero(f[y0:y1, :, 3] > 0)[1]
        out.append(float(xs.mean()) if len(xs) else 0.0)
    return out


DRIFT = {"south": 1.5, "north": 1.5, "south-east": 2.0, "north-east": 2.0}


def colour_counts(f, band, palette):
    """Counts of head pixels per palette colour (nearest within 24), plus pixels far from every colour."""
    y0, y1 = band
    px = f[y0:y1][f[y0:y1, :, 3] > 0][:, :3]
    if not len(px):
        return np.zeros(len(palette)), 0
    dist = np.abs(px[:, None, :] - palette[None, :, :]).sum(2)
    near = dist.argmin(1)
    ok = dist.min(1) <= 24
    return np.bincount(near[ok], minlength=len(palette)), int((~ok).sum())


def check(sid, anim):
    out = []
    fw, fh = SPRITES[sid]["size"]
    walk_legs = {d: motion(frames(sid, "walk", d), bands(sid, d)[1]["feet"])
                 for d in DIRS if "walk" in SPRITES[sid]["anims"] and frames(sid, "walk", d)}
    per = {}
    for d in DIRS:
        fr = frames(sid, anim, d)
        if not fr:
            continue
        rot, b = bands(sid, d)
        per[d] = (fr, rot, b, {k: motion(fr, v) for k, v in b.items()})
    if not per:
        return out
    best_legs = max(v[3]["legs"] for v in per.values())
    med_body = float(np.median([v[3]["body"] for v in per.values()]))
    med_feet = float(np.median([v[3]["feet"] for v in per.values()]))
    for d, (fr, rot, b, m) in per.items():
        flags = []
        if anim == "walk" and best_legs and m["legs"] < 0.65 * best_legs:
            flags.append(("legs-still", "legs move %.0f px/frame vs %.0f in the liveliest direction" % (m["legs"], best_legs)))
        if anim == "walk" and d in DRIFT:
            xs = head_x(fr, b["head"])
            if max(xs) - min(xs) >= DRIFT[d] * max(1.0, fw / 44.0):
                flags.append(("drift", "head swings %.1f px sideways (x %s)"
                              % (max(xs) - min(xs), " ".join("%.1f" % x for x in xs))))
        if anim == "idle" and m["feet"] > 15 and m["feet"] > 1.5 * med_feet:
            flags.append(("idle-walks", "feet move %.0f px/frame vs %.0f in the other idle directions" % (m["feet"], med_feet)))
        if anim == "idle" and med_body and m["body"] < 0.6 * med_body:
            flags.append(("frozen", "body moves %.0f px/frame vs %.0f in the other directions" % (m["body"], med_body)))
        if rot is not None:
            hb = b["head"]
            pops, patches = head_flicker(fr, hb)
            if pops:
                flags.append(("detail-pops", "a head detail vanishes on frame(s) %s (colour #%02x%02x%02x)" % pops))
            if patches:
                flags.append(("new-colour", "a %d px head patch shows up only on frame(s) %s (colour #%02x%02x%02x)" % patches))
            base = edge_darkness(rot)
            dark = [edge_darkness(f) for f in fr]
            if base - min(dark) > 0.12:
                flags.append(("outline", "outline %.0f%% dark on frame %d vs %.0f%% in the rotation"
                              % (100 * min(dark), int(np.argmin(dark)) + 1, 100 * base)))
        out.append({"sprite": sid, "anim": anim, "dir": d, "motion": {k: round(v) for k, v in m.items()},
                    "flags": [{"rule": r, "why": w} for r, w in flags]})
    return out


def main(argv):
    js = None
    if "--json" in argv:
        i = argv.index("--json")
        js = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    sids = sorted(SPRITES) if argv[:1] == ["--all"] else argv[:1]
    if not sids:
        print(__doc__)
        return 1
    anims = argv[1:] if argv[:1] != ["--all"] else []
    res = []
    for sid in sids:
        for anim in (anims or [a for a in SPRITES[sid]["anims"] if a != "rot"]):
            if anim in SPRITES[sid]["anims"]:
                res += check(sid, anim)
    for r in res:
        tag = ", ".join(f["rule"] for f in r["flags"]) or "ok"
        print("%-12s %-8s %-11s %s" % (r["sprite"], r["anim"], r["dir"], tag))
        for f in r["flags"]:
            print("%35s- %s" % ("", f["why"]))
    if js:
        json.dump(res, open(js, "w"), indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
