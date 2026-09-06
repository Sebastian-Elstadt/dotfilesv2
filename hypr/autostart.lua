-- Skemos — autostart. Everything the desktop needs, nothing else.
-- No browser, no second bar, no tray-spam.

local HOME    = os.getenv("HOME")
local SCRIPTS = HOME .. "/.config/hypr/scripts"

-- Are we in a VM? hyprpaper / hyprlock crash in their aquamarine backend under
-- software GL (VirtualBox VMSVGA), so the wallpaper daemon is skipped there and
-- misc.background_color (look.lua) carries the desktop. On bare metal this is
-- false and the wallpaper runs normally — no config edit needed.
local function in_vm()
  local ok = os.execute("systemd-detect-virt --quiet")
  return ok == true or ok == 0
end
local VM = in_vm()

hl.on("hyprland.start", function()
  -- polkit auth agent (GUI privilege prompts)
  hl.exec_cmd("systemctl --user start hyprpolkitagent.service")

  -- notifications
  hl.exec_cmd("mako")

  -- clipboard history store (both text and images)
  hl.exec_cmd("wl-paste --type text  --watch cliphist store")
  hl.exec_cmd("wl-paste --type image --watch cliphist store")

  -- wallpaper daemon + Skemos schematic sheet (bare metal only)
  if not VM then
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd(SCRIPTS .. "/wallpaper.sh")
  end

  -- bar
  hl.exec_cmd("waybar")

  -- idle daemon (dim -> lock -> dpms)
  hl.exec_cmd("hypridle")
end)

-- Regenerate + reapply the wallpaper when monitors change (bare metal only).
if not VM then
  hl.on("monitor.layout_changed", function()
    hl.exec_cmd(SCRIPTS .. "/wallpaper.sh")
  end)
end
