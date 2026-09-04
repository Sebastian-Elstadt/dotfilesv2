#!/usr/bin/env bash
# Night Vellum — Waybar minimized-count module. Counts windows parked in
# special:minimized. Emits empty text when zero (module collapses via CSS).
# minimize.lua sends SIGRTMIN+9 to waybar on minimize / restore / drawer toggle.

set -euo pipefail

n="$(hyprctl -j clients 2>/dev/null | jq '[.[] | select(.workspace.name == "special:minimized")] | length' 2>/dev/null || echo 0)"
n="${n:-0}"

if [ "$n" -gt 0 ]; then
  printf '{"text":"MIN %s","class":"has","tooltip":"%s window(s) minimized · SUPER+SHIFT+M"}\n' "$n" "$n"
else
  printf '{"text":"","class":"empty"}\n'
fi
