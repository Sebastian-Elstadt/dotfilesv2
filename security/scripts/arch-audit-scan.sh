#!/usr/bin/env bash
# Skemos security — arch-audit job: known-CVE exposure in installed packages.
#
# arch-audit's exit-code convention could not be confirmed on the machine this
# was written on (the package was not installed), so this does NOT rely on it:
# findings are recognised by output SHAPE ("<pkg> is/are affected by ..."), and
# any other output, or an exit status above 1, is treated as "arch-audit could
# not run" rather than being counted as vulnerable packages.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
JOB=arch-audit

rc=0
out="$(arch-audit 2>&1)" || rc=$?
sk_write_log "$JOB" "exit status $rc"$'\n'"${out:-(no output)}"

findings=0
if [[ -n $out ]]; then
  findings=$(grep -cE '^[^[:space:]]+ (is|are) affected by ' <<<"$out" || true)
fi

if (( findings > 0 )); then
  sk_write_summary "$JOB" warn "$findings package(s) with known advisories — see log"
elif [[ -z $out ]] && (( rc <= 1 )); then
  sk_write_summary "$JOB" ok "no known-vulnerable packages installed"
elif (( rc != 0 )); then
  sk_write_summary "$JOB" fail "arch-audit could not run — see log"
else
  sk_write_summary "$JOB" warn "arch-audit printed unexpected output — see log"
fi
