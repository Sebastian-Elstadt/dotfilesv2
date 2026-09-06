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
  -- login gate — bring the session up already locked, so the schematic
  -- hyprlock screen is the first thing shown at boot instead of the bare
  -- agetty text prompt. agetty autologins `bas` on tty1 (no password at the
  -- console) -> ~/.bash_profile -> start-hyprland -> this. Same screen and
  -- same password prompt as SUPER+L; lock.sh's watchdog fails it open if
  -- hyprlock ever dies. Requires the getty@tty1 autologin drop-in (INSTALL
  -- §3); without it you just get the normal text login and this is a no-op
  -- lock you dismiss with your password anyway.
  hl.exec_cmd(SCRIPTS .. "/lock.sh")

  -- Dark by default. There's no DE to hold this preference, so apps that
  -- "follow the system" (GTK4 / libadwaita, Firefox, Chromium, Electron,
  -- Qt 6.5+) read it from the xdg-desktop-portal Settings interface, which
  -- xdg-desktop-portal-gtk sources from these GNOME keys. GTK3 apps also read
  -- ~/.config/gtk-3.0/settings.ini (kept in the repo). Idempotent; safe to
  -- re-run every start.
  hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme prefer-dark")
  hl.exec_cmd("gsettings set org.gnome.desktop.interface gtk-theme Adwaita-dark")

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

  -- orange "PROGRAM DRAWER" banner: shown along the bottom whenever the
  -- minimize drawer (special:minimized) is on screen. Follows socket2 events.
  hl.exec_cmd(SCRIPTS .. "/drawer-banner.sh")

  -- idle daemon (dim -> lock -> dpms)
  hl.exec_cmd("hypridle")
end)

-- Regenerate + reapply the wallpaper when monitors change (bare metal only).
if not VM then
  hl.on("monitor.layout_changed", function()
    hl.exec_cmd(SCRIPTS .. "/wallpaper.sh")
  end)
end
