#!/usr/bin/env bash
# Skemos — OPTIONAL Claude Code install (called by bootstrap.sh).
#
# Claude Code is not in the official Arch repos, so this is a deliberate,
# documented exception to the "official repos only" rule: opt-in (default No),
# never run non-interactively, never as root, never via npm/AUR, and the
# installer is downloaded to a file (not piped to a shell). Anthropic's
# installer verifies the binary against a checksum manifest fetched from the
# same host — that catches corruption, not a compromised origin.
# Every failure here is non-fatal: the panel's analyze action just stays off.
set -uo pipefail
say()  { printf '\n\033[1m>> %s\033[0m\n' "$*"; }
warn() { printf '   note: %s\n' "$*" >&2; }
URL=https://claude.ai/install.sh

[[ $EUID -ne 0 ]] || { echo "claude-code.sh: refusing to run as root (it installs into your home)" >&2; exit 1; }

if command -v claude >/dev/null 2>&1 || [[ -x $HOME/.local/bin/claude ]]; then
  say "Claude Code already installed — skipping."
  exit 0
fi
if [[ ! -t 0 ]]; then
  say "Claude Code not installed (non-interactive run, skipped). To install later: see INSTALL.md, 'Claude Code'."
  exit 0
fi

say "Claude Code (optional): powers the 'analyze with Claude' action in SUPER+S."
echo "   It is NOT in the official Arch repos; this uses Anthropic's own installer"
echo "   (downloaded to a file, run as you, into ~/.local — never sudo)."
echo "   Skip this on machines where sending data to an external AI is not allowed."
read -r -p "   Install Claude Code? [y/N] " a || a=n
[[ $a == [yY]* ]] || { say "Skipping Claude Code."; exit 0; }

tmp=$(mktemp -d) || { warn "could not create a temp dir"; exit 0; }
trap 'rm -rf -- "$tmp"' EXIT
if ! curl -fsSL --proto '=https' --tlsv1.2 -m 60 -o "$tmp/install.sh" "$URL"; then
  warn "download failed — skipping. Retry later (see INSTALL.md)."
  exit 0
fi
size=$(wc -c < "$tmp/install.sh")
if (( size < 1000 )) || ! head -1 "$tmp/install.sh" | grep -q '^#!'; then
  warn "downloaded file does not look like the installer (${size} bytes) — skipping."
  exit 0
fi
say "Downloaded installer: ${size} bytes, sha256 $(sha256sum < "$tmp/install.sh" | cut -d' ' -f1)"
if bash "$tmp/install.sh"; then
  say "Claude Code installed. Run 'claude' once to sign in; the panel then enables the analyze action."
else
  warn "the installer reported a failure — Claude Code is not installed."
fi
exit 0
