# SKEMOS — rice status & handoff

A Hyprland rice: the **look** of a high-tech schematics / blueprint terminal
(Anduril / Hadrian / Saronic — corner brackets, registration marks, schema
lines, title-block framing). Not the *feel* of e-ink — motion is fast and
mechanical, not slow fades. (Renamed from "Night Vellum".)

This file is the running log so any session can pick up. `INSTALL.md` is the
bare-metal setup guide; this is "where we are and why".

---

## Machine

`saber` — bare-metal desktop, migrated off a Windows VM Sept 2026.

- **GPU**: NVIDIA RTX 5070 (`nvidia-open` 610, PCI `01:00.0`, `card0`) **+** AMD
  Granite Ridge iGPU (`12:00.0`, `card1`). `mesa` stays installed (iGPU + GL
  loader). The NVIDIA card is pinned primary via
  `AQ_DRM_DEVICES=/dev/dri/card0:/dev/dri/card1` in `hyprland.lua` — see below.
- **Display**: single `DP-1`, 2560×1440@180 (`monitors.lua` asks `highrr`), scale
  1 — **wired to a DP port on the
  NVIDIA card** (`card0-DP-1`), which is why NVIDIA must be the primary render
  node (else every frame is rendered on the iGPU and PCIe-copied to NVIDIA just
  to scan out). Resolution hardcoded in `hypr/shaders/skemos.frag`, figured live
  by `hypr/scripts/wallpaper.sh`.
- **Launch**: `~/.bash_profile` → `exec start-hyprland` on tty1 (not uwsm, not a
  display manager). `~/.bash_profile` is NOT in the repo.
- **Hyprland 0.56.2**, Lua config.

## Stability (done)

- `systemctl enable nvidia-suspend nvidia-resume nvidia-persistenced` — without
  these, resume from suspend black-screens (the cmdline
  `NVreg_PreserveVideoMemoryAllocations=1` is a no-op alone).
- `/etc/modprobe.d/nouveau-blacklist.conf` → `blacklist nouveau`; `mkinitcpio -P`.
- `AQ_DRM_DEVICES=/dev/dri/card0:/dev/dri/card1` set in `hyprland.lua` (plain
  node paths — `/dev/dri/by-path/*` symlinks crash Aquamarine 0.15,
  `CBackend::create() failed!`). Pins the NVIDIA card (`card0`, the one the
  monitor is on) as primary. Before this, Aquamarine's primary pick raced boot
  to boot: iGPU-primary boots ran the whole desktop on Mesa/iGPU with a
  per-frame PCIe copy to NVIDIA for scanout, and also flipped the `skemos.frag`
  shader-link error on and off (Mesa strict / NVIDIA lenient). `card0` = NVIDIA
  is deterministic (`nvidia_drm` in initramfs `MODULES`, claims DRM minor 0
  before `amdgpu`). **Needs a reboot / full Hyprland restart to take effect —
  `hyprctl reload` won't do it.**
- **Untested by us**: whether `AQ_DRM_DEVICES` via `hl.env` reliably beats
  Aquamarine's backend init after a real reboot (verified config parses; live
  switch not yet confirmed). Verify: `grep 'becomes primary drm'
  $XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.log` should show
  `card0`. Fallback if not: put the same `export` in `~/.bash_profile` before
  `start-hyprland`.
- **Untested by us**: an actual `systemctl suspend` / resume cycle. Worth doing.

---

## Config map (`hypr/*.lua`, order in `hyprland.lua`)

