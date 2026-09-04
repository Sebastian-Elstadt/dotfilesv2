#!/usr/bin/env bash
# Night Vellum — lock wrapper.
# Runs hyprlock, but if hyprlock dies within a few seconds while the session is
# still locked (e.g. a GPU/aquamarine crash under a VM's software GL), release
# the lock so you are never stuck on a dead lock screen.
# On real hardware hyprlock stays up and this wrapper is a no-op.

pidof hyprlock >/dev/null 2>&1 && exit 0

hyprlock &
lp=$!

sleep 3
if ! kill -0 "$lp" 2>/dev/null; then
  loginctl unlock-session 2>/dev/null || true
  command -v notify-send >/dev/null && \
    notify-send -u critical "hyprlock exited" "session auto-unlocked — check GPU / 3D accel"
fi
