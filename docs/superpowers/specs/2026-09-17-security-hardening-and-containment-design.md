# Skemos — security hardening & containment (design spec)

Status: **approved, pre-implementation**. This is the durable record of what we
agreed to build; extend this file (don't lose it) as scope grows before
implementation starts. Once an implementation plan exists, it lives alongside
this spec, not in place of it.

## Goals

1. **Supply-chain integrity** — the concern that triggered this: malware
   riding in via a compromised package/plugin/update, not full OS/network
   hardening. No disk encryption (explicitly declined). No compliance
   framework to satisfy — general good judgment, sized to a personal
   workstation with sensitive work access.
2. **Self-monitoring** — lightweight, mostly-official-repo tooling that
   watches for "filth and disease": unauthorized file changes, rootkit
   signatures, known-CVE exposure in installed packages, firewall posture.
   Not bloat: no continuously-nagging daemons, no duplicate tools.
3. **Containment / reproducibility** — clone `~/.config` onto a fresh Arch
   box, run one script, get the same OS: same look, same keybinds, same
   security posture, same base dev tooling (`git`, `neovim`, `ssh` are
   non-negotiable; `spotify`/`zed`/`yay` are deliberately excluded — those
   stay manual, outside the reproducible flow).
4. A **security interface** (`SUPER+S`) to operate all of the above: view
   aggregated logs, trigger scans on demand, see live busy/idle state
   regardless of what triggered a scan, tail live output.
5. Every future change to this rice follows the same two standing rules:
   **be secure, be contained.** (Recorded in assistant memory as a durable
   project rule, not just in this file.)

---

## Part A — Supply-chain integrity

### A1. Checksum-pin the Departure Mono fetch
`install/bootstrap.sh` downloads `DepartureMono-1.500.zip` directly from a
GitHub release (not pacman, not AUR — see A2). Add a hardcoded `sha256sum`
check immediately after download; on mismatch, abort that step with a loud
error and do **not** extract/install the archive. (The actual hash gets
computed and hardcoded during implementation, against the exact pinned URL
already in the script.)

### A2. Written provenance policy
State explicitly, in both `SKEMOS.md` and `INSTALL.md`: the reproducible
flow (`packages.txt` + `bootstrap.sh`) installs **only from official Arch
repos** (`core`/`extra`), by design. No AUR, no `yay`, no Hyprland plugins,
ever, in that flow. `yay`, `spotify`, `zed` remain hand-installed, forever
outside `packages.txt`/`bootstrap.sh`. This turns an already-true fact into
a stated rule so it can't drift silently as the rice grows.

### A3. Pre-commit secret scan
The repo stays **public** (explicit decision). Add `.githooks/pre-commit`
(tracked in the repo) that runs `gitleaks protect --staged` (official Arch
package, added to `packages.txt`) against the staged diff and blocks the
commit on a hit. Wired via `git config core.hooksPath .githooks/`, done once
by `bootstrap.sh` (idempotent — checks current `core.hooksPath` before
setting). This is a safety net, not a substitute for judgment.

---

## Part B — Reproducible, hardware-auto-detecting install

### B1. `packages.txt` restructure
Split into:
- **Core** (always installed, every machine): the existing full list, plus
  the additions this project requires — `neovim`, `openssh` (essential per
  the original ask), and the Part A/A-monitoring tool set: `ufw`, `audit`,
  `rkhunter`, `arch-audit`, `lynis`, `gitleaks`, `fzf`.
- **Conditional, selected by `bootstrap.sh`, not hand-edited**: CPU
  microcode (`amd-ucode`/`intel-ucode`, detected via `/proc/cpuinfo
  vendor_id`) and GPU packages (`mesa` always; `nvidia-open-dkms
  linux-headers egl-wayland` added only if `lspci` shows an NVIDIA VGA/3D
  device `10de:*`). These conditional package names live as small arrays in
  `bootstrap.sh` itself, not as a tagging syntax inside the text file —
  keeps `packages.txt` simple, declarative, and the logic in one place.
- `kitty` stays listed as core (it's cheap, already themed) but remains the
  documented manual toggle in `hypr/binds.lua` for default terminal —
  unrelated to reproducibility, a cosmetic choice, not touched.

### B2. Hardware auto-detection in `bootstrap.sh`
- CPU vendor → microcode package, still shown to the user before the
  `pacman` run (same review step that already exists).
- GPU vendor(s) → NVIDIA package set added automatically if present.
- **NVIDIA system-level changes stay confirm-before-apply**: kernel cmdline
  edit, `mkinitcpio.conf` `MODULES` edit, `/etc/modprobe.d` nouveau
  blacklist, enabling `nvidia-suspend`/`nvidia-resume`/`nvidia-persistenced`.
  The script computes the exact diff for each, shows it, and asks y/n before
  touching `/etc` or running `mkinitcpio -P`. This matches the approved
  "auto-detect but don't silently touch boot-critical stuff" scope.
- The dual-GPU `AQ_DRM_DEVICES` primary-pin (`hyprland.lua`) stays a
  **documented manual step** — which physical port the monitor is in can't
  be safely auto-guessed, and getting it wrong just costs a render-path
  performance regression, not a broken boot; not worth automating.
- Idempotency: every new step checks current state before reapplying
  (mirrors the existing `.bash_profile`/`.bashrc` append pattern) — re-running
  `bootstrap.sh` on an already-set-up machine stays a safe no-op.

### B3. SSH made functionally ready
If no SSH keypair exists (`~/.ssh/id_ed25519` or equivalent), offer to
generate one (`ed25519`; the interactive `ssh-keygen` passphrase prompt is used — an empty
passphrase is not blocked) and print the pubkey for the user to add to GitHub/wherever.
`openssh` is installed (client + server binaries), but `sshd.service` is
**never enabled by default** — an unsolicited listening SSH server is a
worse default than not having one. `INSTALL.md` notes how to enable it
manually, and that doing so is also when `fail2ban` (declined for now,
Part A discussion) becomes worth adding.

### B4. `INSTALL.md` simplification
Collapses from "9 sections, several manual edits" toward "clone, run one
script, answer the few prompts it can't safely decide for you (NVIDIA
system changes, autologin)." The `hyprlock`-only-boot / `agetty` autologin
section gets a stronger explicit callout: it trades a locked-screen-only
boot for a larger physical-access window — worth a second thought on a
machine used for work.

---

## Part C — Security interface (`SUPER+S`)

`SUPER+S` is unbound today — confirmed against `hypr/binds.lua`.

### C1. Every scan is a systemd unit — this is the load-bearing design choice
`skemos-integrity`, `rkhunter-scan`, `arch-audit-scan`, `ufw-status`,
`audit-status` are each a `systemd` **system**-level oneshot `.service` +
paired `.timer`. All five follow the identical pattern (three actually
*scan*, two just *snapshot current status* — same shape either way):

- The timer fires the service on schedule; the dashboard's "run now" starts
  the **same unit** (`systemctl start <unit>`). There is exactly one
  execution path per job, so "is this busy, and who started it" is never a
  question the dashboard has to answer itself:
  `systemctl is-active <unit>` is authoritative, always, regardless of
  trigger source.
- Live output: `journalctl -u <unit> -f`. History: `journalctl -u <unit>
  --since ...`. No hand-rolled PID/lock-file tracking anywhere — systemd
  and journald already are that state store.
- Each service, on completion, writes two things, both into the root-owned
  `/var/log/skemos-security/` (see C2 for why never into the user's home): a
  full-detail log at `<job>.log`, and a small summary at
  `<job>.summary.json`:
  `{"last_run": "<ISO8601>", "status": "ok|warn|fail", "detail": "<short
  string>"}`. The dashboard reads only the summaries for its table (fast,
  structured) and the full logs on drill-down ("view last log" in the panel).

### C2. Privilege model
`rkhunter` and reading `auditd`'s log need root; `ufw status`, `arch-audit`
mostly don't but stay in the same uniform pattern for consistency.

- A dedicated `skemos-security` group; the user is added to it during
  `bootstrap.sh`.
- `/var/log/skemos-security/` is `root:skemos-security`, mode `750`; each
  `<job>.log` inside is `640`. Every wrapper (which runs as root, being a
  systemd system service) writes both the logs and the
  `<job>.summary.json` files there (`root:skemos-security`, `640`). Root
  **never writes to, chowns, or creates anything inside a user-owned
  directory**: a user-controlled path handed to a root process is a symlink
  attack (plant a symlink at the expected filename, root overwrites and
  chowns its target — root escalation). The user only *reads*, via group
  membership. **Reading any log or summary, ever, needs no privilege
  prompt.** (Found in review of Task 14, 2026-09-18; the original design
  wrote summaries into `~/.local/state/skemos/security/`.)
- Exactly **one** narrow `/etc/sudoers.d/skemos-security` rule: `NOPASSWD`
  for a single fixed wrapper, `/usr/local/bin/skemos-security-run
  <jobname>`, which only accepts one of the 5 known job names as its sole
  argument (hardcoded allowlist, rejects anything else). This is what lets
  the dashboard's "run now" action start a privileged scan instantly with no
  password — while the grant itself is one small, auditable file that can't
  be leveraged for anything beyond "run one of these 5 specific scripts."
  No blanket `sudo`, no broad polkit rule.
- **Critical ownership rule**: anything a root-run sudoers command or a
  systemd *system* service executes (the wrapper itself, the 5 per-job
  scripts, `security/scripts/lib.sh`, the unit files, the sudoers rule, the
  pacman hook, the audit rules) must **not** be writable by the unprivileged
  user, or the NOPASSWD grant becomes an instant root escalation (edit the
  script the wrapper calls, then trigger it with no password). The
  repo copies of these under `~/.config/security/` are the **source** —
  editable, version-controlled — but they are never executed from there
  directly. `bootstrap.sh` **installs** them by copying into root-owned
  locations and fixing ownership/mode, every time it runs (so "edit the repo,
  re-run `bootstrap.sh`" is the update flow):
  - `security/scripts/*.sh` → `/usr/local/lib/skemos-security/` (root:root,
    `0755` dirs / `0755` scripts, not group- or world-writable)
  - the wrapper script → `/usr/local/bin/skemos-security-run` (root:root,
    `0755`)
  - `security/systemd/*.{service,timer}` → `/etc/systemd/system/`
    (root:root, `0644`), followed by `systemctl daemon-reload`
  - `security/sudoers.d/skemos-security` → written to a temp file,
    validated with `visudo -c -f <tmp>`, only then moved to
    `/etc/sudoers.d/skemos-security` (root:root, `0440` — required exact
    mode or `sudo` refuses to load it)
  - `security/pacman-hooks/99-skemos-integrity-resync.hook` →
    `/etc/pacman.d/hooks/` (root:root, `0644`)
  - `security/audit-rules/skemos.rules` → `/etc/audit/rules.d/` (root:root,
    `0640`), followed by `augenrules --load`
  - The user's own `~/.config` clone stays user-writable, same as always
    (root never writes into the user's home) — only the
    **executed-as-root** artifacts get copied out to root-owned locations.

### C3. The panel UI
`SUPER+S` → a floating, centered `foot` window (fixed size, ~70% of screen;
window rule keyed on a distinct app-id in `hypr/rules.lua`; schematic
palette + box-drawing consistent with `bash/skemos.bash`'s banner) running
`security/scripts/security-panel.sh`.

- Renders a 5-row table in plain bash (redrawn on a 2 s poll loop; `fzf` is
  used only for the per-job action menu): job · last result
  (`OK`/`WARN`/`FAIL`/`—`) · last-run time · live state (`IDLE`/`RUNNING`),
  re-reading the summary files + `systemctl is-active` for each unit on every
  refresh.
- Press `1`-`5` to pick a job; an `fzf` menu then offers **run now** (`sudo -n
  /usr/local/bin/skemos-security-run <job>` — no password prompt per C2; it is
  backgrounded so the table keeps refreshing, and a failure to start, e.g. a
  missing sudoers rule, is surfaced as a desktop notification), **view last
  log** (`/var/log/skemos-security/<job>.log` via `less`) and **tail live**
  (`journalctl -u <unit> -f`) — the last only offered while that job is
  `RUNNING`. `q` at the table closes the panel.

### C4. What's watched / scanned
- **`skemos-integrity`** (home-grown, no new package — the direct answer to
  "a worm modified something via/around the package manager"): a curated
  path list (core system binaries — `bash`, `sudo`, `ssh`, `pacman`,
  `systemd`; shell rc files; `/etc/passwd`, `/etc/sudoers`,
  `/etc/pacman.conf`, `/etc/pacman.d/hooks/`; this repo's own `hypr/*.lua`)
  gets `sha256`-hashed into a baseline at `/var/lib/skemos-security/
  integrity.db`. Each run diffs current hashes against the baseline and
  flags anything changed. The list is split into **system** paths (binaries,
  `/etc` files, `/etc/pacman.d/hooks`, `/etc/sudoers.d`,
  `/usr/local/lib/skemos-security`, `/usr/local/bin/skemos-security-run` — the
  root-executed payload itself) and **user** paths (everything under the
  user's home: rc files, `hypr/*.lua`). A **pacman hook**
  (`/etc/pacman.d/hooks/99-skemos-integrity-resync.hook`, installed by
  `bootstrap.sh`) runs `--rebaseline` after every legitimate `pacman`
  transaction, which refreshes the **system** entries only and carries the
  user-path entries over unchanged — otherwise malware editing `~/.bashrc`
  would be silently absorbed at the next `pacman -Syu`. So a `WARN` on a
  system path means something changed **outside** a tracked package-manager
  transaction, and a `WARN` on a user path persists until accepted with the
  explicit `--rebaseline-all` (which rehashes everything; also used by the
  bootstrap seed step). Only regular, non-symlink files are hashed, each under
  a timeout, so a planted FIFO/symlink cannot hang the root job or the pacman
  transaction; the baseline is written atomically (temp file + rename) and
  runs are serialised with `flock`.
- **`audit`/auditd**: real-time kernel watch rules
  (`/etc/audit/rules.d/skemos.rules`) on `~/.ssh`, `/etc/shadow`,
  `/etc/sudoers.d/`, `/etc/pacman.d/`, `/etc/passwd`, all under the single
  audit key `skemos` (so `audit-status` runs `ausearch -k skemos` and does not
  count unrelated logins/sudo/service events) — logs who/what/when
  touched them, always-on (not scan-on-demand; `audit-status` just snapshots
  recent matching events via `ausearch` into the uniform log/summary shape).
- **`rkhunter`**: signature/heuristic rootkit, backdoor, hidden-process, and
  suspicious-permission scan. Timer-fired (weekly), plus on-demand.
- **`arch-audit`**: checks installed packages against the Arch Linux
  Security Tracker CVE feed. Timer-fired (weekly), plus on-demand.
- **`ufw`**: enabled with `default deny incoming` / `default allow
  outgoing` (currently installed but off — this project turns it on).
  `ufw-status` snapshots `ufw status verbose` into the uniform shape. No
  inbound allow rules by default, since `sshd` stays disabled (B3); the docs
  note adding `ufw allow ssh` if the user ever enables inbound SSH.
- **`lynis`**: installed, but deliberately **not** wired into the panel or
  any timer — a broader one-shot posture audit whose output is long-form and
  better read interactively (`sudo lynis audit system`) than pushed through
  a notification. Documented in `SKEMOS.md`/`INSTALL.md` as an available
  on-demand tool.

### C5. Notifications
Every run that produces a `WARN`/`FAIL` summary — whether started by its timer,
the pacman hook or the panel's "run now" — also fires a `notify-send` through
`mako`, consistent with the rice's existing notification surface. (Deliberate
deviation from the original "timer-fired only" idea: the summary writer cannot
cheaply tell who started the unit, and one notification per non-OK run is
cheap.) `OK` results stay silent — only surface when there's something to see.

**Explicitly declined** (Part A discussion): `opensnitch` (per-connection
popups — the interactive friction/bloat this project is trying to avoid)
and `fail2ban` (nothing to protect while `sshd` is disabled by default; add
later if inbound SSH is ever turned on).

---

## Files touched (implementation-plan level, not final)

- `install/packages.txt` — core/conditional restructure, new packages.
- `install/bootstrap.sh` — hardware detection, checksum pin, SSH keygen
  offer, `skemos-security` group, sudoers.d install, systemd units install +
  enable, pacman hook install, audit rules install, ufw enable, git hooks
  wiring.
- New `security/` directory (mirrors `bash/`, `waybar/` convention) — the
  **source** of everything root-run; `bootstrap.sh` installs copies into
  root-owned locations per the ownership rule in Part C2:
  `security/scripts/{lib.sh,security-panel.sh,integrity-check.sh,
  rkhunter-scan.sh,arch-audit-scan.sh,ufw-status.sh,audit-status.sh,
  skemos-security-run}`, `security/systemd/*.{service,timer}` (5 services +
  5 timers), `security/sudoers.d/skemos-security`,
  `security/pacman-hooks/99-skemos-integrity-resync.hook`,
  `security/audit-rules/skemos.rules`. `security-panel.sh` is the one script
  that runs unprivileged, as the user, from `SUPER+S` — it can stay run
  directly from the repo checkout, no install-copy needed.
- `.githooks/pre-commit` (new, `gitleaks`-backed).
- `hypr/binds.lua` — `SUPER+S` bind.
- `hypr/rules.lua` — floating window rule for the security panel.
- `.gitignore` — already updated to whitelist `/docs/` (this spec) and will
  need `/security/` and `/.githooks/` added when those directories exist.
- `SKEMOS.md` — config map rows, a new "Security — decisions made" section,
  gotchas, open/next.
- `INSTALL.md` — package table, keybinds table (`SUPER+S`), new "Security"
  section (privilege model, what's watched, how to read/trigger scans
  manually from a plain shell if the panel isn't used).

## Testing / verification plan

- `bash -n` on every new/edited shell script; `visudo -c` on the sudoers.d
  file before it's considered valid.
- `Hyprland --verify-config` after the bind/rule additions.
- Each systemd unit: `systemctl status`, a manual `systemctl start` to
  confirm oneshot behavior and log/summary output land correctly, and a
  timer dry-run (`systemctl list-timers`) to confirm scheduling.
- Trigger one deliberate integrity mismatch (edit a watched file outside
  pacman) and confirm the panel shows `WARN` and the pacman-hook resync
  clears it after a real `pacman -Syu`.
- Confirm the sudoers rule rejects an unlisted argument
  (`skemos-security-run rm-rf-everything` should fail closed).
- Manual pass through the panel: open, watch a timer-fired run show up as
  `RUNNING` without having triggered it, tail its live output, confirm it
  flips back to `IDLE` with an updated summary on completion.
- The hardware auto-detect / confirm-before-apply NVIDIA flow can only be
  fully verified on a second real machine or a fresh VM — call this out
  explicitly as a follow-up the user does themselves, not something claimed
  as verified from this machine alone.

## Explicitly out of scope

- Disk encryption (declined).
- Making the GitHub repo private (declined — public, with the `gitleaks`
  safety net instead).
- `opensnitch`, `fail2ban` (declined for now — see C5).
- Automating the `AQ_DRM_DEVICES` GPU-primary pin (machine-specific, low
  cost if wrong, not worth the complexity).
- A waybar cell for security status — mentioned as a possible future nicety,
  not part of this pass.

## Revision 2026-09-19 — SUPER+S panel redesign

Supersedes the C-section panel layout above (table + `fzf` menu + `less`): the
panel is now a left-edge fixed window (900 px, full height, pinned, toggled by
`security-toggle.sh`) with the job list in a left column and the selected job's
log in a right column. Selection shows the log in place; `r` runs, `f` toggles
the live journal. Rendering is diff-based (alternate screen, changed lines
only) to eliminate flicker. `fzf` is no longer used and was dropped from
`packages.txt`. The privilege model is unchanged.
