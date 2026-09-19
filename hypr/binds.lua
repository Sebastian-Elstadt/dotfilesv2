-- Skemos — keybindings.

local modes    = require("modes")
local minimize = require("minimize")
require("alttab")   -- ALT+TAB / ALT+SHIFT+TAB — MRU window walk

local mod   = "SUPER"
local HOME  = os.getenv("HOME")
local SCRIPTS  = HOME .. "/.config/hypr/scripts"
local SECURITY = HOME .. "/.config/security/scripts"

-- Terminal: foot on the VM. METAL: change this one word to "kitty" and reload.
local terminal = "foot"
local launcher = "rofi -show drun"

-- --- core (spec) ---------------------------------------------------------
hl.bind(mod .. " + Q",              hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + Return",         hl.dsp.exec_cmd(terminal))   -- alias (Hyprland-default muscle memory)
hl.bind(mod .. " + D",              hl.dsp.exec_cmd(launcher))   -- spec bind
hl.bind(mod .. " + R",              hl.dsp.exec_cmd(launcher))   -- alias
hl.bind(mod .. " + C",              hl.dsp.window.close())
hl.bind(mod .. " + W",              hl.dsp.exec_cmd(SCRIPTS .. "/window-switch.sh"))  -- search all windows, jump to one
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

-- ==== SECURITY PANEL ====================================================
-- SUPER+S opens the security dashboard: aggregated scan status, live
-- busy/idle per job, log viewing, and live-tail for anything running.
-- See SKEMOS.md "Security" and
-- docs/superpowers/specs/2026-09-17-security-hardening-and-containment-design.md
hl.bind(mod .. " + S", hl.dsp.exec_cmd(
  "foot -a skemos-security -W 110x32 -T 'SKEMOS SECURITY' -e " .. SECURITY .. "/security-panel.sh"))
-- ==== end SECURITY PANEL =================================================

-- ==== GROUP BARS — trial (added 2026-09-07) ==========================
-- SUPER+G       fold the focused window into / out of a group (tab stack)
-- SUPER+]  / [  next / previous tab in the group
-- SUPER+SHIFT+] / [  move the active window along the tab order
-- Add more windows by dragging their titlebar onto the groupbar.
-- TO REMOVE: delete this block and the "GROUP BARS" block in look.lua.
hl.bind(mod .. " + G",             hl.dsp.group.toggle())
hl.bind(mod .. " + bracketright",  hl.dsp.group.next())
hl.bind(mod .. " + bracketleft",   hl.dsp.group.prev())
hl.bind(mod .. " + SHIFT + bracketright", hl.dsp.group.move_window({ direction = "f" }))
hl.bind(mod .. " + SHIFT + bracketleft",  hl.dsp.group.move_window({ direction = "b" }))
-- ==== end GROUP BARS ================================================

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
