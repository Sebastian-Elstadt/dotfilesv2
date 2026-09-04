-- Night Vellum — look and feel.
-- Dark + warm off-white, reversed-technical-drawing. No blue. rounding 0,
-- border 1. Flat tiled windows; hairline paper umbra on FLOATING only (rules.lua).
-- Motion: a single ~90ms linear fade — no slide, no scale. An e-ink panel redraw.

local c = require("colors")

hl.config({
  general = {
    border_size      = 1,
    gaps_in          = 4,     -- TILE: tight
    gaps_out         = 8,
    gaps_workspaces  = 0,
    layout           = "dwindle",
    resize_on_border = true,
    hover_icon_on_border = false,
    allow_tearing    = false,

    col = {
      active_border          = c.rgba.ink,        -- focused = white hairline
      inactive_border        = c.rgba.rule,       -- unfocused = faint rule
      nogroup_border         = c.rgba.rule,
      nogroup_border_active  = c.rgba.ink,
    },

    snap = { enabled = true },
  },

  decoration = {
    rounding          = 0,
    rounding_power    = 2,
    active_opacity    = 1.0,
    inactive_opacity  = 1.0,
    fullscreen_opacity = 1.0,
    dim_inactive      = false,
    dim_around        = 0.0,
    dim_special       = 0.35,   -- darken the workspace behind the minimized drawer

    blur   = { enabled = false },
    shadow = { enabled = false },   -- rules.lua re-enables a hairline for floating only
    glow        = { enabled = false },
    motion_blur = { enabled = false },
  },

  dwindle = {
    preserve_split = true,
    smart_split    = false,
    smart_resizing = true,
    default_split_ratio = 1.0,
  },

  misc = {
    disable_hyprland_logo     = true,
    disable_splash_rendering  = true,
    force_default_wallpaper   = 0,
    background_color          = "rgb(" .. c.hex.bg .. ")",
    focus_on_activate         = false,
    middle_click_paste        = false,
    enable_swallow            = false,
    key_press_enables_dpms    = true,
    mouse_move_enables_dpms   = true,
  },

  input = {
    kb_layout    = "us",
    follow_mouse = 1,
    sensitivity  = 0,
    accel_profile = "flat",
    numlock_by_default = true,
    repeat_delay = 300,
    repeat_rate  = 40,
    touchpad = {
      natural_scroll       = true,
      disable_while_typing = true,
      tap_to_click         = true,
      clickfinger_behavior = true,
    },
  },

  gestures = { workspace_swipe_distance = 300 },
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- ---- Motion: one 90ms linear fade, nothing else ---------------------------
-- `linear` bezier is built in. speed ~11 ≈ 90ms.
hl.config({ animations = { enabled = true } })

hl.animation({ leaf = "global",       enabled = true,  speed = 11, bezier = "linear" })
-- windows: appear/disappear at full size (no scale), opacity handled by fade*
hl.animation({ leaf = "windows",      enabled = true,  speed = 11, bezier = "linear", style = "popin 100%" })
hl.animation({ leaf = "windowsIn",    enabled = true,  speed = 11, bezier = "linear", style = "popin 100%" })
hl.animation({ leaf = "windowsOut",   enabled = true,  speed = 11, bezier = "linear", style = "popin 100%" })
hl.animation({ leaf = "windowsMove",  enabled = false })              -- tiles/floats snap
hl.animation({ leaf = "fade",         enabled = true,  speed = 11, bezier = "linear" })
hl.animation({ leaf = "fadeIn",       enabled = true,  speed = 11, bezier = "linear" })
hl.animation({ leaf = "fadeOut",      enabled = true,  speed = 11, bezier = "linear" })
hl.animation({ leaf = "border",       enabled = false })              -- focus change is instant
hl.animation({ leaf = "borderangle",  enabled = false })
hl.animation({ leaf = "workspaces",   enabled = true,  speed = 11, bezier = "linear", style = "fade" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 11, bezier = "linear", style = "fade" })
hl.animation({ leaf = "layers",       enabled = true,  speed = 11, bezier = "linear", style = "fade" })
