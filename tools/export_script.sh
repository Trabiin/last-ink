#!/usr/bin/env bash
# Writes the whole game script, one readable Markdown file per chapter, for proofreading (issue #142).
# Usage: tools/export_script.sh [out dir]   (default build/script)   GODOT=/path/to/godot to pick the binary.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || echo "$HOME/godot/godot")}"
timeout 600 "$GODOT" --headless --import >/dev/null 2>&1 || true
timeout 300 "$GODOT" --headless --audio-driver Dummy --path . -s tools/export_script.gd -- "${1:-res://build/script}"
