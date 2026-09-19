# Skemos — install on bare metal

Getting this rice onto a fresh Arch machine. Assumes a UEFI dual-boot target.

The config auto-adapts: `hypr/autostart.lua` detects a VM and skips the wallpaper
daemon there, so on real hardware `hyprpaper`, `hyprlock` and `kitty` all just
work with no edits.

---

## 0 · Base Arch install

Do a **standard Arch base install** — your partitioning, your bootloader. This
guide does not touch disks. Recommended choices:

- UEFI boot; keep or create an ESP you share with the other OS
- `base base-devel linux linux-firmware linux-headers` + your **microcode**
  (`amd-ucode` or `intel-ucode`)
- a bootloader (systemd-boot or GRUB) — set it up for dual-boot as you prefer
- `git` and `networkmanager` (bootstrap installs the rest)
- a **normal user in group `wheel`**, with `sudo` for `wheel` enabled
- **no** desktop environment, **no** display manager

Boot into the new system and log in as your user on tty1.

Reference: <https://wiki.archlinux.org/title/Installation_guide>

---

## 1 · Network + git

```sh
nmtui                     # or: nmcli device wifi connect "SSID" --ask
sudo pacman -S --needed git
```

---

## 2 · Get the dotfiles

The repo currently lives only on the VM. **On the VM**, push it somewhere you
can reach from the new machine — a private GitHub repo, your own git host, or a
bundle on a USB stick:

```sh
# VM — pick one:
git -C ~/.config remote add origin git@github.com:<you>/dotfiles.git
git -C ~/.config push -u origin master
#   …or bundle to a USB stick:
git -C ~/.config bundle create /mnt/usb/skemos.bundle --all
```

**On the new machine**, `~/.config` already has stray files from first boot.
The whitelist `.gitignore` means you can lay the repo over the top of them:

```sh
cd ~/.config
git init
git remote add origin <url-or-/path/to/skemos.bundle>
git fetch origin
git checkout -f master
git branch --set-upstream-to=origin/master master
```

`git status` should now be clean (stray files stay ignored).

---

## 3 · Packages + system setup

```sh
# Optional: review the list first (choosing kitty is a §5 config choice, not a package edit).
less ~/.config/install/packages.txt

~/.config/install/bootstrap.sh
```

`bootstrap.sh` auto-detects your CPU vendor and GPU (adding microcode and,
if NVIDIA is present, the NVIDIA package set automatically — no more
hand-editing `packages.txt`), then runs `sudo pacman -Syu --needed` on the
combined list. It enables PipeWire + NetworkManager, rebuilds the font
cache (fetching Departure Mono into `~/.local/share/fonts`, checksum-
verified, if not already installed), offers to generate an SSH keypair if
you don't have one, wires the `gitleaks` pre-commit hook, appends the
Hyprland launch line to `~/.bash_profile`, sources the Skemos shell
dressing from `~/.bashrc`, enables `ufw` with default-deny-incoming /
allow-outgoing, enables `auditd` with watch rules for `~/.ssh`, `/etc/shadow`,
`/etc/sudoers.d`, `/etc/pacman.d`, and `/etc/passwd`, and installs the
security-monitoring tooling (systemd units, a scoped sudoers rule, a pacman
hook, audit rules — see `SKEMOS.md` "Security"). Any NVIDIA kernel-module/initramfs/nouveau-
blacklist change is shown to you and asks before touching `/etc`. It does not
touch disks, partitioning, the bootloader or autologin; the only boot-adjacent
action is a `mkinitcpio -P` you are asked to confirm, which rewrites the
initramfs image(s) in `/boot`. Review it before running — it is the only
privileged step.

### Boot straight into the schematic lock screen

There is no display manager. By default boot lands on the bare `agetty` text
prompt; you log in and `~/.bash_profile` starts Hyprland. To instead see the
`hyprlock` screen (the `SUPER+L` look) as the boot login, autologin `bas` on
tty1 and let Hyprland come up locked — `autostart.lua` runs `lock.sh` first, so
the schematic screen with its password field is the first thing on screen.

```sh
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf >/dev/null <<'EOF'
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin bas --noclear %I $TERM
EOF
sudo systemctl daemon-reload
```

Trade-off: the console itself no longer asks for a password, so physical access
= a shell in the ~1 s before `hyprlock` paints, and a logged-in tty1 if Hyprland
ever fails to start. Acceptable on a personal box without disk encryption; if
that matters, skip this and keep the text login. To undo:
`sudo rm /etc/systemd/system/getty@tty1.service.d/autologin.conf && sudo systemctl daemon-reload`.

---

## 4 · GPU

