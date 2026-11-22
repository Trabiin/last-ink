#!/usr/bin/env bash
# Records a trailer shot (issue #152): tools/capture/shots/<name>.json played by tools/capture.gd,
# recorded frame by frame with Godot's movie maker at a fixed 60 fps, trimmed to the shot and
# encoded to a near-lossless MP4. Nothing here ships: tools/* is left out of every export.
#
# Usage: tools/capture.sh <shot> [--4k | --720p | --preview] [--keep-frames] [--audio] [key=value ...]
#   <shot>          a name in tools/capture/shots/ (or "all" for every shot)
#   --4k            3840x2160 (6x the 640x360 layout grid); default 1920x1080 (3x)
#   --720p          1280x720 (2x), quick and still pixel-exact
#   --preview       960x540, fastest, for blocking out a camera path (not pixel-exact)
#   --keep-frames   keep the PNG frames next to the MP4 (for an editor that wants an image sequence)
#   --audio         keep the game's own sound in the MP4 (off by default: trailers get their music in the edit)
#   key=value       passed to the shot, e.g. day=0.9 seed=3 seconds=4 party=ash,odile,velvette
#
# Output: build/captures/<shot>.mp4 (OUT=dir to change), plus <shot>.log with the beat timings.
# Then tools/clips.sh turns MP4s into store GIFs, WebMs and the vertical social cut.
#
# Needs Godot 4.3 (GODOT=path, default godot then ~/godot/godot), ffmpeg, and a display: on a machine
# without one, xvfb-run is used automatically. Rendering is slower than real time without a GPU.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || echo "$HOME/godot/godot")}"
OUT="${OUT:-build/captures}"
RES="1920x1080"
KEEP=0
AUDIO=0
SHOT=""
PASS=()
for a in "$@"; do
	case "$a" in
		--4k) RES="3840x2160" ;;
		--720p) RES="1280x720" ;;
		--preview) RES="960x540" ;;
		--keep-frames) KEEP=1 ;;
		--audio) AUDIO=1 ;;
		-h|--help) sed -n '2,20p' "$0"; exit 0 ;;
		*=*) PASS+=("$a") ;;
		*) SHOT="$a" ;;
	esac
done
if [ -z "$SHOT" ]; then
	sed -n '2,20p' "$0"
	exit 1
fi
if [ "$SHOT" = "all" ]; then
	for f in tools/capture/shots/*.json; do
		args=("$(basename "$f" .json)")
		[ "$RES" = "3840x2160" ] && args+=(--4k)
		[ "$RES" = "1280x720" ] && args+=(--720p)
		[ "$RES" = "960x540" ] && args+=(--preview)
		[ $KEEP = 1 ] && args+=(--keep-frames)
		[ $AUDIO = 1 ] && args+=(--audio)
		"$0" "${args[@]}" ${PASS[@]+"${PASS[@]}"}
	done
	exit 0
fi
[ -f "tools/capture/shots/$SHOT.json" ] || { echo "No shot tools/capture/shots/$SHOT.json"; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg is needed (apt install ffmpeg / brew install ffmpeg)"; exit 1; }

mkdir -p "$OUT"
FRAMES="$OUT/$SHOT.frames"
rm -rf "$FRAMES"
mkdir -p "$FRAMES"
LOG="$OUT/$SHOT.log"
W="${RES%x*}"
H="${RES#*x}"

RUN=("$GODOT" --path . --resolution "$RES" --fixed-fps 60 --write-movie "$FRAMES/f.png" -s tools/capture.gd -- "shot=$SHOT" ${PASS[@]+"${PASS[@]}"})
[ $AUDIO = 1 ] || RUN=("${RUN[0]}" --audio-driver Dummy "${RUN[@]:1}")
if [ -z "${DISPLAY:-}" ] && [ "$(uname)" = "Linux" ]; then
	RUN=(xvfb-run -a -s "-screen 0 ${W}x${H}x24" "${RUN[@]}")
fi
echo "Recording $SHOT at $RES (slower than real time without a GPU)..."
"${RUN[@]}" >"$LOG" 2>&1 || true

START=$(sed -n 's/^CAPTURE_START frame=\([0-9]*\).*/\1/p' "$LOG" | head -1)
END=$(sed -n 's/^CAPTURE_END frame=\([0-9]*\).*/\1/p' "$LOG" | head -1)
if [ -z "$START" ] || [ -z "$END" ]; then
	echo "The shot did not finish; see $LOG"
	grep -E "SCRIPT ERROR|^ERROR|capture:" "$LOG" | grep -v f_wav | head -20 || true
	exit 1
fi
# Movie frame files count from 0; the script's frame counter from 1.
FIRST=$((START - 1))
COUNT=$((END - START))
SS=$(awk "BEGIN{printf \"%.4f\", $FIRST/60}")
DUR=$(awk "BEGIN{printf \"%.4f\", $COUNT/60}")

ENC=(ffmpeg -loglevel error -y -framerate 60 -start_number "$FIRST" -i "$FRAMES/f%08d.png")
if [ $AUDIO = 1 ] && [ -s "$FRAMES/f.wav" ]; then
	ENC+=(-ss "$SS" -t "$DUR" -i "$FRAMES/f.wav" -c:a aac -b:a 192k)
fi
# The frames are already the target size with hard pixel edges: no scaling, high quality, and
# yuv420p so every player and store page takes it.
ENC+=(-frames:v "$COUNT" -c:v libx264 -preset slow -crf 12 -pix_fmt yuv420p -tune animation -movflags +faststart "$OUT/$SHOT.mp4")
"${ENC[@]}"

if [ $KEEP = 1 ]; then
	# Keep only the shot's frames, renumbered from 0.
	mkdir -p "$OUT/$SHOT.png"
	for ((i = 0; i < COUNT; i++)); do
		mv "$FRAMES/$(printf 'f%08d.png' $((FIRST + i)))" "$OUT/$SHOT.png/$(printf '%05d.png' "$i")"
	done
fi
rm -rf "$FRAMES"
grep "^CAPTURE_BEAT" "$LOG" | sed 's/^CAPTURE_BEAT /  /' || true
echo "Wrote $OUT/$SHOT.mp4 ($COUNT frames, $(awk "BEGIN{printf \"%.1f\", $COUNT/60}") s at $RES)"
