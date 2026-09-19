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
| `look.lua` | borders, gaps, `decoration:screen_shader`, **animations** (curves `skLinear/skOut/skSnap/skGone`, per-leaf speeds), **group bars** (fenced `GROUP BARS — trial` block — flat tabbed title strip; delete block + the binds block to remove) |
| `rules.lua` | window rules; floating-only shadow; **rofi layer rule** (`slide`) |
| `binds.lua` | keybinds. terminal `SUPER+Q` (+ `Return` alias), close `SUPER+C`, rofi `SUPER+D`/`R`, window switcher `SUPER+W` (`scripts/window-switch.sh` — `hyprctl clients` → rofi `-dmenu` → `hl.dsp.focus({window=…})`, which pulls the target workspace into view). **Group bars trial** (fenced block): `SUPER+G` fold in/out of a group, `SUPER+]`/`[` next/prev tab, `SUPER+SHIFT+]`/`[` reorder. |
| `modes.lua` | per-workspace **TILE ⇄ DESK** toggle (`SUPER+SHIFT+SPACE`), persisted to `~/.local/state/skemos/`. Bails with a notify if the focused window is in the drawer (its real ws is *under* the drawer — a blind toggle would reshuffle that). |
| `alttab.lua` | **`ALT+TAB` / `ALT+SHIFT+TAB`** — walk windows in MRU order (`hl.get_windows()` sorted by `focus_history_id`). Snapshots the order per run; a run goes stale after 2 s or an outside focus change. Skips `special:*`. `require`d for side effects in `binds.lua`. |
| `minimize.lua` | `special:minimized` drawer (`SUPER+M` minimize / restore, `SUPER+SHIFT+M` show-hide). Restore uses `hl.get_active_workspace()`, which correctly returns the real ws under the drawer — verified, not buggy. |
| `autostart.lua` | **`lock.sh` first** (boot comes up locked — the schematic hyprlock screen is the boot login), then waybar, **`drawer-banner.sh`**, hyprpaper+wallpaper, mako, hypridle, polkit, cliphist. VM-detect branch still present. |

Other: `waybar/` (config.jsonc + style.css + scripts; **`drawer.jsonc` + `drawer.css`** = the bottom drawer banner), `rofi/skemos.rasi`,
`mako/config`, `hypr/hyprlock.conf`, `hypr/shaders/skemos.frag`,
`hypr/scripts/wallpaper.sh`, `kitty/skemos.conf` + `foot/foot.ini`.

`bash/skemos.bash` — shell dressing: a two-line title-block prompt (`╭─ user@host
· ~/path · <rev><*>` / `╰▸`, rev + `✕ N` exit marker) and a compact login
banner (once per terminal — parent-process check, since SHLVL is 2+ for every
terminal under the single login shell). Sourced from `~/.bashrc` (NOT in the
repo; `bootstrap.sh` adds the line). `SKEMOS_BANNER=0` drops the banner.

`security/` (scripts, systemd units, sudoers/pacman-hook/audit-rule
templates — source of truth for the SUPER+S panel; installed root-owned by
`bootstrap.sh`, see "Security" below).

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
- **Group bars** (trial, added 2026-09-07 — fenced blocks in `look.lua` +
  `binds.lua`, delete both to remove): native tabbed window stacks with a
  title-block strip on top. Styled flat — `gradients = false`, Departure Mono
  9px, `height 16`, `indicator_height 2` (the one orange line under the active
  tab), group frame in burnt orange. `group:auto_group` defaults to **true** in
  0.56.2, so once a group exists new windows join it; `SUPER+G` pops the focused
  one back out. Keyboard-add-a-specific-window isn't wired: `moveintogroup` /
  `movewindoworgroup` have **no Lua dispatcher** in 0.56.2 (only `toggle`,
  `next`, `prev`, `move_window`, `lock` under `hl.dsp.group`) — drag a titlebar
  onto the bar instead.
