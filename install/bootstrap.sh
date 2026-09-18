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

# 1. hardware detection ---------------------------------------------------
detect_cpu_pkg() {
  case "$(grep -m1 '^vendor_id' /proc/cpuinfo | awk '{print $NF}')" in
    AuthenticAMD) echo amd-ucode ;;
    GenuineIntel) echo intel-ucode ;;
    *) echo "" ;;
  esac
}

detect_gpu_pkgs() {
  if lspci -nn 2>/dev/null | grep -Eq '(VGA compatible controller|3D controller).*\[10de:'; then
    echo "nvidia-open-dkms linux-headers egl-wayland"
  fi
}

cpu_pkg="$(detect_cpu_pkg)"
gpu_pkgs="$(detect_gpu_pkgs)"

say "Detected CPU: $(grep -m1 '^model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//') -> ${cpu_pkg:-'(unknown vendor — add your microcode package manually)'}"
say "Detected GPU(s):"
lspci -nn 2>/dev/null | grep -E 'VGA compatible controller|3D controller' | sed 's/^/   /'
if [[ -n $gpu_pkgs ]]; then
  say "  -> NVIDIA present, adding: $gpu_pkgs"
fi

# 2. packages ---------------------------------------------------------
mapfile -t PKGS < <(sed -E 's/#.*//' "$HERE/packages.txt" | tr -s ' \t' '\n' | grep -E '^[a-z0-9]')
ALL_PKGS=("${PKGS[@]}" mesa)
[[ -n $cpu_pkg ]] && ALL_PKGS+=("$cpu_pkg")
[[ -n $gpu_pkgs ]] && ALL_PKGS+=($gpu_pkgs)

say "Install / verify ${#ALL_PKGS[@]} packages:"
printf '   %s\n' "${ALL_PKGS[@]}"
read -r -p "   Enter to run 'sudo pacman -Syu --needed ...', Ctrl-C to abort. " _
sudo pacman -Syu --needed "${ALL_PKGS[@]}"

# 2. nvidia system changes (confirm-before-apply) --------------------
if [[ -n $gpu_pkgs ]]; then
  say "NVIDIA detected — reviewing system-level changes. Each one asks"
  say "before touching /etc; none of this touches the bootloader or disks."

  NOUVEAU_CONF=/etc/modprobe.d/nouveau-blacklist.conf
  if [[ -f $NOUVEAU_CONF ]] && grep -q '^blacklist nouveau' "$NOUVEAU_CONF" 2>/dev/null; then
    say "  $NOUVEAU_CONF already blacklists nouveau — skipping."
  else
    echo "  Would create $NOUVEAU_CONF containing: blacklist nouveau"
    read -r -p "  Apply? [y/N] " a
    if [[ $a == y || $a == Y ]]; then
      echo "blacklist nouveau" | sudo tee "$NOUVEAU_CONF" >/dev/null
    fi
  fi

  MKINITCPIO=/etc/mkinitcpio.conf
  if grep -qE '^MODULES=.*nvidia' "$MKINITCPIO" 2>/dev/null; then
    say "  $MKINITCPIO already lists an nvidia module set — skipping."
  else
    say "  $MKINITCPIO needs an nvidia module set, e.g.:"
    say '    MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)'
    read -r -p "  Open it in \$EDITOR now? [y/N] " a
    if [[ $a == y || $a == Y ]]; then
      sudo "${EDITOR:-vi}" "$MKINITCPIO"
      read -r -p "  Run 'sudo mkinitcpio -P' now (needed for the change to take effect)? [y/N] " b
      [[ $b == y || $b == Y ]] && sudo mkinitcpio -P
    fi
  fi

  for svc in nvidia-suspend nvidia-resume nvidia-persistenced; do
    if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
      say "  $svc.service already enabled — skipping."
    else
      read -r -p "  Enable $svc.service (needed for suspend/resume to work)? [Y/n] " a
      [[ $a != n && $a != N ]] && sudo systemctl enable "$svc"
    fi
  done

  say "  Kernel cmdline still needs (bootloader-specific, manual — see INSTALL.md §4):"
  say "    nvidia_drm.modeset=1 nvidia.NVreg_PreserveVideoMemoryAllocations=1"
