#version 440
// Ares helm, pass 2 (FEAT-ares-sentinel-lock): the silhouette as a field of emitting LEDs.
// Compile: /usr/lib/qt6/bin/qsb --qt6 -o helm.frag.qsb helm.frag
// `field` is pass 1 (helm-field.frag): the blended pose, reconstructed as a smooth coverage map with one texel per
// LED (96*density square). This pass thresholds it into small round LEDs, antialiased to about one screen pixel
// at any size, and adds the life and state effects. Everything outside lit LEDs is pure black (OLED).

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(binding = 1) uniform sampler2D field;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float energy;     // typing excitement 0..1
    float alert;      // red, deny 0..1
    float check;      // amber, PAM in flight 0..1
    float caps;       // blue 0..1
    float glitch;     // deny tear 0..1
    float ripple;     // seconds since the last keystroke
    float dissolve;   // grant: LEDs rise and fade 0..1
    float dim;        // overall brightness
    float scan;       // sentinel scan beam position 0..1 (top -> bottom), <0 = off
    float lockon;     // 0..1: facing and locked on the subject
    float minor;      // peripheral helm
    float density;    // LEDs per source dot along each axis
};

const float N = 96.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float cover(vec2 q) {   // q in source-dot units
    if (q.x < 0.0 || q.y < 0.0 || q.x >= N || q.y >= N) return 0.0;
    return texture(field, q / N).r;
}

void main() {
    float D = max(1.0, density);
    vec2 p = qt_TexCoord0 * N;

    // Deny: banded horizontal tearing, in whole LEDs.
    float band = floor(p.y / 3.0);
    float tear = (hash(vec2(band, floor(time * 20.0))) - 0.5) * 10.0 * glitch
               * step(0.6, hash(vec2(band, 7.0)));
    p.x += floor(tear * D) / D;

    // Grant: each source column rises at its own rate and burns out.
    float colSeed = hash(vec2(floor(p.x), 3.1));
    float rise = dissolve * dissolve * (20.0 + 70.0 * colSeed);
    p.y += rise;

    // LED grid: one LED per field texel.
    vec2 P = p * D;
    vec2 fcell = floor(P);
    vec2 fl = fract(P) - 0.5;
    vec2 q = (fcell + 0.5) / D;
    float cov = cover(q);
    float on = smoothstep(0.40, 0.60, cov);
    float ny = q.y / N;

    float h = hash(fcell);
    // Life: each LED breathes slightly out of phase; the crest (upper third) shimmers.
    float breathe = 0.84 + 0.16 * sin(time * 1.3 + h * 6.283);
    float crest = smoothstep(0.42, 0.0, ny);
    float shimmer = 1.0 + crest * 0.3 * sin(time * (3.0 + 6.0 * energy) + h * 40.0);
    // Sparse sparkle, more while typing (thinned for the denser grid).
    float spark = step(1.0 - (0.004 + energy * 0.02) / (D * D), hash(fcell + floor(time * 8.0)));
    // Edge LEDs (partial coverage) sit a little dimmer, which reads as a soft, antialiased contour.
    float edge = mix(0.55, 1.0, smoothstep(0.45, 0.85, cov));

    // Keystroke ripple: a bright band climbs from the bottom of the helm.
    float rp = clamp(ripple / 0.55, 0.0, 1.0);
    float rippleBand = (1.0 - rp) * exp(-abs((1.0 - ny) - rp) * 14.0) * step(ripple, 0.55);

    // Sentinel scan beam: a thin bright line with a short fading trail above it.
    float beam = scan >= 0.0
        ? exp(-abs(ny - scan) * 70.0) + 0.22 * exp(-max(0.0, scan - ny) * 14.0) * step(ny, scan)
        : 0.0;

    // Dissolve: LEDs burn out as they rise.
    float burn = step(colSeed * 0.8 + h * 0.2, 1.0 - dissolve);

    float lit = on * edge * breathe * shimmer * burn;
    lit += on * burn * (rippleBand * 1.2 + beam * 0.9 + spark * 0.8);
    lit *= 0.85 + 0.25 * lockon;

    // Round LED: about one screen pixel of antialiasing at any size, with a hot core.
    float aa = max(fwidth(P.x), 1e-4) * 0.8;
    float r = length(fl);
    float R = 0.36;
    float dotShape = 1.0 - smoothstep(R - aa, R + aa, r);
    float core = 1.0 - smoothstep(0.0, 0.18 + aa, r);

    // Faint halo from the continuous silhouette, between lit LEDs.
    float halo = cover(p) * burn * 0.05 * (1.0 - dotShape);

    vec3 cyan  = vec3(0.039, 0.741, 0.776);
    vec3 blue  = vec3(0.000, 0.447, 1.000);
    vec3 amber = vec3(1.000, 0.549, 0.000);
    vec3 red   = vec3(1.000, 0.000, 0.235);
    vec3 col = cyan;
    col = mix(col, blue, caps);
    col = mix(col, amber, check);
    col = mix(col, red, alert);
    col = mix(col, vec3(0.75, 1.0, 1.0), dissolve * 0.7 + beam * 0.25);

    vec3 hot = mix(col, vec3(0.85, 1.0, 1.0), 0.5);
    vec3 c = col * (lit * dotShape) + hot * on * edge * burn * core * 0.3 * (0.6 + 0.4 * lockon)
           + col * halo * breathe;
    // Chromatic fringe while glitching.
    c.r += glitch * 0.5 * on * dotShape * step(0.7, hash(vec2(band, 2.0)));
    c *= dim * (minor > 0.5 ? 0.55 : 1.0);
    fragColor = vec4(c, 1.0) * qt_Opacity;
}
