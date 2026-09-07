# Skemos — bash dressing: a title-block prompt + a login banner.
#
# Sourced from ~/.bashrc (which is NOT in the repo):
#     [[ -f ~/.config/bash/skemos.bash ]] && . ~/.config/bash/skemos.bash
#
# Interactive shells only. Set SKEMOS_BANNER=0 in the environment to suppress
# the banner (the prompt stays). Remove the source line in ~/.bashrc to drop
# the whole thing.

case $- in *i*) ;; *) return ;; esac   # interactive only

# ---- palette (mirrors hypr/colors.lua) -----------------------------------
#   ink e5e1d6 · ink-dim 9a948a · faint 55514a · accent c1663a
# Prompt copies wrap the SGR in \[ \] so bash excludes them from width math.
_p_ink='\[\e[38;2;229;225;214m\]'
_p_dim='\[\e[38;2;154;148;138m\]'
_p_fnt='\[\e[38;2;85;81;74m\]'
_p_acc='\[\e[38;2;193;102;58m\]'
_p_rst='\[\e[0m\]'
# Bare copies for the banner (plain echo, no readline markers).
_b_ink=$'\e[38;2;229;225;214m'
_b_dim=$'\e[38;2;154;148;138m'
_b_fnt=$'\e[38;2;85;81;74m'
_b_acc=$'\e[38;2;193;102;58m'
_b_rst=$'\e[0m'

# ---- prompt -------------------------------------------------------------
#   ╭─ user@host · ~/path · a1b2c3d*            ✕ N
#   ╰▸
# rev block: only inside a git work tree; '*' = dirty tracked files.
# '✕ N':     only after a non-zero exit.
_sk_prompt() {
  local code=$?

  local rev='' hash
  hash=$(git rev-parse --short=7 HEAD 2>/dev/null) || hash=''
  if [[ -n $hash ]]; then
    local dirty=''
    git diff --quiet --ignore-submodules HEAD 2>/dev/null || dirty='*'
    rev=" ${_p_fnt}·${_p_rst} ${_p_dim}${hash}${_p_acc}${dirty}${_p_rst}"
  fi

  local err=''
  (( code )) && err="   ${_p_acc}✕ ${_p_dim}${code}${_p_rst}"

  PS1="${_p_fnt}╭─${_p_rst} ${_p_dim}\\u${_p_fnt}@${_p_dim}\\h${_p_rst} ${_p_fnt}·${_p_rst} ${_p_ink}\\w${_p_rst}${rev}${err}"$'\n'"${_p_fnt}╰${_p_acc}▸${_p_rst} "
}
PROMPT_COMMAND=_sk_prompt

# ---- login banner ----------------------------------------------------
# Compact title block, once per terminal: shown when this shell's parent is a
# terminal emulator / multiplexer (not another shell), so nested shells and
# scripts stay quiet. SKEMOS_BANNER=0 disables it. (SHLVL is unreliable here —
# the whole session descends from one login shell, so every terminal is 2+.)
_sk_banner() {
  [[ ${SKEMOS_BANNER:-1} == 0 ]] && return
  [[ -t 1 ]] || return
  case $(ps -o comm= -p "${PPID:-0}" 2>/dev/null) in
    *sh|zsh|fish|nu|xonsh) return ;;   # nested under another shell — stay quiet
  esac

  local rule; printf -v rule '%s╶%s╸%s' "$_b_fnt" "$(printf '─%.0s' {1..54})" "$_b_rst"
  local kern host date
  kern=$(uname -r); host=$(uname -n)
  printf -v date '%(%Y-%m-%d %H:%M)T' -1

  printf '\n %s\n' "$rule"
  printf ' %sS K E M O S%s  %s·%s SESSION%18s%sSK-01%s\n' \
    "$_b_ink" "$_b_rst" "$_b_acc" "$_b_rst" '' "$_b_acc" "$_b_rst"
  printf ' %shost%s   %-20s %skernel%s  %s\n' "$_b_dim" "$_b_rst" "$host" "$_b_dim" "$_b_rst" "$kern"
  printf ' %suser%s   %-20s %sclock%s   %s\n'  "$_b_dim" "$_b_rst" "$USER" "$_b_dim" "$_b_rst" "$date"
  printf ' %s\n\n' "$rule"
}
_sk_banner
