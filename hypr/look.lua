-- Night Vellum — look and feel.
-- Dark + warm off-white, reversed-technical-drawing. No blue. rounding 0,
-- border 1. Flat tiled windows; hairline paper umbra on FLOATING only (rules.lua).
-- Motion: a single ~90ms linear fade — no slide, no scale. An e-ink panel redraw.

local c = require("colors")

local HOME = os.getenv("HOME")

hl.config({
  general = {
    border_size      = 1,
    gaps_in          = 5,     -- TILE: tight, + 1px for the borders-plus-plus rule
    gaps_out         = { top = 3, right = 10, bottom = 10, left = 10 },  -- tiny top gap: no wallpaper seam under the bar
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

    -- Schematic HUD + halftone. Static shader (no `time`), so damage tracking
    -- stays on. See hypr/shaders/night-vellum.frag for the tunables.
    screen_shader = HOME .. "/.config/hypr/shaders/night-vellum.frag",
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

-- ---- Motion: fast schematic-instrument, not e-ink smear -------------------
-- Everything is short (~90-140ms) with a hard decel. The halftone shader turns
-- the quick fades into a stipple "dissolve". Focus changes snap the border like
-- a reticle locking on. Tiled windows still teleport (no windowsMove).
hl.config({ animations = { enabled = true } })

hl.curve("nvLinear", { type = "bezier", points = { { 0.0,  0.0 }, { 1.0, 1.0 } } })
hl.curve("nvOut",    { type = "bezier", points = { { 0.12, 0.9 }, { 0.2, 1.0 } } })  -- snap-to-rest
hl.curve("nvSnap",   { type = "bezier", points = { { 0.3,  0.0 }, { 0.1, 1.0 } } })  -- near-instant
hl.curve("nvGone",   { type = "bezier", points = { { 0.05, 0.9 }, { 0.15, 1.0 } } })  -- front-loaded cut

hl.animation({ leaf = "global",          enabled = true,  speed = 8,  bezier = "nvOut" })

-- windows: a hair of assemble (popin 96%) under a fast fade -> "materialise".
-- close is near-instant: front-loaded curve + high speed, more cut than fade.
hl.animation({ leaf = "windows",          enabled = true,  speed = 9,  bezier = "nvOut",  style = "popin 96%" })
hl.animation({ leaf = "windowsIn",        enabled = true,  speed = 9,  bezier = "nvOut",  style = "popin 96%" })
hl.animation({ leaf = "windowsOut",       enabled = true,  speed = 20, bezier = "nvGone", style = "popin 98%" })
hl.animation({ leaf = "windowsMove",      enabled = false })                       -- tiles/floats teleport

-- fade: the core of the dissolve
hl.animation({ leaf = "fade",             enabled = true,  speed = 9,  bezier = "nvLinear" })
hl.animation({ leaf = "fadeIn",           enabled = true,  speed = 9,  bezier = "nvLinear" })
hl.animation({ leaf = "fadeOut",          enabled = true,  speed = 20, bezier = "nvGone" })

-- border: reticle lock on focus change
hl.animation({ leaf = "border",           enabled = true,  speed = 7,  bezier = "nvSnap" })
hl.animation({ leaf = "borderangle",      enabled = false })

-- workspaces / drawer / layers: panels swap with a short slide + fade
hl.animation({ leaf = "workspaces",       enabled = true,  speed = 8,  bezier = "nvOut", style = "slidefade 12%" })
hl.animation({ leaf = "specialWorkspace", enabled = true,  speed = 9,  bezier = "nvOut", style = "slidevert" })
hl.animation({ leaf = "layers",           enabled = true,  speed = 9,  bezier = "nvOut", style = "slidefade 8%" })
