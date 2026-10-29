#version 440
// logomark.qs.frag — Qt6/ShaderEffect dialect (GLSL 4.40, compiled to .qsb by qsb)
// See logomark.frag for the moderngl/offline-render dialect (GLSL 3.30).
// Geometry, math, and all constants are identical between the two files.
// Differences vs logomark.frag:
//   (1) layout(location=N) I/O qualifiers required by Qt6/Vulkan-style GLSL;
//   (2) uniforms wrapped in std140 uniform block `buf` at binding=0;
//   (3) qt_Matrix and qt_Opacity auto-populated by ShaderEffect framework;
//   (4) all uniform references use ubuf. prefix.
//
// Compile with:
//   /usr/lib/qt6/bin/qsb --glsl "330,400,410,420,430,440"
//       -o shaders/logomark.frag.qsb shaders/logomark.qs.frag

layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;

layout(std140, binding=0) uniform buf {
    mat4  qt_Matrix;          // auto-set by ShaderEffect
    float qt_Opacity;         // auto-set by ShaderEffect
    float u_time;
    float u_outerState;       // 0.0 = idle, 1.0 = active
    float u_innerState;       // 0.0 = idle, 1.0 = active
    float u_outerPulsePhase;  // sine phase for outer ring opacity pulse
    float u_innerPulsePhase;  // 180° offset from outer during dual-active
    vec2  u_resolution;
    vec4  u_cyan;
    vec4  u_amber;
} ubuf;

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
    float sweepAngle = mod(ubuf.u_time / period, 1.0) * 6.2831853 * direction;
    float delta      = angle - sweepAngle;
    // Wrap into [-π, π]
    delta = mod(delta + 3.14159265, 6.2831853) - 3.14159265;
    float halfArc    = radians(SWEEP_ARC_DEG * 0.5);
    return mix(1.0, SWEEP_GAIN, smoothstep(halfArc, 0.0, abs(delta)));
}

void main() {
    vec2 uv = qt_TexCoord0 - 0.5;

    // Stroke widens 2px → 4px during active state
    float outerStroke = mix(STROKE, STROKE * 2.0, ubuf.u_outerState);
    float innerStroke = mix(STROKE, STROKE * 2.0, ubuf.u_innerState);

    // Layer C: sub-pixel AA boundary jitter (~0.1 Hz, ±0.3px)
    float jitterOuter = sin(ubuf.u_time * 0.628 + 1.3) * sin(ubuf.u_time * 0.471 + 2.7)
                        * (0.3 / 240.0);
    float jitterInner = sin(ubuf.u_time * 0.628 + 3.9) * sin(ubuf.u_time * 0.471 + 5.1)
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
    float outerPulse = mix(1.0,
        0.7 + 0.3 * sin(ubuf.u_time * 2.618 + ubuf.u_outerPulsePhase),
        ubuf.u_outerState);
    float innerPulse = mix(1.0,
        0.7 + 0.3 * sin(ubuf.u_time * 2.618 + ubuf.u_innerPulsePhase),
        ubuf.u_innerState);

    // Base opacity: 30% idle → 85% active
    float outerOpacity = mix(IDLE_OPACITY, 0.85, ubuf.u_outerState);
    float innerOpacity = mix(IDLE_OPACITY, 0.85, ubuf.u_innerState);

    // Color: cyan at idle, amber at active
    vec4 outerColor = mix(ubuf.u_cyan, ubuf.u_amber, ubuf.u_outerState);
    vec4 innerColor = mix(ubuf.u_cyan, ubuf.u_amber, ubuf.u_innerState);

    // Ring contribution (premultiplied alpha)
    vec4 ring =
        outerMask * outerColor * outerOpacity * outerSweep * outerPulse +
        innerMask * innerColor * innerOpacity * innerSweep * innerPulse;

    // Additive glow
    float outerGlowR = mix(GLOW_IDLE, GLOW_ACTIVE, ubuf.u_outerState);
    float innerGlowR = mix(GLOW_IDLE, GLOW_ACTIVE, ubuf.u_innerState);
    float outerGlow  = exp(-abs(outerSdf) * OUTER_R / outerGlowR)
                       * outerOpacity * 0.30 * outerSweep;
    float innerGlow  = exp(-abs(innerSdf) * INNER_R / innerGlowR)
                       * innerOpacity * 0.30 * innerSweep;

    fragColor = clamp(ring + outerGlow * outerColor + innerGlow * innerColor,
                      0.0, 1.0) * ubuf.qt_Opacity;
}
