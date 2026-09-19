-- Skemos — window & workspace rules.

local c = require("colors")

-- Ignore app-driven maximize requests (tidier tiling).
hl.window_rule({
  name  = "sk-suppress-maximize",
  match = { class = ".*" },
  suppress_event = "maximize",
})

-- --- Hairline paper umbra: FLOATING windows only; tiled windows stay flat. ---
-- look.lua leaves shadow disabled; enable one soft ink hairline here, then
-- strip it from tiled windows. Must be required AFTER look.lua.
hl.config({
  decoration = {
    shadow = {
      enabled        = true,
      range          = 6,
      render_power   = 2,
      sharp          = false,
      offset         = { 0, 2 },
      color          = tonumber("0x66" .. c.hex.bg),   -- ~40% ink-black
      color_inactive = tonumber("0x33" .. c.hex.bg),
    },
  },
})
hl.window_rule({ name = "sk-no-shadow-tiled", match = { float = false }, no_shadow = true })

-- --- Common floating dialogs -------------------------------------------------
hl.window_rule({
  match = { class = "^(pavucontrol|nm-connection-editor|blueman-manager|org.pulseaudio.pavucontrol)$" },
  float = true,
})
hl.window_rule({
  match  = { title = "^(Open File|Open Files|Save File|Save As|Choose Files|Select a File)$" },
  float  = true,
  center = true,
})

-- --- security panel: fixed panel on the LEFT edge, mirror of rofi ------------
-- 900px wide, full height below the waybar, inset 12px like rofi (gaps_out 10
-- + 2px border). Pinned so it shows on every workspace; SUPER+S toggles it.
hl.window_rule({
  name    = "sk-security-panel",
  match   = { class = "^skemos-security$" },
  float   = true,
  pin     = true,
  size    = "900 (monitor_h-46)",
  move    = "12 34",
  animation = "slide left",
})

-- --- special:minimized drawer: roomy, clearly a tray --------------------
hl.workspace_rule({ workspace = "special:minimized", gaps_in = 10, gaps_out = 44 })

-- --- rofi launcher: slide in from the right edge -----------------------
-- The .rasi anchors it as a full-height right-side panel; `slide` brings it in
-- from that anchored edge. Timing comes from the `layers` animation (look.lua).
hl.layer_rule({
  name      = "sk-rofi-slide",
  match     = { namespace = "^rofi$" },
  animation = "slide",
})
