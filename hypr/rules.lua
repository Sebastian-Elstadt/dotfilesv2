-- Night Vellum — window & workspace rules.

local c = require("colors")

-- Ignore app-driven maximize requests (tidier tiling).
hl.window_rule({
  name  = "nv-suppress-maximize",
  match = { class = ".*" },
  suppress_event = "maximize",
})

-- --- Hairline paper umbra: FLOATING windows only; tiled windows stay flat. ---
-- look.lua leaves shadow disabled; enable a single soft hairline here, then
-- strip it from tiled windows. "Last hl.config wins", so this must be required
-- after look.lua (hyprland.lua controls the order).
hl.config({
  decoration = {
    shadow = {
      enabled        = true,
      range          = 6,
      render_power   = 2,
      sharp          = false,
      offset         = { 0, 2 },
      color          = tonumber("0x55" .. c.hex.paper_bg),  -- ~33% alpha over paper-dark
      color_inactive = tonumber("0x33" .. c.hex.paper_bg),
    },
  },
})
hl.window_rule({ name = "nv-no-shadow-tiled", match = { float = false }, no_shadow = true })

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

-- --- special:minimized drawer: roomy, clearly a tray --------------------
hl.workspace_rule({ workspace = "special:minimized", gaps_in = 10, gaps_out = 44 })
