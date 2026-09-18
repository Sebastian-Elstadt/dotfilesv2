#!/usr/bin/env bash
# Skemos security — arch-audit job: known-CVE exposure in installed packages.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
JOB=arch-audit

out="$(arch-audit 2>&1)" || true
sk_write_log "$JOB" "${out:-(no output)}"

if [[ -z $out ]]; then
  sk_write_summary "$JOB" ok "no known-vulnerable packages installed"
else
  count=$(wc -l <<<"$out")
  sk_write_summary "$JOB" warn "$count package(s) with known advisories — see log"
fi
