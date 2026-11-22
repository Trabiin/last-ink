#!/usr/bin/env bash
# Turns recorded shots (tools/capture.sh) into store and social clips with ffmpeg (issue #152).
#
#   tools/clips.sh gif      <in.mp4> [out.gif]  [--from S] [--len S] [--max 3M] [--width 640] [--fps 20] [--crop F]
#       Store-page GIF under a size cap (Steam description images: keep under 3 MB). Pixel art gets
#       nearest-neighbour scaling and an undithered 64-colour palette, so edges stay hard. If the GIF
#       is over the cap it steps down width, then frame rate, until it fits. --crop 0.6 keeps the
#       middle 60% of the frame (closer on the action, fewer bytes). GIFs compress what stays still:
#       shots with a held camera (like gif_*.json) fit in far more seconds than moving ones.
#   tools/clips.sh webm     <in.mp4> [out.webm] [--from S] [--len S] [--max 3M] [--width 1280] [--crop F]
#       VP9 WebM under a size cap (two-pass, bitrate worked out from the cap). Silent.
#   tools/clips.sh vertical <in.mp4> [out.mp4]  [--from S] [--len 15] [--fit] [--x 0.5]
#       9:16 1080x1920 for social posts. Default crops a column out of the middle (--x 0..1 moves it);
#       --fit shows the whole frame over a blurred, darkened copy of itself.
#   tools/clips.sh reel     <out.mp4> <a.mp4> <b.mp4> ... [--fade 0.25]
#       Joins shots end to end. Hard cuts, or a dip through black of --fade seconds at each join.
#   tools/clips.sh captions <in.mp4> <subs.srt> [out.mp4]
#       Burns captions in (muted autoplay on store pages and social), in the game's font.
#   tools/clips.sh still    <in.mp4> <time S> [out.png]
#       One frame as a PNG (store screenshots from a shot).
#
# Outputs default to build/captures/ next to the input, named after it.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v ffmpeg >/dev/null || { echo "ffmpeg is needed (apt install ffmpeg / brew install ffmpeg)"; exit 1; }
CMD="${1:-}"
[ -n "$CMD" ] && shift || { sed -n '2,24p' "$0"; exit 1; }

FROM=0
LEN=""
MAX="3M"
WIDTH=""
FPS=""
CROP=1
COLORS=64
FIT=0
XPOS=0.5
FADE=0
POS=()
while [ $# -gt 0 ]; do
	case "$1" in
		--from) FROM="$2"; shift ;;
		--len) LEN="$2"; shift ;;
		--max) MAX="$2"; shift ;;
		--width) WIDTH="$2"; shift ;;
		--fps) FPS="$2"; shift ;;
		--crop) CROP="$2"; shift ;;
		--colors) COLORS="$2"; shift ;;
		--fit) FIT=1 ;;
		--x) XPOS="$2"; shift ;;
		--fade) FADE="$2"; shift ;;
		*) POS+=("$1") ;;
	esac
	shift
done

bytes() {  # 3M -> 3000000 (store limits are decimal megabytes)
	local v="$1"
	case "$v" in
		*M|*m) awk "BEGIN{printf \"%d\", ${v%?} * 1000000}" ;;
		*K|*k) awk "BEGIN{printf \"%d\", ${v%?} * 1000}" ;;
		*) echo "$v" ;;
	esac
}
size_of() { wc -c <"$1" | tr -d ' '; }
duration_of() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }
trim_args() {  # -ss/-t for --from/--len
	local a=(-ss "$FROM")
	[ -n "$LEN" ] && a+=(-t "$LEN")
	echo "${a[@]}"
}
crop_vf() {  # the middle CROP fraction of the frame, as a filter (nothing when 1)
	awk "BEGIN{exit !($CROP < 1)}" && echo "crop=iw*$CROP:ih*$CROP," || true
}
out_for() {  # default output path: next to the input, new suffix
	local in="$1" suffix="$2"
	echo "${in%.*}$suffix"
}

case "$CMD" in
gif)
	IN="${POS[0]:?input mp4}"
	OUTF="${POS[1]:-$(out_for "$IN" .gif)}"
	CAP=$(bytes "$MAX")
	W="${WIDTH:-640}"
	F="${FPS:-20}"
	PAL=$(mktemp --suffix=.png 2>/dev/null || mktemp -t pal).png
	while :; do
		# Nearest-neighbour keeps pixel edges; one palette for the whole clip so colours don't flicker.
		VF="$(crop_vf)fps=$F,scale=$W:-2:flags=neighbor"
		ffmpeg -loglevel error -y $(trim_args) -i "$IN" -vf "$VF,palettegen=max_colors=$COLORS:stats_mode=diff" "$PAL"
		ffmpeg -loglevel error -y $(trim_args) -i "$IN" -i "$PAL" -lavfi "$VF[x];[x][1:v]paletteuse=dither=none:diff_mode=rectangle" -loop 0 "$OUTF"
		S=$(size_of "$OUTF")
		echo "  $W px wide, $F fps: $((S / 1000)) KB"
		[ "$S" -le "$CAP" ] && break
		if [ "$W" -gt 480 ]; then
			W=$((W * 3 / 4 / 2 * 2))
		elif [ "$F" -gt 12 ]; then
			F=$((F * 3 / 4))
		else
			echo "Still over $MAX at $W px / $F fps: shorten it with --len."
			rm -f "$PAL"
			exit 1
		fi
	done
	rm -f "$PAL"
	echo "Wrote $OUTF"
	;;
