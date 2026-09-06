# Night Vellum — install on bare metal

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
git -C ~/.config bundle create /mnt/usb/night-vellum.bundle --all
```

**On the new machine**, `~/.config` already has stray files from first boot.
The whitelist `.gitignore` means you can lay the repo over the top of them:

```sh
cd ~/.config
git init
git remote add origin <url-or-/path/to/night-vellum.bundle>
git fetch origin
git checkout -f master
git branch --set-upstream-to=origin/master master
```

`git status` should now be clean (stray files stay ignored).

---

## 3 · Packages + system setup

```sh
# Edit first if you have NVIDIA or want kitty as default (see §5):
$EDITOR ~/.config/install/packages.txt

~/.config/install/bootstrap.sh
```

`bootstrap.sh` runs `sudo pacman -Syu --needed` on the list, enables PipeWire +
NetworkManager, rebuilds the font cache, and appends the Hyprland launch line to
`~/.bash_profile`. It never touches disks, the ESP, the bootloader, or autologin.
Review it before running — it is the only privileged step.

---

## 4 · GPU

- **AMD / Intel only** — `mesa` (in the list) is all you need.
- **NVIDIA** — reference <https://wiki.hypr.land/Nvidia/>. What `saber`
  (RTX 5070, `nvidia-open` 610) actually runs, all confirmed working:

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
  6. Multi-GPU render node is pinned in `hypr/hyprland.lua` via `AQ_DRM_DEVICES`
     (NVIDIA card first, by stable PCI path). Adjust the PCI addresses if the
     hardware differs — `lspci -k | grep -A2 VGA`.
  7. `__GLX_VENDOR_LIBRARY_NAME=nvidia` is set in `hypr/hyprland.lua`. HW video
     decode (`LIBVA_DRIVER_NAME`) is deliberately not set — the VAAPI bridge is
     AUR-only; add `libva-nvidia-driver` yourself if you want it.

---

## 5 · Optional config choices

All under `~/.config/`, committed — edit and `git commit` your machine's choices.

| Want | Change |
|---|---|
| **kitty** as the terminal instead of foot | `hypr/binds.lua`: `local terminal = "kitty"` |
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
| `SUPER`+`SHIFT`+`SPACE` | toggle TILE ↔ DESK on the current workspace |
| `SUPER`+`SPACE` | float / tile the active window |
| `SUPER`+`M` / `SUPER`+`SHIFT`+`M` | minimize to drawer / toggle drawer |
| `SUPER`+`L` | lock · `SUPER`+`SHIFT`+`E` logout |
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

## 9 · Plugins — borders-plus-plus

The per-window double rule (`hypr/plugins.lua`) needs one out-of-band install.
Toolchain (`cmake meson ninja`) is in `packages.txt`.

```sh
hyprpm update                                              # builds against the running Hyprland
hyprpm add https://github.com/hyprwm/hyprland-plugins
hyprpm enable borders-plus-plus
hyprctl reload
```

`autostart.lua` runs `hyprpm reload -n` on session start, so it persists. Until
it's enabled, `plugins.lua` just logs `unknown config key 'plugin.borders_plus_plus.*'`
— harmless. Rebuild after every Hyprland upgrade: `hyprpm update`.
