-- ============================================================================
--  Night Vellum — Hyprland entrypoint
--  Dark-mode e-ink paper with a blueprint overlay.
--  Config language: Lua (hyprlang is deprecated since Hyprland 0.55).
--  Split into modules under ~/.config/hypr/ ; order below matters.
-- ============================================================================

require("colors")     -- palette (no side effects, just data)
require("monitors")   -- outputs — generic, no hardcoded connector
require("look")       -- rounding 0, border 1, no blur/shadow, anims off
require("rules")      -- window/workspace rules; floating-only umbra (AFTER look)
require("binds")      -- keybindings (pulls in modes + minimize)
require("autostart")  -- waybar, hyprpaper, mako, hypridle, polkit, cliphist
