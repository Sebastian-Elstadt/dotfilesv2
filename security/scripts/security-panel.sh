#!/usr/bin/env bash
# Skemos security — SUPER+S panel. Left column: the five jobs (state at a
# glance, pick one with j/k or 1-5). Right column: that job's log, live.
# Runs unprivileged, straight from the repo checkout. Nothing here runs as
# root; scan triggers go through `sudo skemos-security-run`, gated by the
# narrow NOPASSWD rule in /etc/sudoers.d/skemos-security.
#
# No flicker: alternate screen, one write per frame, and only lines whose
# content changed since the last frame are repainted (an idle panel writes
# nothing). The screen is never cleared after the first paint.
set -uo pipefail

LOG_DIR="/var/log/skemos-security"
JOBS=(integrity rkhunter arch-audit ufw-status audit-status)
declare -A UNIT=(
  [integrity]=skemos-integrity.service
  [rkhunter]=rkhunter-scan.service
  [arch-audit]=arch-audit-scan.service
  [ufw-status]=ufw-status.service
  [audit-status]=audit-status.service
)
declare -A LABEL=(
  [integrity]="INTEGRITY"
  [rkhunter]="RKHUNTER"
  [arch-audit]="ARCH-AUDIT"
  [ufw-status]="UFW"
  [audit-status]="AUDITD"
)

declare -A DESC=(
  [integrity]="Detects changes to watched system files"
  [rkhunter]="Scans for rootkits and known malware"
  [arch-audit]="Lists installed packages with known CVEs"
  [ufw-status]="Checks the firewall is active"
  [audit-status]="Flags changes to ssh, sudo, passwd files"
)

LW=46          # left column width (chars)

# palette — mirrors hypr/colors.lua / bash/skemos.bash
ink=$'\e[38;2;229;225;214m'; dim=$'\e[38;2;154;148;138m'
fnt=$'\e[38;2;85;81;74m';    acc=$'\e[38;2;193;102;58m'
sel=$'\e[48;2;229;225;214m\e[38;2;22;21;19m'   # inverted block, like rofi
rst=$'\e[0m'

# per-job data, refreshed every tick
declare -A STATUS WHEN LIVE
selected=0
follow=0          # 1 = show the unit's journal even when idle
msg=""; msg_until=0
declare -a PREV=()
full=1

refresh_state() {
  local job i=0 out line
  # one systemctl call for all units; oneshot running = "activating"
  mapfile -t out < <(systemctl is-active \
    "${UNIT[integrity]}" "${UNIT[rkhunter]}" "${UNIT[arch-audit]}" \
    "${UNIT[ufw-status]}" "${UNIT[audit-status]}" 2>/dev/null)
  for job in "${JOBS[@]}"; do
    line=${out[i]:-inactive}; ((i++))
    [[ $line == active || $line == activating ]] && LIVE[$job]=RUNNING || LIVE[$job]=IDLE
    STATUS[$job]="—"; WHEN[$job]="—"
    if [[ -f $LOG_DIR/$job.summary.json ]]; then
      local s w
      { IFS=$'\t' read -r s w; } < <(jq -r '[.status // "—", .last_run // "—"] | @tsv' \
        "$LOG_DIR/$job.summary.json" 2>/dev/null)
      STATUS[$job]=$(tr '[:lower:]' '[:upper:]' <<<"${s:-—}")
      w=${w:-—}
      [[ $w == ????-??-??T??:??* ]] && w="${w:5:5} ${w:11:5}"
      WHEN[$job]=$w
    fi
  done
}

# Last $2 lines of the selected job's log, sanitised. Short logs sit at the top.
fetch_log() {
  local job=$1 n=$2
  if [[ $follow == 1 || ${LIVE[$job]} == RUNNING ]]; then
    journalctl -u "${UNIT[$job]}" -n "$n" --no-pager -o cat 2>/dev/null
  elif [[ -r $LOG_DIR/$job.log ]]; then
    tail -n "$n" "$LOG_DIR/$job.log" 2>/dev/null
  else
    echo "no log yet for $job"
  fi | LC_ALL=C tr '\t' ' ' | LC_ALL=C tr -d '\000-\010\013-\037\177'
}

