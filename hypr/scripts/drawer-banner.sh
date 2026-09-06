#!/usr/bin/env bash
# Skemos — "PROGRAM DRAWER" banner controller.
#
# Shows a thin orange Waybar strip along the bottom edge whenever the minimize
# drawer (special:minimized) is on screen, and hides it otherwise. Runs for the
# whole session, following Hyprland's socket2 event stream, so it always matches
# reality — including the drawer auto-closing when its last window is restored.
#
# Started once from hypr/autostart.lua. Needs `nc` (openbsd-netcat) for the
# UNIX-socket read.

set -u

cfg="$HOME/.config/waybar/drawer.jsonc"
css="$HOME/.config/waybar/drawer.css"
sig="${HYPRLAND_INSTANCE_SIGNATURE:?not inside a Hyprland session}"
sock="${XDG_RUNTIME_DIR}/hypr/${sig}/.socket2.sock"

match="waybar -c ${cfg}"
show() { pgrep -f -- "$match" >/dev/null 2>&1 || setsid -f waybar -c "$cfg" -s "$css" >/dev/null 2>&1; }
hide() { pkill -f -- "$match" 2>/dev/null || true; }

hide                 # clean slate on (re)start
trap hide EXIT

# socket2 lines: "activespecial>>special:minimized,DP-1" on show,
#                "activespecial>>,DP-1"                   on hide.
# -d: never read stdin (else nc drops the connection at stdin EOF under setsid).
# Reconnect if Hyprland closes the socket (it won't normally, but be safe).
while :; do
  nc -d -U "$sock" 2>/dev/null | while IFS= read -r ev; do
    case $ev in
      activespecial\>\>special:minimized,*) show ;;
      activespecial\>\>,*)                   hide ;;
    esac
  done
  sleep 2
done
