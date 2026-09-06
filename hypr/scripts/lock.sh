#!/usr/bin/env bash
# Skemos — lock wrapper.
#
# Runs hyprlock and watches it for its WHOLE lifetime. hyprlock exits 0 only on
# a clean password unlock; any non-zero exit (crash, OOM-kill, SIGKILL, a config
# error that makes it bail) means the session may be stuck locked with a dead or
# frozen lock surface — so we force it back open. This is the recovery path for
# "screen says locked but the lockscreen app died".

pidof hyprlock >/dev/null 2>&1 && exit 0

# Detach the watchdog so hypridle's lock_cmd returns immediately.
setsid --fork bash -c '
  hyprlock --grace 0
  ec=$?
  if [ "$ec" -ne 0 ]; then
    loginctl unlock-session 2>/dev/null || true
    hyprctl dispatch "hl.clear_crashed_lockscreen()" >/dev/null 2>&1 || true
    command -v notify-send >/dev/null 2>&1 && \
      notify-send -u critical "hyprlock exited ($ec)" \
        "screen was auto-unlocked — check hyprlock.conf / GPU"
  fi
'
