#!/usr/bin/env bash
# Skemos security — file-integrity job. Hashes a curated path list and
# diffs against a baseline; a WARN means something changed OUTSIDE a
# tracked pacman transaction (the paired pacman hook re-baselines after
# every real upgrade — see 99-skemos-integrity-resync.hook).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

JOB=integrity
DB_DIR=/var/lib/skemos-security
DB_FILE="$DB_DIR/integrity.db"

WATCH_PATHS=(
  /usr/bin/sh /usr/bin/bash /usr/bin/sudo /usr/bin/ssh /usr/bin/pacman
  /usr/lib/systemd/systemd
  /etc/passwd /etc/sudoers /etc/pacman.conf
  "$SKEMOS_HOME/.bashrc" "$SKEMOS_HOME/.bash_profile"
  "$SKEMOS_HOME/.config/hypr/hyprland.lua"
  "$SKEMOS_HOME/.config/hypr/binds.lua"
  "$SKEMOS_HOME/.config/hypr/look.lua"
)
WATCH_DIRS=( /etc/pacman.d/hooks )

hash_current() {
  local f d
  for f in "${WATCH_PATHS[@]}"; do
    [[ -e $f ]] && sha256sum "$f"
  done
  for d in "${WATCH_DIRS[@]}"; do
    [[ -d $d ]] && find "$d" -type f -exec sha256sum {} \;
  done
  return 0
}

install -d -o root -g root -m 0750 "$DB_DIR"

if [[ "${1:-}" == "--rebaseline" ]]; then
  hash_current | sort -k2 > "$DB_FILE"
  chmod 0600 "$DB_FILE"
  sk_write_log "$JOB" "rebaselined ($(wc -l < "$DB_FILE") paths)"
  sk_write_summary "$JOB" ok "baseline refreshed"
  exit 0
fi

if [[ ! -f $DB_FILE ]]; then
  hash_current | sort -k2 > "$DB_FILE"
  chmod 0600 "$DB_FILE"
  sk_write_log "$JOB" "first run — baseline created"
  sk_write_summary "$JOB" ok "baseline created"
  exit 0
fi

current="$(hash_current | sort -k2)"
diff_out="$(diff "$DB_FILE" <(printf '%s\n' "$current") || true)"

if [[ -z $diff_out ]]; then
  sk_write_log "$JOB" "clean — no changes"
  sk_write_summary "$JOB" ok "no changes"
else
  sk_write_log "$JOB" "CHANGED:"$'\n'"$diff_out"
  changed_count=$(grep -c '^[<>]' <<<"$diff_out" || true)
  sk_write_summary "$JOB" warn "$changed_count path(s) changed outside a tracked pacman transaction"
fi
