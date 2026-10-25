// Written by Save Module from output_deck.tox so git shows readable diffs. Edit this
// DAT inside output_deck in TouchDesigner, then press Save Module; edits here change nothing.

// Output deck framing: place the picture (input 0) on the output canvas, fade its edges into
// the background so there is no hard cut, and fill the rest. Input 1 is the picture blurred
// to cover the canvas, for the Blurred Picture background (black for the other backgrounds).

uniform vec4 uFit;    // fit (0 fit inside, 1 fill, 2 stretch, 3 native), zoom, position x, position y
uniform vec4 uEdge;   // soft edge (share of the picture's shorter side), shape (0 rectangle, 1 oval),
                      // blend (0 over, 1 add, 2 screen, 3 lighten), background (0 colour, 1 blurred, 2 mirrored, 3 transparent)
uniform vec4 uBack;   // background colour, picture in background
uniform vec4 uLimit;  // rendered size / requested size, so Native keeps its scale under a licence limit

layout(location = 0) out vec4 fragColor;

void main()
{
	vec2 canvas = uTDOutputInfo.res.zw;
	vec2 source = uTD2DInfos[0].res.zw;
	int fit = int(uFit.x + 0.5);

	// The picture's size on the canvas, then zoom; position moves its centre by half canvases.
	vec2 ratio = canvas / source;
	vec2 size = source * min(ratio.x, ratio.y);
	if (fit == 1) size = source * max(ratio.x, ratio.y);
	if (fit == 2) size = canvas;
	if (fit == 3) size = source * uLimit.x;
	size *= uFit.y;
	vec2 halfSize = 0.5 * size;
	vec2 centre = canvas * (0.5 + 0.5 * uFit.zw);
	vec2 p = gl_FragCoord.xy - centre;
	vec2 uv = p / size + 0.5;

	// Soft edge over `feather` pixels, at least one so a hard edge is still antialiased.
	float feather = max(uEdge.x * min(size.x, size.y), 1.0);
	float mask;
	if (int(uEdge.y + 0.5) == 1) {
		float d = (length(p / halfSize) - 1.0) * min(halfSize.x, halfSize.y);
		mask = 1.0 - smoothstep(-feather, 0.0, d);
	} else {
		vec2 lo = centre - halfSize;
		vec2 hi = centre + halfSize;
		vec4 inside = vec4(gl_FragCoord.xy - lo, hi - gl_FragCoord.xy);
		// A side on or past the canvas border has nothing to fade into: it stays sharp, so a
		// picture that fills the output is never darkened at the frame.
		inside = mix(inside, vec4(1e6), step(vec4(lo, -hi), vec4(0.5, 0.5, 0.5 - canvas)));
		vec4 s = smoothstep(0.0, feather, inside);
		mask = s.x * s.y * s.z * s.w;
	}

	int back = int(uEdge.w + 0.5);
	vec3 bg = uBack.rgb;
	float bgAlpha = 1.0;
	if (back == 1) bg = mix(uBack.rgb, texture(sTD2DInputs[1], vUV.st).rgb, uBack.a);
	if (back == 2) bg = mix(uBack.rgb, texture(sTD2DInputs[0], 1.0 - abs(mod(uv, 2.0) - 1.0)).rgb, uBack.a);
	if (back == 3) { bg = vec3(0.0); bgAlpha = 0.0; }

	// The picture is premultiplied; the edge fade scales colour and alpha together.
	vec4 pic = texture(sTD2DInputs[0], uv) * mask;
	int blend = int(uEdge.z + 0.5);
	vec3 col = pic.rgb + bg * (1.0 - pic.a);
	if (blend == 1) col = bg + pic.rgb;
	if (blend == 2) col = 1.0 - (1.0 - bg) * (1.0 - pic.rgb);
	if (blend == 3) col = max(bg, pic.rgb);
	float alpha = max(bgAlpha, pic.a);

	fragColor = TDOutputSwizzle(TDDither(vec4(col, alpha)));
}
