#!/bin/bash
# Records the top of the main display (the menu bar) and converts it to docs/demo.gif.
#
# Usage: scripts/record-demo.sh [seconds] [width] [right-margin] [display] [height]
#   seconds       recording length (default 15)
#   width         capture width in points (default 500)
#   right-margin  points left out at the right edge, to keep the clock and system icons
#                 out of the GIF (default 253)
#   display       1 for the main display, 2 for the next one, and so on (default 1).
#                 The displays are listed when this is run.
#   height        capture height in points from the top of the display (default 30)
#
# Start Hanare first, then do this during the recording: hover over the archer (会), click it (離れ),
# wait for the icons to hide again. Needs Screen Recording permission for the terminal and ffmpeg.
set -euo pipefail

cd "$(dirname "$0")/.."
SECONDS_TO_RECORD="${1:-15}"
WIDTH="${2:-500}"
RIGHT_MARGIN="${3:-253}"
DISPLAY_INDEX="${4:-1}"
HEIGHT="${5:-30}"
OUT="docs/demo.gif"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Each line: index, left edge, top edge, width of a display, in the global point coordinates
# that screencapture -R uses (origin at the top left of the main display).
DISPLAYS="$(osascript -l JavaScript -e '
ObjC.import("AppKit");
const screens = $.NSScreen.screens;
const mainHeight = screens.objectAtIndex(0).frame.size.height;
const lines = [];
for (let i = 0; i < screens.count; i++) {
  const f = screens.objectAtIndex(i).frame;
  lines.push([i + 1, f.origin.x, mainHeight - (f.origin.y + f.size.height), f.size.width].join(" "));
}
lines.join("\n");
')"
echo "Displays (index left top width):"
echo "$DISPLAYS"

read -r _ LEFT TOP SCREEN_WIDTH < <(echo "$DISPLAYS" | awk -v n="$DISPLAY_INDEX" '$1 == n')
if [ -z "${SCREEN_WIDTH:-}" ]; then
    echo "Display $DISPLAY_INDEX not found" >&2
    exit 1
fi
X=$((LEFT + ${SCREEN_WIDTH%.*} - RIGHT_MARGIN - WIDTH))
Y=${TOP%.*}

for count in 3 2 1; do
    printf '\rRecording in %s... ' "$count"
    sleep 1
done
printf '\rRecording now (%s seconds)\n' "$SECONDS_TO_RECORD"
screencapture -v -V "$SECONDS_TO_RECORD" -R "$X,$Y,$WIDTH,$HEIGHT" "$TMP/demo.mov"

ffmpeg -loglevel error -y -i "$TMP/demo.mov" \
  -vf "fps=15,scale=${WIDTH}:-1:flags=lanczos,palettegen=stats_mode=diff" "$TMP/palette.png"
ffmpeg -loglevel error -y -i "$TMP/demo.mov" -i "$TMP/palette.png" \
  -lavfi "fps=15,scale=${WIDTH}:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=5" "$OUT"
echo "Wrote $OUT ($(du -h "$OUT" | cut -f1))"
