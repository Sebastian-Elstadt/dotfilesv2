#!/usr/bin/env bash
# Night Vellum — wallpaper generator + applier.
# Dark laid-paper grain + faint blueprint grid + crop/registration marks at the
# four MONITOR corners. One image per resolution, cached. Portable: reads the
# real monitor list from hyprctl, no hardcoded connector or resolution.
#
# Usage:
#   wallpaper.sh                 generate (if missing) + apply to every monitor
#   wallpaper.sh --force         regenerate even if cached, then apply
#   wallpaper.sh --preview WxH   just write ~/.cache/night-vellum/preview.png

set -euo pipefail

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/night-vellum"
mkdir -p "$CACHE"

# --- palette -------------------------------------------------------------
PAPER="#161513"
INK_DIM="#8a857c"
RULE="#3a3934"
BLUE="#6a8494"

GRID=48          # blueprint grid pitch (px)
GRID_ALPHA=0.11  # grid opacity
GRAIN_PCT=7      # paper grain opacity (percent) — Overlay, zero-mean, no luma shift

gen() { # gen W H OUTFILE
  local w=$1 h=$2 out=$3
  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  # 1. blueprint grid, as a tiled 1px hairline, knocked back to GRID_ALPHA
  magick -size "${GRID}x${GRID}" xc:none \
    -stroke "$BLUE" -strokewidth 1 -fill none \
    -draw "line 0,0 ${GRID},0" -draw "line 0,0 0,${GRID}" \
    "$tmp/tile.png"
  magick -size "${w}x${h}" tile:"$tmp/tile.png" \
    -channel A -evaluate multiply "$GRID_ALPHA" +channel \
    "$tmp/grid.png"

  # 2. paper grain — zero-mean monochrome gaussian noise around gray50.
  #    Composited with Overlay, gray50 is a no-op so there is no net luminance
  #    shift; only the deviations add a faint laid-paper tooth.
  magick -size "${w}x${h}" xc:gray50 \
    -attenuate 0.8 +noise Gaussian -colorspace Gray -blur 0x0.3 \
    "$tmp/grain.png"

  # 3. compose base + grain (Overlay, faint) + grid (Over)
  magick -size "${w}x${h}" xc:"$PAPER" \
    \( "$tmp/grain.png" -alpha on -channel A -evaluate set "${GRAIN_PCT}%" +channel \) \
    -compose Overlay -composite \
    "$tmp/grid.png" -compose Over -composite \
    "$tmp/flat.png"

  # 4. crop / registration marks at the four monitor corners
  local inset=28 len=46 reg=72
  local d=""
  for corner in "0 0 1 1" "$((w-1)) 0 -1 1" "0 $((h-1)) 1 -1" "$((w-1)) $((h-1)) -1 -1"; do
    read -r cx cy sx sy <<<"$corner"
    local ax=$(( cx + sx*inset ))       ay=$(( cy + sy*inset ))
    # L bracket
    d+=" line ${ax},${ay} $(( ax + sx*len )),${ay}"
    d+=" line ${ax},${ay} ${ax},$(( ay + sy*len ))"
    # registration cross-in-circle further in
    local rx=$(( cx + sx*reg )) ry=$(( cy + sy*reg )) r=7
    d+=" circle ${rx},${ry} ${rx},$(( ry - r ))"
    d+=" line $(( rx - r-3 )),${ry} $(( rx + r+3 )),${ry}"
    d+=" line ${rx},$(( ry - r-3 )) ${rx},$(( ry + r+3 ))"
  done
  # edge tick marks — every GRID*4 along top and left, short, ink-dim
  local ticks=""
  local step=$(( GRID*4 ))
  for (( x=step; x<w; x+=step )); do ticks+=" line ${x},0 ${x},8"; done
  for (( y=step; y<h; y+=step )); do ticks+=" line 0,${y} 8,${y}"; done

  magick "$tmp/flat.png" \
    -stroke "$BLUE"    -strokewidth 1 -fill none -draw "$d" \
    -stroke "$INK_DIM" -strokewidth 1 -fill none -draw "$ticks" \
    -strip -define png:compression-level=9 -define png:compression-filter=5 "$out"
}

apply() {
  command -v hyprctl >/dev/null || { echo "no hyprctl; not applying" >&2; return 0; }
  # wait for hyprpaper IPC (up to ~10s)
  for _ in $(seq 1 50); do
    hyprctl hyprpaper listloaded >/dev/null 2>&1 && break
    sleep 0.2
  done

  local force=$1
  mapfile -t MONS < <(hyprctl -j monitors | jq -r '.[] | "\(.name) \(.width) \(.height)"')
  local used=()
  for line in "${MONS[@]}"; do
    read -r name w h <<<"$line"
    local png="$CACHE/wall-${w}x${h}.png"
    if [[ "$force" == "1" || ! -f "$png" ]]; then gen "$w" "$h" "$png"; fi
    hyprctl hyprpaper preload "$png"        >/dev/null 2>&1 || true
    hyprctl hyprpaper wallpaper "${name},${png}" >/dev/null 2>&1 || true
    used+=("$png")
  done

  # drop any preloaded images we are not using
  while read -r loaded; do
    [[ -z "$loaded" ]] && continue
    local keep=0
    for u in "${used[@]}"; do [[ "$u" == "$loaded" ]] && keep=1; done
    [[ $keep -eq 0 ]] && hyprctl hyprpaper unload "$loaded" >/dev/null 2>&1 || true
  done < <(hyprctl hyprpaper listloaded 2>/dev/null || true)
}

case "${1:-}" in
  --preview)
    read -r w h <<<"$(echo "${2:-1920x1080}" | tr 'x' ' ')"
    gen "$w" "$h" "$CACHE/preview.png"
    echo "$CACHE/preview.png"
    ;;
  --force) apply 1 ;;
  *)       apply 0 ;;
esac
