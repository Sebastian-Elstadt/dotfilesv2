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
generate one (`ed25519`, passphrase prompted interactively — never
generated blank) and print the pubkey for the user to add to GitHub/wherever.
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
- Each service, on completion, writes two things as its logged-in user
  (not root — see C2 for how): a full-detail log at
  `/var/log/skemos-security/<job>.log`, and a small summary at
  `~/.local/state/skemos/security/<job>.summary.json`:
  `{"last_run": "<ISO8601>", "status": "ok|warn|fail", "detail": "<short
  string>"}`. The dashboard reads only the summaries for its table (fast,
  structured) and the full logs on drill-down (`[l]`).

### C2. Privilege model
`rkhunter` and reading `auditd`'s log need root; `ufw status`, `arch-audit`
mostly don't but stay in the same uniform pattern for consistency.

- A dedicated `skemos-security` group; the user is added to it during
  `bootstrap.sh`.
- `/var/log/skemos-security/` is `root:skemos-security`, mode `750`; each
  `<job>.log` inside is `640`. Every wrapper (which runs as root, being a
  systemd system service) writes there and to the user's own
  `~/.local/state/skemos/security/` (ownership set correctly at write time —
  the wrapper is generated for this specific single-user machine, matching
  the rest of the rice's single-user assumptions). **Reading any log or
  summary, ever, needs no privilege prompt.**
- Exactly **one** narrow `/etc/sudoers.d/skemos-security` rule: `NOPASSWD`
  for a single fixed wrapper, `/usr/local/bin/skemos-security-run
  <jobname>`, which only accepts one of the 5 known job names as its sole
  argument (hardcoded allowlist, rejects anything else). This is what lets
  the dashboard's `[r]` action start a privileged scan instantly with no
  password — while the grant itself is one small, auditable file that can't
  be leveraged for anything beyond "run one of these 5 specific scripts."
  No blanket `sudo`, no broad polkit rule.

### C3. The panel UI
`SUPER+S` → a floating, centered `foot` window (fixed size, ~70% of screen;
window rule keyed on a distinct app-id in `hypr/rules.lua`; schematic
palette + box-drawing consistent with `bash/skemos.bash`'s banner) running
`security/scripts/security-panel.sh`.

- Renders a 5-row table via `fzf` (added to `packages.txt` — tiny, official,
  gives a clean live-updating selectable list; picked over a hand-rolled
  bash table for UX): job · last result (`OK`/`WARN`/`FAIL`/`—`) ·
  last-run time · live state (`IDLE`/`RUNNING`). Refreshes on a ~2s loop by
  re-reading the summary files + `systemctl is-active` for each unit.
- Per-row actions: `[r]` run/refresh now (`sudo
  /usr/local/bin/skemos-security-run <job>` — no password prompt per C2),
  `[l]` view last full log (`/var/log/skemos-security/<job>.log` via
  `less`), `[t]` tail live output (`journalctl -u <unit> -f`) — only offered
  while that row is `RUNNING`. `q`/`Esc` backs out of a sub-view to the
  table; `q` at the table closes the panel.

### C4. What's watched / scanned
- **`skemos-integrity`** (home-grown, no new package — the direct answer to
  "a worm modified something via/around the package manager"): a curated
  path list (core system binaries — `sh`, `bash`, `sudo`, `ssh`, `pacman`,
  `systemd`; shell rc files; `/etc/passwd`, `/etc/sudoers`,
  `/etc/pacman.conf`, `/etc/pacman.d/hooks/`; this repo's own `hypr/*.lua`)
  gets `sha256`-hashed into a baseline at `/var/lib/skemos-security/
  integrity.db`. Each run diffs current hashes against the baseline and
  flags anything changed. A **pacman hook**
  (`/etc/pacman.d/hooks/99-skemos-integrity-resync.hook`, installed by
  `bootstrap.sh`) re-baselines automatically after every legitimate `pacman`
  transaction — so a `WARN` means something changed **outside** a tracked
  package-manager transaction, which is exactly the threat being watched
  for.
- **`audit`/auditd**: real-time kernel watch rules
  (`/etc/audit/rules.d/skemos.rules`) on `~/.ssh`, `/etc/shadow`,
  `/etc/sudoers.d/`, `/etc/pacman.d/`, `/etc/passwd` — logs who/what/when
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
Every timer-fired (not manually-triggered — avoid duplicate noise when the
user is already watching the panel) run that produces a `WARN`/`FAIL`
summary also fires a `notify-send` through `mako`, consistent with the
rice's existing notification surface. `OK` results stay silent — only
surface when there's something to see.

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
- New `security/` directory (mirrors `bash/`, `waybar/` convention):
  `security/scripts/{security-panel.sh,integrity-check.sh,
  skemos-security-run}`, `security/systemd/*.{service,timer}`,
  `security/sudoers.d/skemos-security`,
  `security/pacman-hooks/99-skemos-integrity-resync.hook`,
  `security/audit-rules/skemos.rules`.
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
