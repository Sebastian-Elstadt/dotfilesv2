-- Night Vellum — look and feel.
-- rounding 0, border 1, no blur, no neon, no glass, no heavy shadow.
-- Flat tiled windows; an optional hairline paper umbra on FLOATING windows only
-- is applied in rules.lua (not here).

local c = require("colors")

hl.config({
  general = {
    border_size      = 1,
    gaps_in          = 4,     -- TILE mode: tight
    gaps_out         = 8,     -- TILE mode: tight
    gaps_workspaces  = 0,
    layout           = "dwindle",
    resize_on_border = true,
    hover_icon_on_border = false,
    allow_tearing    = false,

    col = {
      active_border   = c.rgba.blueprint,          -- active = blueprint hairline
      inactive_border = c.rgba.rule,               -- inactive = paper rule
      nogroup_border        = c.rgba.rule,
      nogroup_border_active = c.rgba.blueprint,
    },

    snap = { enabled = true },
  },

  decoration = {
    rounding          = 0,
    rounding_power    = 2,
    active_opacity    = 1.0,
    inactive_opacity  = 1.0,
    fullscreen_opacity = 1.0,

    dim_inactive   = false,
    dim_around     = 0.0,
    dim_special    = 0.0,

    blur   = { enabled = false },

    -- Global shadow OFF. rules.lua re-enables a single hairline shadow for
    -- floating windows only.
    shadow = { enabled = false },

    -- no glow, no motion blur
    glow        = { enabled = false },
    motion_blur = { enabled = false },
  },

  -- Animations OFF on the VM. For the metal machine, flip enabled = true and
  -- keep every curve to a <=120ms linear move (see the commented block below).
  animations = {
    enabled = false,
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
    background_color          = tonumber("0x" .. c.hex.paper_bg), -- fallback bg = paper
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
      natural_scroll        = true,
      disable_while_typing  = true,
      tap_to_click          = true,
      clickfinger_behavior  = true,
    },
  },

  gestures = {
    workspace_swipe_distance = 300,
  },
})

-- Touchpad: 3-finger horizontal swipe = switch workspace (new live-gesture API).
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- Cursor size via env (portable). HYPRCURSOR_SIZE for hyprcursor, XCURSOR_SIZE
-- for xcursor/XWayland apps.
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- ---------------------------------------------------------------------------
-- METAL: to enable motion but keep it minimal (<=120ms linear), uncomment:
--
-- hl.curve("nv-linear", { type = "bezier", points = { {0, 0}, {1, 1} } })
-- hl.config({ animations = { enabled = true } })
-- hl.animation({ leaf = "global",     enabled = true, speed = 6, bezier = "nv-linear" })
-- hl.animation({ leaf = "windows",    enabled = true, speed = 8, bezier = "nv-linear", style = "popin 100%" })
-- hl.animation({ leaf = "fade",       enabled = true, speed = 8, bezier = "nv-linear" })
-- hl.animation({ leaf = "workspaces", enabled = true, speed = 8, bezier = "nv-linear", style = "fade" })
-- hl.animation({ leaf = "border",     enabled = false })
-- ---------------------------------------------------------------------------