- **AMD / Intel only** — `mesa` (in the list) is all you need.
- **NVIDIA** — reference <https://wiki.hypr.land/Nvidia/>. What `saber`
  (RTX 5070, `nvidia-open` 610) actually runs, all confirmed working. (Note:
  steps 1, 3, 4, and 5 below — packages, mkinitcpio, nouveau blacklist, and
  suspend/resume services — are now automated/prompted by `bootstrap.sh`; step
  2, kernel cmdline, and step 6, `AQ_DRM_DEVICES` primary-GPU pin, remain
  manual.)

  1. Packages: `mesa nvidia-open-dkms nvidia-utils linux-headers egl-wayland`
     (`mesa` stays — the box also has an AMD iGPU).
  2. Kernel cmdline: `nvidia_drm.modeset=1 nvidia.NVreg_PreserveVideoMemoryAllocations=1`
  3. `/etc/mkinitcpio.conf`: `MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)`,
     then `sudo mkinitcpio -P`.
  4. `/etc/modprobe.d/nouveau-blacklist.conf` → `blacklist nouveau`
     (the `kms` hook would otherwise pull nouveau into the initramfs).
  5. **Suspend/resume** — without these the `PreserveVideoMemoryAllocations`
     flag is a no-op and resume black-screens:
     `sudo systemctl enable nvidia-suspend.service nvidia-resume.service nvidia-persistenced.service`
  6. **The monitor is on a DP port of the NVIDIA card**, so the NVIDIA card is
     pinned primary in `hypr/hyprland.lua` via
     `AQ_DRM_DEVICES=/dev/dri/card0:/dev/dri/card1` (first = primary). Without
     this, Aquamarine's primary pick races each boot; when the iGPU wins it
     renders the desktop on the iGPU and copies every frame to the NVIDIA card
     for scanout (latency, no direct scanout, 5070 idle). `card0` = NVIDIA
     because `nvidia_drm` is in the initramfs `MODULES` and claims DRM minor 0
     before `amdgpu` loads. Plain node paths only — `/dev/dri/by-path/*`
     symlinks crash Aquamarine 0.15 (`CBackend::create() failed!`). Verify the
     mapping with `ls -l /dev/dri/by-path/pci-0000:01:00.0-card`; if a monitor
     is instead wired to the motherboard (iGPU) port, drop this env or list the
     iGPU first.
  7. `__GLX_VENDOR_LIBRARY_NAME=nvidia` is set in `hypr/hyprland.lua`. HW video
     decode (`LIBVA_DRIVER_NAME`) is deliberately not set — the VAAPI bridge is
     AUR-only; add `libva-nvidia-driver` yourself if you want it.

---

## 5 · Optional config choices

All under `~/.config/`, committed — edit and `git commit` your machine's choices.

| Want | Change |
|---|---|
| **kitty** as the terminal instead of foot | `hypr/binds.lua`: `local terminal = "kitty"` |
| Drop the shell **login banner** (keep the prompt) | `export SKEMOS_BANNER=0` in `~/.bashrc`; or remove the `skemos.bash` source line for both |
| A specific mode / scale / position for your panel | `hypr/monitors.lua`: add `hl.monitor({ output = "eDP-1", mode = "...", scale = 1.5, position = "auto" })` **above** the wildcard rule |
| Suspend on long idle | `hypr/hypridle.conf`: uncomment the `systemctl suspend` listener |
| Different lock / dim / dpms timeouts | `hypr/hypridle.conf` |
| HiDPI | set `scale` in `hypr/monitors.lua`; the fonts are already sized for ~1× — bump `font_size` in `foot/foot.ini`, `kitty/kitty.conf`, `waybar/style.css` if needed |

The backlight-dim idle step and the `brightnessctl` / `XF86MonBrightness` binds
are no-ops in the VM and become live on a real panel — nothing to enable.

---

## 6 · First launch

```sh
Hyprland --verify-config      # expect: config ok
```

Log out of the TTY and log back in — `~/.bash_profile` runs `start-hyprland`.
(To start manually instead, comment that block out and run `start-hyprland`.)
With the tty1 autologin drop-in from §3 in place, a reboot goes straight to the
`hyprlock` screen; without it you get the text login first, then the same
`hyprlock` gate once Hyprland starts.

You should get: the schematic-sheet wallpaper (first generation takes a few
seconds), the thin top bar, `SUPER+Return` → foot, `SUPER+D` / `SUPER+R` → rofi.

Sanity checks:

```sh
hyprctl monitors             # confirm resolution / refresh / scale
hyprctl binds | wc -l        # ~60 binds
systemctl --user status hyprpolkitagent
```

---

## 7 · Keybinds

| Bind | Action |
|---|---|
| `SUPER`+`Q` (or `Return`) | terminal · `SUPER`+`D` / `SUPER`+`R` rofi · `SUPER`+`C` close |
| `SUPER`+`W` | window switcher — search all windows on all workspaces, jump to one |
| `ALT`+`TAB` / `ALT`+`SHIFT`+`TAB` | walk windows in most-recently-used order (tap to go further) |
| `SUPER`+`G` · `SUPER`+`]` / `[` | group bars (trial) — fold window in/out of a tab stack · next / prev tab |
| `SUPER`+`SHIFT`+`SPACE` | toggle TILE ↔ DESK on the current workspace |
| `SUPER`+`SPACE` | float / tile the active window |
| `SUPER`+`M` / `SUPER`+`SHIFT`+`M` | minimize to drawer / toggle drawer |
| `SUPER`+`L` | lock · `SUPER`+`SHIFT`+`E` logout |
| `SUPER`+`S` | security panel (left edge, toggles) — job status, live log pane |
| `SUPER`+arrows / `SUPER`+`SHIFT`+arrows | move focus / move window |
| `SUPER`+`1`‥`0` (+`SHIFT`) | workspace (move window) |
| `SUPER`+`F` fullscreen · `SUPER`+`P` pseudo · `SUPER`+`J` split |
| `SUPER`+`V` clipboard history · `Print` / `SUPER`+`Print` / `SHIFT`+`Print` screenshots |

