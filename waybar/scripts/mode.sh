#!/usr/bin/env bash
# Skemos — Waybar MODE module. Prints TILE or DESK for the ACTIVE
# workspace as one line of JSON. modes.lua persists the DESK set to the state
# file below and sends SIGRTMIN+8 to waybar on every toggle.

set -euo pipefail
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/skemos/desk-workspaces"

id="$(hyprctl -j activeworkspace 2>/dev/null | jq -r '.id // empty')"
if [ -z "$id" ]; then
  echo '{"text":"","class":"none"}'
  exit 0
fi

if [ -f "$STATE" ] && grep -qx -- "$id" "$STATE"; then
  printf '{"text":"DESK","class":"desk","tooltip":"workspace %s · DESK — everything floats"}\n' "$id"
else
  printf '{"text":"TILE","class":"tile","tooltip":"workspace %s · TILE — dwindle"}\n' "$id"
fi
