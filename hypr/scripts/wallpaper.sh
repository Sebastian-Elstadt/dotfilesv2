#!/usr/bin/env bash
# Skemos — wallpaper generator + applier.
# Dark laid-paper grain + faint white schematic grid + crop/registration marks
# and a corner title block. Reversed technical drawing. One image per
# resolution, cached. Portable: reads the real monitor list from hyprctl.
#
# Usage:
#   wallpaper.sh                 generate (if missing) + apply to every monitor
#   wallpaper.sh --force         regenerate even if cached, then apply
#   wallpaper.sh --preview WxH   just write ~/.cache/skemos/preview.png

set -euo pipefail

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/skemos"
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

  # 4. corner crop brackets + registration crosshairs (white / ink-dim).
  # Top corners are pushed down TOPSHIFT px so the 22px waybar doesn't eat the
  # top margin. Bottom-right is omitted — the title block lives there.
  local inset=30 len=64 reg=88 topshift=24
  local brackets="" regs=""
  for corner in "0 0 1 1" "$((w-1)) 0 -1 1" "0 $((h-1)) 1 -1"; do
    read -r cx cy sx sy <<<"$corner"
    local yoff=0; (( cy == 0 )) && yoff=$topshift
    local ax=$(( cx + sx*inset )) ay=$(( cy + sy*inset + yoff ))
    brackets+=" line ${ax},${ay} $(( ax + sx*len )),${ay}"
    brackets+=" line ${ax},${ay} ${ax},$(( ay + sy*len ))"
    local rx=$(( cx + sx*reg )) ry=$(( cy + sy*reg + yoff )) r=8
    regs+=" circle ${rx},${ry} ${rx},$(( ry - r ))"
    regs+=" line $(( rx - r-4 )),${ry} $(( rx + r+4 )),${ry}"
    regs+=" line ${rx},$(( ry - r-4 )) ${rx},$(( ry + r+4 ))"
  done

  # 5. edge ticks — minor every GRID*2, major (longer) every GRID*8
  local minor="" major=""
  for (( x=GRID*2; x<w; x+=GRID*2 )); do
    if (( x % (GRID*8) == 0 )); then major+=" line ${x},0 ${x},14  line ${x},$((h-1)) ${x},$((h-15))"
    else                              minor+=" line ${x},0 ${x},7   line ${x},$((h-1)) ${x},$((h-8))"; fi
  done
  for (( y=GRID*2; y<h; y+=GRID*2 )); do
    if (( y % (GRID*8) == 0 )); then major+=" line 0,${y} 14,${y}  line $((w-1)),${y} $((w-15)),${y}"
    else                              minor+=" line 0,${y} 7,${y}   line $((w-1)),${y} $((w-8)),${y}"; fi
  done

  # 6. title block, bottom-right
  local bw=232 bh=62
  local bx=$(( w - 24 - bw ))
  local by=$(( h - 24 - bh ))
  local tb="rectangle ${bx},${by} $((bx+bw)),$((by+bh))"
  tb+=" line ${bx},$((by+22)) $((bx+bw)),$((by+22))"
  tb+=" line $((bx+bw-46)),${by} $((bx+bw-46)),$((by+bh))"
  local sheet; sheet="$(date +%Y-%m-%d)"

  magick "$tmp/flat.png" \
    -stroke "$INK"       -strokewidth 1 -fill none -draw "$brackets" \
    -stroke "$INK_DIM"   -strokewidth 1 -fill none -draw "$regs" \
    -stroke "$INK_FAINT" -strokewidth 1 -fill none -draw "$minor" \
    -stroke "$INK_DIM"   -strokewidth 1 -fill none -draw "$major" \
    -stroke "$INK_DIM"   -strokewidth 1 -fill none -draw "$tb" \
    -stroke none -fill "$ACCENT" -draw "rectangle $((bx+bw-34)),$((by+30)) $((bx+bw-12)),$((by+52))" \
    ${FONT:+-font "$FONT"} -stroke none -fill "$INK" -pointsize 13 \
      -draw "text $((bx+12)),$((by+16)) 'SKEMOS'" \
    -fill "$INK_DIM" -pointsize 10 \
      -draw "text $((bx+12)),$((by+38)) 'DWG  SK-01'" \
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
