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
SK_STATE_DIR="$SKEMOS_HOME/.local/state/skemos/security"

sk_log_path()     { echo "$SK_LOG_DIR/$1.log"; }
sk_summary_path() { echo "$SK_STATE_DIR/$1.summary.json"; }

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

# sk_write_summary <job> <status: ok|warn|fail> <detail> — overwrites the
# job's small JSON summary (what the panel's table reads) and notifies on
# warn/fail regardless of what triggered this run (see plan header).
sk_write_summary() {
  local job=$1 status=$2 detail=$3
  install -d -o "$SKEMOS_USER" -g "$SKEMOS_USER" -m 0700 "$SK_STATE_DIR"
  local ts; ts=$(date -Is)
  printf '{"last_run":"%s","status":"%s","detail":"%s"}\n' \
    "$ts" "$status" "${detail//\"/\\\"}" > "$(sk_summary_path "$job")"
  chown "$SKEMOS_USER:$SKEMOS_USER" "$(sk_summary_path "$job")"
  if [[ $status == warn || $status == fail ]]; then
    sk_notify "Skemos security: $job" "$detail"
  fi
}

# sk_notify <title> <body> — sends a desktop notification into the user's
# running mako, from a root process, via that user's D-Bus session.
sk_notify() {
  local uid; uid=$(id -u "$SKEMOS_USER" 2>/dev/null) || return 0
  [[ -S "/run/user/$uid/bus" ]] || return 0
  sudo -u "$SKEMOS_USER" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
    XDG_RUNTIME_DIR="/run/user/$uid" \
    notify-send -a "Skemos Security" "$1" "$2" || true
}
