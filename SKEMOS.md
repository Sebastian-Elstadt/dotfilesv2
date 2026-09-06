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

- **GPU**: NVIDIA RTX 5070 (`nvidia-open` 610, PCI `01:00.0`) **+** AMD Granite
  Ridge iGPU (`12:00.0`). Compositor runs on the NVIDIA card. `mesa` stays
  installed (iGPU + GL loader).
- **Display**: single `DP-1`, 2560×1440, scale 1. Hardcoded in
  `hypr/shaders/skemos.frag` and figured live by `hypr/scripts/wallpaper.sh`.
- **Launch**: `~/.bash_profile` → `exec start-hyprland` on tty1 (not uwsm, not a
  display manager). `~/.bash_profile` is NOT in the repo.
- **Hyprland 0.56.2**, Lua config.

## Stability (done)

- `systemctl enable nvidia-suspend nvidia-resume nvidia-persistenced` — without
  these, resume from suspend black-screens (the cmdline
  `NVreg_PreserveVideoMemoryAllocations=1` is a no-op alone).
- `/etc/modprobe.d/nouveau-blacklist.conf` → `blacklist nouveau`; `mkinitcpio -P`.
- `AQ_DRM_DEVICES` is deliberately NOT set — by-path symlinks crash Aquamarine
  (`CBackend::create() failed!`). If pinning is ever needed use plain node paths
  and test.
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
- **waybar**: solid `@raised` strip, quiet 1px cell dividers, `SK-01` stamp
  left, `MODE` the one boxed cell. Right side is a telemetry cluster:
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
