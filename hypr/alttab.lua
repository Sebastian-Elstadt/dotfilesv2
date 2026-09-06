-- Skemos — ALT+TAB: walk through windows in most-recently-used order.
--
--   ALT+TAB          : step one window *older* in MRU order
--   ALT+SHIFT+TAB    : step one window *newer*
--
-- Keep tapping to walk further; each tap moves one step through a snapshot of
-- the MRU order taken when the run began. A fresh run starts when the previous
-- one goes stale — >STALE seconds since the last tap, or focus landed somewhere
-- outside the snapshot (you did something else in between). No need to hold ALT.
--
-- Works in any layout (TILE or DESK) and across workspaces. Windows parked in
-- the minimize drawer (special:*) are skipped.
--
-- Hyprland Lua facts this relies on (0.56):
--   * hl.get_windows() -> every window; each has .address, .workspace,
--     .focus_history_id (0 = focused, 1 = previous, ...).
--   * hl.bind(key, fn, opts) ; SHIFT+Tab can arrive as ISO_Left_Tab.

local M = {}

local STALE = 2          -- seconds; taps farther apart than this start a new run

local snap = {}          -- frozen array of window addresses, MRU order
local idx  = 1           -- 1-based cursor into snap (1 == the window we set out from)
local last = 0           -- os.time() of the last tap

local function mru_snapshot()
  local wins = hl.get_windows() or {}
  local live = {}
  for _, w in ipairs(wins) do
    local ws = w.workspace and w.workspace.name or ""
    if not tostring(ws):match("^special:") then
      live[#live + 1] = w
    end
  end
  table.sort(live, function(a, b)
    return (a.focus_history_id or 1e9) < (b.focus_history_id or 1e9)
  end)
  local addrs = {}
  for _, w in ipairs(live) do addrs[#addrs + 1] = w.address end
  return addrs
end

local function run_is_live()
  if os.time() - last > STALE then return false end
  if #snap < 2 then return false end
  local cur = hl.get_active_window()
  return cur ~= nil and snap[idx] == cur.address
end

local function step(dir)
  if not run_is_live() then
    snap = mru_snapshot()
    idx  = 1
  end
  last = os.time()
  if #snap < 2 then return end
  idx = ((idx - 1 + dir) % #snap) + 1
  hl.dispatch(hl.dsp.focus({ window = "address:" .. snap[idx] }))
end

M.step = step   -- exposed for testing

hl.bind("ALT + Tab",                  function() step(1)  end)
hl.bind("ALT + SHIFT + Tab",          function() step(-1) end)
hl.bind("ALT + SHIFT + ISO_Left_Tab", function() step(-1) end)  -- SHIFT+Tab alias

return M
