#version 330
// The Scanline Sweeper (Scuff3D Rook, Rook & Possum, 2026) for the glyph data of the font library (font/scanline.odin has the layout), written from the description of the paper:
// the coverage of the pixel is the signed area that the monotonic curves sweep to the right inside of it.
in vec2 fragEm;
flat in int fragSlot;
flat in int fragColor;
out vec4 finalColor;
uniform sampler2D glyphData;
uniform vec4 textParams;        // x: the exponent of the coverage (1: as it is, under 1: heavier text)

vec4 texel(int index)
{
    return texelFetch(glyphData, ivec2(index & 4095, index >> 12), 0);
}

vec2 curveAt(vec2 p0, vec2 p1, vec2 p2, float t)
{
    vec2 a = mix(p0, p1, t);
    vec2 b = mix(p1, p2, t);
    return mix(a, b, t);
}

// the parameter where one coordinate of a monotonic curve is the target (the end that it is beyond when it is outside of the range)
float monotonicRoot(float c0, float c1, float c2, float target)
{
    float low = min(c0, c2);
    float high = max(c0, c2);
    if (target <= low) return c0 <= c2 ? 0.0 : 1.0;
    if (target >= high) return c0 <= c2 ? 1.0 : 0.0;
    float a = c0 - 2.0 * c1 + c2;
    float b = 2.0 * (c1 - c0);
    float c = c0 - target;
    if (abs(a) < 1e-7) return clamp(-c / b, 0.0, 1.0);
    float root = sqrt(max(b * b - 4.0 * a * c, 0.0));
    float t1 = (-b + root) / (2.0 * a);
    float t2 = (-b - root) / (2.0 * a);
    if (t1 >= -1e-4 && t1 <= 1.0 + 1e-4) return clamp(t1, 0.0, 1.0);
    if (t2 >= -1e-4 && t2 <= 1.0 + 1e-4) return clamp(t2, 0.0, 1.0);
    return clamp(abs(t1 - 0.5) < abs(t2 - 0.5) ? t1 : t2, 0.0, 1.0);
}

float curveSweepArea(vec2 p0, vec2 p1, vec2 p2, vec2 low, vec2 high)
{
    if (p0.y == p2.y) return 0.0;
    if (max(p0.y, p2.y) <= low.y || min(p0.y, p2.y) >= high.y) return 0.0;
    float width = high.x - low.x;
    bool up = p2.y > p0.y;
    float tLow = monotonicRoot(p0.y, p1.y, p2.y, low.y);
    float tHigh = monotonicRoot(p0.y, p1.y, p2.y, high.y);
    float start = up ? tLow : tHigh;
    float end = up ? tHigh : tLow;
    if (end <= start) return 0.0;
    float marks[4];
    marks[0] = start;
    marks[1] = clamp(monotonicRoot(p0.x, p1.x, p2.x, low.x), start, end);
    marks[2] = clamp(monotonicRoot(p0.x, p1.x, p2.x, high.x), start, end);
    marks[3] = end;
    if (marks[1] > marks[2]) { float swapped = marks[1]; marks[1] = marks[2]; marks[2] = swapped; }
    float area = 0.0;
    for (int i = 0; i < 3; i++)
    {
        float t0 = marks[i];
        float t1 = marks[i + 1];
        if (t1 <= t0) continue;
        vec2 a = curveAt(p0, p1, p2, t0);
        vec2 b = curveAt(p0, p1, p2, t1);
        vec2 middle = curveAt(p0, p1, p2, (t0 + t1) * 0.5);
        if (middle.x <= low.x)
        {
            area += (b.y - a.y) * width;
        }
        else if (middle.x < high.x)
        {
            vec2 previous = a;
            for (int step = 1; step <= 3; step++)
            {
                vec2 current = step < 3 ? curveAt(p0, p1, p2, mix(t0, t1, float(step) / 3.0)) : b;
                area += ((high.x - previous.x) + (high.x - current.x)) * 0.5 * (current.y - previous.y);
                previous = current;
            }
        }
    }
    return area;
}

float scanlineCoverage(int slot, vec2 point, vec2 halfSize)
{
    vec4 info = texel(slot * 2);
    vec4 transform = texel(slot * 2 + 1);
    int start = int(info.x);
    int stripeMax = int(info.z);
    vec2 low = point - halfSize;
    vec2 high = point + halfSize;
    int first = clamp(int(low.y * transform.y + transform.w), 0, stripeMax);
    int last = clamp(int(high.y * transform.y + transform.w), 0, stripeMax);
    float total = 0.0;
    for (int stripe = first; stripe <= last; stripe++)
    {
        vec2 partLow = low;
        vec2 partHigh = high;
        if (stripe > first) partLow.y = (float(stripe) - transform.w) / transform.y;
        if (stripe < last) partHigh.y = (float(stripe + 1) - transform.w) / transform.y;
        vec4 header = texel(start + stripe);
        int count = int(header.x);
        int at = int(header.y);
        for (int k = 0; k < count; k++)
        {
            vec4 a = texel(at + 2 * k);
            vec4 b = texel(at + 2 * k + 1);
            if (min(a.x, b.x) >= partHigh.x) break;
            total += curveSweepArea(a.xy, a.zw, b.xy, partLow, partHigh);
        }
    }
    return clamp(abs(total) / ((high.x - low.x) * (high.y - low.y)), 0.0, 1.0);
}

void main()
{
    vec2 emsPerPixel = vec2(length(vec2(dFdx(fragEm.x), dFdy(fragEm.x))), length(vec2(dFdx(fragEm.y), dFdy(fragEm.y))));
    float coverage = scanlineCoverage(fragSlot, fragEm, 0.5 * emsPerPixel);
    if (textParams.x != 1.0) coverage = pow(coverage, textParams.x);
    vec4 paint = texel(4096 + fragColor);
    finalColor = vec4(paint.rgb, paint.a * coverage);
}