padr() {  # padr "text" width — pad by characters (printf pads by bytes)
  local t=$1 w=$2
  printf '%s%*s' "$t" $(( w - ${#t} > 0 ? w - ${#t} : 0 )) ''
}

trunc() {  # trunc "text" width
  local t=$1 w=$2
  (( ${#t} > w )) && t="${t:0:w-1}…"
  printf '%s' "$t"
}

build_frame() {
  local cols=$1 rows=$2
  local rw=$(( cols - LW - 3 ))
  (( rw < 10 )) && rw=10
  local job=${JOBS[$selected]}
  local -a L=()   # left cells, index = row-1
  local -a R=()   # right cells
  local i j text color live

  # ---- left column ------------------------------------------------------
  L[0]="${ink}$(padr " SKEMOS SECURITY" "$LW")${rst}"
  L[1]="${fnt}$(printf '─%.0s' $(seq 1 "$LW"))${rst}"
  local r=2
  for j in "${!JOBS[@]}"; do
    local jb=${JOBS[$j]}
    live=${LIVE[$jb]}
    color=$dim
    [[ ${STATUS[$jb]} == WARN || ${STATUS[$jb]} == FAIL || $live == RUNNING ]] && color=$acc
    text=$(printf ' %d  %-*s %s' $((j+1)) 12 "${LABEL[$jb]}" "$live")
    text=$(padr "$text" "$LW")
    if (( j == selected )); then
      L[r]="${sel}${text}${rst}"
    else
      L[r]="${ink}${text}${rst}"
    fi
    ((r++))
    text=$(printf '    %-6s %s' "${STATUS[$jb]}" "${WHEN[$jb]}")
    L[r]="${color}$(padr "$text" "$LW")${rst}"
    ((r++))
    L[r]="${dim}$(padr "    $(trunc "${DESC[$jb]}" $((LW-5)))" "$LW")${rst}"
    ((r++))
    L[r]=$(printf '%*s' "$LW" '')
    ((r++))
  done
  while (( r < rows )); do L[r]=$(printf '%*s' "$LW" ''); ((r++)); done
  # footer hints, pinned to the bottom of the left column
  local -a hints=("j/k      select" "1-5      jump" "r        run now" "f        live journal" "q        quit")
  local h=${#hints[@]} k
  for k in "${!hints[@]}"; do
    L[rows-h+k]="${dim}$(padr " ${hints[k]}" "$LW")${rst}"
  done
  if (( $(date +%s) < msg_until )); then
    L[rows-h-1]="${acc}$(padr " $(trunc "$msg" $((LW-2)))" "$LW")${rst}"
  fi

  # ---- right column -----------------------------------------------------
  local mode="LAST LOG"
  [[ $follow == 1 || ${LIVE[$job]} == RUNNING ]] && mode="LIVE"
  R[0]="${ink} ${LABEL[$job]} · ${STATUS[$job]} · ${mode}${rst}"
  R[1]="${fnt}$(printf '─%.0s' $(seq 1 $((rw+2))))${rst}"
  local n=$(( rows - 2 )) line
  local -a lg=()
  mapfile -t lg < <(fetch_log "$job" "$n")
  # Hard-wrap every raw line to the pane width (continuations indented by 2),
  # then show the last $n visual lines — short logs sit at the top.
  local -a vl=() vc=()
  local raw chunk
  for raw in "${lg[@]}"; do
    color=$ink
    case $raw in *WARN*|*FAIL*|*Warning*|*ERROR*) color=$acc ;; esac
    vl+=("${raw:0:rw}"); vc+=("$color")
    raw=${raw:rw}
    while [[ -n $raw ]]; do
      vl+=("  ${raw:0:rw-2}"); vc+=("$color")
      raw=${raw:rw-2}
    done
  done
  local off=$(( ${#vl[@]} - n ))
  (( off < 0 )) && off=0
  for ((i=0; i<n; i++)); do
    line=${vl[i+off]:-}
    R[i+2]="${vc[i+off]:-$ink} ${line}${rst}"
  done

  # ---- join ---------------------------------------------------------------
  for ((i=0; i<rows; i++)); do
    printf '%s%s│%s%s\n' "${L[i]:-}" "$fnt" "$rst" "${R[i]:-}"
  done
}

paint() {
  local cols rows
  read -r rows cols < <(stty size 2>/dev/null)
  rows=${rows:-32}; cols=${cols:-110}
  local -a NEW=()
  mapfile -t NEW < <(build_frame "$cols" "$rows")
  local buf="" i
  if (( full )); then
    buf=$'\e[2J'; PREV=(); full=0
  fi
  for ((i=0; i<rows; i++)); do
    if [[ ${NEW[i]:-} != "${PREV[i]:-}" ]]; then
      buf+=$'\e['$((i+1))';1H'"${NEW[i]:-}"$'\e[K'
      PREV[i]=${NEW[i]:-}
    fi
  done
  # synchronized-output wrapper: the terminal shows the frame atomically
  [[ -n $buf ]] && printf '\e[?2026h%s\e[?2026l' "$buf"
}

run_job() {
  local job=$1
  # Backgrounded so the panel keeps refreshing. `sudo -n` fails fast (no TTY
  # password read) if the NOPASSWD rule is missing, and the failure is
  # surfaced as a desktop notification instead of vanishing.
  (
    if ! sudo -n /usr/local/bin/skemos-security-run "$job" >/dev/null 2>&1; then
      command -v notify-send >/dev/null 2>&1 &&
        notify-send -a "Skemos Security" "Skemos security" \
          "could not start $job (is the sudoers rule installed?)"
    fi
  ) >/dev/null 2>&1 &
  msg="starting ${LABEL[$job]}…"; msg_until=$(( $(date +%s) + 3 ))
}

cleanup() { printf '\e[?25h\e[?1049l'; }
trap cleanup EXIT
trap 'full=1' WINCH
printf '\e[?1049h\e[?25l'

while true; do
  refresh_state
  paint
  if read -rsn1 -t 1 key; then
    if [[ $key == $'\e' ]]; then
      read -rsn2 -t 0.05 rest || rest=""
      case "$rest" in
        '[A') key=k ;;
        '[B') key=j ;;
        "")   key=q ;;      # bare Esc quits
        *)    key="" ;;
      esac
    fi
    case "$key" in
      q) exit 0 ;;
      j) (( selected < ${#JOBS[@]}-1 )) && ((selected++)) ;;
      k) (( selected > 0 )) && ((selected--)) ;;
      [1-5]) selected=$((key-1)) ;;
      r) run_job "${JOBS[$selected]}" ;;
      f) follow=$(( 1 - follow )) ;;
    esac
  fi
done
