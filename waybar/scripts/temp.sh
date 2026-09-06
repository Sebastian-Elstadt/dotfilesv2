#!/usr/bin/env bash
# Skemos — waybar CPU temperature. k10temp Tctl (AMD); falls back to the first
# hwmon temp1_input if lm_sensors / jq are missing.

set -euo pipefail

t=""
if command -v sensors >/dev/null && command -v jq >/dev/null; then
  t="$(sensors -j 2>/dev/null \
      | jq -r 'to_entries[] | select(.key|startswith("k10temp")) | .value.Tctl.temp1_input // empty' \
      | head -1)"
fi
if [ -z "$t" ]; then
  for f in /sys/class/hwmon/hwmon*/temp1_input; do
    [ -r "$f" ] && { t="$(( $(cat "$f") / 1000 ))"; break; }
  done
fi
[ -z "$t" ] && { echo '{"text":""}'; exit 0; }

ti="${t%.*}"
cls="cool"; [ "$ti" -ge 80 ] 2>/dev/null && cls="hot"
printf '{"text":"%s°","class":"%s","tooltip":"CPU %s°C"}\n' "$ti" "$cls" "$ti"
