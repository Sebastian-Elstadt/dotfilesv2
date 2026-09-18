# Skemos Security Hardening & Containment — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden `~/.config` (the Skemos Hyprland rice) against supply-chain
risk, add lightweight self-monitoring for file tampering/rootkits/known
CVEs, make the whole rice reproducible on a fresh Arch box via one script,
and add a `SUPER+S` panel to operate and observe the monitoring tools.

**Architecture:** A new `security/` directory (source of truth, tracked in
the repo) holds job scripts, systemd units, and privileged-file templates.
`install/bootstrap.sh` is the only thing that ever writes into root-owned
locations — it copies `security/*` into `/usr/local/lib/skemos-security`,
`/usr/local/bin`, `/etc/systemd/system`, `/etc/sudoers.d`,
`/etc/pacman.d/hooks`, and `/etc/audit/rules.d`, fixing ownership so nothing
executed as root is writable by the unprivileged user. Every scan is a real
systemd oneshot service + timer; the `SUPER+S` panel and the timers start
the *same* unit, so "is a scan running, and who started it" is answered by
`systemctl is-active`/`journalctl` — no custom state tracking.

**Tech Stack:** bash, systemd (services/timers), `sudoers.d`, pacman hooks,
Linux audit framework (`auditd`), `rkhunter`, `arch-audit`, `ufw`, `gitleaks`,
`fzf`, `jq`, Hyprland Lua config (`hl.bind`, `hl.window_rule`).

**Spec:** `docs/superpowers/specs/2026-09-17-security-hardening-and-containment-design.md`
(read this first — this plan implements it, including its 2026-09-17
privilege-escalation correction).

## Global Constraints

- **Official Arch repos only** in the reproducible flow (`packages.txt`,
  `bootstrap.sh`, and everything `security/`) — no AUR, no `yay`, no
  Hyprland plugins. `spotify`/`zed`/`yay` stay outside this flow, forever.
- **No disk encryption, repo stays public** — both explicitly declined by
  the user. The `gitleaks` pre-commit hook is the safety net for the public
  repo, not a private repo.
- **Ownership rule (spec Part C2, 2026-09-17 correction)**: anything
  executed as root (systemd system services, the sudoers-granted wrapper,
  the pacman hook, the audit rules) must be installed into a **root-owned,
  not-user-writable** location by `bootstrap.sh` — never executed directly
  from `~/.config`. `security-panel.sh` is the one exception (runs
  unprivileged, as the user, straight from the repo checkout).
- **Single-user machine assumption** carries through, same as the rest of
  this rice (`/etc/skemos-security.conf`, written by `bootstrap.sh`, is how
  root-run scripts learn the real username/home — see Task 4).
- **`sudo` needs an interactive TTY.** Tasks 1–13 (writing files under
  `~/.config/security/`, `install/`, `hypr/`, `.githooks/`) are fully
  scriptable by an executor with no special privileges. Task 14 (installing
  those files into root-owned system locations) and Task 16 (end-to-end
  verification) require a human to actually run `install/bootstrap.sh` and
  type their `sudo` password — they cannot be completed non-interactively.
  Do the writing/verification-by-inspection for those tasks, then hand the
  live run back to the user.
- **Verification tools available without root**: `bash -n` (syntax),
  `shellcheck` if installed (skip gracefully if not present — don't install
  it just for this), `systemd-analyze verify <unit-file>` (works on
  arbitrary unit file paths, no install needed), `visudo -c -f <file>`
  (works on any file, no install needed), `Hyprland --verify-config`.
- **Notification simplification** (deviates slightly from the spec's
  wording, noted here rather than silently): notify on `WARN`/`FAIL`
  **regardless of trigger source** (timer or manual "run now"), not only
  timer-fired. The spec's "one execution path per job" design makes
  distinguishing trigger source inside the unit require either duplicate
  units or environment tricks that undermine that exact design goal — not
  worth it for what's at most a mildly redundant notification when a manual
  run happens to find something.
- The Departure Mono zip's pinned checksum (Task 3) is
  `bf3e48059aeef4617ec585bdea81dcc3491c576b3e7a472f52faf40e09ee5c3a` —
  computed directly against the exact pinned URL already in
  `bootstrap.sh`, not guessed.

---

### Task 1: `packages.txt` restructure + `.gitignore` whitelist

**Files:**
- Modify: `install/packages.txt`
- Modify: `.gitignore`

**Interfaces:**
- Produces: a flat list of **core** package names (everything except CPU
  microcode and NVIDIA packages, which move to `bootstrap.sh` in Task 2) that
  `bootstrap.sh` parses the same way it already does (`sed -E 's/#.*//' |
  tr -s ' \t' '\n' | grep -E '^[a-z0-9]'`).

- [ ] **Step 1: Add the new core packages and provenance-policy header to `packages.txt`**

Edit `install/packages.txt`: add a header comment block right under the
existing top comment, before `# --- compositor + session ---`:

```
# Provenance policy: every package below comes from the official Arch
# 'core'/'extra' repos. No AUR, no yay, no Hyprland plugins in this file or
# in bootstrap.sh — ever. That's deliberate (supply-chain risk), not an
# oversight. AUR software (yay, spotify, zed) is installed by hand and
# stays outside this reproducible flow permanently.
#
# CPU microcode and NVIDIA packages are NOT listed here — bootstrap.sh
# detects your hardware and adds them itself. See install/bootstrap.sh.
```

Then:
- Remove the `# --- CPU microcode ---` section (the `amd-ucode` /
  `# intel-ucode` lines) entirely — Task 2 makes `bootstrap.sh` choose this.
- Remove the `nvidia-open-dkms   linux-headers   egl-wayland` line from the
  `# --- GPU ---` section (keep `mesa`, keep the section's explanatory
  comment, just drop that one line) — Task 2 adds it conditionally.
- Under `# --- vcs / dev essentials ---` (rename the existing `# ---
  networking / auth / vcs ---` comment to include this), add:

```
neovim                         # essential editor — always present, no exceptions
openssh                        # ssh + sshd binaries. sshd is installed but
                                # NEVER enabled by default (see INSTALL.md).
```

- Under `# --- small CLI helpers used by the config ---`, add:

```
less                            # pager — used by the security panel's log view
```

- Add a new section after the fonts section:

```
# --- security monitoring (SUPER+S panel — see SKEMOS.md "Security") -----
ufw                            # firewall — enabled default-deny-incoming by bootstrap.sh
audit                          # provides auditd: real-time watch rules on sensitive paths
rkhunter                       # rootkit/backdoor signature scan
arch-audit                     # checks installed packages against Arch's CVE tracker
lynis                          # broader on-demand security posture audit (not automated)
gitleaks                       # secret scanner — powers the pre-commit hook
fzf                            # the security panel's row-action picker
```

- [ ] **Step 2: Whitelist the new tracked directories in `.gitignore`**

Edit `.gitignore`, add after the existing `!/docs/` line (added in the spec
commit):

```
!/security/
!/.githooks/
```

- [ ] **Step 3: Verify the package list still parses correctly**

Run:
```sh
sed -E 's/#.*//' install/packages.txt | tr -s ' \t' '\n' | grep -E '^[a-z0-9]' | sort
```
Expected: a clean alphabetically-sortable list of package names, no leftover
`amd-ucode`/`intel-ucode`/`nvidia-open-dkms`, and including `neovim`,
`openssh`, `less`, `ufw`, `audit`, `rkhunter`, `arch-audit`, `lynis`,
`gitleaks`, `fzf`.

