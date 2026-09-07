#!/usr/bin/env bash
#
# Skemos — bare-metal bootstrap. Run AFTER a standard Arch base install,
# as your normal user (in group wheel), from a TTY:
#
#     ~/.config/install/bootstrap.sh
#
# Does only: pacman install, enable PipeWire + NetworkManager, font cache,
# append the Hyprland launch line to ~/.bash_profile, source the Skemos shell
# dressing from ~/.bashrc.
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
# Departure Mono (waybar chrome) is AUR-only. If it is not installed, drop the
# OFL OTF into the per-user font dir — no root needed.
if ! fc-list | grep -qi 'Departure Mono'; then
  say "Fetching Departure Mono into ~/.local/share/fonts (or: yay -S otf-departure-mono)"
  dmurl="https://github.com/rektdeckard/departure-mono/releases/download/v1.500/DepartureMono-1.500.zip"
  if tmp="$(mktemp -d)" && curl -fsSL -o "$tmp/dm.zip" "$dmurl"; then
    mkdir -p "$HOME/.local/share/fonts/DepartureMono"
    bsdtar -xf "$tmp/dm.zip" -C "$tmp" 2>/dev/null || unzip -oq "$tmp/dm.zip" -d "$tmp"
    find "$tmp" -iname '*.otf' -exec cp {} "$HOME/.local/share/fonts/DepartureMono/" \;
    rm -rf "$tmp"
  else
    say "  (fetch failed — waybar will fall back to Iosevka; install it later)"
  fi
fi
fc-cache -f

# 5. launch on login ----------------------------------------------
if ! grep -q 'start-hyprland' "$HOME/.bash_profile" 2>/dev/null; then
  say "Appending the Hyprland launch guard to ~/.bash_profile"
  printf '\n' >> "$HOME/.bash_profile"
  cat "$HERE/bash_profile.snippet" >> "$HOME/.bash_profile"
else
  say "~/.bash_profile already has a start-hyprland line — leaving it."
fi

# 6. shell dressing -------------------------------------------------
if ! grep -q 'bash/skemos.bash' "$HOME/.bashrc" 2>/dev/null; then
  say "Sourcing the Skemos shell dressing (prompt + banner) from ~/.bashrc"
  {
    printf '\n# Skemos shell dressing (title-block prompt + login banner).\n'
    printf '[[ -f ~/.config/bash/skemos.bash ]] && . ~/.config/bash/skemos.bash\n'
  } >> "$HOME/.bashrc"
fi

say "Done. Verify with 'Hyprland --verify-config', then log out and log back in."
