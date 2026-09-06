-- Skemos — monitors. Portable: no hardcoded connector names.
-- The VM currently exposes card0-Virtual-1; the bare-metal machine will expose
-- something else (eDP-1 / DP-1 / HDMI-A-1). The wildcard rule below covers all.

-- Generic rule for every output: use its preferred mode, auto-place, no scaling.
-- On the real machine, add a second hl.monitor({ output = "eDP-1", ... }) ABOVE
-- this one if you need a specific mode/scale/position — last match wins.
hl.monitor({
  output   = "",          -- "" = all outputs
  mode     = "preferred",
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