- [ ] **Step 4: Commit**

```bash
git add install/packages.txt .gitignore
git commit -m "packages: restructure core list, add essentials + security tooling

neovim and openssh are now guaranteed core packages. CPU microcode and
NVIDIA packages move to bootstrap.sh (auto-detected, see next commit).
Adds the security-monitoring package set for the SUPER+S panel."
```

---

### Task 2: `bootstrap.sh` — hardware auto-detection & confirm-before-apply NVIDIA changes

**Files:**
- Modify: `install/bootstrap.sh`

**Interfaces:**
- Produces: `detect_cpu_pkg()` (echoes `amd-ucode`, `intel-ucode`, or empty),
  `detect_gpu_pkgs()` (echoes `"nvidia-open-dkms linux-headers egl-wayland"`
  or empty) — used again nowhere else in this plan, but keep the names
  stable in case of future reference.

- [ ] **Step 1: Replace bootstrap.sh's package-install section (section 1) with hardware-aware selection**

Replace the current:
```bash
# 1. packages -------------------------------------------------------------
mapfile -t PKGS < <(sed -E 's/#.*//' "$HERE/packages.txt" | tr -s ' \t' '\n' | grep -E '^[a-z0-9]')
say "Install / verify ${#PKGS[@]} packages:"
printf '   %s\n' "${PKGS[@]}"
say "Add your CPU microcode (amd-ucode / intel-ucode) and, for NVIDIA, the"
say "nvidia packages — edit packages.txt first if you have not."
read -r -p "   Enter to run 'sudo pacman -Syu --needed ...', Ctrl-C to abort. " _
sudo pacman -Syu --needed "${PKGS[@]}"
```

with:

```bash
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
```

(Note `mesa` moves here from `packages.txt` — it's unconditional but grouped
with the other hardware-driven packages for clarity. `packages.txt` should
NOT list `mesa` anymore; if Task 1 left it there, remove it now as part of
this step and re-verify Task 1's Step 3 list doesn't include it twice.)

- [ ] **Step 2: Add the confirm-before-apply NVIDIA system-changes block**

Insert this immediately after the package-install block from Step 1 (still
before the existing `# 2. audio` section, which should now be renumbered
`# 3. audio` — renumber every subsequent section comment by one):

```bash
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
```

- [ ] **Step 3: Verify**

```sh
bash -n install/bootstrap.sh
```
Expected: no output (syntax OK). Also manually re-read the file top to
bottom to confirm section numbering in the `say` comments is consistent
after the insert (cosmetic, but the plan's later tasks assume the file
still parses as one coherent script).

- [ ] **Step 4: Commit**

```bash
git add install/bootstrap.sh
git commit -m "bootstrap: auto-detect CPU/GPU, confirm before NVIDIA system edits

CPU microcode and NVIDIA packages are now chosen automatically instead
of requiring a packages.txt hand-edit. Kernel-module-list, nouveau
blacklist, and suspend-service changes still ask before touching /etc;
the bootloader and kernel cmdline remain fully manual (documented)."
```

---

### Task 3: `bootstrap.sh` — SSH readiness, checksum-pinned font fetch, gitleaks hook wiring

**Files:**
- Modify: `install/bootstrap.sh`

- [ ] **Step 1: Add the checksum check to the existing Departure Mono fetch**

Find the existing block (now under the renumbered `# 5. fonts` section):
```bash
  dmurl="https://github.com/rektdeckard/departure-mono/releases/download/v1.500/DepartureMono-1.500.zip"
  if tmp="$(mktemp -d)" && curl -fsSL -o "$tmp/dm.zip" "$dmurl"; then
    mkdir -p "$HOME/.local/share/fonts/DepartureMono"
    bsdtar -xf "$tmp/dm.zip" -C "$tmp" 2>/dev/null || unzip -oq "$tmp/dm.zip" -d "$tmp"
    find "$tmp" -iname '*.otf' -exec cp {} "$HOME/.local/share/fonts/DepartureMono/" \;
    rm -rf "$tmp"
  else
    say "  (fetch failed — waybar will fall back to Iosevka; install it later)"
  fi
```

Replace with:
```bash
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
```

- [ ] **Step 2: Add SSH readiness after the font section (before the "launch on login" section)**

