-- Night Vellum — MINIMIZE via special:minimized.
--
-- The old 5-bind wiki trick (togglespecialworkspace + movetoworkspace +0 ...)
-- broke on Hyprland 0.54+: restore flashes onto the active workspace then
-- bounces straight back. See https://github.com/hyprwm/Hyprland/discussions/13703
--
-- This is the modern equivalent, done natively in Lua. A single Lua bind runs
-- its dispatches in one pass, which is exactly what avoids the race that broke
-- the multi-bind version.
--
--   SUPER+M        : active window -> special:minimized, silently (focus stays).
--                    If the active window is ALREADY in the drawer, it is
--                    restored to the current real workspace instead.
--   SUPER+SHIFT+M  : show / hide the minimized drawer.
--
-- Waybar shows the count of windows in special:minimized (see
-- waybar/scripts/minimized.sh).

local M = {}
local NAME  = "minimized"
local SPECIAL = "special:" .. NAME

local function refresh_bar() hl.exec_cmd("pkill -RTMIN+9 waybar") end

function M.minimize()
  local w = hl.get_active_window()
  if not w then return end

  local ws = w.workspace
  if ws and ws.name == SPECIAL then
    -- already minimized -> restore to the real workspace under the drawer
    local target = hl.get_active_workspace()   -- real ws, not the special
    if target and not target.special then
      hl.dispatch(hl.dsp.window.move({
        window = "address:" .. w.address,
        workspace = tostring(target.id),
        follow = true,
      }))
    end
  else
    hl.dispatch(hl.dsp.window.move({
      window = "address:" .. w.address,
      workspace = SPECIAL,
      follow = false,           -- silent: don't pull focus to the drawer
    }))
  end
  refresh_bar()
end

function M.toggle_drawer()
  hl.dispatch(hl.dsp.workspace.toggle_special(NAME))
  refresh_bar()
end

return M
