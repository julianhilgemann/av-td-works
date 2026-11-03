// glsl_beams: one output pixel per frequency bin. Each bin walks its strip of the picture
// along the beam direction and keeps what stays the same from sample to sample: the streaked
// beams. rgb = the beam colour, a = how much of the strip has turned into beam (0-1).
uniform vec4 uBeam;   // x beam direction (0 vertical beams, 1 horizontal), y coherence sharpness

layout(location = 0) out vec4 fragColor;

void main() {
    bool vertical = uBeam.x < 0.5;
    float bin = uTDOutputInfo.res.x;               // bin width in uv
    vec3 acc = vec3(0.0);
    float wsum = 0.0;
    const int STEPS = 96;
    for (int i = 0; i < STEPS; i++) {
        float t = (float(i) + 0.5) / float(STEPS);
        for (int j = -1; j <= 1; j++) {
            float u = vUV.s + float(j) * bin / 3.0;
            vec2 uv = vertical ? vec2(u, t) : vec2(t, u);
            vec2 step = vertical ? vec2(0.0, 1.0 / float(STEPS)) : vec2(1.0 / float(STEPS), 0.0);
            vec3 c = texture(sTD2DInputs[0], uv).rgb;
            vec3 n = texture(sTD2DInputs[0], uv + step).rgb;
            float w = exp(-length(c - n) * uBeam.y);
            acc += w * c;
            wsum += w;
        }
    }
    vec3 beam = acc / max(wsum, 1e-4);
    float coverage = wsum / float(STEPS * 3);
    fragColor = TDOutputSwizzle(vec4(beam, coverage));
}
