#!/usr/bin/env bash
# Skemos security — rkhunter job: rootkit/backdoor/hidden-process scan.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
JOB=rkhunter

out="$(rkhunter --check --sk --nocolors 2>&1)" || true
sk_write_log "$JOB" "$out"

warnings=$(grep -c '^Warning:' <<<"$out" || true)
if [[ ${warnings:-0} -gt 0 ]]; then
  sk_write_summary "$JOB" warn "$warnings warning(s) — see log"
else
  sk_write_summary "$JOB" ok "no warnings"
fi
