// The Scanline Sweeper (Scuff3D Rook, Rook & Possum, 2026) for the glyph data of the font library (font/scanline.odin has the layout), for the Direct3D 11 backend of Karl2D, written from the
// description of the paper: the coverage of the pixel is the signed area that the monotonic curves sweep to the right inside of it.
cbuffer constants : register(b0) {
	float4x4 view_projection;
	float4 text_color;
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

float2 curve_at(float2 p0, float2 p1, float2 p2, float t)
{
	float2 a = lerp(p0, p1, t);
	float2 b = lerp(p1, p2, t);
	return lerp(a, b, t);
}

float monotonic_root(float c0, float c1, float c2, float target)
{
	float low = min(c0, c2);
	float high = max(c0, c2);
	if (target <= low) return c0 <= c2 ? 0.0 : 1.0;
	if (target >= high) return c0 <= c2 ? 1.0 : 0.0;
	float a = c0 - 2.0 * c1 + c2;
	float b = 2.0 * (c1 - c0);
	float c = c0 - target;
	if (abs(a) < 1e-7) return saturate(-c / b);
	float root = sqrt(max(b * b - 4.0 * a * c, 0.0));
	float t1 = (-b + root) / (2.0 * a);
	float t2 = (-b - root) / (2.0 * a);
	if (t1 >= -1e-4 && t1 <= 1.0 + 1e-4) return saturate(t1);
	if (t2 >= -1e-4 && t2 <= 1.0 + 1e-4) return saturate(t2);
	return saturate(abs(t1 - 0.5) < abs(t2 - 0.5) ? t1 : t2);
}

float curve_sweep_area(float2 p0, float2 p1, float2 p2, float2 low, float2 high)
{
	if (p0.y == p2.y) return 0.0;
	if (max(p0.y, p2.y) <= low.y || min(p0.y, p2.y) >= high.y) return 0.0;
	float width = high.x - low.x;
	bool up = p2.y > p0.y;
	float t_low = monotonic_root(p0.y, p1.y, p2.y, low.y);
	float t_high = monotonic_root(p0.y, p1.y, p2.y, high.y);
	float start = up ? t_low : t_high;
	float end = up ? t_high : t_low;
	if (end <= start) return 0.0;
	float marks[4];
	marks[0] = start;
	marks[1] = clamp(monotonic_root(p0.x, p1.x, p2.x, low.x), start, end);
	marks[2] = clamp(monotonic_root(p0.x, p1.x, p2.x, high.x), start, end);
	marks[3] = end;
	if (marks[1] > marks[2]) { float swapped = marks[1]; marks[1] = marks[2]; marks[2] = swapped; }
	float area = 0.0;
	[unroll] for (int i = 0; i < 3; i++)
	{
		float t0 = marks[i];
		float t1 = marks[i + 1];
		if (t1 <= t0) continue;
		float2 a = curve_at(p0, p1, p2, t0);
		float2 b = curve_at(p0, p1, p2, t1);
		float2 middle = curve_at(p0, p1, p2, (t0 + t1) * 0.5);
		if (middle.x <= low.x)
		{
			area += (b.y - a.y) * width;
		}
		else if (middle.x < high.x)
		{
			float2 previous = a;
			[unroll] for (int step = 1; step <= 3; step++)
			{
				float2 current = step < 3 ? curve_at(p0, p1, p2, lerp(t0, t1, float(step) / 3.0)) : b;
				area += ((high.x - previous.x) + (high.x - current.x)) * 0.5 * (current.y - previous.y);
				previous = current;
			}
		}
	}
	return area;
}

float scanline_coverage(int slot, float2 center, float2 half_size)
{
	float4 info = texel(slot * 2);
	float4 transform = texel(slot * 2 + 1);
	int start = int(info.x);
	int stripe_max = int(info.z);
	float2 low = center - half_size;
	float2 high = center + half_size;
	int first = clamp(int(low.y * transform.y + transform.w), 0, stripe_max);
	int last = clamp(int(high.y * transform.y + transform.w), 0, stripe_max);
	float total = 0.0;
	[loop] for (int stripe = first; stripe <= last; stripe++)
	{
		float2 part_low = low;
		float2 part_high = high;
		if (stripe > first) part_low.y = (float(stripe) - transform.w) / transform.y;
		if (stripe < last) part_high.y = (float(stripe + 1) - transform.w) / transform.y;
		float4 header = texel(start + stripe);
		int count = int(header.x);
		int at = int(header.y);
		[loop] for (int k = 0; k < count; k++)
		{
			float4 a = texel(at + 2 * k);
			float4 b = texel(at + 2 * k + 1);
			if (min(a.x, b.x) >= part_high.x) break;
			total += curve_sweep_area(a.xy, a.zw, b.xy, part_low, part_high);
		}
	}
	return saturate(abs(total) / ((high.x - low.x) * (high.y - low.y)));
}

float4 ps_main(vs_out input) : SV_TARGET
{
	int slot = int(input.color.r * 255.0 + 0.5) + 256 * int(input.color.g * 255.0 + 0.5);
	float2 half_size = 0.5 * fwidth(input.em);
	float coverage = scanline_coverage(slot, input.em, half_size);
	// reading one texel through the sampler keeps it in the shader, which Karl2D looks for when it matches the texture with its sampler (the first texel of the glyph table is never negative, so this adds nothing, and the compiler cannot know it)
	float keep = min(glyph_data.SampleLevel(glyph_sampler, float2(0.0, 0.0), 0).x, 0.0);
	return float4(text_color.rgb, text_color.a * (coverage + keep));
}
