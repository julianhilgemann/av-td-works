// Written by Save Module from crt_filter.tox so git shows readable diffs. Edit this
// DAT inside crt_filter in TouchDesigner, then press Save Module; edits here change nothing.

// CRT filter, analog signal stage: line jitter, a horizontal wave, a rolling tracking-noise
// band, VHS head-switching tear, vertical roll, optional pixelation, smear in which colour
// (I, Q) bleeds further and later than brightness (Y), a ghost echo, dropouts, grain,
// colour noise and flicker. With a vertical scan direction everything runs along columns.
// Input 0: the source image.

uniform vec4 uSig;   // x smear 0-1, y ghost 0-1, z line jitter (px), w tracking band 0-1
uniform vec4 uTime;  // x time (s, wraps every 600 s), y frame (wrapped), z grain, w scanline count
uniform vec4 uSig2;  // x source columns (0 = off), y chroma delay (px), z ghost offset (px), w wave (px)
uniform vec4 uSig3;  // x wave cycles per picture, y head switching 0-1, z tracking speed, w tracking height
uniform vec4 uSig4;  // x vertical roll (screens/s), y dropouts 0-1, z colour noise, w flicker 0-1
uniform vec4 uDir;   // x scan direction (0 horizontal, 1 vertical)

layout(location = 0) out vec4 fragColor;

const mat3 RGB2YIQ = mat3(0.299, 0.596, 0.211, 0.587, -0.274, -0.523, 0.114, -0.322, 0.312);
const mat3 YIQ2RGB = mat3(1.0, 1.0, 1.0, 0.956, -0.272, -1.106, 0.621, -0.647, 1.703);

bool vert;

float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Sample the source in scan space (x along a line, y across lines), optionally pixelated.
vec3 source(vec2 s) {
    if (uSig2.x >= 2.0) {
        s.x = (floor(s.x * uSig2.x) + 0.5) / uSig2.x;
    }
    return texture(sTD2DInputs[0], vert ? s.yx : s).rgb;
}

void main() {
    vert = uDir.x > 0.5;
    vec2 uv = vert ? vUV.st.yx : vUV.st;
    vec2 px = vert ? uTD2DInfos[0].res.yx : uTD2DInfos[0].res.xy;
    float t = uTime.x;
    float frame = uTime.y;

    // Vertical roll: the picture slides through a dark blanking bar.
    float y = fract(uv.y + t * uSig4.x);
    float blank = abs(uSig4.x) > 1e-4 ? smoothstep(0.0, 0.025, y) * smoothstep(1.0, 0.975, y) : 1.0;
    float line = floor(y * max(uTime.w, 1.0));

    // Tracking band rolling down; head-switching tear along the bottom; wave; line jitter.
    float band = uSig.w * exp(-pow((y - (1.0 - fract(t * uSig3.z))) / max(uSig3.w, 0.002), 2.0));
    float tear = hash(vec2(line, frame)) - 0.5;
    float head = uSig3.y * pow(smoothstep(0.06, 0.0, y), 1.5);
    float wave = uSig2.w * sin(6.2831853 * (y * uSig3.x + t * 0.7));
    float shift = tear * (uSig.z + band * 40.0) + wave + head * (30.0 + 40.0 * tear);
    vec2 s = vec2(uv.x + shift * px.x, y);

    // Smear: an exponentially fading trail to the left; colour bleeds further, and later.
    float decayY = 0.6 * uSig.x;
    float decayC = mix(0.35, 0.9, uSig.x);
    float wY = 1.0, wC = 1.0, sumY = 0.0, sumC = 0.0, accY = 0.0;
    vec2 accC = vec2(0.0);
    for (int i = 0; i < 10; i++) {
        float o = float(i) * 1.5 * px.x;
        accY += (RGB2YIQ * source(s - vec2(o, 0.0))).x * wY;
        accC += (RGB2YIQ * source(s - vec2(o + uSig2.y * px.x, 0.0))).yz * wC;
        sumY += wY; wY *= decayY;
        sumC += wC; wC *= decayC;
    }
    vec3 col = YIQ2RGB * vec3(accY / sumY, accC / sumC);

    // Ghost echo.
    col += uSig.y * 0.5 * source(s - vec2(uSig2.z * px.x, 0.0));

    // Dropouts: white streaks along a few random lines.
    float x0 = hash(vec2(line, frame + 5.0));
    float len = 0.03 + 0.15 * hash(vec2(line + 3.0, frame));
    float dropLine = step(hash(vec2(line * 1.7, frame + 11.0)), uSig4.y * 0.03);
    col = mix(col, vec3(0.9), dropLine * step(x0, uv.x) * smoothstep(x0 + len, x0, uv.x));

    // Grain, colour noise, the tracking band's speckle, flicker and the blanking bar.
    vec2 np = vUV.st * uTD2DInfos[0].res.zw;
    float n = hash(np + vec2(frame * 7.13, frame * 3.71));
    col += (n - 0.5) * uTime.z * 0.12;
    col += (vec3(hash(np + frame * 1.31), hash(np + frame * 2.17 + 5.0), hash(np + frame * 3.07 + 9.0)) - 0.5) * uSig4.z * 0.15;
    float speck = step(0.75, hash(vec2(floor(uv.x * 400.0), line + frame)));
    col = mix(col, vec3(n), band * speck * 0.8);
    col *= (1.0 + uSig4.w * (hash(vec2(frame, 1.0)) - 0.5) * 0.4) * blank;
    fragColor = TDOutputSwizzle(vec4(max(col, 0.0), 1.0));
}
