// The Slug method (Eric Lengyel, JCGT 2017) for the glyph data of the font library (font/slug.odin has the layout), for the Direct3D 11 backend of Karl2D: a version of the reference
// pixel shader, which is MIT licensed, Copyright 2017 by Eric Lengyel, with the data read from one float texture.
cbuffer constants : register(b0) {
	float4x4 view_projection;
	float4 text_params;          // x: the exponent of the coverage (1: as it is, under 1: heavier text)
}

struct vs_in {
	float3 position : position;
	float2 texcoord : texcoord;
	float4 color    : color;
};

struct vs_out {
	float4 position : SV_POSITION;
	float2 em : texcoord;
	nointerpolation float4 color : color;
};

Texture2D<float4> glyph_data : register(t1);
SamplerState glyph_sampler : register(s1);          // Karl2D wants a sampler for every texture, the shader only fetches

float4 texel(int index)
{
	return glyph_data.Load(int3(index & 4095, index >> 12, 0));
}

vs_out vs_main(vs_in input)
{
	vs_out output;
	output.position = mul(view_projection, float4(input.position, 1.0f));
	output.em = input.texcoord;
	output.color = input.color;
	return output;
}

uint calc_root_code(float y1, float y2, float y3)
{
	uint i1 = asuint(y1) >> 31U;
	uint i2 = asuint(y2) >> 30U;
	uint i3 = asuint(y3) >> 29U;
	uint shift = (i2 & 2U) | (i1 & ~2U);
	shift = (i3 & 4U) | (shift & ~4U);
	return ((0x2E74U >> shift) & 0x0101U);
}

float2 solve_horiz(float4 p12, float2 p3)
{
	float2 a = p12.xy - p12.zw * 2.0 + p3;
	float2 b = p12.xy - p12.zw;
	float ra = 1.0 / a.y;
	float rb = 0.5 / b.y;
	float d = sqrt(max(b.y * b.y - a.y * p12.y, 0.0));
	float t1 = (b.y - d) * ra;
	float t2 = (b.y + d) * ra;
	if (abs(a.y) < 1.0 / 65536.0) t1 = t2 = p12.y * rb;
	return float2((a.x * t1 - b.x * 2.0) * t1 + p12.x, (a.x * t2 - b.x * 2.0) * t2 + p12.x);
}

float2 solve_vert(float4 p12, float2 p3)
{
	float2 a = p12.xy - p12.zw * 2.0 + p3;
	float2 b = p12.xy - p12.zw;
	float ra = 1.0 / a.x;
	float rb = 0.5 / b.x;
	float d = sqrt(max(b.x * b.x - a.x * p12.x, 0.0));
	float t1 = (b.x - d) * ra;
	float t2 = (b.x + d) * ra;
	if (abs(a.x) < 1.0 / 65536.0) t1 = t2 = p12.x * rb;
	return float2((a.y * t1 - b.y * 2.0) * t1 + p12.y, (a.y * t2 - b.y * 2.0) * t2 + p12.y);
}

float slug_coverage(int slot, float2 render_coord, float2 pixels_per_em)
{
	float4 info = texel(slot * 2);
	float4 transform = texel(slot * 2 + 1);
	int start = int(info.x);
	int2 band_max = int2(int(info.y), int(info.z));
	int2 band_index = clamp(int2(render_coord * transform.xy + transform.zw), int2(0, 0), band_max);

	float xcov = 0.0;
	float xwgt = 0.0;
	float4 hband = texel(start + band_index.y);
	int hcount = int(hband.x);
	int hlist = int(hband.y);
	[loop] for (int k = 0; k < hcount; k++)
	{
		int curve = int(texel(hlist + k).x);
		float4 p12 = texel(curve) - float4(render_coord, render_coord);
		float2 p3 = texel(curve + 1).xy - render_coord;
		if (max(max(p12.x, p12.z), p3.x) * pixels_per_em.x < -0.5) break;
		uint code = calc_root_code(p12.y, p12.w, p3.y);
		if (code != 0U)
		{
			float2 r = solve_horiz(p12, p3) * pixels_per_em.x;
			if ((code & 1U) != 0U)
			{
				xcov += saturate(r.x + 0.5);
				xwgt = max(xwgt, saturate(1.0 - abs(r.x) * 2.0));
			}
			if (code > 1U)
			{
				xcov -= saturate(r.y + 0.5);
				xwgt = max(xwgt, saturate(1.0 - abs(r.y) * 2.0));
			}
		}
	}

	float ycov = 0.0;
	float ywgt = 0.0;
	float4 vband = texel(start + band_max.y + 1 + band_index.x);
	int vcount = int(vband.x);
	int vlist = int(vband.y);
	[loop] for (int j = 0; j < vcount; j++)
	{
		int curve = int(texel(vlist + j).x);
		float4 p12 = texel(curve) - float4(render_coord, render_coord);
		float2 p3 = texel(curve + 1).xy - render_coord;
		if (max(max(p12.y, p12.w), p3.y) * pixels_per_em.y < -0.5) break;
		uint code = calc_root_code(p12.x, p12.z, p3.x);
		if (code != 0U)
		{
			float2 r = solve_vert(p12, p3) * pixels_per_em.y;
			if ((code & 1U) != 0U)
			{
				ycov -= saturate(r.x + 0.5);
				ywgt = max(ywgt, saturate(1.0 - abs(r.x) * 2.0));
			}
			if (code > 1U)
			{
				ycov += saturate(r.y + 0.5);
				ywgt = max(ywgt, saturate(1.0 - abs(r.y) * 2.0));
			}
		}
	}
	float coverage = max(abs(xcov * xwgt + ycov * ywgt) / max(xwgt + ywgt, 1.0 / 65536.0), min(abs(xcov), abs(ycov)));
	return saturate(coverage);
}

float4 ps_main(vs_out input) : SV_TARGET
{
	int slot = int(input.color.r * 255.0 + 0.5) + 256 * int(input.color.g * 255.0 + 0.5);
	int color_index = int(input.color.b * 255.0 + 0.5);
	float2 ems_per_pixel = float2(length(float2(ddx(input.em.x), ddy(input.em.x))), length(float2(ddx(input.em.y), ddy(input.em.y))));
	float coverage = slug_coverage(slot, input.em, 1.0 / ems_per_pixel);
	// reading one texel through the sampler keeps it in the shader, which Karl2D looks for when it matches the texture with its sampler (the first texel of the glyph table is never negative, so this adds nothing, and the compiler cannot know it)
	float keep = min(glyph_data.SampleLevel(glyph_sampler, float2(0.0, 0.0), 0).x, 0.0);
	if (text_params.x != 1.0) coverage = pow(coverage, text_params.x);
	float4 paint = texel(4096 + color_index);
	return float4(paint.rgb, paint.a * (coverage + keep) * input.color.a);
}