fi

# 3. audio --------------------------------------------------------------
say "Enabling PipeWire user services."
systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service

# 4. networking -------------------------------------------------------
say "Enabling NetworkManager."
sudo systemctl enable --now NetworkManager.service

# 5. fonts -----------------------------------------------------------
say "Rebuilding font cache."
# Departure Mono (waybar chrome) is AUR-only. If it is not installed, drop the
# OFL OTF into the per-user font dir — no root needed.
if ! fc-list | grep -qi 'Departure Mono'; then
  say "Fetching Departure Mono into ~/.local/share/fonts (or: yay -S otf-departure-mono)"
  dmurl="https://github.com/rektdeckard/departure-mono/releases/download/v1.500/DepartureMono-1.500.zip"
  dmsha256="bf3e48059aeef4617ec585bdea81dcc3491c576b3e7a472f52faf40e09ee5c3a"
  if tmp="$(mktemp -d)" && curl -fsSL -o "$tmp/dm.zip" "$dmurl"; then
    if echo "$dmsha256  $tmp/dm.zip" | sha256sum -c - >/dev/null 2>&1; then
      mkdir -p "$HOME/.local/share/fonts/DepartureMono"
      bsdtar -xf "$tmp/dm.zip" -C "$tmp" 2>/dev/null || unzip -oq "$tmp/dm.zip" -d "$tmp"
      find "$tmp" -iname '*.otf' -exec cp {} "$HOME/.local/share/fonts/DepartureMono/" \;
    else
      say "  Checksum mismatch on Departure Mono download — refusing to install it."
      say "  Expected $dmsha256"
      say "  Got      $(sha256sum "$tmp/dm.zip" | awk '{print $1}')"
    fi
    rm -rf "$tmp"
  else
    say "  (fetch failed — waybar will fall back to Iosevka; install it later)"
  fi
fi
fc-cache -f

# 6. ssh readiness -----------------------------------------------------
say "Checking SSH readiness."
if ! compgen -G "$HOME/.ssh/id_ed25519" >/dev/null && ! compgen -G "$HOME/.ssh/id_rsa" >/dev/null; then
  read -r -p "  No SSH keypair found. Generate one now (ed25519)? [Y/n] " a
  if [[ $a != n && $a != N ]]; then
    ssh-keygen -t ed25519 -C "$USER@$(uname -n)" -f "$HOME/.ssh/id_ed25519"
    say "  Public key (add this to GitHub/GitLab/wherever you push):"
    cat "$HOME/.ssh/id_ed25519.pub"
  fi
else
  say "  SSH keypair already present — skipping."
fi

# 7. git hooks (gitleaks secret scan) ----------------------------------
if [[ "$(git -C "$HOME/.config" config --get core.hooksPath 2>/dev/null)" != ".githooks" ]]; then
  say "Wiring the gitleaks pre-commit hook (git config core.hooksPath .githooks)."
  git -C "$HOME/.config" config core.hooksPath .githooks
else
  say "git hooks already wired — skipping."
fi

# 8. launch on login ----------------------------------------------
if ! grep -q 'start-hyprland' "$HOME/.bash_profile" 2>/dev/null; then
  say "Appending the Hyprland launch guard to ~/.bash_profile"
  printf '\n' >> "$HOME/.bash_profile"
  cat "$HERE/bash_profile.snippet" >> "$HOME/.bash_profile"
else
  say "~/.bash_profile already has a start-hyprland line — leaving it."
fi

# 9. shell dressing -------------------------------------------------
if ! grep -q 'bash/skemos.bash' "$HOME/.bashrc" 2>/dev/null; then
  say "Sourcing the Skemos shell dressing (prompt + banner) from ~/.bashrc"
  {
    printf '\n# Skemos shell dressing (title-block prompt + login banner).\n'
    printf '[[ -f ~/.config/bash/skemos.bash ]] && . ~/.config/bash/skemos.bash\n'
  } >> "$HOME/.bashrc"
fi

say "Done. Verify with 'Hyprland --verify-config', then log out and log back in."
