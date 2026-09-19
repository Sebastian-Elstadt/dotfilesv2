#!/usr/bin/env bash
# Skemos security — ufw-status job: snapshots the firewall's current state.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
JOB=ufw-status

out="$(ufw status verbose 2>&1)" || true
sk_write_log "$JOB" "$out"

if grep -q '^Status: active' <<<"$out"; then
  sk_write_summary "$JOB" ok "active"
else
  sk_write_summary "$JOB" warn "ufw is not active"
fi