- **waybar**: solid `@raised` strip, quiet 1px cell dividers, the logged-in
  user (`custom/sheet`, upper-cased) stamped left, `MODE` the one boxed cell.
  **Font is Departure Mono** (pixel/plotter face, `~/.local/share/fonts`, AUR
  `otf-departure-mono`) with an Iosevka fallback for glyphs it lacks. Right side
  is a telemetry cluster: `CPU · MEM · °C · NET · SND · REV · clock`
  (tray removed — it was the empty gap; re-add `"tray"` to `modules-right` if a
  GTK tray app is needed). Telemetry cells have fixed `min-width` (style.css) so
  digit-count changes don't reflow the row; `custom/temp.sh` reads k10temp Tctl.
  - **`custom/rev`** (`scripts/rev.sh`): `REV <7-char HEAD>` of `~/.config`,
    `*` when the tracked tree is dirty (`.dirty` class → a touch brighter).
    Click opens `git log` in foot. Polled every 30 s.
  - **Workspaces** are a coordinate row: `format-icons` zero-pad the ids
    (`01`…`10`), `persistent-workspaces {"*":[1..5]}` keeps 5 slots always
    present, active slot gets the orange underline (CSS `button.active`). The
    number/list form is used because `{"*": 5}` did not take on waybar 0.15.0.
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

## Security — decisions made

- **Threat model is supply-chain, not full OS hardening**: the concern is a
  compromised package/AUR-helper/plugin, not disk encryption (declined) or
  a compliance framework (none targeted). The repo stays **public**
  (declined making it private) — the `gitleaks` pre-commit hook
  (`.githooks/pre-commit`, wired via `git config core.hooksPath`) is the
  safety net for that.
- **Official-repos-only policy**: `packages.txt` + `bootstrap.sh` install
  only from Arch `core`/`extra`. No AUR, no `yay`, no Hyprland plugins in
  that flow, ever — `yay`/`spotify`/`zed` stay hand-installed, outside it.
