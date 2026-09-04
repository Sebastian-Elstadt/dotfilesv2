-- Night Vellum — WINDOW MODES: TILE (default) <-> DESK, per workspace, persisted.
--
--   TILE : dwindle, new windows tile, tight gaps (global gaps from look.lua)
--   DESK : every window on THAT workspace floats; new windows float until
--          toggled back; slightly larger gaps.
--
-- Per-workspace: toggling workspace 2 to DESK does not touch workspace 1.
-- Persisted: the set of DESK workspaces is written to a state file and replayed
-- on Hyprland start, so DESK survives a reload / logout / reboot.
--
-- Implementation (native Lua, verified against Hyprland 0.56.2 stubs):
--   * one NAMED window-rule per workspace: { match = {workspace=N}, float=true },
--     created disabled, enabled while that workspace is in DESK  -> new windows float
--   * one workspace-rule per workspace with the larger DESK gaps, created
--     disabled, enabled while in DESK                            -> gaps
--   * on toggle, existing windows on the workspace are floated/tiled explicitly
--   * state file + hyprland.start replay                         -> persistence
--   * hl.dsp.event("nvmode,<MODE>") on every toggle              -> Waybar updates
--
-- Sources: wiki Window-Rules (named rule :set_enabled), Workspace-Rules,
-- Lua-utilities (hl.get_active_workspace / hl.get_workspace_windows),
-- Dispatchers (window.float, dsp.event).

local M = {}

local HOME       = os.getenv("HOME")
local STATE_DIR  = (os.getenv("XDG_STATE_HOME") or (HOME .. "/.local/state")) .. "/night-vellum"
local STATE_FILE = STATE_DIR .. "/desk-workspaces"

local DESK_IN, DESK_OUT = 10, 20   -- DESK gaps (TILE uses the global 4 / 8)

local desk        = {}   -- desk[wsid] = true
local float_rules = {}   -- wsid -> HL.WindowRule    (named, float=true)
local gaps_rules  = {}   -- wsid -> HL.WorkspaceRule (DESK gaps)

-- ---- persistence --------------------------------------------------------
local function persist()
  os.execute("mkdir -p '" .. STATE_DIR .. "'")
  local f = io.open(STATE_FILE, "w")
  if not f then return end
  for id in pairs(desk) do f:write(tostring(id) .. "\n") end
  f:close()
end

local function load_ids()
  local ids, f = {}, io.open(STATE_FILE, "r")
  if not f then return ids end
  for line in f:lines() do
    local n = tonumber((line:gsub("%s+", "")))
    if n then ids[#ids + 1] = n end
  end
  f:close()
  return ids
end

-- ---- lazily-created per-workspace rule handles -------------------------
local function float_rule_for(id)
  if not float_rules[id] then
    float_rules[id] = hl.window_rule({
      name    = "nv-desk-float-ws" .. id,
      match   = { workspace = tostring(id) },
      float   = true,
      enabled = false,
    })
  end
  return float_rules[id]
end

local function gaps_rule_for(id)
  if not gaps_rules[id] then
    gaps_rules[id] = hl.workspace_rule({
      workspace = tostring(id),
      gaps_in   = DESK_IN,
      gaps_out  = DESK_OUT,
      enabled   = false,
    })
  end
  return gaps_rules[id]
end

-- ---- apply --------------------------------------------------------------
local function set_windows_float(id, on)
  local action = on and "enable" or "disable"
  for _, w in ipairs(hl.get_workspace_windows(id) or {}) do
    hl.dispatch(hl.dsp.window.float({ window = "address:" .. w.address, action = action }))
  end
end

local function enter_desk(id)
  desk[id] = true
  float_rule_for(id):set_enabled(true)
  gaps_rule_for(id):set_enabled(true)
  set_windows_float(id, true)
end

local function enter_tile(id)
  desk[id] = nil
  if float_rules[id] then float_rules[id]:set_enabled(false) end
  if gaps_rules[id]  then gaps_rules[id]:set_enabled(false)  end
  set_windows_float(id, false)
end

-- ---- public ------------------------------------------------------------
function M.mode_of(id) return desk[id] and "DESK" or "TILE" end

function M.toggle()
  local ws = hl.get_active_workspace()
  if not ws or ws.special then return end   -- ignore special workspaces
  local id = ws.id
  if desk[id] then enter_tile(id) else enter_desk(id) end
  persist()
  hl.dispatch(hl.dsp.event("nvmode," .. M.mode_of(id)))   -- socket2 (future socat use)
  hl.exec_cmd("pkill -RTMIN+8 waybar")                    -- instant Waybar MODE refresh
end

-- ---- startup replay --------------------------------------------------
hl.on("hyprland.start", function()
  for _, id in ipairs(load_ids()) do enter_desk(id) end
end)

-- Belt-and-braces: if a window maps on a DESK workspace before the named
-- rule settles, float it explicitly.
hl.on("window.open", function(w)
  if w and w.workspace and desk[w.workspace.id] and not w.floating then
    hl.dispatch(hl.dsp.window.float({ window = "address:" .. w.address, action = "enable" }))
  end
end)

return M
