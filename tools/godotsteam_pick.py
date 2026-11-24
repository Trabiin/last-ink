"""Picks a GodotSteam GDExtension download for tools/fetch_godotsteam.sh (issue #150).

Goes through GitHub releases newest first (or just the pinned one), downloads each release's
GDExtension zip ("...gdextension...zip" by GodotSteam's naming) and keeps the first whose
.gdextension file says it loads in our Godot (compatibility_minimum <= ours). Newer GodotSteam
releases can need a newer Godot than the game uses.

Usage: python3 tools/godotsteam_pick.py <releases.json> <out.zip> <godot version>
Prints "<tag> <url> <file name>" and leaves the zip at <out.zip>; exits 1 when none fits.
"""
import json
import re
import sys
import urllib.request
import zipfile

MAX_TRIES = 25


def ver(s):
    return tuple(int(x) for x in re.findall(r"\d+", s)[:3])


def main(releases_path, out, godot):
    tried = []
    for rel in json.load(open(releases_path)):
        if rel.get("draft") or rel.get("prerelease"):
            continue
        for a in rel.get("assets", []):
            n = a["name"].lower()
            if not (("gdextension" in n or "gde" in n.replace("godot", "")) and n.endswith(".zip") and "example" not in n):
                continue
            urllib.request.urlretrieve(a["browser_download_url"], out)
            with zipfile.ZipFile(out) as z:
                ext = [f for f in z.namelist() if f.endswith(".gdextension")]
                text = z.read(ext[0]).decode("utf-8", "replace") if ext else ""
            m = re.search(r'compatibility_minimum\s*=\s*"?([0-9.]+)', text)
            need = m.group(1) if m else "0"
            if ext and ver(need) <= ver(godot):
                print(rel["tag_name"], a["browser_download_url"], a["name"])
                return 0
            tried.append("%s (%s, needs Godot %s)" % (rel["tag_name"], a["name"], need))
            break
        if len(tried) >= MAX_TRIES:
            break
    sys.stderr.write("releases seen:\n")
    for rel in json.load(open(releases_path)):
        sys.stderr.write("  %s%s: %s\n" % (rel.get("tag_name"), " (pre)" if rel.get("prerelease") else "",
                                           ", ".join(a["name"] for a in rel.get("assets", []))[:160] or "(no files)"))
    sys.stderr.write("no GodotSteam GDExtension release loads in Godot %s; tried: %s\n" % (godot, ", ".join(tried) or "none"))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3]))
