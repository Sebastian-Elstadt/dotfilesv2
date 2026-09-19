#!/usr/bin/env bash
# SUPER+S: open the security panel, or close it if it is already open.
# Placement (left edge, fixed size) comes from the window rule in
# hypr/rules.lua, matched on the `skemos-security` app-id.
set -u
pat='^foot -a skemos-security '
if pgrep -f -- "$pat" >/dev/null; then
  pkill -f -- "$pat"
else
  exec foot -a skemos-security -T 'SKEMOS SECURITY' -e "$(dirname "$(readlink -f "$0")")/security-panel.sh"
fi
