-- Night Vellum — Hyprland plugins (borders-plus-plus).
--
-- Requires the plugin to be installed once, out of band:
--
--     hyprpm update
--     hyprpm add https://github.com/hyprwm/hyprland-plugins
--     hyprpm enable borders-plus-plus
--
-- autostart.lua runs `hyprpm reload -n` on session start so it loads every time.
-- This file only carries the config; if the plugin isn't loaded Hyprland just
-- logs a warning and moves on.
--
-- Effect: outside the 1px focus border (look.lua) we stack a bg-coloured gap
-- and one faint hairline — the technical "component frame" / double rule you
-- see boxing every part on a schematic sheet.

local c = require("colors")

hl.config({
  plugin = {
    borders_plus_plus = {
      add_borders      = 2,      -- draw 2 extra borders, outward

      col = {
        border_1 = "rgb(" .. c.hex.bg .. ")",         -- acts as the gap
        border_2 = "rgb(" .. c.hex.ink_faint .. ")",  -- the outer hairline
      },

      border_size_1    = 3,      -- gap width
      border_size_2    = 1,      -- hairline
      natural_rounding = false,
    },
  },
})
