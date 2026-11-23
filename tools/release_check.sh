#!/usr/bin/env bash
# Release check (issue #118): fails while the game would ship anything unfinished.
#   - data/placeholders.json must be empty: every stand-in (recoloured art, borrowed music, missing CGs) has been
#     replaced by its final file (tools/make_placeholders.py, the "Chapter 2 art swap" issue).
# Add new checks here as the release candidate list in #118 grows. CI runs this on every v* tag
# (.github/workflows/desktop.yml): it blocks 1.0 and later, and only warns on 0.x playtest builds.
# Usage: tools/release_check.sh
set -uo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import json, sys
left = json.load(open("data/placeholders.json"))["placeholders"]
if left:
    print("Release check FAILED: %d placeholder(s) still in data/placeholders.json:" % len(left))
    for e in left:
        print("  %-28s %-9s %s  (for: %s)" % (e["id"], e["kind"], e["path"], e.get("for", "")))
    sys.exit(1)
print("Release check passed: no placeholders left.")
PY
