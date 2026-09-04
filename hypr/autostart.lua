-- Night Vellum — autostart. Everything the desktop needs, nothing else.
-- No browser, no second bar, no tray-spam.

local HOME    = os.getenv("HOME")
local SCRIPTS = HOME .. "/.config/hypr/scripts"

hl.on("hyprland.start", function()
  -- polkit auth agent (GUI privilege prompts)
  hl.exec_cmd("systemctl --user start hyprpolkitagent.service")

  -- notifications
  hl.exec_cmd("mako")

  -- clipboard history store (both text and images)
  hl.exec_cmd("wl-paste --type text  --watch cliphist store")
  hl.exec_cmd("wl-paste --type image --watch cliphist store")

  -- Wallpaper: DEFERRED on the VM. hyprpaper 0.8.4 core-dumps in its aquamarine
  -- backend under VirtualBox software GL ("vmwgfx: Failed to open channel").
  -- Until the VM gets working 3D accel (or we switch to swaybg), the desktop
  -- falls back to misc.background_color = paper-bg (#161513), set in look.lua.
  -- To re-enable once the GPU cooperates, uncomment:
  --   hl.exec_cmd("hyprpaper")
  --   hl.exec_cmd(SCRIPTS .. "/wallpaper.sh")

  -- bar
  hl.exec_cmd("waybar")

  -- idle daemon (dim -> lock -> dpms)
  hl.exec_cmd("hypridle")
end)

-- Regenerate + reapply the wallpaper when monitors change (resolution, hotplug).
-- DEFERRED with the wallpaper (see above).
-- hl.on("monitor.layout_changed", function()
--   hl.exec_cmd(SCRIPTS .. "/wallpaper.sh")
-- end)
