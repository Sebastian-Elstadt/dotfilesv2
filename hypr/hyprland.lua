-- ============================================================================
--  Night Vellum — Hyprland entrypoint
--  Dark-mode e-ink paper with a blueprint overlay.
--  Config language: Lua (hyprlang is deprecated since Hyprland 0.55).
--  Split into modules under ~/.config/hypr/ ; order below matters.
-- ============================================================================

-- GPU: NVIDIA RTX 5070 (01:00.0) + AMD iGPU (12:00.0). The compositor boots on
-- the NVIDIA card on its own here — no AQ_DRM_DEVICES needed. (Aquamarine's
-- explicit device list rejects /dev/dri/by-path/* symlinks and crashes with
-- "CBackend::create() failed!"; if pinning ever becomes necessary use plain
-- node paths, e.g. AQ_DRM_DEVICES=/dev/dri/card1:/dev/dri/card0, and test it.)
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")

require("colors")     -- palette (no side effects, just data)
require("monitors")   -- outputs — generic, no hardcoded connector
require("look")       -- rounding 0, border 1, no blur/shadow, anims off
require("rules")      -- window/workspace rules; floating-only umbra (AFTER look)
require("binds")      -- keybindings (pulls in modes + minimize)
require("autostart")  -- waybar, hyprpaper, mako, hypridle, polkit, cliphist
