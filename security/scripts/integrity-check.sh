#!/usr/bin/env bash
# Skemos security — file-integrity job. Hashes a curated path list and
# diffs against a baseline; a WARN means something changed OUTSIDE a
# tracked pacman transaction (the paired pacman hook re-baselines the
# SYSTEM paths after every real upgrade — see 99-skemos-integrity-resync.hook).
#
# Modes:
#   (no argument)       check current hashes against the baseline.
#   --rebaseline        refresh ONLY the system entries (binaries, /etc,
#                       the security tooling itself); user-path entries
#                       (everything under $SKEMOS_HOME) are carried over
#                       from the old DB unchanged, so a pacman transaction
#                       can never launder edits to ~/.bashrc etc. into the
#                       baseline. Run by the pacman hook.
#   --rebaseline-all    rehash EVERYTHING — the bootstrap seed step, and the
#                       manual "I changed that file on purpose" accept.
#
# Threat model: this runs as root over paths malware-as-the-user can
# replace with symlinks or FIFOs. Only regular, non-symlink files are
# hashed, and every hash is time-bounded, so a planted FIFO or a symlink
# to /dev/zero can never hang the job (or the pacman transaction that
# runs this synchronously).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

# Same collation in the timer, the pacman hook and bootstrap, so sorted
# baseline and sorted current output can never disagree on ordering.
export LC_ALL=C

JOB=integrity
DB_DIR=/var/lib/skemos-security
DB_FILE="$DB_DIR/integrity.db"
LOCK_FILE="$DB_DIR/integrity.lock"
ACCEPT_HINT="sudo /usr/local/lib/skemos-security/integrity-check.sh --rebaseline-all"

# SYSTEM set — root-owned; refreshed by --rebaseline.
SYS_PATHS=(
  /usr/bin/bash /usr/bin/sudo /usr/bin/ssh /usr/bin/pacman
  /usr/lib/systemd/systemd
  /etc/passwd /etc/sudoers /etc/pacman.conf
  /usr/local/bin/skemos-security-run
)
SYS_DIRS=( /etc/pacman.d/hooks /etc/sudoers.d /usr/local/lib/skemos-security )

# USER set — everything under $SKEMOS_HOME; only --rebaseline-all accepts
# changes to these.
USER_PATHS=(
  "$SKEMOS_HOME/.bashrc" "$SKEMOS_HOME/.bash_profile"
  "$SKEMOS_HOME/.config/hypr/hyprland.lua"
  "$SKEMOS_HOME/.config/hypr/binds.lua"
  "$SKEMOS_HOME/.config/hypr/look.lua"
)
USER_DIRS=()

# hash_one <file> — prints "<sha256>  <path>" for a regular, non-symlink
# file; silently skips anything else (a file replaced by a symlink/FIFO
# simply vanishes from the output, which the diff reports as a change).
# Bounded by timeout so a racy swap to a FIFO still cannot hang us.
# Returns non-zero only if hashing an eligible file actually failed.
hash_one() {
  [[ -f $1 && ! -L $1 ]] || return 0
  timeout 30 sha256sum -- "$1"
}

# hash_set <paths-array-name> <dirs-array-name> — hashes each path, and
# every regular file under each dir. Returns 1 if any hash failed (output
# for the rest is still produced). Explicit rc tracking, not set -e: this
# runs inside `if` / command substitution where errexit is suspended.
hash_set() {
  local -n _paths=$1 _dirs=$2
  local f d rc=0
  for f in "${_paths[@]}"; do
    hash_one "$f" || rc=1
  done
  for d in "${_dirs[@]}"; do
    [[ -d $d && ! -L $d ]] || continue
    while IFS= read -r -d '' f; do
      hash_one "$f" || rc=1
    done < <(find "$d" -type f -print0)
  done
  return "$rc"
}

hash_system() { hash_set SYS_PATHS SYS_DIRS; }
hash_user()   { hash_set USER_PATHS USER_DIRS; }
hash_all()    { local rc=0; hash_system || rc=1; hash_user || rc=1; return "$rc"; }

