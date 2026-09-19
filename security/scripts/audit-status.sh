#!/usr/bin/env bash
# Skemos security — audit-status job: snapshots today's watched-path events.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
JOB=audit-status

out="$(ausearch -ts today -k skemos 2>&1)" || out=""
if [[ -z $out ]] || ! grep -q '^type=' <<<"$out"; then
  sk_write_log "$JOB" "no watched-path events today"
  sk_write_summary "$JOB" ok "no watched-path events today"
else
  sk_write_log "$JOB" "$out"
  count=$(grep -c '^type=' <<<"$out")
  sk_write_summary "$JOB" warn "$count watched-path event(s) today — see log"
fi
