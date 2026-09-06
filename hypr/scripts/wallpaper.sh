#!/usr/bin/env bash
# Night Vellum — wallpaper generator + applier.
# Dark laid-paper grain + faint white schematic grid + a bottom-right title
# block. Corner brackets / registration marks are the screen-shader HUD's job
# now, not the wallpaper's. One image per resolution, cached. Portable: reads
# the real monitor list from hyprctl.
#
# Usage:
#   wallpaper.sh                 generate (if missing) + apply to every monitor
#   wallpaper.sh --force         regenerate even if cached, then apply
#   wallpaper.sh --preview WxH   just write ~/.cache/night-vellum/preview.png

set -euo pipefail

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/night-vellum"
mkdir -p "$CACHE"

# --- palette (mirrors hypr/colors.lua) --------------------------------
PAPER="#161513"
INK="#e5e1d6"
INK_DIM="#9a948a"
INK_FAINT="#55514a"
ACCENT="#c1663a"

GRID=48            # schematic grid pitch (px)
GRID_ALPHA=0.055   # grid opacity — faint
GRAIN_PCT=7        # paper grain opacity (%)
FONT="$(fc-match -f '%{file}' 'Iosevka' 2>/dev/null || true)"

gen() { # gen W H OUTFILE
  local w=$1 h=$2 out=$3
  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN

  # 1. schematic grid — 1px white hairline tile, knocked back
  magick -size "${GRID}x${GRID}" xc:none \
    -stroke "$INK" -strokewidth 1 -fill none \
    -draw "line 0,0 ${GRID},0" -draw "line 0,0 0,${GRID}" \
    "$tmp/tile.png"
  magick -size "${w}x${h}" tile:"$tmp/tile.png" \
    -channel A -evaluate multiply "$GRID_ALPHA" +channel \
    "$tmp/grid.png"

  # 2. paper grain — zero-mean gaussian noise, Overlay (no luminance shift)
  magick -size "${w}x${h}" xc:gray50 \
    -attenuate 0.8 +noise Gaussian -colorspace Gray -blur 0x0.3 \
    "$tmp/grain.png"

  # 3. base + grain + grid
  magick -size "${w}x${h}" xc:"$PAPER" \
    \( "$tmp/grain.png" -alpha on -channel A -evaluate set "${GRAIN_PCT}%" +channel \) \
    -compose Overlay -composite \
    "$tmp/grid.png" -compose Over -composite \
    "$tmp/flat.png"

  # The corner brackets / registration marks / edge ticks that used to live here
  # are now the screen-shader HUD's job (hypr/shaders/night-vellum.frag) — drawing
  # them again in the wallpaper double-stamped every corner. The wallpaper is now
  # just the paper field (grain + faint grid) plus the title block.

  # 4. title block, bottom-right
  local bw=232 bh=62
  local bx=$(( w - 24 - bw ))
  local by=$(( h - 24 - bh ))
  local tb="rectangle ${bx},${by} $((bx+bw)),$((by+bh))"
  tb+=" line ${bx},$((by+22)) $((bx+bw)),$((by+22))"
  tb+=" line $((bx+bw-46)),${by} $((bx+bw-46)),$((by+bh))"
  local sheet; sheet="$(date +%Y-%m-%d)"

  magick "$tmp/flat.png" \
    -stroke "$INK_DIM"   -strokewidth 1 -fill none -draw "$tb" \
    -stroke none -fill "$ACCENT" -draw "rectangle $((bx+bw-34)),$((by+30)) $((bx+bw-12)),$((by+52))" \
    ${FONT:+-font "$FONT"} -stroke none -fill "$INK" -pointsize 13 \
      -draw "text $((bx+12)),$((by+16)) 'NIGHT VELLUM'" \
    -fill "$INK_DIM" -pointsize 10 \
      -draw "text $((bx+12)),$((by+38)) 'DWG  NV-01'" \
      -draw "text $((bx+12)),$((by+54)) \"$sheet\"" \
    -strip -define png:compression-level=9 -define png:compression-filter=5 "$out"
}

apply() {
  command -v hyprctl >/dev/null || { echo "no hyprctl; not applying" >&2; return 0; }
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
    hyprctl hyprpaper preload "$png"             >/dev/null 2>&1 || true
    hyprctl hyprpaper wallpaper "${name},${png}" >/dev/null 2>&1 || true
    used+=("$png")
  done
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
