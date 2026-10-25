// Written by Save Module from crt_filter.tox so git shows readable diffs. Edit this
// DAT inside crt_filter in TouchDesigner, then press Save Module; edits here change nothing.

// CRT filter, tube stage: curved glass with rounded corners and glare, convergence error,
// scanlines whose beam widens on bright colours (horizontal or vertical), interlace and a
// hum bar, a phosphor mask, halation and diffusion, grading, monochrome phosphors and
// phosphor persistence. Input 0: the signal stage. Input 1: the signal blurred (glow source).
// Input 2: this stage's previous output (persistence feedback).

uniform vec4 uGeom;   // x curvature, y corner radius, z vignette, w screen size
uniform vec4 uScan;   // x scanline count, y scanline depth, z beam bloom, w convergence (px)
uniform vec4 uMask;   // x mask (0 off, 1 shadow, 2 aperture grille, 3 slot), y pitch (px), z depth, w brightness
uniform vec4 uTube;   // x halation, y black level, z saturation, w field (frame parity)
uniform vec4 uScan2;  // x scan direction (0 horizontal, 1 vertical), y interlace, z hum bar, w hum phase 0-1
uniform vec4 uMask2;  // x dot softness, y mask follows glass, z glare, w edge softness
uniform vec4 uGlow;   // x halation threshold, y diffusion, z persistence, w phosphor (0 colour, 1 green, 2 amber, 3 white)
uniform vec4 uGrade;  // x contrast, y gamma
uniform vec4 uHalo;   // halation tint
uniform vec4 uBezel;  // colour outside the tube
uniform vec4 uTint;   // white point

layout(location = 0) out vec4 fragColor;

const vec3 LUMA = vec3(0.299, 0.587, 0.114);

// Phosphor pattern at pixel p; each channel lights a third of the pattern.
vec3 phosphorMask(vec2 p, float pitch, float type, float soft) {
    float inner = mix(0.5, 0.05, soft);
    if (type < 1.5) {
        // Shadow mask: round R, G, B dots; every other row shifted by half a triad.
        vec2 g = p / pitch;
        g.x += mod(floor(g.y), 2.0) * 1.5;
        float c = mod(floor(g.x), 3.0);
        float dotShape = 1.0 - smoothstep(inner * 0.6, 0.6, length(fract(g) - 0.5));
        return vec3(c < 0.5, c > 0.5 && c < 1.5, c > 1.5) * dotShape;
    }
    float c = mod(floor(p.x / pitch), 3.0);
    float across = abs(fract(p.x / pitch) - 0.5);
    vec3 stripe = vec3(c < 0.5, c > 0.5 && c < 1.5, c > 1.5) * (1.0 - smoothstep(inner, 0.55, across));
    if (type < 2.5) {
        return stripe;  // aperture grille: continuous vertical stripes
    }
    // Slot mask: stripes broken into slots, staggered every other triad.
    float slotY = fract(p.y / (pitch * 3.0) + 0.5 * mod(floor(p.x / (pitch * 3.0)), 2.0));
    float gap = mix(0.12, 0.3, soft);
    return stripe * smoothstep(0.0, gap, slotY) * smoothstep(1.0, 1.0 - gap, slotY);
}

vec3 phosphorColor(float mode) {
    return mode < 1.5 ? vec3(0.25, 1.0, 0.4) : mode < 2.5 ? vec3(1.0, 0.62, 0.12) : vec3(0.92, 0.95, 1.0);
}

