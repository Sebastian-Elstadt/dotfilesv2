// Skemos — halftone screen shader.
// Wired in via decoration:screen_shader in hypr/look.lua.
//
// Static (no `time` uniform, so debug:damage_tracking stays ON, no GPU cost).
// A fine ordered (Bayer 4x4) dither weighted toward the shadows: the ink-black
// field reads as a plotted schematic panel while text stays crisp. It also
// carries the "dissolve" — a window crossing the quantisation steps as it fades
// in (fast fades, look.lua) briefly breaks into stipple. Faint scanline +
// vignette on top.
//
// The corner-bracket / registration-mark HUD lives on the WALLPAPER now
// (hypr/scripts/wallpaper.sh) so it never sits over windows.

precision highp float;
varying vec2 v_texcoord;
uniform sampler2D tex;

// ---- tunables -------------------------------------------------------------
const float DITHER_STEPS = 34.0;   // quantisation levels; lower = chunkier stipple
const float DITHER_DARK  = 0.85;   // dither strength in shadows  (0..1)
const float DITHER_LIGHT = 0.10;   // dither strength in highlights
const float SCANLINE     = 0.010;  // horizontal line modulation; 0 = off
const float VIGNETTE     = 0.10;   // edge falloff; 0 = off

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

void main() {
    vec3 col = texture2D(tex, v_texcoord).rgb;
    vec2 p   = gl_FragCoord.xy;

    // halftone
    float thr = bayer4x4(p) - 0.5;
    vec3  q   = floor(col * DITHER_STEPS + 0.5 + thr) / DITHER_STEPS;
    float lum = dot(col, vec3(0.299, 0.587, 0.114));
    float amt = mix(DITHER_DARK, DITHER_LIGHT, smoothstep(0.04, 0.55, lum));
    col = mix(col, q, amt);

    // display texture
    if (SCANLINE > 0.0)
        col *= 1.0 - SCANLINE * (0.5 - 0.5 * cos(p.y * 2.0943951));  // ~3px period
    if (VIGNETTE > 0.0) {
        vec2 uv = v_texcoord - 0.5;
        col *= 1.0 - dot(uv, uv) * VIGNETTE;
    }

    gl_FragColor = vec4(col, 1.0);
}
