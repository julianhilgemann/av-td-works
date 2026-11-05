// Written by Save Module from blob_tracker.tox so git shows readable diffs. Edit this
// DAT inside blob_tracker in TouchDesigner, then press Save Module; edits here change nothing.

// Boxes, crosshairs and link lines of the tracked points on a transparent layer, with trails.
// Input 0 = points texture from choptotop_points, one column per slot:
//   row 0 = u v w h (box centre and size, 0..1), row 1 = id age active conf, row 2 = x1 y1 x2 y2
// Input 1 = this layer one frame earlier (feedback_trails), faded by the trail amount.
// Live points and links are packed first, so both loops stop at the first empty slot.

#define MAX_POINTS 128
#define MAX_LINKS 256

uniform vec4 uBox;        // x = style (0 outline, 1 corners, 2 dashed, 3 filled, 4 none), y = width px,
                          // z = corner length (share of the side), w = fill alpha
uniform vec4 uMarks;      // x = crosshair half-size px (0 = none), y = centre dot radius px,
                          // z = dash length px, w = trail amount (0 = none)
uniform vec4 uLine;       // x = width px, y = fade with length (0/1), z = longest link (frame heights),
                          // w = dash length px (0 = solid)
uniform vec4 uBoxColor;   // Colors page: rgb + alpha
uniform vec4 uLineColor;  // Colors page: rgb + alpha

layout(location = 0) out vec4 fragColor;

// Coverage of a band of half-width hw around distance d, anti-aliased over one pixel.
float band(float d, float hw)
{
	return 1.0 - smoothstep(hw - 0.5, hw + 0.5, d);
}

float segmentDistance(vec2 p, vec2 a, vec2 b, out float along)
{
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
	along = t * length(ab);
	return length(p - (a + ab * t));
}

void main()
{
	vec2 res = uTDOutputInfo.res.zw;
	vec2 p = gl_FragCoord.xy;
	int style = int(uBox.x + 0.5);
	float hw = uBox.y * 0.5;
	float boxA = 0.0;
	float slots = uTD2DInfos[0].res.z;

	for (int i = 0; i < MAX_POINTS; i++)
	{
		if (float(i) >= slots) break;
		if (texelFetch(sTD2DInputs[0], ivec2(i, 1), 0).z < 0.5) break;
		vec4 box = texelFetch(sTD2DInputs[0], ivec2(i, 0), 0);
		vec2 c = box.xy * res;
		vec2 hs = box.zw * res * 0.5;
		vec2 d = p - c;
		vec2 ad = abs(d);
		float reach = max(max(hs.x, hs.y), uMarks.x) + hw + 2.0;
		if (ad.x > reach || ad.y > reach) continue;

		if (style < 4)
		{
			vec2 q = ad - hs;
			float edge = max(q.x, q.y);  // <0 inside, 0 on the outline
			float ring = band(abs(edge), hw);
			if (style == 1)
			{
				vec2 len = hs * 2.0 * uBox.z;
				ring *= step(hs.x - len.x, ad.x) * step(hs.y - len.y, ad.y);
			}
			else if (style == 2)
			{
				float run = (q.x > q.y) ? d.y + hs.y : d.x + hs.x;
				ring *= step(0.5, fract(run / max(uMarks.z * 2.0, 1.0)));
			}
			else if (style == 3)
			{
				ring = max(ring, uBox.w * step(edge, 0.0));
			}
			boxA = max(boxA, ring);
		}
		if (uMarks.x > 0.0)
		{
			float cross = max(band(ad.x, hw) * step(ad.y, uMarks.x), band(ad.y, hw) * step(ad.x, uMarks.x));
			boxA = max(boxA, cross);
		}
		if (uMarks.y > 0.0)
		{
			boxA = max(boxA, band(length(d), uMarks.y));
		}
	}

	float lineA = 0.0;
	float lhw = uLine.x * 0.5;
	for (int k = 0; k < MAX_LINKS; k++)
	{
		if (float(k) >= slots) break;
		vec4 seg = texelFetch(sTD2DInputs[0], ivec2(k, 2), 0);
		if (seg.x < 0.0) break;
		vec2 a = seg.xy * res;
		vec2 b = seg.zw * res;
		if (p.x < min(a.x, b.x) - lhw - 1.0 || p.x > max(a.x, b.x) + lhw + 1.0 ||
			p.y < min(a.y, b.y) - lhw - 1.0 || p.y > max(a.y, b.y) + lhw + 1.0) continue;
		float along;
		float cover = band(segmentDistance(p, a, b, along), lhw);
		if (uLine.w > 0.0) cover *= step(0.5, fract(along / (uLine.w * 2.0)));
		if (uLine.y > 0.5) cover *= clamp(1.0 - length(b - a) / max(uLine.z * res.y, 1.0), 0.0, 1.0);
		lineA = max(lineA, cover);
	}

	boxA *= uBoxColor.a;
	lineA *= uLineColor.a;
	vec4 layer = vec4(uBoxColor.rgb * boxA + uLineColor.rgb * lineA * (1.0 - boxA),
		boxA + lineA * (1.0 - boxA));
	vec4 trail = texture(sTD2DInputs[1], vUV.st) * uMarks.w;
	fragColor = TDOutputSwizzle(layer + trail * (1.0 - layer.a));
}
