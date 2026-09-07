-- Skemos — look and feel.
-- Dark + warm off-white, reversed-technical-drawing. No blue. rounding 0,
-- border 1. Flat tiled windows; hairline paper umbra on FLOATING only (rules.lua).
-- Motion: a single ~90ms linear fade — no slide, no scale. An e-ink panel redraw.

local c = require("colors")

local HOME = os.getenv("HOME")

hl.config({
  general = {
    border_size      = 2,     -- one border only: white active, faint inactive
    gaps_in          = 4,     -- TILE: tight
    gaps_out         = 10,    -- equal on every side, incl. under the waybar
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

    -- Halftone screen shader. Static (no `time`), so damage tracking stays on.
    -- Corner brackets / reg marks are on the wallpaper, not here. Tunables at
    -- the top of the file.
    screen_shader = HOME .. "/.config/hypr/shaders/skemos.frag",
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

-- ==== GROUP BARS — trial (added 2026-09-07) ==============================
-- Tabbed window stacks with a title-block strip along the top. Native, no
-- plugin. Styled to match: flat, no gradients, hairline, the active tab in
-- burnt orange. Keybinds are in binds.lua under the same "GROUP BARS — trial"
-- banner. TO REMOVE: delete this whole block and that bind block — nothing
-- else references groups.
hl.config({
  group = {
    ["col.border_active"]   = c.rgba.accent,   -- grouped + focused = orange frame
    ["col.border_inactive"] = c.rgba.rule,
    groupbar = {
      enabled          = true,
      render_titles    = true,
      stacked          = false,
      gradients        = false,               -- flat tabs, not the default candy
      font_family      = "Departure Mono",
      font_size        = 9,
      height           = 16,
      indicator_height = 2,                    -- the one accent line under a tab
      text_color          = c.rgba.ink_dim,
      ["col.active"]      = c.rgba.raised,     -- active tab ground
      ["col.inactive"]    = c.rgba.bg,
    },
  },
})
-- ==== end GROUP BARS ====================================================

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- ---- Motion: fast schematic-instrument, not e-ink smear -------------------
-- Everything is short (~90-140ms) with a hard decel. The halftone shader turns
-- the quick fades into a stipple "dissolve". Focus changes snap the border like
-- a reticle locking on. Tiled windows still teleport (no windowsMove).
hl.config({ animations = { enabled = true } })

hl.curve("skLinear", { type = "bezier", points = { { 0.0,  0.0 }, { 1.0, 1.0 } } })
hl.curve("skOut",    { type = "bezier", points = { { 0.12, 0.9 }, { 0.2, 1.0 } } })  -- snap-to-rest
hl.curve("skSnap",   { type = "bezier", points = { { 0.3,  0.0 }, { 0.1, 1.0 } } })  -- near-instant
hl.curve("skGone",   { type = "bezier", points = { { 0.05, 0.9 }, { 0.15, 1.0 } } })  -- front-loaded cut

hl.animation({ leaf = "global",          enabled = true,  speed = 8,  bezier = "skOut" })

-- windows: a hair of assemble (popin 96%) under a fast fade -> "materialise".
-- close is near-instant: front-loaded curve + high speed, more cut than fade.
hl.animation({ leaf = "windows",          enabled = true,  speed = 9,  bezier = "skOut",  style = "popin 96%" })
hl.animation({ leaf = "windowsIn",        enabled = true,  speed = 9,  bezier = "skOut",  style = "popin 96%" })
hl.animation({ leaf = "windowsOut",       enabled = true,  speed = 20, bezier = "skGone", style = "popin 98%" })
hl.animation({ leaf = "windowsMove",      enabled = false })                       -- tiles/floats teleport

-- fade: the core of the dissolve
hl.animation({ leaf = "fade",             enabled = true,  speed = 9,  bezier = "skLinear" })
hl.animation({ leaf = "fadeIn",           enabled = true,  speed = 9,  bezier = "skLinear" })
hl.animation({ leaf = "fadeOut",          enabled = true,  speed = 20, bezier = "skGone" })

-- border: focus colour change is instant (no half-faded border lingering on a
-- workspace switch); angle animation off
hl.animation({ leaf = "border",           enabled = false })
hl.animation({ leaf = "borderangle",      enabled = false })

-- workspaces / drawer / layers: panels swap with a short slide + fade
hl.animation({ leaf = "workspaces",       enabled = true,  speed = 8,  bezier = "skOut", style = "slidefade 12%" })
hl.animation({ leaf = "specialWorkspace", enabled = true,  speed = 9,  bezier = "skOut", style = "slidevert" })
hl.animation({ leaf = "layers",           enabled = true,  speed = 12, bezier = "skOut", style = "slidefade 8%" })
