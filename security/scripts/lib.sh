#!/usr/bin/env bash
# Skemos security — shared helpers, sourced (not executed) by every job
# script. Installed read-only, root:root, at
# /usr/local/lib/skemos-security/lib.sh by bootstrap.sh (Task 14) — never
# run directly from ~/.config (see the ownership rule in the plan header).
set -euo pipefail

SKEMOS_SECURITY_CONF="/etc/skemos-security.conf"
[[ -r "$SKEMOS_SECURITY_CONF" ]] && source "$SKEMOS_SECURITY_CONF"
: "${SKEMOS_USER:?SKEMOS_USER not set — run install/bootstrap.sh first}"
: "${SKEMOS_HOME:?SKEMOS_HOME not set — run install/bootstrap.sh first}"

SK_LOG_DIR="/var/log/skemos-security"

sk_log_path()     { echo "$SK_LOG_DIR/$1.log"; }
sk_summary_path() { echo "$SK_LOG_DIR/$1.summary.json"; }

# sk_write_log <job> <text...> — appends a timestamped block to the job's
# group-readable log.
sk_write_log() {
  local job=$1; shift
  install -d -o root -g skemos-security -m 0750 "$SK_LOG_DIR"
  {
    printf -- '--- %s ---\n' "$(date -Is)"
    printf '%s\n' "$*"
  } >> "$(sk_log_path "$job")"
  chown root:skemos-security "$(sk_log_path "$job")"
  chmod 0640 "$(sk_log_path "$job")"
}

# sk_write_summary <job> <status: ok|warn|fail> <detail> — atomically
# replaces the job's small JSON summary (what the panel's table reads) and
# notifies on warn/fail regardless of what triggered this run (see plan
# header). <detail> must stay script-generated text — the JSON escaping
# below only handles `"`, so never pass raw tool output (or anything a user
# can influence) as the detail. The summary lives in the root-owned log dir next to the logs
# (root:skemos-security 0640); root never writes into a user-owned directory.
sk_write_summary() {
  local job=$1 status=$2 detail=$3
  install -d -o root -g skemos-security -m 0750 "$SK_LOG_DIR"
  local ts; ts=$(date -Is)
  local final tmp
  final=$(sk_summary_path "$job")
  tmp=$(mktemp "$SK_LOG_DIR/.summary.XXXXXX")
  printf '{"last_run":"%s","status":"%s","detail":"%s"}\n' \
    "$ts" "$status" "${detail//\"/\\\"}" > "$tmp"
  chown root:skemos-security "$tmp"
  chmod 0640 "$tmp"
  mv -f "$tmp" "$final"
  if [[ $status == warn || $status == fail ]]; then
    sk_notify "Skemos security: $job" "$detail"
  fi
}

# sk_notify <title> <body> — sends a desktop notification into the user's
# running mako, from a root process, via that user's D-Bus session.
sk_notify() {
  local uid; uid=$(id -u "$SKEMOS_USER" 2>/dev/null) || return 0
  [[ -S "/run/user/$uid/bus" ]] || return 0
  sudo -u "$SKEMOS_USER" env \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
    XDG_RUNTIME_DIR="/run/user/$uid" \
    notify-send -a "Skemos Security" "$1" "$2" || true
}