# carry_user — the user-path lines of the existing DB, unchanged. A DB line
# is "<64 hex>  <path>", so the path starts at column 67.
carry_user() {
  awk -v p="$SKEMOS_HOME/" 'substr($0, 67, length(p)) == p' "$DB_FILE"
}

# write_db — reads baseline lines on stdin, sorts, and replaces the DB
# atomically (0600 temp file in the root-owned DB dir, then rename), so a
# failure midway leaves the previous baseline intact.
write_db() {
  local tmp="$DB_FILE.tmp"
  rm -f "$tmp"
  if ! ( umask 077; sed '/^$/d' | sort -k2 > "$tmp" ); then
    rm -f "$tmp"
    return 1
  fi
  chmod 0600 "$tmp"
  mv -f "$tmp" "$DB_FILE"
}

fail_run() {
  sk_write_log "$JOB" "FAILED: $1 — baseline left untouched"
  sk_write_summary "$JOB" fail "$1"
  exit 1
}

# do_baseline <all|system>
do_baseline() {
  local scope=$1 sys usr=""
  sys=$(hash_system) || fail_run "could not hash all system paths"
  if [[ $scope == all ]]; then
    usr=$(hash_user) || fail_run "could not hash all user paths"
  else
    usr=$(carry_user) || fail_run "could not read the existing baseline"
  fi
  printf '%s\n%s\n' "$sys" "$usr" | write_db || fail_run "could not write the baseline"
  chmod 0600 "$DB_FILE"
  if [[ $scope == all ]]; then
    sk_write_log "$JOB" "baseline written — all paths ($(wc -l < "$DB_FILE") entries)"
  else
    sk_write_log "$JOB" "baseline refreshed — system paths only; user-path entries carried over unchanged ($(wc -l < "$DB_FILE") entries)"
  fi
}

mode="${1:-}"
case "$mode" in
  ""|--rebaseline|--rebaseline-all) ;;
  *) echo "usage: integrity-check.sh [--rebaseline | --rebaseline-all]" >&2; exit 2 ;;
esac

install -d -o root -g root -m 0750 "$DB_DIR"

# Serialise every run (timer, pacman hook, bootstrap seed, panel run-now).
exec 9>"$LOCK_FILE"
flock -w 120 9 || fail_run "another integrity run holds the lock"

case "$mode" in
  --rebaseline-all)
    do_baseline all
    sk_write_summary "$JOB" ok "baseline accepted (all paths)"
    exit 0
    ;;
  --rebaseline)
    # System entries only; falls through to the check so edits to user files
    # still surface as a WARN instead of being reset to "ok".
    if [[ -f $DB_FILE ]]; then do_baseline system; else do_baseline all; fi
    ;;
  "")
    if [[ ! -f $DB_FILE ]]; then
      do_baseline all
      sk_write_summary "$JOB" ok "baseline created"
      exit 0
    fi
    ;;
esac

hash_failed=0
current_raw=$(hash_all) || hash_failed=1
current=$(printf '%s\n' "$current_raw" | sed '/^$/d' | sort -k2)
diff_out="$(diff "$DB_FILE" <(printf '%s\n' "$current" | sed '/^$/d') || true)"

if [[ -z $diff_out ]]; then
  if (( hash_failed )); then
    sk_write_log "$JOB" "no changes seen, but some watched files could not be hashed"
    sk_write_summary "$JOB" warn "some watched files could not be hashed — see log"
  else
    sk_write_log "$JOB" "clean — no changes"
    sk_write_summary "$JOB" ok "no changes"
  fi
else
  changed_count=$(grep -c '^[<>]' <<<"$diff_out" || true)
  user_changed=$(grep -cF -- "  $SKEMOS_HOME/" <<<"$diff_out" || true)
  detail="$changed_count line(s) changed outside a tracked pacman transaction"
  log="CHANGED:"$'\n'"$diff_out"
  if (( user_changed > 0 )); then
    detail+=" — user file(s) changed — accept with: $ACCEPT_HINT"
    log+=$'\n'"user file(s) changed — accept with: $ACCEPT_HINT"
  fi
  if (( hash_failed )); then
    detail+=" (some files could not be hashed)"
  fi
  sk_write_log "$JOB" "$log"
  sk_write_summary "$JOB" warn "$detail"
fi
