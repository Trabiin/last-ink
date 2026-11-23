#!/usr/bin/env python3
"""Keeps the game's sprites in step with hand edits made in PixelLab (or Pixelorama, saved back to PixelLab).

Every sprite strip in assets/sprites/<id>/<anim>_<dir>.png came from one PixelLab character and one of its
animations. tools/pixellab_sources.json records which, plus a hash of the PixelLab frames as they were when
the strip was imported. When someone touches up frames in PixelLab, the hash changes, so this tool can tell
exactly which strips were edited and pull only those, without searching through every generation.

Fetching is free: it only downloads the characters' ZIP exports (no generation, no credit used).

    python3 tools/pixellab_sync.py               # check: list strips edited in PixelLab since the last pull
    python3 tools/pixellab_sync.py pull          # rebuild those strips from PixelLab, update the hashes
    python3 tools/pixellab_sync.py pull --only ash
    python3 tools/pixellab_sync.py push          # write the game's version of changed strips back into PixelLab
    python3 tools/pixellab_sync.py push --dry    # list what push would write
    python3 tools/pixellab_sync.py list          # which PixelLab character feeds each game sprite
    python3 tools/pixellab_sync.py map RAW_DIR   # (re)build the source map from downloaded characters

TWO-WAY RULE: PixelLab and the game hold the same pixels for every strip marked "direct". After any change
made in the repo (fix_frames.py, recolor_sprite.py, a regeneration), run `push`: it saves the game's frames
into the PixelLab animation direction (free; PixelLab's old frames are kept in PIXELLAB_BACKUP as the undo),
re-fetches to verify, and marks the strip direct. Fixes it carried are marked "baked" in ai_fixes.json so
fix_frames.py does not run them again over later edits. Pushed strips skip palette_lock.clean on pull.

A strip marked "processed" could not be pushed (two game strips share one PixelLab animation, or several
PixelLab animations share its name): its pixels live only in the game's PNG. Pulling it would drop the game's
change, so `pull` skips it and says so unless --force is given. Edit those PNGs directly.

The list of sources is also written to docs/PIXELLAB_SOURCES.md, so you can see which PixelLab character
and animation to open when you want to edit something in the game.
"""
import argparse
import glob
import hashlib
import json
import os
import re
import sys
import tempfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import palette_lock  # noqa: E402

MAP = os.path.join(HERE, "pixellab_sources.json")
DOC = os.path.join(ROOT, "docs", "PIXELLAB_SOURCES.md")
SPRITES = os.path.join(ROOT, "data", "sprites.json")


