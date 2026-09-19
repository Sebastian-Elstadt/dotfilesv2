#!/usr/bin/env bash
# Skemos security — audit-status job: today's watched-path events, digested.
#
# ausearch prints several raw records per event; this groups them into events
# and drops two ROUTINE sources so they don't raise a WARN until midnight:
#   * auditctl loading the rules (bootstrap / boot): a CONFIG_CHANGE by
#     /usr/bin/auditctl;
#   * gpg refreshing the pacman keyring's trust database (every pacman
#     transaction): the ONLY paths touched are trustdb.gpg / its lock files.
# Everything else stays flagged — including other keyring files (pubring.kbx =
# a key import), sudoers.d, passwd, ~/.ssh, and any audit-rule change made by
# something other than auditctl.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
JOB=audit-status

# ausearch exits 1 for "no matches"; anything higher means it could not run.
rc=0
raw="$(ausearch -ts today -k skemos 2>&1)" || rc=$?
if (( rc > 1 )); then
  sk_write_log "$JOB" "ausearch failed (exit $rc)"$'\n'"${raw:-(no output)}"
  sk_write_summary "$JOB" fail "ausearch could not run — see log"
  exit 0
fi
if ! grep -q '^type=' <<<"$raw"; then
  sk_write_log "$JOB" "no watched-path events today"
  sk_write_summary "$JOB" ok "no watched-path events today"
  exit 0
fi

# one line per event: ts \037 exe \037 auid \037 uid \037 config-change \037 paths
AWK_PROG='
function fld(s, k,   m, v) {
  if (match(s, " " k "=\"[^\"]*\"")) return substr(s, RSTART + length(k) + 3, RLENGTH - length(k) - 4)
  if (match(s, " " k "=[^ ]*"))      return substr(s, RSTART + length(k) + 2, RLENGTH - length(k) - 2)
  return ""
}
/^type=/ {
  if (!match($0, /msg=audit\([0-9]+\.[0-9]+:[0-9]+\)/)) next
  id = substr($0, RSTART + 10, RLENGTH - 11); split(id, p, "[.:]"); ser = p[3]
  if (!(ser in seen)) { seen[ser] = 1; order[++n] = ser; ts[ser] = p[1] }
  t = substr($0, 6); sub(/ .*/, "", t)
  if (t == "SYSCALL") { exe[ser] = fld($0, "exe"); auid[ser] = fld($0, "auid"); uid[ser] = fld($0, "uid") }
  else if (t == "PATH") { nm = fld($0, "name"); nt = fld($0, "nametype")
    if (nm != "" && nt != "PARENT") pa[ser] = pa[ser] (pa[ser] == "" ? "" : " ") nm }
  else if (t == "CONFIG_CHANGE") cfg[ser] = 1
}
END { for (i = 1; i <= n; i++) { s = order[i]
  printf "%s\037%s\037%s\037%s\037%s\037%s\n", ts[s], exe[s], auid[s], uid[s], (cfg[s] ? 1 : 0), pa[s] } }'
events="$(awk "$AWK_PROG" <<<"$raw")"

routine_paths() {   # every path is the pacman keyring trust db (or its lock)
  local -a ps; local p
  read -ra ps <<<"$1"
  (( ${#ps[@]} > 0 )) || return 1
  for p in "${ps[@]}"; do
    [[ $p == /etc/pacman.d/gnupg/trustdb.gpg || $p == /etc/pacman.d/gnupg/.#lk* ]] || return 1
  done
}

flagged=""; nflag=0; nrules=0; ntrust=0
while IFS=$'\037' read -r ts exe auid uid cfg paths; do
  [[ -n $ts ]] || continue
  if [[ $cfg == 1 && $exe == /usr/bin/auditctl ]]; then nrules=$((nrules+1)); continue; fi
  if [[ $cfg == 0 && $exe == /usr/bin/gpg ]] && routine_paths "$paths"; then ntrust=$((ntrust+1)); continue; fi
  [[ $auid == 4294967295 ]] && auid=unset
  what=${paths:-"(audit rules changed)"}
  flagged+="$(date -d "@$ts" +%T)  ${exe:-?} (uid=${uid:-?} auid=${auid:-?})  $what"$'\n'
  nflag=$((nflag+1))
done <<<"$events"

log=""
if (( nflag > 0 )); then
  log+="FLAGGED ($nflag):"$'\n'"$flagged"
  log+="details: sudo ausearch -ts today -k skemos -i"$'\n'
else
  log+="FLAGGED: none"$'\n'
fi
log+="Routine, not flagged: $nrules audit-rule load(s), $ntrust pacman keyring trustdb update(s)"
sk_write_log "$JOB" "$log"

if (( nflag > 0 )); then
  sk_write_summary "$JOB" warn "$nflag unexpected watched-path event(s) today — see log"
else
  sk_write_summary "$JOB" ok "no unexpected watched-path events today ($((nrules+ntrust)) routine)"
fi
