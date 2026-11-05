// Written by Save Module from blob_tracker.tox so git shows readable diffs. Edit this
// DAT inside blob_tracker in TouchDesigner, then press Save Module; edits here change nothing.

// Detection mask of the blob tracker, at the detection size.
// R = 1 where a pixel counts toward a blob, G = luminance (corner detection reads it),
// B = the raw detection value before the threshold (shown by Show Mask).
// Inputs: 0 = the blurred small frame, 1 = the same one frame earlier (for motion).

uniform vec4 uDetect;  // x = source (0 bright, 1 dark, 2 motion, 3 edges), y = threshold, z = gain

layout(location = 0) out vec4 fragColor;

float luma(vec3 c)
{
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float lumaAt(vec2 uv)
{
	return luma(texture(sTD2DInputs[0], uv).rgb);
}

void main()
{
	vec2 uv = vUV.st;
	float l = lumaAt(uv);
	int source = int(uDetect.x + 0.5);
	float value = l;
	if (source == 1)
	{
		value = 1.0 - l;
	}
	else if (source == 2)
	{
		value = abs(l - luma(texture(sTD2DInputs[1], uv).rgb)) * uDetect.z;
	}
	else if (source == 3)
	{
		vec2 px = uTD2DInfos[0].res.xy;
		float gx = lumaAt(uv + vec2(px.x, 0.0)) - lumaAt(uv - vec2(px.x, 0.0));
		float gy = lumaAt(uv + vec2(0.0, px.y)) - lumaAt(uv - vec2(0.0, px.y));
		value = length(vec2(gx, gy)) * uDetect.z;
	}
	float inside = step(uDetect.y, value);
	fragColor = TDOutputSwizzle(vec4(inside, l, clamp(value, 0.0, 1.0), 1.0));
}
