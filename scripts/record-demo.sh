#!/bin/bash
# Records the top of the main display (the menu bar) and converts it to docs/demo.gif.
#
# Usage: scripts/record-demo.sh [seconds] [width]
#   seconds  recording length (default 12)
#   width    capture width in points, counted from the right edge of the display (default 700)
#
# Start Hanare first, then do this during the recording: hover over the archer (会), click it (離れ),
# wait for the icons to hide again. Needs Screen Recording permission for the terminal and ffmpeg.
set -euo pipefail

cd "$(dirname "$0")/.."
SECONDS_TO_RECORD="${1:-12}"
WIDTH="${2:-700}"
OUT="docs/demo.gif"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SCREEN_WIDTH="$(osascript -e 'tell application "Finder" to get item 3 of (get bounds of window of desktop)')"
X=$((SCREEN_WIDTH - WIDTH))
HEIGHT=40

echo "Recording in 3 seconds..."
sleep 3
screencapture -v -V "$SECONDS_TO_RECORD" -R "$X,0,$WIDTH,$HEIGHT" "$TMP/demo.mov"

ffmpeg -loglevel error -y -i "$TMP/demo.mov" \
  -vf "fps=15,scale=${WIDTH}:-1:flags=lanczos,palettegen=stats_mode=diff" "$TMP/palette.png"
ffmpeg -loglevel error -y -i "$TMP/demo.mov" -i "$TMP/palette.png" \
  -lavfi "fps=15,scale=${WIDTH}:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=5" "$OUT"
echo "Wrote $OUT ($(du -h "$OUT" | cut -f1))"
