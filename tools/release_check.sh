#!/usr/bin/env bash
# Release check (issue #118): fails while the game would ship anything unfinished.
#   - data/placeholders.json must be empty: every stand-in (recoloured art, borrowed music, missing CGs) has been
#     replaced by its final file (tools/make_placeholders.py, issue #205).
#   - data/feedback.json must have an https endpoint, so players can send bug reports from the game
#     (report inbox, issue #175, docs/FEEDBACK.md).
# Add new checks here as the release candidate list in #118 grows. CI runs this on every v* tag
# (.github/workflows/desktop.yml): it blocks 1.0 and later, and only warns on 0.x playtest builds.
# Usage: tools/release_check.sh
set -uo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import json, sys
failed = False
left = json.load(open("data/placeholders.json"))["placeholders"]
if left:
    failed = True
    print("Release check FAILED: %d placeholder(s) still in data/placeholders.json:" % len(left))
    for e in left:
        print("  %-28s %-9s %s  (for: %s)" % (e["id"], e["kind"], e["path"], e.get("for", "")))
endpoint = json.load(open("data/feedback.json")).get("endpoint", "")
if not endpoint.startswith("https://"):
    failed = True
    print("Release check FAILED: no report inbox in data/feedback.json (endpoint %r), so players can only save"
          " bug reports to a file. Deploy it as in docs/FEEDBACK.md \"One-time setup\" (issue #175)." % endpoint)
if failed:
    sys.exit(1)
print("Release check passed: no placeholders left, report inbox set.")
PY