```bash
# N. ssh readiness -----------------------------------------------------
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
```
(Renumber this and all following `say`-labeled sections by one; keep the
numbering internally consistent, it's cosmetic only.)

- [ ] **Step 3: Add gitleaks pre-commit hook wiring, in the same new section or its own — after SSH readiness**

```bash
# N. git hooks (gitleaks secret scan) ----------------------------------
if [[ "$(git -C "$HOME/.config" config --get core.hooksPath 2>/dev/null)" != ".githooks" ]]; then
  say "Wiring the gitleaks pre-commit hook (git config core.hooksPath .githooks)."
  git -C "$HOME/.config" config core.hooksPath .githooks
else
  say "git hooks already wired — skipping."
fi
```

- [ ] **Step 4: Verify**

```sh
bash -n install/bootstrap.sh
```
Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add install/bootstrap.sh
git commit -m "bootstrap: checksum-pin font fetch, offer SSH keygen, wire gitleaks hook

Departure Mono's zip is now verified against a hardcoded sha256 before
extraction. SSH becomes functionally ready (not just installed) on a
fresh machine. The gitleaks pre-commit hook (added next) gets wired
automatically."
```

---

### Task 4: `security/scripts/lib.sh` — shared job helpers

**Files:**
- Create: `security/scripts/lib.sh`

**Interfaces:**
- Consumes: `/etc/skemos-security.conf` (written by Task 14) providing
  `SKEMOS_USER`, `SKEMOS_HOME` — falls back to erroring loudly if missing,
  since every job script needs these.
- Produces (sourced by every other job script — Tasks 5, 6, 7):
  `sk_log_path(job) -> path`, `sk_summary_path(job) -> path`,
  `sk_write_log(job, text...)`, `sk_write_summary(job, status, detail)`,
  `sk_notify(title, body)`.

- [ ] **Step 1: Write `security/scripts/lib.sh`**

```bash
#!/usr/bin/env bash
# Skemos security — shared helpers, sourced (not executed) by every job
# script. Installed read-only, root:root, at
# /usr/local/lib/skemos-security/lib.sh by bootstrap.sh (Task 14) — never
# run directly from ~/.config (see the ownership rule in the plan header).
set -euo pipefail

SKEMOS_SECURITY_CONF="/etc/skemos-security.conf"
[[ -r "$SKEMOS_SECURITY_CONF" ]] && source "$SKEMOS_SECURITY_CONF"
: "${SKEMOS_USER:?SKEMOS_USER not set — run install/bootstrap.sh first}"
: "${SKEMOS_HOME:?SKEMOS_HOME not set — run install/bootstrap.sh first}"

SK_LOG_DIR="/var/log/skemos-security"
SK_STATE_DIR="$SKEMOS_HOME/.local/state/skemos/security"

sk_log_path()     { echo "$SK_LOG_DIR/$1.log"; }
sk_summary_path() { echo "$SK_STATE_DIR/$1.summary.json"; }

# sk_write_log <job> <text...> — appends a timestamped block to the job's
# group-readable log.
sk_write_log() {
  local job=$1; shift
  install -d -o root -g skemos-security -m 0750 "$SK_LOG_DIR"
  {
    printf -- '--- %s ---\n' "$(date -Is)"
    printf '%s\n' "$*"
  } >> "$(sk_log_path "$job")"
  chown root:skemos-security "$(sk_log_path "$job")"
  chmod 0640 "$(sk_log_path "$job")"
}

# sk_write_summary <job> <status: ok|warn|fail> <detail> — overwrites the
# job's small JSON summary (what the panel's table reads) and notifies on
# warn/fail regardless of what triggered this run (see plan header).
sk_write_summary() {
  local job=$1 status=$2 detail=$3
  install -d -o "$SKEMOS_USER" -g "$SKEMOS_USER" -m 0700 "$SK_STATE_DIR"
  local ts; ts=$(date -Is)
  printf '{"last_run":"%s","status":"%s","detail":"%s"}\n' \
    "$ts" "$status" "${detail//\"/\\\"}" > "$(sk_summary_path "$job")"
  chown "$SKEMOS_USER:$SKEMOS_USER" "$(sk_summary_path "$job")"
  if [[ $status == warn || $status == fail ]]; then
    sk_notify "Skemos security: $job" "$detail"
  fi
}

# sk_notify <title> <body> — sends a desktop notification into the user's
# running mako, from a root process, via that user's D-Bus session.
sk_notify() {
  local uid; uid=$(id -u "$SKEMOS_USER" 2>/dev/null) || return 0
  [[ -S "/run/user/$uid/bus" ]] || return 0
  sudo -u "$SKEMOS_USER" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
    XDG_RUNTIME_DIR="/run/user/$uid" \
    notify-send -a "Skemos Security" "$1" "$2" || true
}
```

- [ ] **Step 2: Verify**

```sh
bash -n security/scripts/lib.sh
command -v shellcheck >/dev/null && shellcheck security/scripts/lib.sh || true
```
Expected: `bash -n` produces no output. If `shellcheck` is installed it may
warn about `set -e` interacting with `||`/conditionals in sourced files —
those are expected/benign here (the functions are designed to be called
from scripts that also set `-euo pipefail`); no code change needed for
those specific warnings.

- [ ] **Step 3: Commit**

```bash
git add security/scripts/lib.sh
git commit -m "security: add shared job-script helpers (log, summary, notify)"
```

---

### Task 5: `security/scripts/integrity-check.sh` + pacman resync hook

**Files:**
- Create: `security/scripts/integrity-check.sh`
- Create: `security/pacman-hooks/99-skemos-integrity-resync.hook`

**Interfaces:**
- Consumes: `security/scripts/lib.sh` (Task 4) — `sk_write_log`,
  `sk_write_summary`, `$SKEMOS_HOME`.
- Produces: baseline DB at `/var/lib/skemos-security/integrity.db`; the
  `--rebaseline` flag, used both by the pacman hook and by Task 14's
  install-time seeding step.

- [ ] **Step 1: Write `security/scripts/integrity-check.sh`**

```bash
#!/usr/bin/env bash
# Skemos security — file-integrity job. Hashes a curated path list and
# diffs against a baseline; a WARN means something changed OUTSIDE a
# tracked pacman transaction (the paired pacman hook re-baselines after
# every real upgrade — see 99-skemos-integrity-resync.hook).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

JOB=integrity
DB_DIR=/var/lib/skemos-security
DB_FILE="$DB_DIR/integrity.db"

WATCH_PATHS=(
  /usr/bin/sh /usr/bin/bash /usr/bin/sudo /usr/bin/ssh /usr/bin/pacman
  /usr/lib/systemd/systemd
  /etc/passwd /etc/sudoers /etc/pacman.conf
  "$SKEMOS_HOME/.bashrc" "$SKEMOS_HOME/.bash_profile"
  "$SKEMOS_HOME/.config/hypr/hyprland.lua"
  "$SKEMOS_HOME/.config/hypr/binds.lua"
  "$SKEMOS_HOME/.config/hypr/look.lua"
)
WATCH_DIRS=( /etc/pacman.d/hooks )

hash_current() {
  local f d
  for f in "${WATCH_PATHS[@]}"; do
    [[ -e $f ]] && sha256sum "$f"
  done
  for d in "${WATCH_DIRS[@]}"; do
    [[ -d $d ]] && find "$d" -type f -exec sha256sum {} \;
  done
}

install -d -o root -g root -m 0750 "$DB_DIR"

if [[ "${1:-}" == "--rebaseline" ]]; then
  hash_current | sort -k2 > "$DB_FILE"
  chmod 0600 "$DB_FILE"
  sk_write_log "$JOB" "rebaselined ($(wc -l < "$DB_FILE") paths)"
  sk_write_summary "$JOB" ok "baseline refreshed"
  exit 0
fi

if [[ ! -f $DB_FILE ]]; then
  hash_current | sort -k2 > "$DB_FILE"
  chmod 0600 "$DB_FILE"
  sk_write_log "$JOB" "first run — baseline created"
  sk_write_summary "$JOB" ok "baseline created"
  exit 0
fi

current="$(hash_current | sort -k2)"
diff_out="$(diff "$DB_FILE" <(printf '%s\n' "$current") || true)"

if [[ -z $diff_out ]]; then
  sk_write_log "$JOB" "clean — no changes"
  sk_write_summary "$JOB" ok "no changes"
else
  sk_write_log "$JOB" "CHANGED:"$'\n'"$diff_out"
  changed_count=$(grep -c '^[<>]' <<<"$diff_out" || true)
  sk_write_summary "$JOB" warn "$changed_count path(s) changed outside a tracked pacman transaction"
fi
```

- [ ] **Step 2: Write the pacman hook**

`security/pacman-hooks/99-skemos-integrity-resync.hook`:
```ini
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Package
Target = *

[Action]
Description = Skemos: re-baselining the file-integrity watch after this transaction
When = PostTransaction
Exec = /usr/local/lib/skemos-security/integrity-check.sh --rebaseline
```

- [ ] **Step 3: Verify**

```sh
bash -n security/scripts/integrity-check.sh
```
Expected: no output. Manually confirm the `.hook` file's `Exec=` path
(`/usr/local/lib/skemos-security/integrity-check.sh`) matches exactly what
Task 14 installs `integrity-check.sh` to.

- [ ] **Step 4: Commit**

```bash
git add security/scripts/integrity-check.sh security/pacman-hooks/99-skemos-integrity-resync.hook
git commit -m "security: add integrity-check job + pacman resync hook

Home-grown file-integrity monitor (no AUR-only aide needed): hashes a
curated path list, diffs against a baseline, WARNs on anything changed
outside a tracked pacman transaction. The pacman hook re-baselines
after every real upgrade so legitimate updates don't false-positive."
```

---

### Task 6: `rkhunter-scan.sh`, `arch-audit-scan.sh`, `ufw-status.sh`, `audit-status.sh`

**Files:**
- Create: `security/scripts/rkhunter-scan.sh`
- Create: `security/scripts/arch-audit-scan.sh`
- Create: `security/scripts/ufw-status.sh`
- Create: `security/scripts/audit-status.sh`

**Interfaces:**
- Consumes: `security/scripts/lib.sh` (Task 4).
- Note: `rkhunter` needs a one-time `rkhunter --propupd` before its first
  real check or it warns about unacknowledged file properties — that
  initialization happens in Task 14's install step, not in this script.

- [ ] **Step 1: Write `security/scripts/rkhunter-scan.sh`**

```bash
#!/usr/bin/env bash
# Skemos security — rkhunter job: rootkit/backdoor/hidden-process scan.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
JOB=rkhunter

out="$(rkhunter --check --sk --nocolors 2>&1)" || true
sk_write_log "$JOB" "$out"

warnings=$(grep -c '^Warning:' <<<"$out" || true)
if [[ ${warnings:-0} -gt 0 ]]; then
  sk_write_summary "$JOB" warn "$warnings warning(s) — see log"
else
  sk_write_summary "$JOB" ok "no warnings"
fi
```

- [ ] **Step 2: Write `security/scripts/arch-audit-scan.sh`**

```bash
#!/usr/bin/env bash
# Skemos security — arch-audit job: known-CVE exposure in installed packages.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
JOB=arch-audit

out="$(arch-audit 2>&1)" || true
sk_write_log "$JOB" "${out:-(no output)}"

if [[ -z $out ]]; then
  sk_write_summary "$JOB" ok "no known-vulnerable packages installed"
else
  count=$(wc -l <<<"$out")
  sk_write_summary "$JOB" warn "$count package(s) with known advisories — see log"
fi
```

- [ ] **Step 3: Write `security/scripts/ufw-status.sh`**

```bash
#!/usr/bin/env bash
# Skemos security — ufw-status job: snapshots the firewall's current state.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
JOB=ufw-status

out="$(ufw status verbose 2>&1)" || true
sk_write_log "$JOB" "$out"

if grep -q '^Status: active' <<<"$out"; then
  rules=$(grep -cE '^\[|^[0-9]+/' <<<"$out" || true)
  sk_write_summary "$JOB" ok "active"
else
  sk_write_summary "$JOB" warn "ufw is not active"
fi
```

- [ ] **Step 4: Write `security/scripts/audit-status.sh`**

```bash
#!/usr/bin/env bash
# Skemos security — audit-status job: snapshots today's watched-path events.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
JOB=audit-status

out="$(ausearch -ts today 2>&1)" || out=""
if [[ -z $out ]] || ! grep -q '^type=' <<<"$out"; then
  sk_write_log "$JOB" "no watched-path events today"
  sk_write_summary "$JOB" ok "no watched-path events today"
else
  sk_write_log "$JOB" "$out"
  count=$(grep -c '^type=' <<<"$out")
  sk_write_summary "$JOB" warn "$count watched-path event(s) today — see log"
fi
```

- [ ] **Step 5: Verify**

```sh
for f in security/scripts/{rkhunter-scan,arch-audit-scan,ufw-status,audit-status}.sh; do
  bash -n "$f" || echo "FAILED: $f"
done
```
Expected: no `FAILED` lines.

- [ ] **Step 6: Commit**

```bash
git add security/scripts/{rkhunter-scan,arch-audit-scan,ufw-status,audit-status}.sh
git commit -m "security: add rkhunter, arch-audit, ufw, and auditd job scripts

All four follow the same shape as integrity-check.sh: run the check,
log full output, write a small ok/warn summary. ufw-status and
audit-status are snapshot-style (nothing to 'scan', just current
state) but use the identical pattern for panel consistency."
```

---

### Task 7: `security/scripts/skemos-security-run` — privileged dispatcher

**Files:**
- Create: `security/scripts/skemos-security-run`

**Interfaces:**
- Consumes: nothing (pure dispatch — deliberately has zero dependency on
  `lib.sh` so its own logic is trivially auditable).
- Produces: the one command the sudoers rule (Task 10) grants NOPASSWD on.
  Accepts exactly one of `integrity`, `rkhunter`, `arch-audit`,
  `ufw-status`, `audit-status` as `$1`; anything else exits 1.

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# Skemos security — privileged dispatcher. Installed root:root 0755 at
# /usr/local/bin/skemos-security-run by bootstrap.sh (Task 14); granted
# NOPASSWD via /etc/sudoers.d/skemos-security for exactly this path.
#
# Only starts one of a hardcoded set of systemd units. Never execute
# arbitrary input here — this file is the entire trust boundary for the
# sudoers rule.
set -euo pipefail

case "${1:-}" in
  integrity)    exec systemctl start skemos-integrity.service ;;
  rkhunter)     exec systemctl start rkhunter-scan.service ;;
  arch-audit)   exec systemctl start arch-audit-scan.service ;;
  ufw-status)   exec systemctl start ufw-status.service ;;
  audit-status) exec systemctl start audit-status.service ;;
  *)
    echo "skemos-security-run: unknown job '${1:-}'" >&2
    echo "expected one of: integrity rkhunter arch-audit ufw-status audit-status" >&2
    exit 1
    ;;
esac
```

- [ ] **Step 2: Verify**

```sh
bash -n security/scripts/skemos-security-run
```
Expected: no output. Also manually confirm the 5 unit names here match
exactly the 5 `.service` filenames created in Task 9.

- [ ] **Step 3: Commit**

```bash
git add security/scripts/skemos-security-run
git commit -m "security: add the sudoers-granted job dispatcher

Fixed 5-job allowlist, no arbitrary argument passthrough. This is the
entire trust boundary for the panel's passwordless 'run now' action."
```

---

### Task 8: `security/audit-rules/skemos.rules` (template)

**Files:**
- Create: `security/audit-rules/skemos.rules`

- [ ] **Step 1: Write the template**

```
## Skemos security — real-time auditd watch rules for sensitive paths.
## This is a TEMPLATE: __SKEMOS_HOME__ is substituted for the real home
## directory by bootstrap.sh (Task 14) before this is installed to
## /etc/audit/rules.d/skemos.rules and loaded with `augenrules --load`.
-w __SKEMOS_HOME__/.ssh -p wa -k skemos_ssh
-w /etc/shadow -p wa -k skemos_shadow
-w /etc/sudoers.d/ -p wa -k skemos_sudoers
-w /etc/pacman.d/ -p wa -k skemos_pacman
-w /etc/passwd -p wa -k skemos_passwd
```

- [ ] **Step 2: Verify**

Manually confirm the placeholder spelling (`__SKEMOS_HOME__`, double
underscores both sides) exactly matches the `sed` substitution string Task
14 will use — a mismatch here means the substitution silently does nothing
and the literal placeholder text ends up in the live audit rule.

- [ ] **Step 3: Commit**

```bash
git add security/audit-rules/skemos.rules
git commit -m "security: add auditd watch-rule template for sensitive paths"
```

---

### Task 9: `security/systemd/*.{service,timer}` — 5 jobs, 10 files

**Files:**
- Create: `security/systemd/skemos-integrity.service`
- Create: `security/systemd/skemos-integrity.timer`
- Create: `security/systemd/rkhunter-scan.service`
- Create: `security/systemd/rkhunter-scan.timer`
- Create: `security/systemd/arch-audit-scan.service`
- Create: `security/systemd/arch-audit-scan.timer`
- Create: `security/systemd/ufw-status.service`
- Create: `security/systemd/ufw-status.timer`
- Create: `security/systemd/audit-status.service`
- Create: `security/systemd/audit-status.timer`

**Interfaces:**
- Consumes: `/usr/local/lib/skemos-security/<job-script>.sh` as
  `ExecStart` targets — these paths only exist after Task 14 runs, but the
  unit files can be authored and syntax-verified before that (see Step 6).

- [ ] **Step 1: Write the integrity unit (daily)**

`security/systemd/skemos-integrity.service`:
```ini
[Unit]
Description=Skemos security — file integrity check

[Service]
Type=oneshot
ExecStart=/usr/local/lib/skemos-security/integrity-check.sh
```

`security/systemd/skemos-integrity.timer`:
```ini
[Unit]
Description=Skemos security — daily file integrity check

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

- [ ] **Step 2: Write the rkhunter unit (weekly)**

`security/systemd/rkhunter-scan.service`:
```ini
[Unit]
Description=Skemos security — rkhunter rootkit scan

[Service]
Type=oneshot
ExecStart=/usr/local/lib/skemos-security/rkhunter-scan.sh
```

`security/systemd/rkhunter-scan.timer`:
```ini
[Unit]
Description=Skemos security — weekly rkhunter scan

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
```

- [ ] **Step 3: Write the arch-audit unit (weekly)**

`security/systemd/arch-audit-scan.service`:
```ini
[Unit]
Description=Skemos security — arch-audit CVE check

[Service]
Type=oneshot
ExecStart=/usr/local/lib/skemos-security/arch-audit-scan.sh
```

`security/systemd/arch-audit-scan.timer`:
```ini
[Unit]
Description=Skemos security — weekly arch-audit CVE check

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
```

- [ ] **Step 4: Write the ufw-status unit (hourly)**

`security/systemd/ufw-status.service`:
```ini
[Unit]
Description=Skemos security — ufw status snapshot

[Service]
Type=oneshot
ExecStart=/usr/local/lib/skemos-security/ufw-status.sh
```

`security/systemd/ufw-status.timer`:
```ini
[Unit]
Description=Skemos security — hourly ufw status snapshot

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
```

- [ ] **Step 5: Write the audit-status unit (hourly)**

`security/systemd/audit-status.service`:
```ini
[Unit]
Description=Skemos security — auditd watched-path event snapshot

[Service]
Type=oneshot
ExecStart=/usr/local/lib/skemos-security/audit-status.sh
```

`security/systemd/audit-status.timer`:
```ini
[Unit]
Description=Skemos security — hourly auditd event snapshot

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
```

- [ ] **Step 6: Verify all 10 unit files**

```sh
for f in security/systemd/*.service security/systemd/*.timer; do
  systemd-analyze verify "$f" 2>&1 | grep -v "Failed to load AppArmor" || true
done
```
Expected: warnings about `ExecStart=` pointing at a file that doesn't
exist yet are acceptable at this stage (the target scripts aren't installed
to `/usr/local/lib/skemos-security/` until Task 14) — real syntax errors
(bad `[Section]` names, malformed keys) are not. If `systemd-analyze verify`
reports only the missing-executable warning for each `ExecStart`, that's a
pass for this task.

- [ ] **Step 7: Commit**

```bash
git add security/systemd/
git commit -m "security: add systemd units for all 5 jobs (3 timers + 2 hourly snapshots)

integrity=daily, rkhunter/arch-audit=weekly, ufw-status/audit-status=
hourly. The SUPER+S panel's 'run now' starts these same units, so
systemctl is-active is authoritative regardless of trigger source."
```

---

### Task 10: `security/sudoers.d/skemos-security` (template)

**Files:**
- Create: `security/sudoers.d/skemos-security`

- [ ] **Step 1: Write the template**

```
# Skemos security — lets the SUPER+S panel trigger a scan with no
# re-prompt. TEMPLATE: __SKEMOS_USER__ is substituted for the real
# username by bootstrap.sh (Task 14), which validates the result with
# `visudo -c` BEFORE installing it to /etc/sudoers.d/skemos-security.
#
# The wrapper (security/scripts/skemos-security-run) only accepts a fixed
# 5-job allowlist — nothing else is reachable through this rule. No
# blanket sudo, no wildcard paths.
__SKEMOS_USER__ ALL=(root) NOPASSWD: /usr/local/bin/skemos-security-run
```

- [ ] **Step 2: Verify the template's post-substitution shape is valid sudoers syntax**

```sh
sed 's/__SKEMOS_USER__/bas/g' security/sudoers.d/skemos-security > /tmp/skemos-sudoers-check
visudo -c -f /tmp/skemos-sudoers-check
rm -f /tmp/skemos-sudoers-check
```
Expected: `/tmp/skemos-sudoers-check: parsed OK`. (This is exactly the
substitution Task 14 performs at real install time, just checked here
against a throwaway username so this task doesn't require root or touch
the real system.)

- [ ] **Step 3: Commit**

```bash
git add security/sudoers.d/skemos-security
git commit -m "security: add sudoers template for the security-run wrapper

Validated with visudo -c against a substituted copy (parses OK).
Real installation always re-validates before activating — see Task 14."
```

---

### Task 11: `.githooks/pre-commit` — gitleaks secret scan

**Files:**
- Create: `.githooks/pre-commit` (executable)

- [ ] **Step 1: Write the hook**

```bash
#!/usr/bin/env bash
# Skemos — pre-commit secret scan. Wired via:
#   git config core.hooksPath .githooks
# (done automatically by install/bootstrap.sh). The repo stays PUBLIC by
# deliberate choice — this is the safety net for that.
set -euo pipefail

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "pre-commit: gitleaks not installed — skipping scan." >&2
  echo "  Install it: see install/packages.txt, or run install/bootstrap.sh." >&2
  exit 0
fi

gitleaks protect --staged --redact -v
```

- [ ] **Step 2: Make it executable and verify syntax**

```sh
chmod +x .githooks/pre-commit
bash -n .githooks/pre-commit
```
Expected: no output from `bash -n`.

- [ ] **Step 3: Functional check — confirm the hook actually blocks a fake secret (only if `gitleaks` is already installed on this machine; skip gracefully otherwise)**

```sh
if command -v gitleaks >/dev/null 2>&1; then
  git config core.hooksPath .githooks
  echo 'AKIAABCDEFGHIJKLMNOP = "fake-test-secret-not-real"' > /tmp/skemos-secret-test.env
  cp /tmp/skemos-secret-test.env ./__skemos_secret_test.env
  git add __skemos_secret_test.env
  git commit -m "test: should be blocked by gitleaks" ; echo "commit exit code: $?"
  git reset HEAD __skemos_secret_test.env >/dev/null 2>&1 || true
  rm -f __skemos_secret_test.env /tmp/skemos-secret-test.env
else
  echo "gitleaks not installed on this machine — functional check deferred to Task 16."
fi
```
Expected (if gitleaks is present): the `git commit` fails (non-zero exit),
gitleaks prints a finding, and the two cleanup lines remove the test file
from the index and working tree so nothing test-related lingers.

- [ ] **Step 4: Commit** (the hook file itself, once the above confirms it's not a footgun)

```bash
git add .githooks/pre-commit
git commit -m "security: add gitleaks pre-commit hook

Wired automatically by bootstrap.sh via core.hooksPath. Degrades
gracefully (warns, doesn't block) if gitleaks isn't installed yet."
```

---

### Task 12: `security/scripts/security-panel.sh` — the `SUPER+S` TUI

**Files:**
- Create: `security/scripts/security-panel.sh` (executable)

**Interfaces:**
- Consumes: `~/.local/state/skemos/security/<job>.summary.json` (written by
  every job script via `sk_write_summary`), `systemctl is-active
  <unit>.service`, `sudo /usr/local/bin/skemos-security-run <job>`,
  `journalctl -u <unit>.service -f`, `/var/log/skemos-security/<job>.log`.
- Runs **unprivileged**, as the user — the one script in `security/` never
  copied to a root-owned location (see plan header).

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# Skemos security — SUPER+S interactive panel. Runs unprivileged, straight
# from the repo checkout. Nothing here runs as root; scan triggers go
# through `sudo skemos-security-run`, gated by the narrow NOPASSWD rule in
# /etc/sudoers.d/skemos-security (Task 10/14).
set -uo pipefail

STATE_DIR="$HOME/.local/state/skemos/security"
JOBS=(integrity rkhunter arch-audit ufw-status audit-status)
declare -A UNIT=(
  [integrity]=skemos-integrity.service
  [rkhunter]=rkhunter-scan.service
  [arch-audit]=arch-audit-scan.service
  [ufw-status]=ufw-status.service
  [audit-status]=audit-status.service
)
declare -A LABEL=(
  [integrity]="INTEGRITY"
  [rkhunter]="RKHUNTER"
  [arch-audit]="ARCH-AUDIT"
  [ufw-status]="UFW"
  [audit-status]="AUDITD"
)

# palette — mirrors hypr/colors.lua / bash/skemos.bash
ink=$'\e[38;2;229;225;214m'; dim=$'\e[38;2;154;148;138m'
fnt=$'\e[38;2;85;81;74m';    acc=$'\e[38;2;193;102;58m'
rst=$'\e[0m'

live_state() {
  local st; st=$(systemctl is-active "${UNIT[$1]}" 2>/dev/null || echo inactive)
  [[ $st == active || $st == activating ]] && echo RUNNING || echo IDLE
}

row() {
  local job=$1 summary="$STATE_DIR/$job.summary.json"
  local status="—" when="—"
  if [[ -f $summary ]]; then
    status=$(jq -r '.status // "—"' "$summary" 2>/dev/null | tr '[:lower:]' '[:upper:]')
    when=$(jq -r '.last_run // "—"' "$summary" 2>/dev/null)
  fi
  local live color
  live=$(live_state "$job")
  color=$dim
  [[ $status == WARN || $status == FAIL ]] && color=$acc
  [[ $live == RUNNING ]] && color=$acc
  printf '%-12s %s%-6s%s  %-25s %s%s%s' "${LABEL[$job]}" "$color" "$status" "$rst" "$when" "$color" "$live" "$rst"
}

draw_table() {
  clear
  printf '%s╭─ SKEMOS SECURITY ────────────────────────────────────────────╮%s\n' "$fnt" "$rst"
  printf '%s   %-12s %-6s  %-25s %s%s\n' "$dim" "JOB" "LAST" "WHEN" "STATE" "$rst"
  local i=1 job
  for job in "${JOBS[@]}"; do
    printf ' %s%d%s %s\n' "$acc" "$i" "$rst" "$(row "$job")"
    ((i++))
  done
  printf '%s╰──────────────────────────────────────────────────────────────╯%s\n' "$fnt" "$rst"
  printf '%s  [1-5] select · q quit%s\n' "$dim" "$rst"
}

action_menu() {
  local job=$1
  local opts="run now
view last log"
  [[ $(live_state "$job") == RUNNING ]] && opts+="
tail live"
  local choice
  choice=$(printf '%s\n' "$opts" | fzf --prompt="${LABEL[$job]}> " --height=6 --reverse --no-info \
    --color="bg+:#34322d,fg+:#e5e1d6,fg:#9a948a,prompt:#c1663a") || return 0
  case "$choice" in
    "run now")
      sudo /usr/local/bin/skemos-security-run "$job"
      ;;
    "view last log")
      if [[ -r "/var/log/skemos-security/$job.log" ]]; then
        less "/var/log/skemos-security/$job.log"
      else
        echo "no log yet for $job — press Enter to go back"
        read -r
      fi
      ;;
    "tail live")
      journalctl -u "${UNIT[$job]}" -f
      ;;
  esac
}

while true; do
  draw_table
  if read -rsn1 -t 2 key; then
    case "$key" in
      q) exit 0 ;;
      [1-5]) action_menu "${JOBS[$((key-1))]}" ;;
    esac
  fi
done
```

- [ ] **Step 2: Make it executable and verify syntax**

```sh
chmod +x security/scripts/security-panel.sh
bash -n security/scripts/security-panel.sh
```
Expected: no output.

- [ ] **Step 3: Manual dry-run against synthetic state (no root, no installed units needed)**

```sh
mkdir -p ~/.local/state/skemos/security
cat > ~/.local/state/skemos/security/integrity.summary.json <<'EOF'
{"last_run":"2026-09-17T12:00:00+00:00","status":"ok","detail":"no changes"}
EOF
cat > ~/.local/state/skemos/security/rkhunter.summary.json <<'EOF'
{"last_run":"2026-09-17T09:00:00+00:00","status":"warn","detail":"2 warning(s) — see log"}
EOF
bash security/scripts/security-panel.sh
# Press 1, confirm the fzf sub-menu opens with "run now"/"view last log".
# Press Esc to back out, then press 2 and confirm rkhunter shows WARN in
# accent color with a "2 warning(s)..." detail visible via jq if inspected
# directly. Press q to quit.
rm -f ~/.local/state/skemos/security/{integrity,rkhunter}.summary.json
```
Expected: the table renders with box-drawing matching the rest of the rice,
row 1 shows `INTEGRITY OK ... IDLE`, row 2 shows `RKHUNTER WARN ... IDLE` in
the accent color, `q` exits cleanly. (`sudo skemos-security-run` and
`journalctl -u ...` will fail at this stage since Task 14 hasn't installed
anything yet — that's expected; this step only verifies the table/picker
render and navigate correctly.)

- [ ] **Step 4: Commit**

```bash
git add security/scripts/security-panel.sh
git commit -m "security: add the SUPER+S interactive panel

Plain-bash 2s-poll table (live RUNNING state from systemctl is-active)
with an fzf action sub-menu per row: run now / view last log / tail
live. Runs unprivileged; 'run now' goes through the sudoers-gated
dispatcher."
```

---

### Task 13: `hypr/binds.lua` + `hypr/rules.lua` — `SUPER+S` bind and floating window rule

**Files:**
- Modify: `hypr/binds.lua`
- Modify: `hypr/rules.lua`

- [ ] **Step 1: Add the `SECURITY` scripts path and the bind**

In `hypr/binds.lua`, add a new path variable next to the existing
`SCRIPTS` line (around line 9):
```lua
local SCRIPTS  = HOME .. "/.config/hypr/scripts"
local SECURITY = HOME .. "/.config/security/scripts"
```

Then add a new fenced block right after the `-- --- window ---` section
(after the `SUPER+J` bind, before the `GROUP BARS` block):
```lua
-- ==== SECURITY PANEL ====================================================
-- SUPER+S opens the security dashboard: aggregated scan status, live
-- busy/idle per job, log viewing, and live-tail for anything running.
-- See SKEMOS.md "Security" and
-- docs/superpowers/specs/2026-09-17-security-hardening-and-containment-design.md
hl.bind(mod .. " + S", hl.dsp.exec_cmd(
  "foot -a skemos-security -W 110x32 -T 'SKEMOS SECURITY' -e " .. SECURITY .. "/security-panel.sh"))
-- ==== end SECURITY PANEL =================================================
```

- [ ] **Step 2: Add the floating window rule**

In `hypr/rules.lua`, add after the existing "Common floating dialogs"
block:
```lua
-- --- security panel: fixed-size, centered floating window ---------------
hl.window_rule({
  name   = "sk-security-panel",
  match  = { class = "^skemos-security$" },
  float  = true,
  center = true,
})
```

- [ ] **Step 3: Verify**

```sh
Hyprland --verify-config
```
Expected: `config ok`. If it errors, the most likely cause is the
`hl.window_rule` field names — re-check against
`/usr/share/hypr/stubs/hl.meta.lua`'s `HL.WindowRuleSpec` and the working
examples already in `hypr/rules.lua` (this rule intentionally uses only
`name`/`match`/`float`/`center`, all of which are already used elsewhere in
that file, so this should not need adjustment).

- [ ] **Step 4: Commit**

```bash
git add hypr/binds.lua hypr/rules.lua
git commit -m "hypr: bind SUPER+S to the security panel, float+center its window

Sized via foot's own -W flag (110x32 chars) rather than a Hyprland
size rule, matching how other fixed-purpose floating windows in this
rice are handled."
```

---

### Task 14: `bootstrap.sh` — install security tooling into root-owned locations

**Files:**
- Modify: `install/bootstrap.sh`

**Interfaces:**
- Consumes every file from Tasks 4–11 (`security/scripts/*`,
  `security/systemd/*`, `security/sudoers.d/skemos-security`,
  `security/pacman-hooks/*`, `security/audit-rules/skemos.rules`).
- Produces: `/etc/skemos-security.conf`, `/usr/local/lib/skemos-security/*`,
  `/usr/local/bin/skemos-security-run`, installed systemd units (enabled +
  started timers), `/etc/sudoers.d/skemos-security`,
  `/etc/pacman.d/hooks/99-skemos-integrity-resync.hook`,
  `/etc/audit/rules.d/skemos.rules`, the `skemos-security` group, `ufw`
  enabled default-deny-incoming.

- [ ] **Step 1: Add the security-tooling install section to `bootstrap.sh`**

Add this as a new section near the end, after the git-hooks wiring from
Task 3 and before the final `say "Done. ..."` line:

```bash
# N. security tooling ---------------------------------------------------
say "Installing Skemos security tooling (systemd units, sudoers rule, pacman hook)."

SEC_SRC="$HERE/../security"

# group + per-machine config
if ! getent group skemos-security >/dev/null; then
  sudo groupadd skemos-security
fi
sudo usermod -aG skemos-security "$USER"

sudo tee /etc/skemos-security.conf >/dev/null <<EOF
SKEMOS_USER=$USER
SKEMOS_HOME=$HOME
EOF

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
for t in skemos-integrity rkhunter-scan arch-audit-scan ufw-status audit-status; do
  sudo systemctl enable --now "$t.timer"
done

# sudoers (template substitution, validated before install)
tmp_sudoers="$(mktemp)"
sed "s/__SKEMOS_USER__/$USER/g" "$SEC_SRC/sudoers.d/skemos-security" > "$tmp_sudoers"
if sudo visudo -c -f "$tmp_sudoers" >/dev/null 2>&1; then
  sudo install -o root -g root -m 0440 "$tmp_sudoers" /etc/sudoers.d/skemos-security
  say "  sudoers rule installed."
else
  say "  sudoers template failed validation — NOT installed. Check $tmp_sudoers."
fi
rm -f "$tmp_sudoers"

# pacman hook
sudo install -d -o root -g root -m 0755 /etc/pacman.d/hooks
sudo install -o root -g root -m 0644 "$SEC_SRC/pacman-hooks/99-skemos-integrity-resync.hook" /etc/pacman.d/hooks/

# audit rules (template substitution)
sudo install -d -o root -g root -m 0750 /etc/audit/rules.d
sed "s|__SKEMOS_HOME__|$HOME|g" "$SEC_SRC/audit-rules/skemos.rules" | sudo tee /etc/audit/rules.d/skemos.rules >/dev/null
sudo chmod 0640 /etc/audit/rules.d/skemos.rules
sudo systemctl enable --now auditd.service
sudo augenrules --load

# ufw — default deny incoming, allow outgoing
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw --force enable

# first-run initialization so the panel's first view isn't just "baseline created"
sudo /usr/local/lib/skemos-security/integrity-check.sh --rebaseline
sudo rkhunter --propupd || true

say "Security tooling installed. Log out/in once for the skemos-security group to take effect."
```

- [ ] **Step 2: Verify**

```sh
bash -n install/bootstrap.sh
```
Expected: no output. This is as far as this task can be verified without
running it — the actual privileged install requires a live `sudo` session
(see Task 16).

- [ ] **Step 3: Commit**

```bash
git add install/bootstrap.sh
git commit -m "bootstrap: install security tooling into root-owned locations

Copies security/ scripts, units, sudoers rule, pacman hook, and audit
rules from the repo (user-writable, source of truth) into
/usr/local/lib, /usr/local/bin, /etc/systemd/system, /etc/sudoers.d,
/etc/pacman.d/hooks, and /etc/audit/rules.d (root-owned) — never
executed directly from ~/.config. Enables ufw default-deny-incoming
and seeds the first integrity baseline + rkhunter property db."
```

---

### Task 15: `SKEMOS.md` + `INSTALL.md` documentation

**Files:**
- Modify: `SKEMOS.md`
- Modify: `INSTALL.md`

- [ ] **Step 1: Add a "Security" section to `SKEMOS.md`**

Add a new top-level section (after "Look — decisions made", before "Open /
next"):

```markdown
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
  note below): `skemos-integrity` (daily, home-grown hash-baseline FIM —
  `aide` is AUR-only so this is hand-rolled; a pacman hook re-baselines
  after every real transaction, so a WARN means something changed outside
  one), `rkhunter-scan` (weekly, rootkit/backdoor signatures),
  `arch-audit-scan` (weekly, known-CVE exposure in installed packages),
  `ufw-status` / `audit-status` (hourly snapshots — `ufw` and `auditd` are
  always-on, these just surface current state). `lynis` is installed but
  deliberately **not** automated — run `sudo lynis audit system` by hand
  when you want its broader, long-form posture audit.
- **`SUPER+S`** opens the panel (`security/scripts/security-panel.sh`, a
  `foot` window, `fzf` for the per-row action menu). It reads
  `~/.local/state/skemos/security/*.summary.json` and asks `systemctl
  is-active` for live state — busy/idle is correct regardless of whether a
  job was started by its timer or by the panel, because both start the
  *same* systemd unit. `[r]` run now, `[l]` last log, `[t]` tail live
  (`journalctl -u <unit> -f`, only offered while `RUNNING`).
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
- **Declined**: `opensnitch` (interactive per-connection popups — exactly
  the friction/bloat this pass was trying to avoid), `fail2ban` (nothing to
  protect while `sshd` stays disabled by default — add it if you ever
  enable inbound SSH).

Full design: `docs/superpowers/specs/2026-09-17-security-hardening-and-containment-design.md`.
```

- [ ] **Step 2: Add a "Config map" row for `security/` in `SKEMOS.md`**

In the existing "Config map" table (near the top), add after the
`bash/skemos.bash` row's paragraph, one new line in the "Other:" list:

```
`security/` (scripts, systemd units, sudoers/pacman-hook/audit-rule
templates — source of truth for the SUPER+S panel; installed root-owned by
`bootstrap.sh`, see "Security" below).
```

- [ ] **Step 3: Update `INSTALL.md`**

In §3 ("Packages + system setup"), update the `bootstrap.sh` description
paragraph to mention hardware auto-detection and the security install:

Replace:
```
`bootstrap.sh` runs `sudo pacman -Syu --needed` on the list, enables PipeWire +
NetworkManager, rebuilds the font cache (fetching Departure Mono into
`~/.local/share/fonts` if it is not already installed), appends the Hyprland
launch line to `~/.bash_profile`, and sources the Skemos shell dressing (prompt
+ login banner) from `~/.bashrc`. It never touches disks, the ESP, the
bootloader, or autologin. Review it before running — it is the only privileged
step.
```
with:
```
`bootstrap.sh` auto-detects your CPU vendor and GPU (adding microcode and,
if NVIDIA is present, the NVIDIA package set automatically — no more
hand-editing `packages.txt`), then runs `sudo pacman -Syu --needed` on the
combined list. It enables PipeWire + NetworkManager, rebuilds the font
cache (fetching Departure Mono into `~/.local/share/fonts`, checksum-
verified, if not already installed), offers to generate an SSH keypair if
you don't have one, wires the `gitleaks` pre-commit hook, appends the
Hyprland launch line to `~/.bash_profile`, sources the Skemos shell
dressing from `~/.bashrc`, and installs the security-monitoring tooling
(systemd units, a scoped sudoers rule, a pacman hook, audit rules — see
`SKEMOS.md` "Security"). Any NVIDIA kernel-module/initramfs/nouveau-
blacklist change is shown to you and asks before touching `/etc`. It never
touches disks, the ESP, the bootloader, or autologin. Review it before
running — it is the only privileged step.
```

In §7 ("Keybinds"), add a row:
```
| `SUPER`+`S` | security panel — scan status, logs, live tail |
```

Add a new `## 10 · Security` section at the end (after the existing "## 9 ·
Plugins" section):
```markdown
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
- `sshd` is installed but never auto-enabled. If you turn on inbound SSH
  (`sudo systemctl enable --now sshd`), also add `sudo ufw allow ssh` and
  consider adding `fail2ban` (not installed by default — nothing to guard
  while `sshd` is off).
- `sudo lynis audit system` is available any time for a deeper, on-demand
  posture check — it's installed but intentionally not wired into the
  automated/notified flow (its output is long-form, better read directly).
```

- [ ] **Step 4: Verify**

Read both files back and confirm no leftover references to the old
manual "edit `packages.txt` for your CPU/GPU" instructions remain anywhere
(they should all now point at auto-detection).

```sh
grep -n "edit packages.txt" INSTALL.md SKEMOS.md || echo "clean"
```
Expected: `clean` (or only matches that are about a genuinely still-manual
edit, like the `kitty` terminal toggle — re-read any hit to confirm it's not
stale CPU/GPU guidance).

- [ ] **Step 5: Commit**

```bash
git add SKEMOS.md INSTALL.md
git commit -m "docs: document the security tooling and auto-detecting install

SKEMOS.md gets a full 'Security' section (threat model, the 5 jobs,
the panel, the ownership rule). INSTALL.md's bootstrap.sh description
and keybind table are updated; a new §10 covers first-boot security
notes (group re-login, sshd-off-by-default, lynis on demand)."
```

---

### Task 16: End-to-end verification (requires a human with `sudo`)

**Files:** none — this task only runs and inspects.

This task cannot be completed non-interactively: `sudo pacman -Syu`,
`sudo mkinitcpio -P` (if NVIDIA), and every step in Task 14's install
section need a live terminal and a typed password. Hand this task to the
user; report back what each check showed.

- [ ] **Step 1: Run the real install**

```sh
~/.config/install/bootstrap.sh
```
Watch for: the hardware-detection banner naming the right CPU/GPU, the
NVIDIA confirm-prompts appearing (only if NVIDIA is present) and not
silently editing anything without asking, the SSH-keygen prompt, and the
security-tooling section completing without the "sudoers template failed
validation" message.

- [ ] **Step 2: Log out and back in** (for the new `skemos-security` group
  to apply to the session), then confirm group membership:

```sh
groups | tr ' ' '\n' | grep skemos-security
```
Expected: `skemos-security` printed.

- [ ] **Step 3: Confirm the systemd units and timers are live**

```sh
systemctl list-timers 'skemos-*' 'rkhunter-*' 'arch-audit-*' 'ufw-status*' 'audit-status*'
systemctl status skemos-integrity.service --no-pager
```
Expected: 5 timers listed with sane next-run times; the integrity service
shows as `inactive (dead)` with an exit code `0` from its install-time
seeding run in Task 14.

- [ ] **Step 4: Trigger a manual run and confirm busy-state + live tail work**

```sh
sudo /usr/local/bin/skemos-security-run rkhunter &
sleep 1
systemctl is-active rkhunter-scan.service   # expect: active or activating
journalctl -u rkhunter-scan.service -f      # Ctrl-C once you see output flowing
wait
systemctl is-active rkhunter-scan.service   # expect: inactive (finished)
cat ~/.local/state/skemos/security/rkhunter.summary.json   # expect valid JSON, ok or warn
```

- [ ] **Step 5: Trigger a deliberate integrity WARN and confirm the pacman-hook resync clears it**

```sh
sudo touch /etc/passwd   # updates mtime; sha256 unchanged, so this alone won't trip it —
# instead, append a harmless trailing newline to actually change the hash:
sudo tee -a /etc/passwd <<< "" >/dev/null
sudo /usr/local/lib/skemos-security/integrity-check.sh
cat ~/.local/state/skemos/security/integrity.summary.json   # expect status: warn
sudo pacman -Syu --needed jq   # any real transaction — triggers the pacman hook
cat ~/.local/state/skemos/security/integrity.summary.json   # expect status: ok, "baseline refreshed"
```
(If `/etc/passwd` already ends in a blank line, pick any other watched,
low-risk file to append a byte to instead — the point is proving a
hash-diff is detected and then cleared by a real transaction, not this
specific file.)

- [ ] **Step 6: Confirm the sudoers rule fails closed on an unlisted argument**

```sh
sudo /usr/local/bin/skemos-security-run rm-rf-everything ; echo "exit: $?"
```
Expected: the "unknown job" message and a non-zero exit code — never an
attempt to run anything.

- [ ] **Step 7: Open the panel for real**

```sh
# from inside Hyprland:
# press SUPER+S
```
Expected: the floating, centered panel opens; all 5 rows render; press a
digit to open a row's `fzf` action menu; confirm a row shows `RUNNING`
live if you start something from a separate terminal
(`sudo /usr/local/bin/skemos-security-run arch-audit`) while the panel is
open, without you having triggered it from the panel itself.

- [ ] **Step 8: Confirm the `gitleaks` pre-commit hook is live**

```sh
cd ~/.config
echo 'AKIAABCDEFGHIJKLMNOP = "fake-test-secret-not-real"' > __skemos_secret_test.env
git add __skemos_secret_test.env
git commit -m "test: should be blocked" ; echo "exit: $?"
git reset HEAD __skemos_secret_test.env
rm -f __skemos_secret_test.env
```
Expected: non-zero exit, gitleaks output showing the finding, nothing
actually committed.

- [ ] **Step 9: Report results back** — this plan is complete once every
  check above passes on the real machine. If anything diverges (e.g., a
  different distro-specific `ausearch`/`rkhunter` output format changes a
  grep pattern's match count), fix the specific script in `security/`, re-run
  Task 14's install step for that one file
  (`sudo install -o root -g root -m 0755 security/scripts/<file>.sh
  /usr/local/lib/skemos-security/`), and re-verify — don't re-run the whole
  of Task 14 unless multiple files changed.
