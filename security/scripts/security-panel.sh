#!/usr/bin/env bash
# Skemos security — SUPER+S interactive panel. Runs unprivileged, straight
# from the repo checkout. Nothing here runs as root; scan triggers go
# through `sudo skemos-security-run`, gated by the narrow NOPASSWD rule in
# /etc/sudoers.d/skemos-security (Task 10/14).
set -uo pipefail

STATE_DIR="/var/log/skemos-security"
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

# palette — mirrors hypr/colors.lua / bash/skemos.bash
ink=$'\e[38;2;229;225;214m'; dim=$'\e[38;2;154;148;138m'
fnt=$'\e[38;2;85;81;74m';    acc=$'\e[38;2;193;102;58m'
rst=$'\e[0m'

live_state() {
  local st; st=$(systemctl is-active "${UNIT[$1]}" 2>/dev/null); st=${st:-inactive}
  [[ $st == active || $st == activating ]] && echo RUNNING || echo IDLE
}

row() {
  local job=$1 summary="$STATE_DIR/$job.summary.json"
  local status="—" when="—"
  if [[ -f $summary ]]; then
    status=$(jq -r '.status // "—"' "$summary" 2>/dev/null | tr '[:lower:]' '[:upper:]')
    when=$(jq -r '.last_run // "—"' "$summary" 2>/dev/null)
  fi
  local live color
  live=$(live_state "$job")
  color=$dim
  [[ $status == WARN || $status == FAIL ]] && color=$acc
  [[ $live == RUNNING ]] && color=$acc
  printf '%-12s %s%-6s%s  %-25s %s%s%s' "${LABEL[$job]}" "$color" "$status" "$rst" "$when" "$color" "$live" "$rst"
}

draw_table() {
  clear
  printf '%s╭─ SKEMOS SECURITY ────────────────────────────────────────────╮%s\n' "$fnt" "$rst"
  printf '%s   %-12s %-6s  %-25s %s%s\n' "$dim" "JOB" "LAST" "WHEN" "STATE" "$rst"
  local i=1 job
  for job in "${JOBS[@]}"; do
    printf ' %s%d%s %s\n' "$acc" "$i" "$rst" "$(row "$job")"
    ((i++))
  done
  printf '%s╰──────────────────────────────────────────────────────────────╯%s\n' "$fnt" "$rst"
  printf '%s  [1-5] select · q quit%s\n' "$dim" "$rst"
}

action_menu() {
  local job=$1
  local opts="run now
view last log"
  [[ $(live_state "$job") == RUNNING ]] && opts+="
tail live"
  local choice
  choice=$(printf '%s\n' "$opts" | fzf --prompt="${LABEL[$job]}> " --height=6 --reverse --no-info \
    --color="bg+:#34322d,fg+:#e5e1d6,fg:#9a948a,prompt:#c1663a") || return 0
  case "$choice" in
    "run now")
      sudo /usr/local/bin/skemos-security-run "$job" >/dev/null 2>&1 &
      ;;
    "view last log")
      if [[ -r "/var/log/skemos-security/$job.log" ]]; then
        less "/var/log/skemos-security/$job.log"
      else
        echo "no log yet for $job — press Enter to go back"
        read -r
      fi
      ;;
    "tail live")
      journalctl -u "${UNIT[$job]}" -f
      ;;
  esac
}

while true; do
  draw_table
  if read -rsn1 -t 2 key; then
    case "$key" in
      q) exit 0 ;;
      [1-5]) action_menu "${JOBS[$((key-1))]}" ;;
    esac
  fi
done
