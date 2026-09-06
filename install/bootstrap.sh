#!/usr/bin/env bash
#
# Skemos — bare-metal bootstrap. Run AFTER a standard Arch base install,
# as your normal user (in group wheel), from a TTY:
#
#     ~/.config/install/bootstrap.sh
#
# Does only: pacman install, enable PipeWire + NetworkManager, font cache,
# append the Hyprland launch line to ~/.bash_profile.
# Does NOT touch disks, the ESP, the bootloader, or enable autologin.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
say() { printf '\n\033[1m>> %s\033[0m\n' "$*"; }

# 1. packages -------------------------------------------------------------
mapfile -t PKGS < <(sed -E 's/#.*//' "$HERE/packages.txt" | tr -s ' \t' '\n' | grep -E '^[a-z0-9]')
say "Install / verify ${#PKGS[@]} packages:"
printf '   %s\n' "${PKGS[@]}"
say "Add your CPU microcode (amd-ucode / intel-ucode) and, for NVIDIA, the"
say "nvidia packages — edit packages.txt first if you have not."
read -r -p "   Enter to run 'sudo pacman -Syu --needed ...', Ctrl-C to abort. " _
sudo pacman -Syu --needed "${PKGS[@]}"

# 2. audio --------------------------------------------------------------
say "Enabling PipeWire user services."
systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service

# 3. networking -------------------------------------------------------
say "Enabling NetworkManager."
sudo systemctl enable --now NetworkManager.service

# 4. fonts -----------------------------------------------------------
say "Rebuilding font cache."
fc-cache -f

# 5. launch on login ----------------------------------------------
if ! grep -q 'start-hyprland' "$HOME/.bash_profile" 2>/dev/null; then
  say "Appending the Hyprland launch guard to ~/.bash_profile"
  printf '\n' >> "$HOME/.bash_profile"
  cat "$HERE/bash_profile.snippet" >> "$HOME/.bash_profile"
else
  say "~/.bash_profile already has a start-hyprland line — leaving it."
fi

say "Done. Verify with 'Hyprland --verify-config', then log out and log back in."
