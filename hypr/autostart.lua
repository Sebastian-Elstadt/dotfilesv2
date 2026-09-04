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

  -- wallpaper daemon, then paint Night Vellum wallpaper + crop marks
  hl.exec_cmd("hyprpaper")
  hl.exec_cmd(SCRIPTS .. "/wallpaper.sh")

  -- bar
  hl.exec_cmd("waybar")

  -- idle daemon (dim -> lock -> dpms)
  hl.exec_cmd("hypridle")
end)

-- Regenerate + reapply the wallpaper when monitors change (resolution, hotplug).
hl.on("monitor.layout_changed", function()
  hl.exec_cmd(SCRIPTS .. "/wallpaper.sh")
end)