- **5 self-monitoring jobs**, each a systemd oneshot `.service` + `.timer`
  pair, installed root-owned by `bootstrap.sh` from the `security/` source
  directory (never executed from `~/.config` directly — see the ownership
  note below): `skemos-integrity` (daily, home-grown hash-baseline FIM — a
  curated watchlist of SYSTEM paths (core binaries, `/etc/passwd`/
  `/etc/sudoers`/`/etc/pacman.conf`, `/etc/pacman.d/hooks`, `/etc/sudoers.d`,
  `/usr/local/lib/skemos-security` and the `/usr/local/bin/skemos-security-run`
  dispatcher — i.e. the root-executed payload itself) and USER paths (your
  `.bashrc`/`.bash_profile` and `hypr/hyprland.lua`/`hypr/binds.lua`/
  `hypr/look.lua`). Only regular non-symlink files are hashed, each under a
  timeout, so a planted FIFO/symlink cannot hang the job. The pacman hook runs
  `--rebaseline`, which refreshes the SYSTEM entries only and carries the user
  entries over unchanged, so a `pacman -Syu` can never launder edits to your
  rc/rice files into the baseline: hand-editing one of those makes it WARN
  **until you accept it** with
  `skemos-integrity --rebaseline-all`
  (which rehashes everything; bootstrap's seed step uses it too);
  `aide` is AUR-only so this is hand-rolled), `rkhunter-scan` (weekly,
  rootkit/backdoor signatures), `arch-audit-scan` (weekly, known-CVE exposure
  in installed packages), `ufw-status` / `audit-status` (hourly snapshots —
  `bootstrap.sh` turns on `ufw` with default-deny-incoming / allow-outgoing
  and enables `auditd` with watch rules for `~/.ssh`, `/etc/shadow`,
  `/etc/sudoers.d`, `/etc/pacman.d`, `/etc/passwd`; these jobs just surface
  current state). `lynis` is installed but deliberately **not** automated —
  run `sudo lynis audit system` by hand when you want its broader, long-form
  posture audit.
- **`SUPER+S`** toggles the panel (`security/scripts/security-toggle.sh` →
  `security-panel.sh` in a `foot` window). It is fixed to the **left** edge —
  960 px wide, full height, inset 12 px, pinned to every workspace — the mirror
  of rofi on the right (placement is the `sk-security-panel` window rule in
  `hypr/rules.lua`). Left panel: the 5 jobs with status, last-run time and
  live `RUNNING`/`IDLE`; right panel: the selected job's log, running down the
  full height, in two outlined panels (bright outline = focused). Keys: `←`/`→`
  switch focus between tools and logs. Tools focused: `↑`/`↓`/`j`/`k` or `1`–`5`
  select a tool. Logs focused: `↑`/`↓`/`j`/`k` scroll a line, `PgUp`/`PgDn` a
  page, `^u`/`^d` half a page, `g`/`G` (or `Home`/`End`) oldest/newest. The mouse
  wheel always scrolls the logs (the panel captures the mouse, so plain
  click-drag select is off — Shift-drag still works, or use `y`). The last 1000
  lines are loaded; scrolling up pins the view while new output arrives, and
  reaching the bottom (or switching tool / `c` / `r`) resumes following.
  `r` run now (clears that job's view first, so you see just that run),
  `c` clear the view (display only — nothing on disk changes; reopening the
  panel restores it), `y` copy the visible log to the clipboard (original,
  unwrapped lines, via `wl-copy`), `a` analyze with Claude (see below), `f` toggle the live journal view (automatic
  while the job is `RUNNING`), `q`/`Esc` quit. State comes from
  `/var/log/skemos-security/*.summary.json` plus one `systemctl is-active` —
  busy/idle is correct whether a job was started by its timer or by the panel,
  because both start the *same* systemd unit. **No flicker:** alternate screen,
  one write per frame, only changed lines repainted (an idle panel writes
  nothing). "Run now" starts in the background so the panel keeps refreshing.
- **`a` — analyze with Claude** (optional, needs `claude` installed and signed
  in; the footer hint says which). Snapshots the selected tool's log
  (`context.txt` + `log.txt`, up to 1000 lines, honoring a cleared view) into
  `$XDG_RUNTIME_DIR/skemos-analysis.*` (0700, tmpfs), opens a new `foot` running
  `security/scripts/security-analyze.sh`, which prints what will be sent and
  waits for **Enter** before starting `claude` there with
  `--tools "Read,Grep,Glob"` (read-only: no shell/edit/web/MCP). Log text can
  carry attacker-controlled strings, so read-only is enforced by the tool
  allowlist, not by trusting the prompt. The dir is deleted on any exit.
  Unprivileged; no sudoers change. The availability probe runs in the
  background (startup + every 30 s, and on demand when `a` is pressed).
- **Privilege model / ownership rule**: `rkhunter` and `auditd` need root.
  Rather than blanket `sudo`, there's a `skemos-security` group (readable
  logs, no prompt) plus exactly one `/etc/sudoers.d/skemos-security`
  NOPASSWD rule scoped to one fixed wrapper
  (`/usr/local/bin/skemos-security-run <jobname>`, 5-name hardcoded
  allowlist). **Everything that rule or a systemd system service executes
  is installed by `bootstrap.sh` into a root-owned, not-user-writable
  location** — the `security/` copies in this repo are the editable
  source; nothing there is ever run directly, because a user-writable
  script behind a passwordless sudo rule is an instant root escalation.
  Edit the repo, re-run `bootstrap.sh`, to update any of it.
- **audit-status digests events.** `ausearch` prints several raw records per
  event and the job used to WARN on any watched-path activity all day —
  including its own setup (`auditctl` loading the rules) and every pacman
  transaction (`gpg` refreshing the keyring's `trustdb.gpg`). It now groups
  records into events, ignores exactly those two routine sources, and flags
  everything else (other keyring files such as `pubring.kbx`, `sudoers.d`,
  `passwd`, `~/.ssh`, audit-rule changes by anything but `auditctl`) as one
  readable line each: time, program, uid/auid, path. An `ausearch` failure is
  now a FAIL, not "no events". The window is still "today", so a real event
  keeps the WARN until midnight.
- **arch-audit acknowledgements.** `arch-audit` compares installed packages to
  Arch's security tracker, and the tracker holds records that were never closed
  (status "Vulnerable"/"Unknown", no fixed version) for CVEs from 2020-2025
  while the installed versions are years newer — a WARN that can never clear.
  `security/arch-audit-ack.txt` lists those tracker ids (each with package,
  installed version and the tracker's "affected" version); the job hides
  acknowledged ids from its WARN but still prints them in the log, and any
  advisory not listed still warns. The file is installed root-owned into
  `/usr/local/lib/skemos-security/arch-audit-ack` (integrity-watched), so only
  someone with sudo can silence a finding. Seeded 2026-09-19 with 20 entries,
  judged stale from the version gap — not verified per package. To
  acknowledge a new one: add a line, then re-run bootstrap (or `sudo install -m
  0644 security/arch-audit-ack.txt /usr/local/lib/skemos-security/arch-audit-ack`).
- **Root never writes into a user-owned directory** — a root job that writes
  or chowns a file inside a directory the user controls is a symlink-attack
  root escalation (user plants a symlink at the expected filename; root
  overwrites and chowns the target). That is why summaries sit beside the
  logs in `/var/log/skemos-security/` rather than in `~/.local/state`. Found
  in review on 2026-09-18.
- **Deliberate exception — Claude Code.** The only software outside the
  official repos: opt-in at bootstrap (default No, never non-interactive,
  never root, no npm/AUR, installer downloaded to a file first), installed
  user-level into `~/.local` by Anthropic's own installer. Sends a tool's log
  to Anthropic only after an explicit Enter in the analysis terminal.
- **Declined**: `opensnitch` (interactive per-connection popups — exactly
  the friction/bloat this pass was trying to avoid), `fail2ban` (nothing to
  protect while `sshd` stays disabled by default — add it if you ever
  enable inbound SSH).

Full design: `docs/superpowers/specs/2026-09-17-security-hardening-and-containment-design.md`.

## Open / next

- Cheat-sheet on `SUPER+/` rendered as a schematic sheet (offered, not built).
- Suspend/resume cycle test.
- **Group bars** — trial in place; user to keep or cut (delete the two fenced
  blocks). If kept: consider a `SUPER+SHIFT+arrow`-into-group path if Hyprland
  ever exposes `moveintogroup` in the Lua API.
- Possible waybar adds: media (`playerctl`), power menu, bluetooth, disk, update
  count.
- Schematic screenshot frame, submap HUD (reuse `drawer-banner.sh`), crosshair
  cursor — all offered, not built.
- Dials the user tunes directly: shader `const`s, `look.lua` anim speeds,
  wallpaper `inset` / `topshift` / `GRID_ALPHA`, `bash/skemos.bash` banner /
  `SKEMOS_BANNER`.

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
- **Departure Mono** is AUR-only (`otf-departure-mono`); we install the OFL OTF
  per-user in `~/.local/share/fonts/DepartureMono/` (no root). `bootstrap.sh`
  fetches it if missing. Every consumer keeps an Iosevka fallback, so a missing
  install just degrades gracefully.
- Waybar `hyprland/workspaces` `persistent-workspaces` on 0.15.0 wants the
  **list** form (`{"*":[1,2,3,4,5]}`); the count form (`{"*":5}`) silently did
  nothing.
- Shell banner can't key off `SHLVL` (every terminal is 2+ under the one login
  shell that `exec`s Hyprland) — it checks the **parent process name** instead.
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