def fit(im, size):
    """Centre a PixelLab frame on the game's square frame (rotations come at 32 px, v3 animations at 44)."""
    w, h = im.size
    if (w, h) == (size, size):
        return im
    c = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    c.paste(im, ((size - w) // 2, (size - h) // 2))
    return c


def frame_hash(paths):
    h = hashlib.sha1()
    for p in paths:
        im = Image.open(p).convert("RGBA")
        h.update(f"{im.size}".encode())
        h.update(im.tobytes())
    return h.hexdigest()[:16]


def index_raw(raw_dir):
    """(animation, direction) -> ordered frame paths, from a fetch_character() folder. Rotations use 'rot'."""
    out = {}
    for p in glob.glob(os.path.join(raw_dir, "*.png")):
        b = os.path.basename(p)[:-4]
        m = re.match(r"(.+)_([a-z-]+)_(\d+)$", b)
        if m:
            out.setdefault((m[1], m[2]), []).append((int(m[3]), p))
        else:
            out.setdefault(("rot", b), []).append((0, p))
    return {k: [p for _, p in sorted(v)] for k, v in out.items()}


def build_strip(paths, size, frames, clean=True):
    """clean=False for strips pushed from the game: PixelLab already holds the game's exact pixels."""
    strip = Image.new("RGBA", (size * frames, size), (0, 0, 0, 0))
    for i, p in enumerate(paths[:frames]):
        im = fit(Image.open(p).convert("RGBA"), size)
        strip.paste(palette_lock.clean(im) if clean else im, (i * size, 0))
    return strip


def load_map():
    with open(MAP) as f:
        return json.load(f)


def save_map(m):
    """One line per strip, so diffs show exactly which strips a pull touched."""
    strips = ",\n".join(f"    {json.dumps(k)}: {json.dumps(v)}" for k, v in sorted(m["strips"].items()))
    chars = ",\n".join(f"    {json.dumps(k)}: {json.dumps(v)}" for k, v in sorted(m["characters"].items()))
    with open(MAP, "w") as f:
        f.write('{\n  "characters": {\n' + chars + '\n  },\n  "unmatched": ' + json.dumps(m.get("unmatched", []))
                + ',\n  "strips": {\n' + strips + "\n  }\n}\n")


def write_doc(m):
    by_sprite = {}
    for key, s in sorted(m["strips"].items()):
        sid, rest = key.split("/")
        by_sprite.setdefault(sid, {}).setdefault(s["character"], []).append((rest, s))
    lines = ["# PixelLab sources", "",
             "Which PixelLab character and animation each game sprite comes from. Generated by",
             "`tools/pixellab_sync.py`; do not edit by hand.", "",
             "To touch up a sprite: open the character below in PixelLab (or Pixelorama), edit the frames of the",
             "listed animation and save. Then ask Claude to sync (`python3 tools/pixellab_sync.py pull`): only",
             "the strips you edited are pulled into the game.", "",
             "\"processed\" means the game's strip exists only in the game files (built or changed in code and it",
             "could not be saved back into PixelLab). Edit those PNGs directly; everything else matches PixelLab.", "",
             "| Game sprite | PixelLab character | Animations used (game name <- PixelLab name) |", "|---|---|---|"]
    for sid, chars in by_sprite.items():
        for cid, rows in chars.items():
            name = m["characters"].get(cid, {}).get("name", cid)
            anims = {}
            for rest, s in rows:
                an, d = rest.rsplit("_", 1)
                tag = f"{an} <- {s['animation']}" + (" (processed)" if s["mode"] == "processed" else "")
                anims.setdefault(tag, []).append(d)
            cell = "; ".join(f"{t}: {', '.join(ds)}" for t, ds in anims.items())
            lines.append(f"| {sid} | {name} | {cell} |")
    unmatched = m.get("unmatched", [])
    if unmatched:
        lines += ["", "No PixelLab source found (made or heavily changed in code): " + ", ".join(unmatched)]
    with open(DOC, "w") as f:
        f.write("\n".join(lines) + "\n")


def fetch(cids, out):
    from pixellab import PL
    from concurrent.futures import ThreadPoolExecutor
    pl = PL("sync")

    def one(cid):
        pl.fetch_character(cid, os.path.join(out, cid))
        return cid, pl.character(cid).get("updated_at")
    with ThreadPoolExecutor(6) as ex:
        return dict(ex.map(one, cids))


# ------------------------------------------------------------------------------------------------ map
def cmd_map(args):
    """Matches every game strip to the PixelLab animation whose frames it came from (silhouette overlap per
    frame; an exact pixel match after palette_lock.clean marks it 'direct')."""
    chars = {c["id"]: c for c in json.load(open(os.path.join(args.raw, "chars.json")))}
    raw = {cid: index_raw(os.path.join(args.raw, cid)) for cid in chars}
    spr = json.load(open(SPRITES))["sprites"]
    cache = {}

    def arr(p, size):
        if (p, size) not in cache:
            cache[(p, size)] = np.asarray(fit(Image.open(p).convert("RGBA"), size))
        return cache[(p, size)]

    strips, unmatched = {}, []
    for sid, e in spr.items():
        if args.only and sid not in args.only:
            continue
        size = e["size"][0]
        # best candidate per (strip, character)
        cands = {}
        for an, a in e["anims"].items():
            for d in a["dirs"]:
                key = f"{sid}/{an}_{d}"
                strip = np.asarray(Image.open(os.path.join(ROOT, "assets", "sprites", sid, f"{an}_{d}.png")).convert("RGBA"))
                n = a["frames"]
                fr = [strip[:, i * size:(i + 1) * size] for i in range(n)]
                per = {}
                for cid, anims in raw.items():
                    for (ran, rd), ps in anims.items():
                        if rd != d or (an == "rot") != (ran == "rot") or len(ps) < n:
                            continue
                        A = [arr(p, size) for p in ps[:n]]
                        if A[0].shape != fr[0].shape:
                            continue
                        iou = 0.0
                        for i in range(n):
                            m1, m2 = fr[i][..., 3] > 128, A[i][..., 3] > 128
                            u = (m1 | m2).sum()
                            iou += (m1 & m2).sum() / u if u else 0
                        iou /= n
                        if cid not in per or iou > per[cid][0]:
                            per[cid] = (iou, ran, ps[:n])
                cands[key] = (strip, n, per)
        # The sprite's own PixelLab character is the one most of its strips match closely; strips that were
        # rebuilt in code can look like some other character, so only that character is accepted for them.
        votes = {}
        for strip, n, per in cands.values():
            for cid, (iou, _, _) in per.items():
                if iou >= 0.95:
                    votes[cid] = votes.get(cid, 0) + 1
        for key, (strip, n, per) in cands.items():
            options = sorted(per.items(), key=lambda kv: (votes.get(kv[0], 0), kv[1][0]), reverse=True)
            options = [o for o in options if o[1][0] >= 0.8]
            # prefer a character the sprite votes for; fall back to any near-perfect match
            pick = next((o for o in options if votes.get(o[0])), None)
            best_any = max(per.items(), key=lambda kv: kv[1][0], default=None)
            if best_any and best_any[1][0] >= 0.97 and (not pick or best_any[1][0] > pick[1][0] + 0.02):
                pick = best_any
            if not pick and not votes and best_any and best_any[1][0] >= 0.85:
                pick = best_any  # every strip of this sprite was changed in code; take the closest source
            if not pick:
                unmatched.append(key)
                continue
            cid, (iou, ran, ps) = pick
            direct = np.array_equal(np.asarray(build_strip(ps, size, n)), strip)
            strips[key] = {"character": cid, "animation": ran, "frames": n, "size": size,
                           "hash": frame_hash(ps), "mode": "direct" if direct else "processed",
                           "match": round(float(iou), 3)}
        print(sid, file=sys.stderr)
    old = load_map() if os.path.exists(MAP) and args.only else {"characters": {}, "strips": {}}
    old["strips"].update(strips)
    used = {s["character"] for s in old["strips"].values()}
    old["characters"] = {cid: {"name": chars[cid]["name"]} if cid in chars else old["characters"].get(cid, {})
                         for cid in sorted(used)}
    old["unmatched"] = sorted(set(old.get("unmatched", [])) - set(strips) | set(unmatched))
    save_map(old)
    write_doc(old)
    print(f"{len(strips)} strips mapped, {len(unmatched)} without a PixelLab source")


# ---------------------------------------------------------------------------------------- check / pull
def changed(m, raw_root, only):
    out = []
    for key, s in sorted(m["strips"].items()):
        if only and key.split("/")[0] not in only:
            continue
        an, d = key.split("/")[1].rsplit("_", 1)
        ps = index_raw(os.path.join(raw_root, s["character"])).get((s["animation"], d), [])
        if len(ps) < s["frames"]:
            out.append((key, s, None, "missing on PixelLab"))
            continue
        h = frame_hash(ps[:s["frames"]])
        if h != s["hash"]:
            out.append((key, s, ps[:s["frames"]], h))
    return out


def cmd_check(args, pull=False):
    m = load_map()
    cids = sorted({s["character"] for k, s in m["strips"].items() if not args.only or k.split("/")[0] in args.only})
    with tempfile.TemporaryDirectory() as tmp:
        fetch(cids, tmp)
        edits = changed(m, tmp, args.only)
        if not edits:
            print("No edits in PixelLab since the last pull.")
            return
        for key, s, ps, h in edits:
            name = m["characters"].get(s["character"], {}).get("name", s["character"])
            if ps is None:
                print(f"  {key}: {h} ({name} / {s['animation']})")
                continue
            sid, rest = key.split("/")
            if not pull:
                print(f"  {key}: edited in PixelLab ({name} / {s['animation']})" + (" [processed]" if s["mode"] == "processed" else ""))
                continue
            if s["mode"] == "processed" and not args.force:
                print(f"  {key}: SKIPPED, the game's strip was changed after import; pull with --force after a look")
                continue
            build_strip(ps, s["size"], s["frames"], s.get("clean", True)).save(os.path.join(ROOT, "assets", "sprites", sid, rest + ".png"))
            s["hash"], s["mode"] = h, "direct"
            print(f"  {key}: pulled")
        if pull:
            save_map(m)
            write_doc(m)


# ------------------------------------------------------------------------------------------------ push
BACKUP = os.environ.get("PIXELLAB_BACKUP", "/mnt/project-files/last-ink/pixellab-backup")


def game_frames(key, s):
    sid, rest = key.split("/")
    strip = Image.open(os.path.join(ROOT, "assets", "sprites", sid, rest + ".png")).convert("RGBA")
    z = s["size"]
    return [strip.crop((i * z, 0, (i + 1) * z, z)) for i in range(s["frames"])]


def unfit(frame, w, h):
    """Inverse of fit(): put a game frame back on PixelLab's canvas (same centring, crop or pad)."""
    z = frame.size[0]
    c = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    c.paste(frame, ((w - z) // 2, (h - z) // 2))
    return c


def b64png(im):
    import base64
    import io
    buf = io.BytesIO()
    im.save(buf, "PNG")
    return {"base64": base64.b64encode(buf.getvalue()).decode()}


def cmd_push(args):
    """Writes the game's version of every strip that differs from PixelLab back into PixelLab
    (POST /save-to-asset: free, returns the replaced frames, which are kept in BACKUP as the undo).
    Afterwards PixelLab and the game hold the same pixels, so edits can be made in either place."""
    import base64
    import time
    from pixellab import PL
    pl = PL("sync")
    m = load_map()
    keys = [k for k in sorted(m["strips"]) if (not args.only or k.split("/")[0] in args.only)
            and (not args.keys or k in args.keys)]
    targets = {}
    for k, s in m["strips"].items():
        targets.setdefault((s["character"], s["animation"], k.rsplit("_", 1)[1]), []).append(k)
    cids = sorted({m["strips"][k]["character"] for k in keys})
    groups = {}
    for cid in cids:
        for a in pl.character(cid).get("animations", []):
            nm = (a.get("display_name") or a.get("animation_type") or "").lower().replace(" ", "_").replace("-", "_")
            for d in a["directions"]:
                groups.setdefault((cid, nm, d["direction"]), []).append(a["animation_group_id"])
    stamp = time.strftime("%Y%m%d-%H%M%S")
    pushed = skipped = same = 0
    with tempfile.TemporaryDirectory() as tmp:
        fetch(cids, tmp)
        raws = {cid: index_raw(os.path.join(tmp, cid)) for cid in cids}
        for key in keys:
            s = m["strips"][key]
            an, d = key.split("/")[1].rsplit("_", 1)
            ps = raws[s["character"]].get((s["animation"], d), [])
            if len(ps) < s["frames"]:
                print(f"  {key}: SKIPPED, not found on PixelLab"); skipped += 1; continue
            game = np.asarray(Image.open(os.path.join(ROOT, "assets", "sprites", key.split("/")[0],
                                                      key.split("/")[1] + ".png")).convert("RGBA"))
            hit = None
            for cl in (False, True):
                if np.array_equal(np.asarray(build_strip(ps, s["size"], s["frames"], cl)), game):
                    hit = cl
                    break
            if hit is not None:
                s["mode"], s["hash"] = "direct", frame_hash(ps[:s["frames"]])
                if hit:
                    s.pop("clean", None)
                else:
                    s["clean"] = False
                same += 1
                continue
            if len(targets[(s["character"], s["animation"], d)]) > 1:
                print(f"  {key}: SKIPPED, PixelLab {s['animation']}/{d} also feeds "
                      + ", ".join(x for x in targets[(s["character"], s["animation"], d)] if x != key)); skipped += 1; continue
            if an == "rot":
                target = f"character:{s['character']}:{d}"
            else:
                g = groups.get((s["character"], s["animation"], d), [])
                if len(g) != 1:
                    print(f"  {key}: SKIPPED, {len(g)} PixelLab animations named {s['animation']} ({d})"); skipped += 1; continue
                target = f"character:{s['character']}:{d}:{g[0]}"
            raw = [Image.open(p).convert("RGBA") for p in ps]
            w, h = raw[0].size
            frames = [unfit(f, w, h) for f in game_frames(key, s)] + raw[s["frames"]:]
            if args.dry:
                print(f"  {key}: would push {len(frames)} frames {w}x{h} -> {target}"); pushed += 1; continue
            r = pl._req("POST", "/save-to-asset", {"target": target, "frames": [b64png(f) for f in frames]}
                        if an != "rot" else {"target": target, "image": b64png(frames[0])})
            bdir = os.path.join(BACKUP, stamp, key.replace("/", "__"))
            os.makedirs(bdir, exist_ok=True)
            prev = r.get("previous_frames") or []
            for i, fr in enumerate(prev):
                b = fr.get("base64") if isinstance(fr, dict) else fr
                if b:
                    open(os.path.join(bdir, f"{i}.png"), "wb").write(base64.b64decode(b.split(",")[-1]))
            json.dump({"target": target, "response": {k: v for k, v in r.items() if k != "previous_frames"}},
                      open(os.path.join(bdir, "target.json"), "w"))
            s["pushed"] = stamp
            pushed += 1
            print(f"  {key}: pushed -> {target} (backup {len(prev)} frames)")
    if not args.dry:
        save_map(m)
    print(f"{pushed} pushed, {same} already identical, {skipped} skipped" + (" (dry run)" if args.dry else ""))
    if pushed and not args.dry and not args.no_verify:
        print("Verifying: fetching PixelLab again ...")
        args.keys = [k for k in keys if m["strips"][k].get("pushed") == stamp]
        args.only = None
        args.no_verify = True
        cmd_push(args)


def cmd_list(args):
    m = load_map()
    write_doc(m)
    print(open(DOC).read())


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", nargs="?", default="check", choices=["check", "pull", "push", "list", "map"])
    ap.add_argument("raw", nargs="?", help="map only: folder with chars.json and one fetch_character() folder per id")
    ap.add_argument("--only", nargs="*", help="sprite ids to limit to")
    ap.add_argument("--force", action="store_true", help="pull: also replace strips marked processed")
    ap.add_argument("--keys", nargs="*", help="push: only these strip keys (sprite/anim_dir)")
    ap.add_argument("--dry", action="store_true", help="push: list what would be written, write nothing")
    ap.add_argument("--no-verify", action="store_true", help=argparse.SUPPRESS)
    args = ap.parse_args()
    if args.cmd == "map":
        cmd_map(args)
    elif args.cmd == "push":
        cmd_push(args)
    elif args.cmd == "list":
        cmd_list(args)
    else:
        cmd_check(args, pull=args.cmd == "pull")


if __name__ == "__main__":
    main()
