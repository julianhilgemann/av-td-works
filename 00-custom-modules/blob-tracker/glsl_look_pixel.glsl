// Written by Save Module from blob_tracker.tox so git shows readable diffs. Edit this
// DAT inside blob_tracker in TouchDesigner, then press Save Module; edits here change nothing.

// Final picture of the blob tracker: the background treatment, the effect inside the boxes,
// and the overlay (boxes, lines, trails) on top.
// Inputs: 0 = video, 1 = points texture (see glsl_overlay_pixel), 2 = overlay layer.

#define MAX_POINTS 128

uniform vec4 uBg;      // x = background (0 original, 1 mono, 2 threshold, 3 invert, 4 black),
                       // y = brightness, z = contrast, w = saturation
uniform vec4 uInside;  // x = inside effect (0 none, 1 original, 2 invert, 3 threshold, 4 tint,
                       // 5 pixelate, 6 zoom), y = amount, z = pixel size px, w = zoom
uniform vec4 uLevels;  // x = background threshold, y = inside threshold
uniform vec4 uTint;    // Colors page: tint for the Tint inside effect

layout(location = 0) out vec4 fragColor;

float luma(vec3 c)
{
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 grade(vec3 c)
{
	c = mix(vec3(luma(c)), c, uBg.w);
	c = (c - 0.5) * uBg.z + 0.5;
	return max(c * uBg.y, 0.0);
}

void main()
{
	vec2 res = uTD2DInfos[0].res.zw;
	vec2 uv = vUV.st;
	vec2 p = uv * res;
	vec3 src = texture(sTD2DInputs[0], uv).rgb;

	int bg = int(uBg.x + 0.5);
	vec3 col = src;
	if (bg == 1) col = vec3(luma(src));
	else if (bg == 2) col = vec3(step(uLevels.x, luma(src)));
	else if (bg == 3) col = 1.0 - src;
	else if (bg == 4) col = vec3(0.0);
	col = grade(col);

	int effect = int(uInside.x + 0.5);
	if (effect > 0)
	{
		float slots = uTD2DInfos[1].res.z;
		for (int i = 0; i < MAX_POINTS; i++)
		{
			if (float(i) >= slots) break;
			if (texelFetch(sTD2DInputs[1], ivec2(i, 1), 0).z < 0.5) break;
			vec4 box = texelFetch(sTD2DInputs[1], ivec2(i, 0), 0);
			vec2 c = box.xy * res;
			vec2 hs = box.zw * res * 0.5;
			if (any(greaterThan(abs(p - c), hs))) continue;
			vec3 inner = src;
			if (effect == 2) inner = 1.0 - col;
			else if (effect == 3) inner = vec3(step(uLevels.y, luma(src)));
			else if (effect == 4) inner = luma(src) * uTint.rgb * 1.5;
			else if (effect == 5)
			{
				float s = max(uInside.z, 1.0);
				inner = texture(sTD2DInputs[0], (floor(p / s) + 0.5) * s / res).rgb;
			}
			else if (effect == 6)
			{
				inner = texture(sTD2DInputs[0], (c + (p - c) / max(uInside.w, 0.01)) / res).rgb;
			}
			col = mix(col, inner, uInside.y);
			break;  // the first box that holds the pixel decides
		}
	}

	vec4 over = texture(sTD2DInputs[2], uv);
	fragColor = TDOutputSwizzle(vec4(over.rgb + col * (1.0 - over.a), 1.0));
}
