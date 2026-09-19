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
#
# Two outlined panels; ←/→ moves focus. Tools focused: ↑/↓ select a tool.
# Logs focused: ↑/↓ scroll. The mouse wheel always scrolls the logs.
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
focus=0           # 0 = tools panel, 1 = logs panel
TOP=-1            # first visible visual line of the log; -1 = follow the newest
follow=0          # 1 = show the unit's journal even when idle
msg=""; msg_until=0
# "clear" only moves what the panel shows; nothing on disk changes. Per job:
# journal lines older than CLEAR_TS and file lines up to CLEAR_LN are hidden.
declare -A CLEAR_TS CLEAR_LN
VIS_FILE=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/skemos-panel.XXXXXX")   # visible raw lines, for `y`
META_FILE="$VIS_FILE.meta"                                           # "total_lines page_rows top", for scrolling
printf -v HBAR '%*s' 400 ''; HBAR=${HBAR// /─}
printf -v BLANK '%*s' 400 ''
MAXLOG=1000       # raw log lines loaded, so there is history to scroll
SELF_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
CLAUDE_FILE="$VIS_FILE.claude"     # written by the background probe: ready | nologin | missing
CLAUDE_STATE=checking
last_probe=-100
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
# Anything hidden by `c` (clear view) stays hidden; new output shows up.
fetch_log() {
  local job=$1 n=$2 skip=${CLEAR_LN[$1]:-0} total
  if [[ $follow == 1 || ${LIVE[$job]} == RUNNING ]]; then
    local -a a=(-u "${UNIT[$job]}" -n "$n" --no-pager -o cat)
    [[ -n ${CLEAR_TS[$job]:-} ]] && a+=(--since "@${CLEAR_TS[$job]}")
    journalctl "${a[@]}" 2>/dev/null | sed -e '/^-- No entries --$/d'
  elif [[ -r $LOG_DIR/$job.log ]]; then
    total=$(wc -l < "$LOG_DIR/$job.log")
    (( total < skip )) && skip=0          # log was replaced/rotated
    tail -n +$((skip+1)) "$LOG_DIR/$job.log" 2>/dev/null | tail -n "$n"
  elif [[ -z ${CLEAR_TS[$job]:-} ]]; then
    echo "no log yet for $job"
  fi | LC_ALL=C tr '\t' ' ' | LC_ALL=C tr -d '\000-\010\013-\037\177'
}

clear_view() {
  local job=$1
  local f=$LOG_DIR/$job.log
  CLEAR_TS[$job]=$(date +%s)
  CLEAR_LN[$job]=0
  [[ -r $f ]] && CLEAR_LN[$job]=$(wc -l < "$f")
}

copy_view() {
  local n
  n=$(wc -l < "$VIS_FILE")
  if (( n == 0 )); then
    msg="nothing to copy"
  elif command -v wl-copy >/dev/null 2>&1 && wl-copy < "$VIS_FILE" >/dev/null 2>&1; then
    msg="copied $n line(s)"
  else
    msg="copy failed (wl-copy?)"
  fi
  msg_until=$(( $(date +%s) + 3 ))
}

# --- Claude analysis (optional; see security-analyze.sh) ---------------------
claude_bin() {
  command -v claude 2>/dev/null && return 0
  [[ -x $HOME/.local/bin/claude ]] && { echo "$HOME/.local/bin/claude"; return 0; }
  return 1
}

# Prints ready | nologin | missing. Slow (starts claude) — only ever run in the
# background, or on demand when the user presses `a`.
claude_probe() {
  local bin
  bin=$(claude_bin) || { echo missing; return 0; }
  if "$bin" auth status --json 2>/dev/null | jq -e '.loggedIn == true' >/dev/null 2>&1; then
    echo ready
  else
    echo nologin
  fi
}

say_msg() { msg=$1; msg_until=$(( $(date +%s) + ${2:-4} )); }

analyze_view() {
  local job=${JOBS[$selected]} d mode="LAST LOG"
  if [[ $CLAUDE_STATE != ready ]]; then CLAUDE_STATE=$(claude_probe); fi   # re-check on demand
  case $CLAUDE_STATE in
    missing) say_msg "claude not installed — see INSTALL.md"; return ;;
    nologin) say_msg "run 'claude' once to sign in"; return ;;
  esac
  if [[ -z ${XDG_RUNTIME_DIR:-} ]]; then say_msg "no XDG_RUNTIME_DIR — cannot make a private dir"; return; fi
  d=$(mktemp -d "$XDG_RUNTIME_DIR/skemos-analysis.XXXXXX") || { say_msg "could not create temp dir"; return; }
  fetch_log "$job" "$MAXLOG" > "$d/log.txt"
  if [[ ! -s $d/log.txt ]]; then
    rm -rf -- "$d"; say_msg "nothing to analyze (log is empty/cleared)"; return
  fi
  [[ $follow == 1 || ${LIVE[$job]} == RUNNING ]] && mode=LIVE
  printf 'tool: %s\npurpose: %s\nstatus: %s\nlast run: %s\nview: %s\n' \
    "${LABEL[$job]}" "${DESC[$job]}" "${STATUS[$job]}" "${WHEN[$job]}" "$mode" > "$d/context.txt"
  setsid foot -a skemos-analysis -T 'SKEMOS ANALYSIS' -e "$SELF_DIR/security-analyze.sh" "$d" >/dev/null 2>&1 &
  say_msg "opened analysis terminal" 3
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
  local lbw=$(( LW + 2 ))                 # left box width, borders included
  local rbw=$(( cols - lbw ))             # right box width, borders included
  local iw=$(( rbw - 2 ))                 # right inner width
  (( iw < 14 )) && iw=14
  local rw=$(( iw - 2 ))                  # log text width (1 col padding each side)
  local n=$(( rows - 2 ))                 # content rows inside the boxes
  local job=${JOBS[$selected]}
  local lb=$fnt rb=$fnt
  (( focus == 0 )) && lb=$ink || rb=$ink  # bright outline = focused panel
  local -a L=() R=()
  local i j c text color live mk

  # ---- left cells (each exactly LW wide) -----------------------------------
  for ((c=0; c<n; c++)); do L[c]=${BLANK:0:LW}; done
  for j in "${!JOBS[@]}"; do
    local jb=${JOBS[$j]}
    live=${LIVE[$jb]}
    color=$dim
    [[ ${STATUS[$jb]} == WARN || ${STATUS[$jb]} == FAIL || $live == RUNNING ]] && color=$acc
    mk=" "; (( j == selected && focus == 1 )) && mk="▸"
    printf -v text '%s%d  %-*s %s' "$mk" $((j+1)) 12 "${LABEL[$jb]}" "$live"
    text=$(padr "$text" "$LW")
    c=$(( 1 + 4*j ))
    if (( j == selected && focus == 0 )); then L[c]="${sel}${text}${rst}"; else L[c]="${ink}${text}${rst}"; fi
    printf -v text '    %-6s %s' "${STATUS[$jb]}" "${WHEN[$jb]}"
    L[c+1]="${color}$(padr "$text" "$LW")${rst}"
    L[c+2]="${dim}$(padr "    $(trunc "${DESC[$jb]}" $((LW-5)))" "$LW")${rst}"
  done
  local -a hints
  if (( focus == 0 )); then
    hints=("↑/↓ j/k  select tool" "1-5      jump to tool" "→        focus logs")
  else
    hints=("↑/↓ j/k  scroll" "PgUp/PgDn page" "^u/^d    half page" "g/G      oldest/newest" "←        focus tools")
  fi
  hints+=("r        run now" "f        live journal" "c        clear view" "y        copy log")
  case $CLAUDE_STATE in
    ready)   hints+=("a        analyze with Claude") ;;
    missing) hints+=("a        analyze (claude missing)") ;;
    nologin) hints+=("a        analyze (sign in first)") ;;
    *)       hints+=("a        analyze (checking…)") ;;
  esac
  hints+=("q        quit")
  local h=${#hints[@]} k
  for k in "${!hints[@]}"; do
    color=$dim; [[ ${hints[k]} == "a "*Claude && $CLAUDE_STATE == ready ]] && color=$ink
    L[n-h+k]="${color}$(padr " ${hints[k]}" "$LW")${rst}"
  done
  if (( $(date +%s) < msg_until )); then
    L[n-h-1]="${acc}$(padr " $(trunc "$msg" $((LW-2)))" "$LW")${rst}"
  fi

  # ---- log lines: load history, wrap, pick the visible window ---------------
  local -a lg=() vl=() vc=() vr=()
  mapfile -t lg < <(fetch_log "$job" "$MAXLOG")
  local raw ri
  for ri in "${!lg[@]}"; do
    raw=${lg[ri]}
    color=$ink
    case $raw in *WARN*|*FAIL*|*Warning*|*ERROR*) color=$acc ;; esac
    vl+=("${raw:0:rw}"); vc+=("$color"); vr+=("$ri")
    raw=${raw:rw}
    while [[ -n $raw ]]; do
      vl+=("  ${raw:0:rw-2}"); vc+=("$color"); vr+=("$ri")
      raw=${raw:rw-2}
    done
  done
  if (( ${#vl[@]} == 0 )) && [[ -n ${CLEAR_TS[$job]:-} ]]; then
    vl=("cleared — waiting for output"); vc=("$dim"); vr=(-1)
  fi
  local total=${#vl[@]} max off
  max=$(( total - n )); (( max < 0 )) && max=0
  if (( TOP >= 0 )); then off=$TOP; (( off > max )) && off=$max; else off=$max; fi
  printf '%s %s %s\n' "$total" "$n" "$off" > "$META_FILE"

  local last=-1 line pad
  : > "$VIS_FILE"
  for ((c=0; c<n; c++)); do
    line=${vl[c+off]:-}
    pad=$(( iw - 1 - ${#line} )); (( pad < 0 )) && pad=0
    R[c]="${vc[c+off]:-$ink} ${line}${BLANK:0:pad}${rst}"
    ri=${vr[c+off]:--1}
    if (( ri >= 0 && ri != last )); then printf '%s\n' "${lg[ri]}" >> "$VIS_FILE"; last=$ri; fi
  done

  # ---- borders + join ---------------------------------------------------------
  local mode="LAST LOG"
  [[ $follow == 1 || ${LIVE[$job]} == RUNNING ]] && mode="LIVE"
  [[ -n ${CLEAR_TS[$job]:-} ]] && mode+=" · CLEARED"
  (( TOP >= 0 && off < max )) && mode+=" · SCROLLED (G = latest)"
  local lt=" SKEMOS SECURITY " rt
  rt=$(trunc " ${LABEL[$job]} · ${STATUS[$job]} · ${mode} " $((iw-1)))
  printf '%s┌─%s%s┐%s┌─%s%s┐%s\n' "$lb" "$lt" "${HBAR:0:lbw-3-${#lt}}" \
    "$rb" "$rt" "${HBAR:0:rbw-3-${#rt}}" "$rst"
  for ((c=0; c<n; c++)); do
    printf '%s│%s%s%s│%s│%s%s%s│%s\n' "$lb" "$rst" "${L[c]}" "$lb" "$rb" "$rst" "${R[c]}" "$rb" "$rst"
  done
  printf '%s└%s┘%s└%s┘%s\n' "$lb" "${HBAR:0:lbw-2}" "$rb" "${HBAR:0:rbw-2}" "$rst"
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
      # no \e[K: every row is exactly `cols` wide, and with autowrap off the
      # cursor rests ON the last cell, so an erase-to-EOL would wipe the border
      buf+=$'\e['$((i+1))';1H'"${NEW[i]:-}"
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

# Scroll the log by <dir>(-1 up / 1 down) x <amount>(lines | half | page).
# TOP stays put while new lines arrive; reaching the bottom resumes following.
scroll_by() {
  local dir=$1 amt=$2 total n max off step
  read -r total n _ < "$META_FILE" 2>/dev/null || return 0
  max=$(( total - n )); (( max <= 0 )) && return 0
  case $amt in page) step=$(( n - 1 )) ;; half) step=$(( n / 2 )) ;; *) step=$amt ;; esac
  if (( TOP >= 0 )); then off=$TOP; else off=$max; fi
  off=$(( off + dir * step ))
  (( off < 0 )) && off=0
  if (( off >= max )); then TOP=-1; else TOP=$off; fi
}

move_sel() {
  local new=$(( selected + $1 ))
  (( new < 0 || new >= ${#JOBS[@]} )) && return 0
  selected=$new; TOP=-1
}

cleanup() { rm -f "$VIS_FILE" "$META_FILE" "$CLAUDE_FILE" "$CLAUDE_FILE.tmp"; printf '\e[?1006l\e[?1000l\e[?7h\e[?25h\e[?1049l'; }
trap cleanup EXIT
trap 'full=1; TOP=-1' WINCH
# alt screen, hidden cursor, no autowrap, SGR mouse reporting (wheel scrolls logs
# instead of the terminal turning it into arrow keys)
printf '\e[?1049h\e[?25l\e[?7l\e[?1000h\e[?1006h'

last_refresh=-1
while true; do
  if (( SECONDS != last_refresh )); then refresh_state; last_refresh=$SECONDS; fi
  if (( SECONDS - last_probe >= 30 )); then
    last_probe=$SECONDS
    ( claude_probe > "$CLAUDE_FILE.tmp" && mv -f "$CLAUDE_FILE.tmp" "$CLAUDE_FILE" ) >/dev/null 2>&1 &
  fi
  [[ -r $CLAUDE_FILE ]] && read -r CLAUDE_STATE < "$CLAUDE_FILE"
  read -t 0 || paint          # while input is queued (wheel bursts), skip the repaint
  if read -rsn1 -t 1 key; then
    if [[ $key == $'\e' ]]; then
      seq=""
      while read -rsn1 -t 0.05 c; do
        seq+=$c
        [[ $seq == O ]] && continue                      # SS3: one more char follows
        [[ $c == [A-Za-z~] && $seq != "[" ]] && break    # CSI final byte
        (( ${#seq} > 24 )) && break
      done
      case "$seq" in
        '[A'|OA) key=UP ;;    '[B'|OB) key=DOWN ;;
        '[C'|OC) key=RIGHT ;; '[D'|OD) key=LEFT ;;
        '[5~') key=PGUP ;;    '[6~') key=PGDN ;;
        '[H'|OH|'[1~') key=HOME ;; '[F'|OF|'[4~') key=END ;;
        '[<64;'*M) key=WUP ;; '[<65;'*M) key=WDN ;;
        "") key=q ;;          # bare Esc quits
        *)  key="" ;;         # clicks, other sequences: ignore
      esac
    fi
    case "$key" in
      q) exit 0 ;;
      UP|k)   if (( focus == 0 )); then move_sel -1; else scroll_by -1 1; fi ;;
      DOWN|j) if (( focus == 0 )); then move_sel 1;  else scroll_by 1 1;  fi ;;
      LEFT)  focus=0 ;;
      RIGHT) focus=1 ;;
      WUP) scroll_by -1 3 ;;
      WDN) scroll_by 1 3 ;;
      PGUP)  (( focus == 1 )) && scroll_by -1 page ;;
      PGDN)  (( focus == 1 )) && scroll_by 1 page ;;
      $'\x15') (( focus == 1 )) && scroll_by -1 half ;;
      $'\x04') (( focus == 1 )) && scroll_by 1 half ;;
      HOME|g) (( focus == 1 )) && TOP=0 ;;
      END|G)  (( focus == 1 )) && TOP=-1 ;;
      [1-5]) selected=$((key-1)); TOP=-1 ;;
      r) clear_view "${JOBS[$selected]}"; TOP=-1; run_job "${JOBS[$selected]}" ;;
      c) clear_view "${JOBS[$selected]}"; TOP=-1 ;;
      y) copy_view ;;
      a) analyze_view ;;
      f) follow=$(( 1 - follow )); TOP=-1 ;;
    esac
  fi
done
