#!/usr/bin/env bash
#
# Skemos — bare-metal bootstrap. Run AFTER a standard Arch base install,
# as your normal user (in group wheel), from a TTY:
#
#     ~/.config/install/bootstrap.sh
#
# Does only: hardware detection, pacman install, enable PipeWire +
# NetworkManager, font cache, SSH key offer, git-hook wiring, append the
# Hyprland launch line to ~/.bash_profile, source the Skemos shell dressing
# from ~/.bashrc, and install the security tooling (root-owned copies,
# systemd timers, sudoers rule, pacman hook, audit rules, ufw).
# Does NOT touch disks, partitioning, the bootloader or autologin. The only
# boot-adjacent action is a `mkinitcpio -P` you are asked to confirm, which
# rewrites the initramfs image(s) in /boot.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
say() { printf '\n\033[1m>> %s\033[0m\n' "$*"; }

# Identity values that feed the root-owned conf, the sudoers rule and the audit
# rules come from the passwd database, not the (user-controllable) environment.
SK_USER="$(id -un)"
SK_HOME="$(getent passwd "$(id -u)" | cut -d: -f6 || true)"
if [[ ! $SK_USER =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "bootstrap: refusing unusual username '$SK_USER'" >&2; exit 1
fi
if [[ $SK_HOME != /* || $SK_HOME == *[[:space:]]* || $SK_HOME == *\\* ]]; then
  echo "bootstrap: refusing unusual home directory '$SK_HOME'" >&2; exit 1
fi
[[ $SK_HOME == "$HOME" ]] || echo "bootstrap: note — \$HOME ($HOME) differs from the passwd home ($SK_HOME); using the passwd home for system config." >&2
# escape for use on the RHS of sed s|...|...|
SK_HOME_SED="$(printf '%s' "$SK_HOME" | sed 's/[&|\\]/\\&/g')"

# 1. hardware detection ---------------------------------------------------
# lspci (pciutils) is needed for detection, which runs before the package
# step — make sure it is there (official repo, tiny).
if ! command -v lspci >/dev/null 2>&1; then
  say "lspci not found — installing pciutils for hardware detection."
  sudo pacman -S --needed pciutils \
    || { echo "bootstrap: could not install pciutils (run 'sudo pacman -Sy pciutils' then re-run)" >&2; exit 1; }
fi
PCI_OUT="$(lspci -nn || true)"

detect_cpu_pkg() {
  case "$(grep -m1 '^vendor_id' /proc/cpuinfo | awk '{print $NF}' || true)" in
    AuthenticAMD) echo amd-ucode ;;
    GenuineIntel) echo intel-ucode ;;
    *) echo "" ;;
  esac
}

detect_gpu_pkgs() {
  # here-string, not a pipe: `grep -q` exiting early would SIGPIPE lspci and
  # pipefail would turn that into a false "no NVIDIA".
  if grep -Eq '(VGA compatible controller|3D controller).*\[10de:' <<<"$PCI_OUT"; then
    echo "nvidia-open-dkms linux-headers egl-wayland"
  fi
}

cpu_pkg="$(detect_cpu_pkg)"
gpu_pkgs="$(detect_gpu_pkgs)"

say "Detected CPU: $(grep -m1 '^model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//' || true) -> ${cpu_pkg:-'(unknown vendor — add your microcode package manually)'}"
say "Detected GPU(s):"
# No VGA/3D line (e.g. a VM's "Display controller") must not kill the script.
grep -E 'VGA compatible controller|3D controller' <<<"$PCI_OUT" | sed 's/^/   /' || true
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

# 3. nvidia system changes (confirm-before-apply) --------------------
if [[ -n $gpu_pkgs ]]; then
  say "NVIDIA detected — reviewing system-level changes. Each one asks"
  say "before touching /etc; none of this touches disks or the bootloader. (The only boot-adjacent step is a 'mkinitcpio -P' you confirm.)"

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
      SUDO_EDITOR="${EDITOR:-${VISUAL:-/usr/bin/nvim}}" sudoedit "$MKINITCPIO" \
        || say "  editor failed — edit $MKINITCPIO by hand, then run 'sudo mkinitcpio -P'."
      say "  'mkinitcpio -P' rewrites the initramfs image(s) in /boot (on systemd-boot layouts /boot is the ESP)."
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

# 4. audio --------------------------------------------------------------
say "Enabling PipeWire user services."
systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service

# 5. networking -------------------------------------------------------
say "Enabling NetworkManager."
sudo systemctl enable --now NetworkManager.service

# 6. fonts -----------------------------------------------------------
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

# 7. ssh readiness -----------------------------------------------------
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

# 8. git hooks (gitleaks secret scan) ----------------------------------
if [[ "$(git -C "$HOME/.config" config --get core.hooksPath 2>/dev/null)" != ".githooks" ]]; then
  say "Wiring the gitleaks pre-commit hook (git config core.hooksPath .githooks)."
  git -C "$HOME/.config" config core.hooksPath .githooks
else
  say "git hooks already wired — skipping."
fi

# 9. launch on login ----------------------------------------------
if ! grep -q 'start-hyprland' "$HOME/.bash_profile" 2>/dev/null; then
  say "Appending the Hyprland launch guard to ~/.bash_profile"
  printf '\n' >> "$HOME/.bash_profile"
  cat "$HERE/bash_profile.snippet" >> "$HOME/.bash_profile"
else
  say "~/.bash_profile already has a start-hyprland line — leaving it."
fi

# 10. shell dressing -------------------------------------------------
if ! grep -q 'bash/skemos.bash' "$HOME/.bashrc" 2>/dev/null; then
  say "Sourcing the Skemos shell dressing (prompt + banner) from ~/.bashrc"
  {
    printf '\n# Skemos shell dressing (title-block prompt + login banner).\n'
    printf '[[ -f ~/.config/bash/skemos.bash ]] && . ~/.config/bash/skemos.bash\n'
  } >> "$HOME/.bashrc"
fi

# 11. security tooling ---------------------------------------------------
say "Installing Skemos security tooling (systemd units, sudoers rule, pacman hook)."

SEC_SRC="$HERE/../security"

# group + per-machine config
if ! getent group skemos-security >/dev/null; then
  sudo groupadd skemos-security
fi
sudo usermod -aG skemos-security "$SK_USER"

# (lib.sh sources this as root, so values are shell-quoted with %q)
printf 'SKEMOS_USER=%q\nSKEMOS_HOME=%q\n' "$SK_USER" "$SK_HOME" \
  | sudo install -o root -g root -m 0644 /dev/stdin /etc/skemos-security.conf

# job scripts + shared lib -> root-owned, not user-writable
sudo install -d -o root -g root -m 0755 /usr/local/lib/skemos-security
sudo install -o root -g root -m 0755 \
  "$SEC_SRC/scripts/lib.sh" \
  "$SEC_SRC/scripts/integrity-check.sh" \
  "$SEC_SRC/scripts/rkhunter-scan.sh" \
  "$SEC_SRC/scripts/arch-audit-scan.sh" \
  "$SEC_SRC/scripts/ufw-status.sh" \
  "$SEC_SRC/scripts/audit-status.sh" \
  /usr/local/lib/skemos-security/

# dispatcher wrapper -> /usr/local/bin (the sudoers Cmnd target)
sudo install -o root -g root -m 0755 "$SEC_SRC/scripts/skemos-security-run" /usr/local/bin/skemos-security-run

# systemd units
sudo install -o root -g root -m 0644 "$SEC_SRC"/systemd/*.service "$SEC_SRC"/systemd/*.timer /etc/systemd/system/
sudo systemctl daemon-reload
# (timers are enabled at the very end, AFTER the first baseline seed, so a
# timer can never race it)

# sudoers (template substitution, validated before install; staged in a
# root-owned temp file so it is never user-writable between check and install)
tmp_sudoers="$(sudo mktemp)"
sudoers_ok=0
sed "s/__SKEMOS_USER__/$SK_USER/g" "$SEC_SRC/sudoers.d/skemos-security" | sudo tee "$tmp_sudoers" >/dev/null
if sudo visudo -c -f "$tmp_sudoers"; then
  sudo install -o root -g root -m 0440 "$tmp_sudoers" /etc/sudoers.d/skemos-security
  sudoers_ok=1
  say "  sudoers rule installed."
else
  say "  sudoers template failed validation — NOT installed (see visudo output above)."
fi
sudo rm -f "$tmp_sudoers"

# pacman hook
sudo install -d -o root -g root -m 0755 /etc/pacman.d/hooks
sudo install -o root -g root -m 0644 "$SEC_SRC/pacman-hooks/99-skemos-integrity-resync.hook" /etc/pacman.d/hooks/

# audit rules (template substitution)
sudo install -d -o root -g root -m 0750 /etc/audit/rules.d
# the ~/.ssh watch needs the directory to exist or auditctl rejects the rule
# (user-owned, created without sudo; ssh itself requires 0700)
install -d -m 0700 "$SK_HOME/.ssh"
sed "s|__SKEMOS_HOME__|$SK_HOME_SED|g" "$SEC_SRC/audit-rules/skemos.rules" | sudo install -o root -g root -m 0640 /dev/stdin /etc/audit/rules.d/skemos.rules
sudo systemctl enable --now auditd.service
sudo augenrules --load || say "  audit rules failed to load — check 'sudo auditctl -l'"

# ufw — default deny incoming, allow outgoing
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo systemctl enable ufw.service   # so the firewall comes back after a reboot
sudo ufw --force enable

# first-run initialization so the panel's first view isn't just "baseline created"
# (--rebaseline-all: hash system AND user paths; the pacman hook's plain
# --rebaseline deliberately never re-accepts user-file edits)
sudo /usr/local/lib/skemos-security/integrity-check.sh --rebaseline-all \
  || say "  first integrity baseline failed — the first timer run will create it; see /var/log/skemos-security/integrity.log"
sudo rkhunter --propupd || true

# timers last, so none of them can race the seed above
for t in skemos-integrity rkhunter-scan arch-audit-scan ufw-status audit-status; do
  sudo systemctl enable --now "$t.timer" || say "  could not enable $t.timer — check 'systemctl status $t.timer'"
done

say "Security tooling installed. Log out/in once for the skemos-security group to take effect."
if (( ! sudoers_ok )); then
  say "WARNING: sudoers rule NOT installed — SUPER+S run-now will not work until fixed."
fi

say "Done. Verify with 'Hyprland --verify-config', then log out and log back in."
