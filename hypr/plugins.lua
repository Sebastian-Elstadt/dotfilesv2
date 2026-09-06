-- Night Vellum — Hyprland plugins (borders-plus-plus).
--
-- One-time install (needs a real terminal for sudo):
--     hyprpm update
--     hyprpm add https://github.com/hyprwm/hyprland-plugins
--     hyprpm enable borders-plus-plus
-- autostart.lua runs `hyprpm reload -n` each session so it persists.
--
-- This build (v1.0) only exposes ONE extra border (border_1 / border_size_1);
-- add_borders=2 / border_2 / natural_rounding log "unknown config key" and are
-- left out. Effect: a single ink-faint hairline just outside the focus border —
-- every window reads as a boxed component on a schematic sheet.

local c = require("colors")

hl.config({
  plugin = {
    borders_plus_plus = {
      add_borders = 1,
      col = { border_1 = "rgb(" .. c.hex.ink_faint .. ")" },
      border_size_1 = 2,
    },
  },
})
