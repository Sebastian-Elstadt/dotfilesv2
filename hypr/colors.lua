-- Night Vellum — palette (single source of truth for the Hyprland side).
--
-- Revised direction (2026-09-03): dark + warm off-white, like a reversed
-- technical drawing / industrial blueprint sheet at night. NO blue accent.
-- One accent only — a burnt drafting orange — used sparingly for state
-- readouts and schematic callouts.
--
-- Other components carry their own copy in their own syntax:
--   waybar/style.css, foot/foot.ini, kitty/night-vellum.conf,
--   rofi/night-vellum.rasi, mako/config, hyprlock.conf, scripts/wallpaper.sh.
--   Keep them in sync.

local M = {}

-- bare hex (no #)
M.hex = {
  bg        = "161513", -- ink-black, faintly warm
  raised    = "1e1d19", -- panels / notification cards
  ink       = "e5e1d6", -- primary "white" — high contrast, paper-warm
  ink_dim   = "9a948a", -- secondary text
  ink_faint = "55514a", -- grid lines, disabled, schematic hairlines
  rule      = "34322d", -- borders / separators
  accent    = "c1663a", -- burnt drafting orange — SPARSE (mode, alerts, ticks)
}

-- back-compat aliases (older module code referenced these names)
M.hex.paper_bg     = M.hex.bg
M.hex.paper_raised = M.hex.raised
M.hex.alert        = M.hex.accent

local function rgba(h, a) return ("rgba(%s%s)"):format(h, a or "ff") end
M.rgba = {}
for k, v in pairs(M.hex) do M.rgba[k] = rgba(v) end

M.rgba_fn = rgba
return M
