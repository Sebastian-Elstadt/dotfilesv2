#!/usr/bin/env bash
# Skemos — window switcher. SUPER+W.
#
# Lists every open window across all workspaces (title · class, with its
# workspace) in the rofi panel; pick one to jump to its workspace and focus it.
# Reuses rofi/skemos.rasi, so it slides in as the same right-side panel.

set -euo pipefail

# address <TAB> workspace-name <TAB> title <TAB> class, ordered by workspace
# (special workspaces — e.g. the minimize drawer — sorted last) then title.
mapfile -t rows < <(hyprctl clients -j | jq -r '
  [ .[] | select(.mapped == true) ]
  | sort_by(
      (if .workspace.id < 0 then 100000 else .workspace.id end),
      (.title | ascii_downcase))
  | .[]
  | [ .address, .workspace.name, .title, .class ] | @tsv')

(( ${#rows[@]} )) || exit 0

lines=()
for r in "${rows[@]}"; do
  IFS=$'\t' read -r _addr ws title class <<<"$r"
  case $ws in
    special:*) ws="[${ws#special:}]" ;;   # drawer etc.
  esac
  [[ -z $title ]] && title='(untitled)'
  printf -v line '%-5s  %s  ·  %s' "$ws" "$title" "$class"
  lines+=("$line")
done

idx=$(printf '%s\n' "${lines[@]}" | rofi -dmenu -i -matching fuzzy \
        -format i -p 'window' \
        -theme-str 'prompt { str: "window ▸"; } entry { placeholder: "filter windows"; }')

[[ $idx =~ ^[0-9]+$ ]] || exit 0

addr=$(cut -f1 <<<"${rows[$idx]}")
[[ -n $addr ]] || exit 0

# hl.dsp.focus({ window = ... }) pulls its workspace into view and focuses it.
# Must be the Lua form — Hyprland 0.56's `hyprctl dispatch` parses Lua, so the
# old `dispatch focuswindow address:0x…` string form is a syntax error (silent
# no-op: the panel closed but nothing moved).
hyprctl dispatch "hl.dsp.focus({ window = \"address:$addr\" })"
