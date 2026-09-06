// Night Vellum — schematic HUD + halftone screen shader.
// Wired in via decoration:screen_shader in hypr/look.lua.
//
// Two static layers (no `time` uniform, so debug:damage_tracking stays ON and
// there is no GPU-utilisation penalty):
//
//   1. HALFTONE — a fine ordered (Bayer 4x4) dither, weighted toward the
//      shadows, so the ink-black field reads as a plotted schematic panel
//      while text stays crisp. It also does the "dissolve": as a window
//      fades in (fast fades, look.lua) it crosses the quantisation steps and
//      briefly breaks into stipple.
//   2. HUD — corner L-brackets, a hairline inset frame, and edge registration
//      crosshairs. The Anduril / Saronic instrument frame, always on.
//
// RES is DP-1's pixel size. If the panel changes, update it here.

precision highp float;
varying vec2 v_texcoord;
uniform sampler2D tex;

const vec2 RES = vec2(2560.0, 1440.0);

// palette — mirrors hypr/colors.lua
const vec3 INK       = vec3(0.898, 0.882, 0.839);   // e5e1d6
const vec3 INK_DIM   = vec3(0.604, 0.580, 0.541);   // 9a948a
const vec3 INK_FAINT = vec3(0.333, 0.318, 0.290);   // 55514a
const vec3 ACCENT    = vec3(0.757, 0.400, 0.227);   // c1663a

// ---- tunables -------------------------------------------------------------
const float DITHER_STEPS = 34.0;   // quantisation levels; lower = chunkier stipple
const float DITHER_DARK  = 0.85;   // dither strength in shadows  (0..1)
const float DITHER_LIGHT = 0.10;   // dither strength in highlights
const float SCANLINE     = 0.010;  // horizontal line modulation; 0 = off
const float VIGNETTE     = 0.10;   // edge falloff; 0 = off

const float TOP_RESERVE = 26.0;    // keep the HUD clear of the 22px waybar
const float HUD_INSET   = 22.0;    // px from screen edge to bracket corner
const float HUD_LEN     = 34.0;    // bracket arm length
const float HUD_TH      = 2.0;     // bracket / crosshair line weight
const float FRAME_INSET = 14.0;    // hairline frame distance from edge
const float FRAME_TH    = 1.0;
const float REG_LEN     = 9.0;     // registration crosshair arm length
const float REG_INSET   = 30.0;    // crosshair distance from edge

const float HUD_A   = 0.60;        // bracket opacity
const float FRAME_A = 0.45;        // frame opacity
const float REG_A   = 0.55;        // crosshair opacity

// ---- helpers ------------------------------------------------------------
float seg(float a, float lo, float hi) { return step(lo, a) * step(a, hi); }

float bayer4x4(vec2 c) {
    c = floor(mod(c, 4.0));
    float i = c.x + c.y * 4.0;
    float b = 0.0;
    b = (i ==  0.0) ?  0.0 : b;  b = (i ==  1.0) ?  8.0 : b;
    b = (i ==  2.0) ?  2.0 : b;  b = (i ==  3.0) ? 10.0 : b;
    b = (i ==  4.0) ? 12.0 : b;  b = (i ==  5.0) ?  4.0 : b;
    b = (i ==  6.0) ? 14.0 : b;  b = (i ==  7.0) ?  6.0 : b;
    b = (i ==  8.0) ?  3.0 : b;  b = (i ==  9.0) ? 11.0 : b;
    b = (i == 10.0) ?  1.0 : b;  b = (i == 11.0) ?  9.0 : b;
    b = (i == 12.0) ? 15.0 : b;  b = (i == 13.0) ?  7.0 : b;
    b = (i == 14.0) ? 13.0 : b;  b = (i == 15.0) ?  5.0 : b;
    return (b + 0.5) / 16.0;
}

// L-bracket. d = (distance to vertical edge, distance to horizontal edge).
float bracket(vec2 d) {
    float a1 = seg(d.x, HUD_INSET, HUD_INSET + HUD_LEN) * seg(d.y, HUD_INSET, HUD_INSET + HUD_TH);
    float a2 = seg(d.y, HUD_INSET, HUD_INSET + HUD_LEN) * seg(d.x, HUD_INSET, HUD_INSET + HUD_TH);
    return clamp(a1 + a2, 0.0, 1.0);
}

// plus sign centred at c (px), arm length r, half-weight w
float plus(vec2 p, vec2 c, float r, float w) {
    vec2 d = abs(p - c);
    float h = step(d.y, w) * step(d.x, r);
    float v = step(d.x, w) * step(d.y, r);
    return clamp(h + v, 0.0, 1.0);
}

void main() {
    vec3 col = texture2D(tex, v_texcoord).rgb;
    vec2 p   = gl_FragCoord.xy;

    // ---- 1. halftone ---------------------------------------------------
    float thr = bayer4x4(p) - 0.5;
    vec3  q   = floor(col * DITHER_STEPS + 0.5 + thr) / DITHER_STEPS;
    float lum = dot(col, vec3(0.299, 0.587, 0.114));
    float amt = mix(DITHER_DARK, DITHER_LIGHT, smoothstep(0.04, 0.55, lum));
    col = mix(col, q, amt);

    // ---- 2. display texture ------------------------------------------
    if (SCANLINE > 0.0)
        col *= 1.0 - SCANLINE * (0.5 - 0.5 * cos(p.y * 2.0943951));  // ~3px period
    if (VIGNETTE > 0.0) {
        vec2 uv = v_texcoord - 0.5;
        col *= 1.0 - dot(uv, uv) * VIGNETTE;
    }

    // ---- 3. HUD -----------------------------------------------------
    // Top edge is pulled down by TOP_RESERVE so nothing collides with the bar.
    float Ld = p.x, Rd = RES.x - p.x, Bd = p.y;
    float Td = (RES.y - TOP_RESERVE) - p.y;

    float br = clamp(
        bracket(vec2(Ld, Bd)) + bracket(vec2(Rd, Bd)) +
        bracket(vec2(Ld, Td)) + bracket(vec2(Rd, Td)), 0.0, 1.0);

    float edgemin = min(min(Ld, Rd), min(Bd, Td));
    float frame   = seg(edgemin, FRAME_INSET, FRAME_INSET + FRAME_TH);

    float midY = (RES.y - TOP_RESERVE) * 0.5;
    float reg = clamp(
        plus(p, vec2(RES.x * 0.5, RES.y - TOP_RESERVE - REG_INSET), REG_LEN, HUD_TH * 0.5) +
        plus(p, vec2(RES.x * 0.5, REG_INSET),                        REG_LEN, HUD_TH * 0.5) +
        plus(p, vec2(REG_INSET,         midY),                       REG_LEN, HUD_TH * 0.5) +
        plus(p, vec2(RES.x - REG_INSET, midY),                       REG_LEN, HUD_TH * 0.5), 0.0, 1.0);

    col = mix(col, INK_FAINT, frame * FRAME_A);
    col = mix(col, INK_DIM,   reg   * REG_A);
    col = mix(col, INK_DIM,   br    * HUD_A);

    // one accent tick: a short stub off the top-left bracket's horizontal arm
    float tick = seg(Ld, HUD_INSET + HUD_LEN + 6.0, HUD_INSET + HUD_LEN + 16.0)
               * seg(Td, HUD_INSET, HUD_INSET + HUD_TH);
    col = mix(col, ACCENT, tick);

    gl_FragColor = vec4(col, 1.0);
}
