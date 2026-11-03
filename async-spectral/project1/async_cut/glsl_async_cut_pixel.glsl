// async_cut: freezes the picture's line at the cut and streaks it across one side.
// Input 0: the video. Input 1: this shader's own previous frame (feedback).
uniform vec4 uCut;    // x progress 0-1 (0 = cut at the far edge, 1 = whole picture streaked), y edge softness (0-1), z direction (0 right, 1 left, 2 up, 3 down)
uniform vec4 uSmear;  // x smoothing 0-1 (temporal lag), y calm (0-1, extra lag toward the far edge), z soften (pixels across the streaks), w sample depth (pixels behind the cut averaged)

layout(location = 0) out vec4 fragColor;

int dir;

// Image uv <-> (along, across): along runs from the cut into the streaks.
vec2 toAxis(vec2 uv) {
    if (dir == 0) return uv;
    if (dir == 1) return vec2(1.0 - uv.x, uv.y);
    if (dir == 2) return vec2(uv.y, uv.x);
    return vec2(1.0 - uv.y, uv.x);
}
vec2 toUV(vec2 ax) {
    if (dir == 0) return ax;
    if (dir == 1) return vec2(1.0 - ax.x, ax.y);
    if (dir == 2) return vec2(ax.y, ax.x);
    return vec2(ax.y, 1.0 - ax.x);
}

void main() {
    dir = int(uCut.z + 0.5);
    vec2 res = uTD2DInfos[0].res.zw;
    vec2 axRes = dir < 2 ? res : res.yx;          // pixels along, across
    vec2 ax = toAxis(vUV.st);
    float cut = 1.0 - uCut.x;

    vec4 video = texture(sTD2DInputs[0], vUV.st);
    float edge = max(uCut.y, 0.5 / axRes.x);
    float inSmear = smoothstep(cut, cut + edge, ax.x);
    if (inSmear <= 0.0) { fragColor = TDOutputSwizzle(video); return; }

    // The line at the cut: averaged a few pixels behind it and softened across,
    // sampled bilinearly so a cut between pixels moves without stepping.
    vec4 line = vec4(0.0);
    float wsum = 0.0;
    for (int i = 0; i < 4; i++) {
        float a = cut - (float(i) + 0.5) * max(uSmear.w, 0.0) / 4.0 / axRes.x;
        for (int j = -3; j <= 3; j++) {
            float w = exp(-float(j * j) / 4.5);
            float b = ax.y + float(j) * uSmear.z / 3.0 / axRes.y;
            line += w * texture(sTD2DInputs[0], toUV(vec2(clamp(a, 0.0, 1.0), b)));
            wsum += w;
        }
    }
    line /= wsum;

    // Streaks lag behind the line in time, more so the further they are from the cut,
    // so the far side settles calmly while the cut stays crisp. No advection: it steps.
    vec4 prev = texture(sTD2DInputs[1], vUV.st);
    float dist = clamp((ax.x - cut) / max(1.0 - cut, 1e-4), 0.0, 1.0);
    float lag = clamp(uSmear.x, 0.0, 0.99);
    lag = clamp(mix(lag, 1.0 - (1.0 - lag) * 0.15, uSmear.y * dist), 0.0, 0.995);
    vec4 streak = mix(line, prev, lag);

    fragColor = TDOutputSwizzle(mix(video, streak, inSmear));
}
