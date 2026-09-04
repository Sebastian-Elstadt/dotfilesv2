-- Night Vellum — keybindings.

local modes    = require("modes")
local minimize = require("minimize")

local mod   = "SUPER"
local HOME  = os.getenv("HOME")
local SCRIPTS = HOME .. "/.config/hypr/scripts"

-- Terminal: foot on the VM. METAL: change this one word to "kitty" and reload.
local terminal = "foot"
local launcher = "rofi -show drun"

-- --- core (spec) ---------------------------------------------------------
hl.bind(mod .. " + Return",         hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + D",              hl.dsp.exec_cmd(launcher))
hl.bind(mod .. " + Q",              hl.dsp.window.close())
hl.bind(mod .. " + SHIFT + SPACE",  function() modes.toggle() end)      -- TILE <-> DESK, this workspace only
hl.bind(mod .. " + SPACE",          hl.dsp.window.float({ action = "toggle" }))  -- float/tile active window only
hl.bind(mod .. " + M",              function() minimize.minimize() end)
hl.bind(mod .. " + SHIFT + M",      function() minimize.toggle_drawer() end)
hl.bind(mod .. " + L",              hl.dsp.exec_cmd(SCRIPTS .. "/lock.sh"))

-- --- session -----------------------------------------------------------
hl.bind(mod .. " + SHIFT + E",      hl.dsp.exec_cmd("hyprshutdown"))
hl.bind(mod .. " + SHIFT + C",      hl.dsp.exec_cmd("hyprctl reload"))

-- --- window ------------------------------------------------------------
hl.bind(mod .. " + F",              hl.dsp.window.fullscreen({ action = "toggle" }))
hl.bind(mod .. " + SHIFT + F",      hl.dsp.window.fullscreen({ action = "toggle", mode = "maximized" }))
hl.bind(mod .. " + P",              hl.dsp.window.pseudo())
hl.bind(mod .. " + J",              hl.dsp.layout("togglesplit"))   -- dwindle

-- --- focus / move: ARROW KEYS -----------------------------------------
local DIR = { Left = "l", Right = "r", Up = "u", Down = "d" }
for key, d in pairs(DIR) do
  hl.bind(mod .. " + " .. key,          hl.dsp.focus({ direction = d }))
  hl.bind(mod .. " + SHIFT + " .. key,  hl.dsp.window.move({ direction = d }))
end

-- --- workspaces 1..10 ------------------------------------------------
for i = 1, 10 do
  local k = i % 10   -- 10 -> key "0"
  hl.bind(mod .. " + " .. k,          hl.dsp.focus({ workspace = i }))
  hl.bind(mod .. " + SHIFT + " .. k,  hl.dsp.window.move({ workspace = i, follow = false }))
end
hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- --- clipboard history (cliphist via rofi) -------------------------
hl.bind(mod .. " + V", hl.dsp.exec_cmd(
  "sh -c \"cliphist list | rofi -dmenu -p clip | cliphist decode | wl-copy\""))

-- --- screenshots -> file + clipboard -------------------------------
hl.bind("Print",             hl.dsp.exec_cmd(SCRIPTS .. "/screenshot.sh region"))
hl.bind(mod .. " + Print",   hl.dsp.exec_cmd(SCRIPTS .. "/screenshot.sh output"))
hl.bind("SHIFT + Print",     hl.dsp.exec_cmd(SCRIPTS .. "/screenshot.sh window"))

-- --- mouse: move / resize floating windows -------------------------
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- --- audio (locked = works while screen is locked) ----------------
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true })

-- --- media (playerctl) -------------------------------------------
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

-- --- backlight (no-op in VM, real on metal) ---------------------
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), { locked = true, repeating = true })
