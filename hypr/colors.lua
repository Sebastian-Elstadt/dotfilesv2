-- Night Vellum — palette (single source of truth for the Hyprland side).
-- Dark-mode e-ink paper with a blueprint overlay. Do NOT substitute Nord/
-- Gruvbox/Catppuccin values. Hex from the design spec.
--
-- Other components carry their own copy of these values in their own syntax:
--   waybar/style.css, foot/foot.ini, kitty/night-vellum.conf, rofi/night-vellum.rasi,
--   mako/config, hyprlock.conf. Keep them all in sync if the palette ever changes.

local M = {}

-- bare hex (no #), for string building
M.hex = {
  paper_bg     = "161513",
  paper_raised = "1c1b18",
  ink          = "c4bfb3",
  ink_dim      = "8a857c",
  rule         = "3a3934",
  blueprint    = "6a8494",
  alert        = "a67c52", -- warnings only, rare
}

-- Hyprland rgba() strings (8-digit hex, last pair = alpha)
local function rgba(h, a) return ("rgba(%s%s)"):format(h, a or "ff") end
M.rgba = {
  paper_bg     = rgba(M.hex.paper_bg),
  paper_raised = rgba(M.hex.paper_raised),
  ink          = rgba(M.hex.ink),
  ink_dim      = rgba(M.hex.ink_dim),
  rule         = rgba(M.hex.rule),
  blueprint    = rgba(M.hex.blueprint),
  alert        = rgba(M.hex.alert),
}

M.rgba_fn = rgba
return M
