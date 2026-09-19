#!/usr/bin/env bash
# Skemos security — arch-audit job: known-CVE exposure in installed packages.
#
# Uses `arch-audit --json` and filters out tracker ids listed in the
# root-owned acknowledgement file (arch-audit-ack, installed beside this
# script — see security/arch-audit-ack.txt for why entries are there). Only
# advisories NOT acknowledged raise a WARN; acknowledged ones are still
# printed in the log under their own heading.
#
# arch-audit's exit-code convention is not relied on: a run counts as "worked"
# only if it printed a JSON array. Anything else is "could not run" (or, with
# exit 0, unexpected output) rather than being counted as vulnerable packages.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
JOB=arch-audit
ACK_FILE="$HERE/arch-audit-ack"

rc=0
out="$(arch-audit --json 2>&1)" || rc=$?

if ! jq -e 'type == "array"' <<<"$out" >/dev/null 2>&1; then
  sk_write_log "$JOB" "exit status $rc"$'\n'"${out:-(no output)}"
  if (( rc != 0 )); then
    sk_write_summary "$JOB" fail "arch-audit could not run — see log"
  else
    sk_write_summary "$JOB" warn "arch-audit printed unexpected output — see log"
  fi
  exit 0
fi

# acknowledged tracker ids -> JSON array (missing/empty file = nothing acked)
ack='[]'
if [[ -r $ACK_FILE ]]; then
  ack="$( { grep -oE '^AVG-[0-9]+' "$ACK_FILE" || true; } | jq -R . | jq -s . )"
fi

fmt='.[] | "\(.packages | join(",")) \(.name) \(.severity) — \(.issues[0:3] | join(",")) (\(.issues | length) CVE(s))"'
new_json="$(jq -c --argjson ack "$ack" '[ .[] | select(.name as $n | ($ack | index($n)) | not) ]' <<<"$out")"
acked_json="$(jq -c --argjson ack "$ack" '[ .[] | select(.name as $n | ($ack | index($n)) != null) ]' <<<"$out")"
new_pkgs="$(jq -r '[.[].packages[]] | unique | length' <<<"$new_json")"
new_n="$(jq 'length' <<<"$new_json")"
acked_n="$(jq 'length' <<<"$acked_json")"

log="exit status $rc"$'\n'
if (( new_n > 0 )); then
  log+="NEW — not acknowledged ($new_n):"$'\n'"$(jq -r "$fmt" <<<"$new_json")"$'\n'
else
  log+="NEW — not acknowledged: none"$'\n'
fi
if (( acked_n > 0 )); then
  log+="ACKNOWLEDGED ($acked_n, see arch-audit-ack):"$'\n'"$(jq -r "$fmt" <<<"$acked_json")"$'\n'
fi
sk_write_log "$JOB" "$log"

if (( new_n > 0 )); then
  sk_write_summary "$JOB" warn "$new_pkgs package(s) with unacknowledged advisories — see log"
elif (( acked_n > 0 )); then
  sk_write_summary "$JOB" ok "no new advisories ($acked_n acknowledged)"
else
  sk_write_summary "$JOB" ok "no known-vulnerable packages installed"
fi
