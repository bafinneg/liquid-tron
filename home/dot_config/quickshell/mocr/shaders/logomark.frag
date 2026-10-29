#version 330
// logomark.frag — offline render dialect (moderngl / render.py)
// See logomark.qs.frag for the Qt6/ShaderEffect dialect (GLSL 4.40).
// Geometry, math, and all constants are identical between the two files.
// Differences: (1) no layout qualifiers; (2) bare uniform declarations;
// (3) no qt_Matrix / qt_Opacity; (4) input varying named qt_TexCoord0
// (moderngl vertex shader must provide this name for parity with Qt6 dialect).

in vec2 qt_TexCoord0;
out vec4 fragColor;

uniform float u_time;
uniform vec2  u_resolution;
uniform float u_outerState;        // 0.0 = idle, 1.0 = active
uniform float u_innerState;        // 0.0 = idle, 1.0 = active
uniform float u_outerPulsePhase;   // sine phase for outer ring opacity pulse
uniform float u_innerPulsePhase;   // 180° offset from outer during dual-active
uniform vec4  u_cyan;
uniform vec4  u_amber;

const float N            = 4.0;
const float OUTER_R      = 0.458;    // 110/240 — outer ring radius
const float INNER_R      = 0.321;    //  77/240 — inner ring radius (70% of outer)
const float STROKE       = 0.0083;   //   2/240 — nominal stroke width
const float IDLE_OPACITY = 0.30;

// Layer A: phase sweep constants
const float OUTER_SWEEP_PERIOD = 15.0;  // seconds, clockwise
const float INNER_SWEEP_PERIOD = 18.0;  // seconds, counter-clockwise
const float SWEEP_ARC_DEG     = 40.0;  // angular width of bright spot
const float SWEEP_GAIN        =  1.8;  // luminance multiplier at sweep center

// Glow radii in normalized UV units: 4px/240 = 0.0167, 10px/240 = 0.0417
const float GLOW_IDLE   = 0.0167;
const float GLOW_ACTIVE = 0.0417;

float superEllipseField(vec2 uv, float r) {
    vec2 a = abs(uv / r);
    return pow(a.x, N) + pow(a.y, N) - 1.0;
}

// Returns SWEEP_GAIN at sweep center, 1.0 outside, smoothly tapered.
float sweepModulation(vec2 uv, float period, float direction) {
    float angle      = atan(uv.y, uv.x);
    float sweepAngle = mod(u_time / period, 1.0) * 6.2831853 * direction;
    float delta      = angle - sweepAngle;
    // Wrap into [-π, π]
    delta = mod(delta + 3.14159265, 6.2831853) - 3.14159265;
    float halfArc    = radians(SWEEP_ARC_DEG * 0.5);
    return mix(1.0, SWEEP_GAIN, smoothstep(halfArc, 0.0, abs(delta)));
}

void main() {
    vec2 uv = qt_TexCoord0 - 0.5;

    // Stroke widens 2px → 4px during active state
    float outerStroke = mix(STROKE, STROKE * 2.0, u_outerState);
    float innerStroke = mix(STROKE, STROKE * 2.0, u_innerState);

    // Layer C: sub-pixel AA boundary jitter (~0.1 Hz, ±0.3px)
    // Two slow sinusoids per ring, different phases to decorrelate them.
    float jitterOuter = sin(u_time * 0.628 + 1.3) * sin(u_time * 0.471 + 2.7)
                        * (0.3 / 240.0);
    float jitterInner = sin(u_time * 0.628 + 3.9) * sin(u_time * 0.471 + 5.1)
                        * (0.3 / 240.0);
    outerStroke += jitterOuter;
    innerStroke += jitterInner;

    float outerSdf  = superEllipseField(uv, OUTER_R);
    float innerSdf  = superEllipseField(uv, INNER_R);
    float outerMask = smoothstep(outerStroke, 0.0, abs(outerSdf) * OUTER_R);
    float innerMask = smoothstep(innerStroke, 0.0, abs(innerSdf) * INNER_R);

    // Layer A: phase sweep — outer CW, inner CCW (always on)
    float outerSweep = sweepModulation(uv, OUTER_SWEEP_PERIOD,  1.0);
    float innerSweep = sweepModulation(uv, INNER_SWEEP_PERIOD, -1.0);

    // Active-state opacity pulse: sine wave, ~2.4s period (2π/2.618 ≈ 2.4s).
    // Layered on top of phase sweep — both run simultaneously.
    float outerPulse = mix(1.0,
        0.7 + 0.3 * sin(u_time * 2.618 + u_outerPulsePhase),
        u_outerState);
    float innerPulse = mix(1.0,
        0.7 + 0.3 * sin(u_time * 2.618 + u_innerPulsePhase),
        u_innerState);

    // Base opacity: 30% idle → 85% active
    float outerOpacity = mix(IDLE_OPACITY, 0.85, u_outerState);
    float innerOpacity = mix(IDLE_OPACITY, 0.85, u_innerState);

    // Color: cyan at idle, amber at active
    vec4 outerColor = mix(u_cyan, u_amber, u_outerState);
    vec4 innerColor = mix(u_cyan, u_amber, u_innerState);

    // Ring contribution (premultiplied alpha: rgb = color * opacity * ...)
    vec4 ring =
        outerMask * outerColor * outerOpacity * outerSweep * outerPulse +
        innerMask * innerColor * innerOpacity * innerSweep * innerPulse;

    // Additive glow: exponential falloff from ring SDF, sweep-modulated.
    // Gives a soft bloom around each ring; scales with opacity for OLED safety.
    float outerGlowR = mix(GLOW_IDLE, GLOW_ACTIVE, u_outerState);
    float innerGlowR = mix(GLOW_IDLE, GLOW_ACTIVE, u_innerState);
    float outerGlow  = exp(-abs(outerSdf) * OUTER_R / outerGlowR)
                       * outerOpacity * 0.30 * outerSweep;
    float innerGlow  = exp(-abs(innerSdf) * INNER_R / innerGlowR)
                       * innerOpacity * 0.30 * innerSweep;

    fragColor = clamp(ring + outerGlow * outerColor + innerGlow * innerColor,
                      0.0, 1.0);
}