| file | role |
|---|---|
| `colors.lua` | palette — single source of truth. warm off-white `#e5e1d6` on ink `#161513`, one accent burnt-orange `#c1663a`, hairline `#34322d`, faint `#55514a`. Other components carry their own copy — keep in sync. |
| `monitors.lua` | generic wildcard output rule |
| `look.lua` | borders, gaps, `decoration:screen_shader`, **animations** (curves `skLinear/skOut/skSnap/skGone`, per-leaf speeds) |
| `rules.lua` | window rules; floating-only shadow; **rofi layer rule** (`slide`) |
| `binds.lua` | keybinds. terminal `SUPER+Q` (+ `Return` alias), close `SUPER+C`, rofi `SUPER+D`/`R`, window switcher `SUPER+W` (`scripts/window-switch.sh` — `hyprctl clients` → rofi `-dmenu` → `focuswindow`) |
| `modes.lua` | per-workspace **TILE ⇄ DESK** toggle (`SUPER+SHIFT+SPACE`), persisted to `~/.local/state/skemos/`. Bails with a notify if the focused window is in the drawer (its real ws is *under* the drawer — a blind toggle would reshuffle that). |
| `alttab.lua` | **`ALT+TAB` / `ALT+SHIFT+TAB`** — walk windows in MRU order (`hl.get_windows()` sorted by `focus_history_id`). Snapshots the order per run; a run goes stale after 2 s or an outside focus change. Skips `special:*`. `require`d for side effects in `binds.lua`. |
| `minimize.lua` | `special:minimized` drawer (`SUPER+M` minimize / restore, `SUPER+SHIFT+M` show-hide). Restore uses `hl.get_active_workspace()`, which correctly returns the real ws under the drawer — verified, not buggy. |
| `autostart.lua` | **`lock.sh` first** (boot comes up locked — the schematic hyprlock screen is the boot login), then waybar, **`drawer-banner.sh`**, hyprpaper+wallpaper, mako, hypridle, polkit, cliphist. VM-detect branch still present. |

Other: `waybar/` (config.jsonc + style.css + scripts; **`drawer.jsonc` + `drawer.css`** = the bottom drawer banner), `rofi/skemos.rasi`,
`mako/config`, `hypr/hyprlock.conf`, `hypr/shaders/skemos.frag`,
`hypr/scripts/wallpaper.sh`, `kitty/skemos.conf` + `foot/foot.ini`.

---

## Look — decisions made

- **Screen shader** (`shaders/skemos.frag`): **halftone only** — shadow-weighted
  Bayer 4×4 dither so dark fields read as a plotted panel, text stays crisp;
  faint scanline + vignette. The corner-bracket HUD used to be here, was
  intrusive over windows, **removed**. Tunables are `const`s at the top.
- **Corner brackets / reg marks / title block** live on the **wallpaper**
  (`wallpaper.sh`) — only visible on a bare desktop, never over a window. Top
  corners pushed down `topshift=24` (waybar clearance); bottom-right omitted
  (title block there). Grid pitch is fitted per-resolution so every screen edge
  cuts a cell by ~25% (no stray partial column); the old edge ticks were removed
  (read as stray white pieces).
- **Motion** (`look.lua`): ~90–140 ms, hard-decel curves. Windows materialise
  (fast fade + 4% assemble); close is near-instant (`skGone`, speed 20);
  workspaces `slidefade`; drawer `slidevert`; **border animation off** (instant
  focus colour change, nothing half-faded on a workspace switch).
- **Windows**: ONE native border, `border_size = 2`, white active / faint
  inactive. Even `gaps_out = 10` all sides. **borders-plus-plus was tried and
  dropped** (v1.0 = one adjacent border, no gap; plugin border didn't fade with
  the window). No plugins now.
- **waybar**: solid `@raised` strip, quiet 1px cell dividers, the logged-in
  user (`custom/sheet`, upper-cased) stamped left, `MODE` the one boxed cell. Right side is a telemetry cluster:
  `CPU · MEM · °C · NET · SND · clock` (tray removed — it was the empty gap;
  re-add `"tray"` to `modules-right` if a GTK tray app is needed). Telemetry
  cells have fixed `min-width` (style.css) so digit-count changes don't reflow
  the row; `custom/temp.sh` reads k10temp Tctl.
- **rofi** (`skemos.rasi`): full-height right-side **panel**, inset 12 px
  top/right/bottom (matches window gap), slides in from the right (`sk-rofi-slide`
  layer rule + `layers` animation speed 12).
