-- ============================================================================
--  Skemos — Hyprland entrypoint
--  Dark-mode e-ink paper with a blueprint overlay.
--  Config language: Lua (hyprlang is deprecated since Hyprland 0.55).
--  Split into modules under ~/.config/hypr/ ; order below matters.
-- ============================================================================

-- GPU: NVIDIA RTX 5070 (01:00.0) + AMD Granite Ridge iGPU (12:00.0). The monitor
-- is on a DisplayPort of the NVIDIA card, so the NVIDIA card must be primary:
-- otherwise Aquamarine renders the whole desktop on the iGPU and copies every
-- frame across PCIe to the NVIDIA card just to scan it out (extra latency, no
-- direct scanout, the 5070 idle). With AQ_DRM_DEVICES unset Aquamarine's pick
-- races boot to boot — sometimes iGPU, sometimes NVIDIA — which also made the
-- screen shader link error (skemos.frag) come and go with the Mesa/NVIDIA path.
--
-- Pin it. card0 = NVIDIA deterministically (nvidia_drm is in the initramfs
-- MODULES and claims DRM minor 0 before amdgpu loads from udev); first entry =
-- primary. Plain node paths only — Aquamarine 0.15 chokes on /dev/dri/by-path/*
-- symlinks ("CBackend::create() failed!"). Verify after a reboot with:
--   hyprctl systeminfo | grep -A2 'GPU information'   # sanity
--   grep 'becomes primary drm' $XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.log
--   ls -l /dev/dri/by-path/pci-0000:01:00.0-card       # must still -> card0
-- If a kernel/mkinitcpio change ever renumbers the cards, fix the paths here.
hl.env("AQ_DRM_DEVICES", "/dev/dri/card0:/dev/dri/card1")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")

require("colors")     -- palette (no side effects, just data)
require("monitors")   -- outputs — generic, no hardcoded connector
require("look")       -- rounding 0, border 2, halftone shader, fast motion
require("rules")      -- window/workspace rules; floating-only umbra (AFTER look)
require("binds")      -- keybindings (pulls in modes + minimize)
require("autostart")  -- waybar, hyprpaper, mako, hypridle, polkit, cliphist