---

## 8 · What differs from the VM

- Wallpaper daemon (`hyprpaper`), `hyprlock` render, and `kitty` render — all
  broken on the VM's software GL, all fine here. No action needed; the VM check
  in `autostart.lua` flips automatically.
- `~/.bash_profile` uses `start-hyprland` (not `uwsm`).
- Snapshots: there is no VirtualBox snapshot to fall back on. If root is Btrfs,
  consider `snapper`; otherwise rely on the git history of `~/.config`.

---

## 9 · Plugins

None. `borders-plus-plus` was tried (v1.0 only exposes one extra border, drawn
adjacent to the native one — no gap, no corner brackets) and dropped: it just
stacked a second border on every window and its plugin-drawn border didn't fade
with the window on a workspace switch. Window framing is native now
(`border_size = 2`, white active / faint inactive in `look.lua`).

If it was enabled on this machine, undo it:

```sh
hyprpm disable borders-plus-plus
hyprpm remove hyprland-plugins     # optional
```

---

## 10 · Security

`bootstrap.sh` installs a small self-monitoring layer: a daily file-
integrity check, weekly `rkhunter` + `arch-audit` scans, hourly `ufw`/
`auditd` status snapshots, all operable from `SUPER+S`. See `SKEMOS.md`
"Security" for the full model and
`docs/superpowers/specs/2026-09-17-security-hardening-and-containment-design.md`
for the design rationale.

A few things worth knowing on a fresh install:
- You'll be added to a new `skemos-security` group — **log out and back in**
  once for that to take effect (group membership doesn't apply to an
  already-running session).
- `ufw` is turned on with default-deny-incoming / allow-outgoing, and `auditd`
  is enabled with watch rules for `~/.ssh`, `/etc/shadow`, `/etc/sudoers.d`,
  `/etc/pacman.d`, and `/etc/passwd` — both tracked by hourly status snapshots
  in the `SUPER+S` panel.
- `sshd` is installed but never auto-enabled. If you turn on inbound SSH
  (`sudo systemctl enable --now sshd`), also add `sudo ufw allow ssh` and
  consider adding `fail2ban` (not installed by default — nothing to guard
  while `sshd` is off).
- The integrity check WARNs when `~/.bashrc`, `~/.bash_profile` or
  `hypr/{hyprland,binds,look}.lua` change, and that WARN **persists** across
  `pacman` upgrades (the pacman hook only re-baselines system paths). After an
  edit you made on purpose, accept it with
  `skemos-integrity --rebaseline-all`.
  The watch list also covers `/etc/sudoers.d`, `/usr/local/lib/skemos-security`
  and `/usr/local/bin/skemos-security-run` (the root-executed tooling).
- `sudo lynis audit system` is available any time for a deeper, on-demand
  posture check — it's installed but intentionally not wired into the
  automated/notified flow (its output is long-form, better read directly).

### Claude Code (optional) — "analyze with Claude"

`bootstrap.sh` ends by asking `Install Claude Code? [y/N]` (default **No**,
skipped on non-interactive runs). Claude Code is **not** in the official Arch
repos, so this is the one deliberate exception to "official repos only": it
runs Anthropic's own installer, downloaded to a file (never piped to a shell),
as you, into `~/.local` — no sudo, no npm, no AUR. The installer checks the
binary against a checksum manifest from the same host, which catches a
corrupted download but not a compromised origin. **Answer N on any machine
where sending data to an external AI service is not allowed.**

Install by hand later (read it first, then run it):

```sh
curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh
less /tmp/claude-install.sh && bash /tmp/claude-install.sh   # then run `claude` once to sign in
```

Once `claude` is installed and signed in, the `SUPER+S` panel enables `a`
(*analyze with Claude*): it snapshots the selected tool's log into a private
tmpfs directory, opens a new terminal that shows what will be sent, and only
after you press **Enter** starts a Claude session that can *only read* those
two files (`--tools "Read,Grep,Glob"` — no shell, no edits, no web, no MCP).
Claude recommends commands; you run them yourself. The log (hostnames, paths,
hashes, firewall/audit events) goes to Anthropic under your account, and the
temp directory is deleted when the terminal closes.

**Without the panel** (plain shell, no `SUPER+S`):

```sh
sudo skemos-security-run <integrity|rkhunter|arch-audit|ufw-status|audit-status>
less /var/log/skemos-security/<job>.log
cat /var/log/skemos-security/<job>.summary.json
systemctl list-timers
```
