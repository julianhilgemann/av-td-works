// Liquid paint: single-pass rotational self-advection ("computational flockarooid dynamics").
// Ported to TouchDesigner from Buffer A of "single pass CFD" by Florian Berger (flockaroo),
// Shadertoy 2016, CC BY-NC-SA 3.0, https://www.shadertoy.com/view/MdKXRy
// Changes from the original: TD samplers and resolutions, right mouse resets instead of
// iFrame / the I key, the centre "motor" is removed so only the brush drives the flow.
//
// Inputs: 0 = canvas (feedback with the brush composited on top)
//         1 = per-pixel noise (stochastic sampling angle)
//         2 = reset image
// The canvas RG channels double as the velocity field: the paint colour IS the flow.

#define RotNum 5   // rotation samples per scale; the fast path below needs it odd

#define Res  (uTD2DInfos[0].res.zw)
#define Res1 (uTD2DInfos[1].res.zw)

uniform float uRMB;    // right mouse button: > 0.5 resets the canvas to input 2
uniform float uFrame;  // frame counter: walks the noise lookup that picks this frame's angle

layout(location = 0) out vec4 fragColor;

const float ang = 2.0 * 3.1415926535 / float(RotNum);
const mat2 m = mat2(cos(ang), sin(ang), -sin(ang), cos(ang));

vec4 randS(vec2 uv)
{
    return texture(sTD2DInputs[1], uv * Res / Res1) - vec4(0.5);
}

// Mean rotation of the field around pos, sampled at RotNum points on a circle of radius |b|.
float getRot(vec2 pos, vec2 b)
{
    vec2 p = b;
    float rot = 0.0;
    for (int i = 0; i < RotNum; i++)
    {
        rot += dot(texture(sTD2DInputs[0], fract((pos + p) / Res)).xy - vec2(0.5), p.yx * vec2(1.0, -1.0));
        p = m * p;
    }
    return rot / float(RotNum) / dot(b, b);
}

void main()
{
    vec2 pos = gl_FragCoord.xy;
    float rnd = randS(vec2(uFrame / Res.x, 0.5 / Res1.y)).x;

    vec2 b = vec2(cos(ang * rnd), sin(ang * rnd));
    vec2 v = vec2(0.0);
    float bbMax = 0.7 * Res.y;
    bbMax *= bbMax;
    for (int l = 0; l < 20; l++)   // one octave of scale per pass: b doubles until it spans the canvas
    {
        if (dot(b, b) > bbMax) break;
        vec2 p = b;
        for (int i = 0; i < RotNum; i++)
        {
            v += p.yx * getRot(pos + p, b);
            p = m * p;
        }
        b *= 2.0;
    }

    vec4 c = texture(sTD2DInputs[0], fract((pos + v * vec2(-1.0, 1.0) * 2.0) / Res));
    if (uRMB > 0.5) c = texture(sTD2DInputs[2], vUV.st);
    // Opaque canvas: the brush composites over it (composite input 0) instead of under it.
    fragColor = TDOutputSwizzle(vec4(c.rgb, 1.0));
}