void main() {
    vec2 res = uTD2DInfos[0].res.zw;
    vec2 asp = vec2(res.x / res.y, 1.0);
    bool vert = uScan2.x > 0.5;
    bool mono = uGlow.w > 0.5;

    // Curved glass: the picture bends outward toward the edges.
    vec2 c = (vUV.st * 2.0 - 1.0) / max(uGeom.w, 0.1);
    c *= 1.0 + uGeom.x * 0.3 * vec2(c.y * c.y, c.x * c.x);
    vec2 cuv = c * 0.5 + 0.5;

    // Rounded screen edge (aspect-correct), vignette, and a glare spot on the glass.
    vec2 q = abs(c) * asp - (asp - uGeom.y);
    float edge = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - uGeom.y;
    float soft = 0.004 + 0.06 * uMask2.w;
    float screen = 1.0 - smoothstep(-soft, soft, edge);
    vec2 v = clamp(cuv * (1.0 - cuv), 0.0, 1.0);
    float vig = mix(1.0, pow(16.0 * v.x * v.y, 0.3), uGeom.z);
    vec2 gp = (c - vec2(-0.45, 0.5)) * vec2(1.0, 1.8);
    float glare = uMask2.z * 0.12 * exp(-dot(gp, gp) * 3.0);

    // Scanlines in scan space: a.x runs along a line, a.y across lines. Each line shows one
    // row of the picture; red and blue land slightly off along the line.
    vec2 a = vert ? cuv.yx : cuv;
    float lines = max(uScan.x, 16.0);
    float ly = a.y * lines;
    float f = fract(ly) - 0.5;
    float row = (floor(ly) + 0.5) / lines;
    float conv = uScan.w / (vert ? res.y : res.x);
    vec2 sR = vec2(a.x + conv, row);
    vec2 sG = vec2(a.x, row);
    vec2 sB = vec2(a.x - conv, row);
    vec3 src = vec3(texture(sTD2DInputs[0], vert ? sR.yx : sR).r,
                    texture(sTD2DInputs[0], vert ? sG.yx : sG).g,
                    texture(sTD2DInputs[0], vert ? sB.yx : sB).b);
    if (mono) {
        src = vec3(dot(src, LUMA));
    }
    // Beam profile: brighter channels draw wider lines; normalised so brightness holds.
    vec3 sigma = 0.17 + 0.25 * uScan.z * clamp(src, 0.0, 1.0);
    vec3 beam = exp(-f * f / (2.0 * sigma * sigma)) / min(sigma * 2.4, vec3(1.0));
    vec3 col = src * mix(vec3(1.0), beam, uScan.y);

    // Interlace: on alternate frames every other line is dimmer. Hum bar: a soft rolling band.
    col *= 1.0 - uScan2.y * 0.6 * abs(mod(floor(ly), 2.0) - uTube.w);
    float hum = pow(0.5 + 0.5 * sin(6.2831853 * (cuv.y - uScan2.w)), 6.0);
    col *= 1.0 + uScan2.z * (hum - 0.15) * 0.6;

    // Phosphor mask, flat on the output or bent with the glass. A monochrome tube shows the
    // dot pattern without colour.
    if (uMask.x > 0.5) {
        vec2 mp = uMask2.y > 0.5 ? cuv * res : gl_FragCoord.xy;
        if (vert) {
            mp = mp.yx;
        }
        vec3 m = phosphorMask(mp, max(uMask.y, 1.0), uMask.x, uMask2.x);
        m = mono ? vec3(m.r + m.g + m.b) : 3.0 * m;
        col *= mix(vec3(1.0), m, uMask.z);
    }

    // Halation (thresholded, tinted, squared so highlights glow) and untinted glass diffusion.
    vec3 glow = texture(sTD2DInputs[1], cuv).rgb;
    if (mono) {
        glow = vec3(dot(glow, LUMA));
    }
    vec3 hot = max(glow - uGlow.x, 0.0) / max(1.0 - uGlow.x, 0.05);
    col += hot * hot * uHalo.rgb * uTube.x + glow * uGlow.y * 0.5;

    // Grade: brightness, contrast, gamma, saturation, white point, phosphor colour, black level.
    col *= uMask.w;
    col = max((col - 0.5) * uGrade.x + 0.5, 0.0);
    col = pow(col, vec3(1.0 / max(uGrade.y, 0.05)));
    col = mix(vec3(dot(col, LUMA)), col, uTube.z) * uTint.rgb;
    if (mono) {
        col = dot(col, LUMA) * phosphorColor(uGlow.w);
    }
    col = (uTube.y + col * (1.0 - uTube.y)) * vig;

    // Persistence: the phosphor keeps glowing as the beam moves on (max, so it never builds up).
    vec3 lit = max(col + vec3(0.9, 0.95, 1.0) * glare, texture(sTD2DInputs[2], vUV.st).rgb * uGlow.z);
    fragColor = TDOutputSwizzle(vec4(mix(uBezel.rgb, lit, screen), 1.0));
}
