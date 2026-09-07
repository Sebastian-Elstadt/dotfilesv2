#!/usr/bin/env bash
# Skemos — Waybar revision cell. Prints the ~/.config git HEAD as a drawing
# revision: "REV a1b2c3d" (+ "*" when the tracked tree is dirty). One line of
# JSON; polled (config.jsonc interval). Silent / hidden when ~/.config is not a
# git repo.

set -euo pipefail
GIT_DIR="$HOME/.config/.git"
WORK="$HOME/.config"

git() { command git --git-dir="$GIT_DIR" --work-tree="$WORK" "$@"; }

hash="$(git rev-parse --short=7 HEAD 2>/dev/null || true)"
if [ -z "$hash" ]; then
  echo '{"text":"","class":"none","tooltip":false}'
  exit 0
fi

dirty=""
git diff --quiet --ignore-submodules HEAD 2>/dev/null || dirty="*"

subject="$(git log -1 --format='%s' 2>/dev/null || true)"
when="$(git log -1 --format='%cd' --date=format:'%Y-%m-%d %H:%M' 2>/dev/null || true)"
class="clean"; [ -n "$dirty" ] && class="dirty"

printf '{"text":"REV %s%s","class":"%s","tooltip":"%s  ·  %s\\n%s"}\n' \
  "$hash" "$dirty" "$class" "$hash" "$when" "${subject//\"/\\\"}"
