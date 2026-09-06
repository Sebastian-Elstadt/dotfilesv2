#!/usr/bin/env bash
# Skemos — screenshots. Boring tools: grim + slurp + wl-clipboard.
# Saves a PNG to ~/Pictures/Screenshots AND copies it to the clipboard.
#
#   screenshot.sh region   select a rectangle
#   screenshot.sh window    current window (via hyprctl geometry)
#   screenshot.sh output    whole focused monitor

set -euo pipefail

DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
mkdir -p "$DIR"
FILE="$DIR/$(date +%Y%m%d-%H%M%S).png"

mode="${1:-region}"
case "$mode" in
  region)
    geom="$(slurp -b 16151380 -c 6a8494ff -w 1 2>/dev/null)" || exit 0
    grim -g "$geom" "$FILE"
    ;;
  window)
    geom="$(hyprctl -j activewindow | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')"
    grim -g "$geom" "$FILE"
    ;;
  output)
    out="$(hyprctl -j monitors | jq -r '.[] | select(.focused) | .name')"
    grim -o "$out" "$FILE"
    ;;
  *)
    echo "usage: screenshot.sh region|window|output" >&2; exit 1 ;;
esac

wl-copy < "$FILE"
if command -v notify-send >/dev/null; then
  notify-send -a "screenshot" "Screenshot saved" "${FILE/#$HOME/~}  (also on clipboard)"
fi
