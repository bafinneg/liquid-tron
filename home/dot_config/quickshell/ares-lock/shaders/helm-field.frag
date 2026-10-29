#version 440
// Ares helm, pass 1 (FEAT-ares-sentinel-lock): rebuild a smooth, high-resolution silhouette from the eikon.
// Compile: /usr/lib/qt6/bin/qsb --qt6 -o helm-field.frag.qsb helm-field.frag
// Rendered into a small offscreen texture, one texel per LED (96*density square). Each texel blends the four
// pose tiles and reconstructs coverage with a normalised Gaussian over the 4x4 nearest source dots, which turns
// the 96x96 staircase into rounded contours while one-dot lines and single dots survive. Pass 2 (helm.frag)
// thresholds this field into LEDs and adds all the effects.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(binding = 1) uniform sampler2D atlas;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 frames;      // four neighbouring atlas tiles along the pose track
    vec4 weights;     // their blend weights (sum 1)
    float cols;       // atlas columns
    float rows;       // atlas rows
};

const float N = 96.0;
const float SIGMA2 = 2.0 * 0.36 * 0.36; // Gaussian 2*sigma^2, sigma = 0.36 source dots (keeps one-dot gaps)

float tileSample(float idx, vec2 cell) {
    if (cell.x < 0.0 || cell.y < 0.0 || cell.x >= N || cell.y >= N) return 0.0;
    vec2 t = vec2(mod(idx, cols), floor(idx / cols));
    vec2 uv = (t * N + cell + 0.5) / vec2(cols * N, rows * N);
    return texture(atlas, uv).r;
}

float dotAt(vec2 cell) {
    return tileSample(frames.x, cell) * weights.x + tileSample(frames.y, cell) * weights.y
         + tileSample(frames.z, cell) * weights.z + tileSample(frames.w, cell) * weights.w;
}

void main() {
    vec2 q = qt_TexCoord0 * N;                // texel centre in source-dot units
    vec2 base = floor(q - 0.5) - 1.0;
    float acc = 0.0, wsum = 0.0;
    for (int j = 0; j < 4; j++) {
        for (int i = 0; i < 4; i++) {
            vec2 c = base + vec2(float(i), float(j));
            vec2 d = q - (c + 0.5);
            float w = exp(-dot(d, d) / SIGMA2);
            acc += w * dotAt(c);
            wsum += w;
        }
    }
    float v = acc / max(wsum, 1e-5);
    fragColor = vec4(v, v, v, 1.0) * qt_Opacity;
}
