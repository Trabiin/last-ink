#!/usr/bin/env python3
"""Keeps the game's icons, props and buildings in the PixelLab Creator gallery identical to the game files.

    python3 tools/pixellab_gallery.py          # check: which files are new or changed since the last push
    python3 tools/pixellab_gallery.py push     # add new files to the gallery, replace changed ones (free)

Each file gets its own gallery image named "Last Ink | <set> | <name>" (type "Last Ink" in the gallery search to
see them all, or "Last Ink | icon" for one set). tools/pixellab_gallery.json maps file -> gallery id + hash of what was
pushed, so a later push replaces the same gallery image (POST /save-to-asset gallery:<id>, which returns the old
pixels; backups go to BACKUP when given). Chapter 2 placeholders are skipped (data/placeholders.json).
The PixelLab API has no folders: the name prefix is how the set stays findable.

Rule: after any repo change to an icon, prop or building PNG, run `push`, the same as pixellab_sync.py for sprites.
"""
import base64
import hashlib
import json
import os
import sys

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from prop_icon_audit import collect  # noqa: E402

MAP = os.path.join(HERE, "pixellab_gallery.json")
API = "https://api.pixellab.ai/v2/save-to-asset"
SET_LABEL = {"icons": "icon", "props": "prop", "buildings": "building"}
CA = "/root/.ccr/ca-bundle.crt"


def load():
    return json.load(open(MAP)) if os.path.exists(MAP) else {"items": {}}


def save(m):
    m["items"] = dict(sorted(m["items"].items()))
    json.dump(m, open(MAP, "w"), indent=1)
    open(MAP, "a").write("\n")


def files():
    out = []
    for s, items in collect().items():
        for n, p in items:
            out.append((s, n, os.path.relpath(p, ROOT)))
    return out


def sha(path):
    return hashlib.sha1(open(os.path.join(ROOT, path), "rb").read()).hexdigest()[:16]


def post(body):
    token = os.environ.get("PIXELLAB_API_KEY", "proxy")
    kw = {"verify": CA} if os.path.exists(CA) else {}
    r = requests.post(API, headers={"Authorization": "Bearer " + token}, json=body, timeout=60, **kw)
    r.raise_for_status()
    return r.json()


def main(argv):
    m = load()
    todo = []
    for s, n, path in files():
        cur = m["items"].get(path)
        h = sha(path)
        if not cur:
            todo.append(("new", s, n, path, h))
        elif cur["hash"] != h:
            todo.append(("changed", s, n, path, h))
    for kind, s, n, path, _ in todo:
        print("%-8s %s" % (kind, path))
    print("%d to push" % len(todo))
    if not argv or argv[0] != "push":
        return 0
    backup = argv[argv.index("--backup") + 1] if "--backup" in argv else None
    for kind, s, n, path, h in todo:
        img = base64.b64encode(open(os.path.join(ROOT, path), "rb").read()).decode()
        if kind == "new":
            r = post({"target": "gallery:new", "image": {"base64": img},
                      "name": "Last Ink | %s | %s" % (SET_LABEL[s], n),
                      "description": "Last Ink game file %s (the in-game version)" % path})
        else:
            r = post({"target": "gallery:" + m["items"][path]["gallery"], "image": {"base64": img}})
            if backup and r.get("previous_frames"):
                os.makedirs(backup, exist_ok=True)
                open(os.path.join(backup, n + ".png"), "wb").write(base64.b64decode(r["previous_frames"][0]))
        gid = r["target"].split(":", 1)[1]
        m["items"][path] = {"gallery": gid, "hash": h}
        save(m)
        print("%-8s %s -> %s (%s)" % (r["action"], path, gid, r.get("usage")))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
