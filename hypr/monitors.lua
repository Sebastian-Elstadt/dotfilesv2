-- Skemos — monitors. Portable: no hardcoded connector names.
-- The VM currently exposes card0-Virtual-1; the bare-metal machine will expose
-- something else (eDP-1 / DP-1 / HDMI-A-1). The wildcard rule below covers all.

-- Generic rule for every output: highest refresh rate it advertises, auto-place,
-- no scaling. "highrr" keeps this connector-agnostic — on saber's Acer it picks
-- 2560x1440@180 over the EDID-preferred 2560x1440@60; a plainer panel just gets
-- its top mode. For a specific mode/scale/position add a second hl.monitor({
-- output = "DP-1", mode = "2560x1440@180", ... }) ABOVE this one — last match wins.
hl.monitor({
  output   = "",          -- "" = all outputs
  mode     = "highrr",    -- highest refresh; "preferred" if modes can't be read
  position = "auto",
  scale    = 1,           -- integer 1; "auto" can misbehave under VMSVGA
})

-- ---------------------------------------------------------------------------
-- VirtualBox / VM notes (safe to ignore on bare metal):
--
--  * Hyprland needs GL. Enable "Display > Screen > Enable 3D Acceleration" in
--    the VM settings (host side) or Hyprland will fail to start.
--  * If it still won't start with a renderer/EGL error, try launching once with
--    a software GL fallback to confirm the config is otherwise fine:
--        LIBGL_ALWAYS_SOFTWARE=1 uwsm start hyprland
--    (slow — do not leave it on.) Do NOT put this in hl.env on bare metal.
-- ---------------------------------------------------------------------------
