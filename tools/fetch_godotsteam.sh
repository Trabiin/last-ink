#!/usr/bin/env bash
# Puts GodotSteam (the GDExtension build, which works with the stock Godot editor and export
# templates) into addons/godotsteam for a Steam build (issue #150, docs/STEAM.md). Only Steam builds
# have it: web, itch.io and plain desktop builds don't, and the game runs the same without it
# (scripts/steam_link.gd). The folder is git-ignored; CI fetches it in .github/workflows/steam.yml.
#
# Usage: tools/fetch_godotsteam.sh
#   GODOTSTEAM_TAG     release tag on github.com/GodotSteam/GodotSteam to use (unpinned runs also look on
#                      codeberg.org/godotsteam/godotsteam). Empty: the newest
#                      release whose GDExtension download loads in our Godot (the tag and checksum
#                      are printed, so they can be pinned).
#   GODOTSTEAM_SHA256  checksum the download must have (recommended once pinned).
#   GODOT_VERSION      our Godot version (default 4.3): newer GodotSteam releases may need a newer one.
#   GITHUB_TOKEN       optional, for the GitHub API's rate limit in CI.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="GodotSteam/GodotSteam"
API="https://api.github.com/repos/$REPO/releases"
TAG="${GODOTSTEAM_TAG:-}"
WANT_SHA="${GODOTSTEAM_SHA256:-}"
AUTH=()
[ -n "${GITHUB_TOKEN:-}" ] && AUTH=(-H "Authorization: Bearer $GITHUB_TOKEN")
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ -n "$TAG" ]; then
	curl -fsSL ${AUTH[@]+"${AUTH[@]}"} "$API/tags/$TAG" -o "$TMP/release.json"
	echo "[$(cat "$TMP/release.json")]" > "$TMP/releases.json"
else
	# GodotSteam publishes module builds and GDExtension builds side by side; look well back.
	for page in 1 2 3; do
		curl -fsSL ${AUTH[@]+"${AUTH[@]}"} "$API?per_page=100&page=$page" -o "$TMP/page$page.json"
	done
	# Since 2025 GodotSteam's main home is Codeberg (same release format, Forgejo API); GitHub keeps
	# mostly the module builds. Codeberg's releases go first.
	for page in 1 2 3; do
		curl -fsSL "https://codeberg.org/api/v1/repos/godotsteam/godotsteam/releases?limit=50&page=$page" -o "$TMP/cb$page.json" || echo "[]" > "$TMP/cb$page.json"
	done
	python3 -c 'import json,sys; print(json.dumps(sum((json.load(open(f)) for f in sys.argv[1:]), [])))' "$TMP"/cb*.json "$TMP"/page*.json > "$TMP/releases.json"
	# Diagnostics: the organisation's repositories (GDExtension builds may live in their own one).
	curl -fsSL ${AUTH[@]+"${AUTH[@]}"} "https://api.github.com/orgs/GodotSteam/repos?per_page=100" 2>/dev/null \
		| python3 -c 'import json,sys; print("GodotSteam repositories:", ", ".join(r["name"] for r in json.load(sys.stdin)))' || true
fi

# Picks the newest release (or the pinned one) whose GDExtension zip loads in our Godot and leaves it
# at $TMP/gs.zip. Prints "<tag> <url> <file name>".
PICKED="$(python3 tools/godotsteam_pick.py "$TMP/releases.json" "$TMP/gs.zip" "${GODOT_VERSION:-4.3}")"
read -r TAG URL NAME <<< "$PICKED"
[ -n "${URL:-}" ] || { echo "could not pick a GodotSteam download" >&2; exit 1; }
echo "GodotSteam: $NAME from release $TAG"
SHA="$(sha256sum "$TMP/gs.zip" | cut -d' ' -f1)"
echo "GodotSteam: sha256 $SHA"
if [ -n "$WANT_SHA" ] && [ "$SHA" != "$WANT_SHA" ]; then
	echo "GodotSteam download does not match GODOTSTEAM_SHA256 ($WANT_SHA)" >&2
	exit 1
fi
unzip -q "$TMP/gs.zip" -d "$TMP/x"
GDEXT="$(find "$TMP/x" -name 'godotsteam.gdextension' | head -n1)"
if [ -z "$GDEXT" ]; then
	GDEXT="$(find "$TMP/x" -name '*.gdextension' | head -n1)"
fi
[ -n "$GDEXT" ] || { echo "no .gdextension file in $NAME" >&2; exit 1; }
SRC="$(dirname "$GDEXT")"
rm -rf addons/godotsteam
mkdir -p addons
cp -R "$SRC" addons/godotsteam
# The .gdextension points at its libraries with res://addons/<folder>/...; keep that path right.
if ! grep -q 'res://addons/godotsteam/' addons/godotsteam/*.gdextension; then
	echo "warning: $(basename "$GDEXT") does not use res://addons/godotsteam/ paths:" >&2
	grep -n 'res://' addons/godotsteam/*.gdextension >&2 || true
fi
# Its licence travels with the Steam build (THIRD_PARTY_LICENSES.md section 4).
LIC="$(find "$TMP/x" -maxdepth 3 -iname 'license*' -type f | head -n1)"
if [ -n "$LIC" ]; then
	cp "$LIC" addons/godotsteam/GODOTSTEAM_LICENSE.txt
else
	echo "warning: no licence file in $NAME; add GodotSteam's MIT licence to the Steam build by hand" >&2
fi
echo "GodotSteam: installed into addons/godotsteam"
cat addons/godotsteam/*.gdextension
# In CI: an annotation and the job summary carry the values to pin (the full log is long).
if [ -n "${GITHUB_ACTIONS:-}" ]; then
	echo "::notice title=GodotSteam::$NAME from release $TAG, sha256 $SHA"
	printf '### GodotSteam\n\n- file: `%s`\n- release: `%s`\n- sha256: `%s`\n' "$NAME" "$TAG" "$SHA" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
fi
echo "tag=$TAG" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "sha256=$SHA" >> "${GITHUB_OUTPUT:-/dev/null}"
