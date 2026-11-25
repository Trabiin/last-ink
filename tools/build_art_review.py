#!/usr/bin/env python3
"""Builds the data for the Art Review page (issue #166): every sprite animation, portrait, prop, building,
icon, tile set and painted piece in the game, packed into a few atlases plus manifest.json, so the review
page can play each animation and keep a checklist per asset.

    python3 tools/build_art_review.py OUT_DIR

OUT_DIR gets manifest.json, sprites/<id>.png (all strips of a character stacked), portraits/<id>.png,
props.png / buildings.png / icons.png / legacy.png (packed atlases), tiles/<set>_*.png and ui/*. The page
itself lives in project files (last-ink/art-review/index.html) and is published as an Artifact with these
files beside it; rebuild and republish when art changes. Each unit carries a hash of its pixels, so the page
can tell when an asset changed after it was checked.
"""
import hashlib
import json
import os
import shutil
import subprocess
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A = os.path.join(ROOT, "assets")
SPRITES = json.load(open(os.path.join(ROOT, "data", "sprites.json")))["sprites"]
PL_SRC = json.load(open(os.path.join(ROOT, "tools", "pixellab_sources.json")))
DIRS = ["south", "south-east", "east", "north-east", "north"]
ROLES = {  # what each sprite is, for grouping on the page
    "hero": ["ash", "bran", "gristle", "ninefingers", "jessamy", "odile", "ottoline", "velvette"],
    "enemy": ["nibbler", "spitter", "moth", "reedling", "scarecrow", "sellsword", "enforcer", "auditor"],
}


def role_of(sid):
    for r, ids in ROLES.items():
        if sid in ids:
            return r
    return "folk" if sid.startswith("folk_") else "npc"


def digest(*images):
    h = hashlib.sha1()
    for im in images:
        h.update(im.tobytes())
    return h.hexdigest()[:12]


def pack(paths, out_path, pad=2, width=1024):
    """Shelf-packs images into one atlas. Returns {name: [x, y, w, h]}."""
    ims = [(os.path.splitext(os.path.basename(p))[0], Image.open(p).convert("RGBA")) for p in paths]
    order = sorted(ims, key=lambda t: -t[1].size[1])
    x = y = shelf = 0
    rects = {}
    for name, im in order:
        w, h = im.size
        if x + w > width:
            x, y, shelf = 0, y + shelf + pad, 0
        rects[name] = [x, y, w, h]
        x += w + pad
        shelf = max(shelf, h)
    atlas = Image.new("RGBA", (width, y + shelf), (0, 0, 0, 0))
    for name, im in ims:
        atlas.paste(im, tuple(rects[name][:2]))
    atlas.save(out_path, optimize=True)
    return rects, {name: im for name, im in ims}