webm)
	IN="${POS[0]:?input mp4}"
	OUTF="${POS[1]:-$(out_for "$IN" .webm)}"
	CAP=$(bytes "$MAX")
	W="${WIDTH:-1280}"
	D="${LEN:-$(awk "BEGIN{print $(duration_of "$IN") - $FROM}")}"
	# 92% of the cap for video bits, the rest is container overhead.
	KBPS=$(awk "BEGIN{printf \"%d\", $CAP * 8 * 0.92 / $D / 1000}")
	LOGP=$(mktemp -u)
	for pass in 1 2; do
		dest="$OUTF"; [ $pass = 1 ] && dest=/dev/null
		ffmpeg -loglevel error -y $(trim_args) -i "$IN" -vf "$(crop_vf)scale=$W:-2:flags=neighbor" -an \
			-c:v libvpx-vp9 -b:v "${KBPS}k" -row-mt 1 -deadline good -cpu-used 2 -pass $pass -passlogfile "$LOGP" \
			-f webm "$dest"
	done
	rm -f "$LOGP"*
	echo "Wrote $OUTF ($(( $(size_of "$OUTF") / 1000 )) KB, ${KBPS} kbit/s)"
	;;
vertical)
	IN="${POS[0]:?input mp4}"
	OUTF="${POS[1]:-$(out_for "$IN" _vertical.mp4)}"
	LEN="${LEN:-15}"
	if [ $FIT = 1 ]; then
		VF="split[a][b];[a]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=24:2,eq=brightness=-0.18[bg];[b]scale=1080:-2:flags=lanczos[fg];[bg][fg]overlay=(W-w)/2:(H-h)/2"
	else
		# A 9:16 column of the frame, scaled up: crop width = height * 9/16.
		VF="crop=ih*9/16:ih:(iw-ih*9/16)*$XPOS:0,scale=1080:1920:flags=neighbor"
	fi
	ffmpeg -loglevel error -y $(trim_args) -i "$IN" -vf "$VF" -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p \
		-c:a aac -b:a 160k -movflags +faststart "$OUTF"
	echo "Wrote $OUTF"
	;;
reel)
	OUTF="${POS[0]:?output mp4}"
	INS=("${POS[@]:1}")
	[ ${#INS[@]} -ge 1 ] || { echo "Give the shots to join"; exit 1; }
	ARGS=()
	FC=""
	for i in "${!INS[@]}"; do
		ARGS+=(-i "${INS[$i]}")
		if awk "BEGIN{exit !($FADE > 0)}"; then
			D=$(duration_of "${INS[$i]}")
			ST=$(awk "BEGIN{print $D - $FADE}")
			FC+="[$i:v]fade=t=in:d=$FADE,fade=t=out:st=$ST:d=$FADE,setsar=1,fps=60[v$i];"
		else
			FC+="[$i:v]setsar=1,fps=60[v$i];"
		fi
	done
	for i in "${!INS[@]}"; do FC+="[v$i]"; done
	FC+="concat=n=${#INS[@]}:v=1:a=0[out]"
	ffmpeg -loglevel error -y "${ARGS[@]}" -filter_complex "$FC" -map "[out]" -c:v libx264 -preset slow -crf 12 \
		-pix_fmt yuv420p -tune animation -movflags +faststart "$OUTF"
	echo "Wrote $OUTF"
	;;
captions)
	IN="${POS[0]:?input mp4}"
	SRT="${POS[1]:?subtitles .srt}"
	OUTF="${POS[2]:-$(out_for "$IN" _captioned.mp4)}"
	FONTS="$(pwd)/assets/fonts"
	STYLE="FontName=Jersey 10,FontSize=26,PrimaryColour=&H00F0EEE8,OutlineColour=&H00201A16,BorderStyle=1,Outline=2,Shadow=0,MarginV=36"
	ffmpeg -loglevel error -y -i "$IN" -vf "subtitles=$SRT:fontsdir=$FONTS:force_style='$STYLE'" \
		-c:v libx264 -preset slow -crf 14 -pix_fmt yuv420p -c:a copy -movflags +faststart "$OUTF"
	echo "Wrote $OUTF"
	;;
still)
	IN="${POS[0]:?input mp4}"
	AT="${POS[1]:?time in seconds}"
	OUTF="${POS[2]:-$(out_for "$IN" "_$AT.png")}"
	ffmpeg -loglevel error -y -ss "$AT" -i "$IN" -frames:v 1 "$OUTF"
	echo "Wrote $OUTF"
	;;
*)
	sed -n '2,24p' "$0"
	exit 1
	;;
esac