- **Minimize drawer** (`special:minimized`): windows keep their float state going
  in, so a floating window stays floating in the drawer while tiled ones tile
  (dwindle) with the roomy `gaps_out = 44` from `rules.lua`. While the drawer is
  on screen, `scripts/drawer-banner.sh` shows a thin **orange "PROGRAM DRAWER"
  strip** along the bottom (a second minimal Waybar, `layer=top`,
  `exclusive=false`, `passthrough=true`). The script follows Hyprland's socket2
  `activespecial>>…` events via `nc -U` (needs `openbsd-netcat`), so the banner
  tracks reality — including the drawer auto-closing when its last window is
  restored.
- **App theme = dark**: no DE, so `autostart.lua` sets the GNOME
  `color-scheme = prefer-dark` / `gtk-theme = Adwaita-dark` keys every start —
  `xdg-desktop-portal-gtk` serves these on the portal Settings interface, which
  is what GTK4/libadwaita, Firefox, Chromium, Electron and Qt 6.5+ read to
  "follow the system". GTK3 apps read `gtk-3.0/settings.ini` (in the repo,
  already dark). Qt5-only apps need `qt5ct` + `QT_QPA_PLATFORMTHEME` if any turn
  up — none in the current app set.
- **mako**: callout cards, `▸` marker (matches rofi prompt), inset from the
  top-right so it clears... (bracket now gone, but the inset is fine).
- **Boot login**: no display manager. `agetty` autologins `bas` on tty1
  (drop-in `/etc/systemd/system/getty@tty1.service.d/autologin.conf`, INSTALL §3,
  NOT in the repo) -> `~/.bash_profile` -> `start-hyprland` -> `autostart.lua`
  runs `lock.sh` first, so the schematic hyprlock screen is the boot login. Undo
  the drop-in to get the plain text login back (the lock still gates either way).
- **hyprlock**: solid field + 4 corner brackets, each arm a solid rect anchored
  `halign/valign = center` with a hardcoded offset from the 2560×1440 centre
  (per-edge halign/valign is buggy — #516/#744; `shape` borders render filled —
  #458). `SK-01` + `SKEMOS` tags. Test/preview with
  `hyprlock --grace 999 --verbose` then `grim` then `pkill hyprlock`.

## Open / next

- Cheat-sheet on `SUPER+/` rendered as a schematic sheet (offered, not built).
- Suspend/resume cycle test.
- Possible waybar adds: media (`playerctl`), power menu, bluetooth, disk, update
  count.
- Dials the user tunes directly: shader `const`s, `look.lua` anim speeds,
  wallpaper `inset` / `topshift` / `GRID_ALPHA`.

## Gotchas

- `hyprctl dispatch '<lua>'` works (0.56 evaluates Lua); `hyprctl keyword` does
  **not** — use `hyprctl reload` to apply config edits.
- Screen-shader `gl_FragCoord` origin is **top-left, y down** (opposite GL).
- Screen shaders **must** start with `#version 320 es` and use GLES3 syntax
  (`in` / `layout(location=0) out vec4 fragColor` / `texture()`). Hyprland 0.56
  only ships 300/320 es screen-shader vertex sources; a versionless shader
  defaults to GLSL ES 1.00 and fails to link (`all shaders must use same
  shading language version`) — but *only* on the strict Mesa path, i.e. boots
  where the AMD iGPU wins the primary-GPU race (`AQ_DRM_DEVICES` unset), so it
  looks intermittent. NVIDIA's compiler links the mismatch silently.
- Screen shaders using `uniform float time` force `debug:damage_tracking = 0`
  (huge GPU cost) — keep shaders static.
- No resolution uniform for screen shaders — `RES` is hardcoded.
- `grim` screenshots DO include the screen-shader output.
- git identity in this repo: `bas <sebastian@elstadt.com>`.

## Iterating

```sh
hyprctl reload                                  # apply hypr/*.lua + shader
pkill -SIGUSR2 waybar                           # reload waybar
~/.config/hypr/scripts/wallpaper.sh --force     # regenerate + apply wallpaper
makoctl reload                                  # reload mako
grim /tmp/shot.png                              # screenshot (incl. shader)
```