def build(out):
    os.makedirs(os.path.join(out, "sprites"), exist_ok=True)
    os.makedirs(os.path.join(out, "portraits"), exist_ok=True)
    os.makedirs(os.path.join(out, "tiles"), exist_ok=True)
    os.makedirs(os.path.join(out, "ui"), exist_ok=True)
    units = []
    portraits = {f[:-4] for f in os.listdir(os.path.join(A, "portraits")) if f.endswith(".png")}

    # Characters: one atlas per sprite, every strip stacked; one identity unit + one unit per animation.
    for sid in sorted(SPRITES):
        spec = SPRITES[sid]
        fw, fh = spec["size"]
        strips, y = [], 0
        layout = {}
        for anim, a in spec["anims"].items():
            layout[anim] = {}
            for d in a["dirs"]:
                p = os.path.join(A, "sprites", sid, "%s_%s.png" % (anim, d))
                if not os.path.exists(p):
                    continue
                im = Image.open(p).convert("RGBA")
                strips.append((anim, d, im, y))
                layout[anim][d] = y
                y += im.size[1]
        w = max(im.size[0] for _, _, im, _ in strips)
        atlas = Image.new("RGBA", (w, y), (0, 0, 0, 0))
        for _, _, im, yy in strips:
            atlas.paste(im, (0, yy))
        atlas.save(os.path.join(out, "sprites", sid + ".png"), optimize=True)
        role = role_of(sid)
        rot = [im for a, _, im, _ in strips if a == "rot"]

        def src_of(anim):
            """Where each direction's pixels live: in PixelLab (same pixels as the game, edit there and sync)
            or only in the game's PNG (built or changed in code; edit the file)."""
            out = {}
            for d in layout.get(anim, {}):
                s_ = PL_SRC["strips"].get("%s/%s_%s" % (sid, anim, d))
                if s_ and s_["mode"] == "direct":
                    out[d] = {"where": "pixellab", "char": PL_SRC["characters"].get(s_["character"], {}).get("name", s_["character"]),
                              "anim": "rotation" if anim == "rot" else s_["animation"]}
                else:
                    out[d] = {"where": "game", "file": "assets/sprites/%s/%s_%s.png" % (sid, anim, d)}
            return out
        units.append({"id": "char-%s/identity" % sid, "doc": "char-" + sid, "cat": "Characters",
                      "group": sid, "role": role, "kind": "identity", "title": "%s: look and proportions" % sid,
                      "sprite": sid, "portrait": sid if sid in portraits else None, "origin": src_of("rot"),
                      "hash": digest(*rot) + (digest(Image.open(os.path.join(A, "portraits", sid + ".png")))
                                              if sid in portraits else "")})
        for anim, a in spec["anims"].items():
            if anim == "rot" or not layout.get(anim):
                continue
            ims = [im for an, _, im, _ in strips if an == anim]
            units.append({"id": "char-%s/%s" % (sid, anim), "doc": "char-" + sid, "cat": "Characters",
                          "group": sid, "role": role, "kind": "anim", "title": "%s: %s" % (sid, anim),
                          "sprite": sid, "anim": anim, "fps": a["fps"], "loop": a["loop"], "frames": a["frames"],
                          "origin": src_of(anim),
                          "hash": digest(*ims)})
    sprites_meta = {sid: {"size": s["size"], "feet": s["feet"], "role": role_of(sid),
                          "anims": {an: {"fps": a["fps"], "loop": a["loop"], "frames": a["frames"]}
                                    for an, a in s["anims"].items()},
                          "rows": {}} for sid, s in SPRITES.items()}
    for sid, s in SPRITES.items():
        y = 0
        for anim, a in s["anims"].items():
            sprites_meta[sid]["rows"][anim] = {}
            for d in a["dirs"]:
                p = os.path.join(A, "sprites", sid, "%s_%s.png" % (anim, d))
                if os.path.exists(p):
                    sprites_meta[sid]["rows"][anim][d] = y
                    y += Image.open(p).size[1]

    # Portraits.
    for pid in sorted(portraits):
        src = os.path.join(A, "portraits", pid + ".png")
        shutil.copy(src, os.path.join(out, "portraits", pid + ".png"))
        units.append({"id": "portraits/" + pid, "doc": "portraits", "cat": "Portraits", "group": "portraits",
                      "kind": "portrait", "title": pid, "portrait": pid,
                      "sprite": pid if pid in SPRITES else None, "hash": digest(Image.open(src).convert("RGBA"))})

    # Props, buildings, icons, legacy paper doll: atlases, grouped by base name (variants together).
    def atlas_units(folder, atlas_name, cat, doc, kind, group_fn):
        d = os.path.join(A, folder)
        paths = sorted(os.path.join(d, f) for f in os.listdir(d) if f.endswith(".png"))
        rects, ims = pack(paths, os.path.join(out, atlas_name))
        groups = {}
        for name in sorted(rects):
            groups.setdefault(group_fn(name), []).append(name)
        for g, names in sorted(groups.items()):
            units.append({"id": "%s/%s" % (doc, g), "doc": doc, "cat": cat, "group": cat.lower(), "kind": kind,
                          "title": g, "atlas": atlas_name,
                          "images": [{"name": n, "rect": rects[n]} for n in names],
                          "hash": digest(*(ims[n] for n in names))})

    def base(name):
        for suf in ("_v1", "_v2", "_v3", "_v4", "_v5"):
            if name.endswith(suf):
                return name[: -len(suf)]
        return name

    def building(name):
        return name.rsplit("_", 1)[0]

    atlas_units("props", "props.png", "Props", "props", "prop", base)
    atlas_units("buildings", "buildings.png", "Buildings", "buildings", "building", building)
    atlas_units("icons", "icons.png", "Icons", "icons", "icon", lambda n: n)
    atlas_units("characters", "legacy.png", "Other", "other", "legacy", lambda n: "paper doll " + n)

    # Ground: 16 corner tiles + the seamless textures per set.
    for ts in sorted(os.listdir(os.path.join(A, "tiles"))):
        d = os.path.join(A, "tiles", ts)
        if not os.path.isdir(d):
            continue
        tiles = sorted(f for f in os.listdir(d) if len(f) == 8 and f.endswith(".png"))
        sheet = Image.new("RGBA", (16 * len(tiles), 16), (0, 0, 0, 0))
        ims = []
        for i, f in enumerate(tiles):
            im = Image.open(os.path.join(d, f)).convert("RGBA")
            ims.append(im)
            sheet.paste(im, (16 * i, 0))
        sheet.save(os.path.join(out, "tiles", ts + "_corners.png"))
        tex = []
        for t in ("grass", "cobbles"):
            p = os.path.join(d, t + ".png")
            if os.path.exists(p):
                shutil.copy(p, os.path.join(out, "tiles", "%s_%s.png" % (ts, t)))
                tex.append("tiles/%s_%s.png" % (ts, t))
                ims.append(Image.open(p).convert("RGBA"))
        units.append({"id": "tiles/" + ts, "doc": "tiles", "cat": "Ground", "group": "ground", "kind": "tiles",
                      "title": ts, "corners": "tiles/%s_corners.png" % ts, "names": [f[:4] for f in tiles],
                      "textures": tex, "hash": digest(*ims)})
    for f in ("dirt.png", "overworld.png"):
        p = os.path.join(A, "tiles", f)
        if os.path.exists(p):
            shutil.copy(p, os.path.join(out, "tiles", f))
            units.append({"id": "tiles/" + f[:-4], "doc": "tiles", "cat": "Ground", "group": "ground",
                          "kind": "picture", "title": f[:-4], "src": "tiles/" + f,
                          "hash": digest(Image.open(p).convert("RGBA"))})

    # Painted and UI pieces.
    for f in sorted(os.listdir(os.path.join(A, "ui"))):
        if f.endswith((".png", ".jpg")):
            shutil.copy(os.path.join(A, "ui", f), os.path.join(out, "ui", f))
            painted = f.endswith(".jpg")
            units.append({"id": "ui/" + f.rsplit(".", 1)[0], "doc": "ui", "cat": "Painted and UI", "group": "ui",
                          "kind": "painting" if painted else "picture", "title": f.rsplit(".", 1)[0],
                          "src": "ui/" + f, "hash": digest(Image.open(os.path.join(A, "ui", f)).convert("RGBA"))})

    # Stand-ins (data/placeholders.json) stay off the page: the final art batch replaces every one, so judging
    # them is wasted effort. Each shows up for review once its entry is deleted, i.e. when its final art lands.
    ph = {}
    for e in json.load(open(os.path.join(ROOT, "data", "placeholders.json")))["placeholders"]:
        kind, name = e["id"].split(":", 1)
        ph.setdefault(kind, set()).add(name)
    unit_kind = {"identity": "sprite", "anim": "sprite", "portrait": "portrait", "prop": "prop", "icon": "icon",
                 "tiles": "tiles"}

    def stand_in(u):
        k = unit_kind.get(u["kind"])
        name = u["sprite"] if k == "sprite" else u["id"].split("/", 1)[1]
        return k is not None and name in ph.get(k, ())

    hidden = [u for u in units if stand_in(u)]
    units = [u for u in units if not stand_in(u)]

    try:
        commit = subprocess.check_output(["git", "-C", ROOT, "rev-parse", "--short", "HEAD"], text=True).strip()
    except Exception:
        commit = ""
    manifest = {"commit": commit, "sprites": sprites_meta, "units": units,
                "backgrounds": {"grass": "tiles/meadow_grass.png", "cobbles": "tiles/town_cobbles.png"}}
    json.dump(manifest, open(os.path.join(out, "manifest.json"), "w"), separators=(",", ":"))
    by = {}
    for u in units:
        by[u["cat"]] = by.get(u["cat"], 0) + 1
    print("%d units: %s (%d stand-ins hidden)" % (len(units), by, len(hidden)))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)
    build(sys.argv[1])
