#version 330
// The Slug method (Eric Lengyel, JCGT 2017) for the glyph data of the font library (font/slug.odin has the layout): a translation to GLSL of the reference pixel shader, which is
// MIT licensed, Copyright 2017 by Eric Lengyel, with the data read from one float texture.
in vec2 fragEm;
flat in int fragSlot;
flat in int fragColor;
flat in float fragAlpha;
out vec4 finalColor;
uniform sampler2D glyphData;
uniform vec4 textParams;        // x: the exponent of the coverage (1: as it is, under 1: heavier text)

vec4 texel(int index)
{
    return texelFetch(glyphData, ivec2(index & 4095, index >> 12), 0);
}

uint calcRootCode(float y1, float y2, float y3)
{
    uint i1 = floatBitsToUint(y1) >> 31u;
    uint i2 = floatBitsToUint(y2) >> 30u;
    uint i3 = floatBitsToUint(y3) >> 29u;
    uint shift = (i2 & 2u) | (i1 & ~2u);
    shift = (i3 & 4u) | (shift & ~4u);
    return (0x2E74u >> shift) & 0x0101u;
}

// where the curve (relative to the sample) crosses y = 0, the x coordinates at the two roots
vec2 solveHoriz(vec4 p12, vec2 p3)
{
    vec2 a = p12.xy - p12.zw * 2.0 + p3;
    vec2 b = p12.xy - p12.zw;
    float ra = 1.0 / a.y;
    float rb = 0.5 / b.y;
    float d = sqrt(max(b.y * b.y - a.y * p12.y, 0.0));
    float t1 = (b.y - d) * ra;
    float t2 = (b.y + d) * ra;
    if (abs(a.y) < 1.0 / 65536.0) t1 = t2 = p12.y * rb;
    return vec2((a.x * t1 - b.x * 2.0) * t1 + p12.x, (a.x * t2 - b.x * 2.0) * t2 + p12.x);
}

vec2 solveVert(vec4 p12, vec2 p3)
{
    vec2 a = p12.xy - p12.zw * 2.0 + p3;
    vec2 b = p12.xy - p12.zw;
    float ra = 1.0 / a.x;
    float rb = 0.5 / b.x;
    float d = sqrt(max(b.x * b.x - a.x * p12.x, 0.0));
    float t1 = (b.x - d) * ra;
    float t2 = (b.x + d) * ra;
    if (abs(a.x) < 1.0 / 65536.0) t1 = t2 = p12.x * rb;
    return vec2((a.y * t1 - b.y * 2.0) * t1 + p12.y, (a.y * t2 - b.y * 2.0) * t2 + p12.y);
}

float slugCoverage(int slot, vec2 renderCoord, vec2 pixelsPerEm)
{
    vec4 info = texel(slot * 2);
    vec4 transform = texel(slot * 2 + 1);
    int start = int(info.x);
    ivec2 bandMax = ivec2(int(info.y), int(info.z));
    ivec2 bandIndex = clamp(ivec2(renderCoord * transform.xy + transform.zw), ivec2(0), bandMax);

    float xcov = 0.0;
    float xwgt = 0.0;
    vec4 hband = texel(start + bandIndex.y);
    int hcount = int(hband.x);
    int hlist = int(hband.y);
    for (int k = 0; k < hcount; k++)
    {
        int curve = int(texel(hlist + k).x);
        vec4 p12 = texel(curve) - vec4(renderCoord, renderCoord);
        vec2 p3 = texel(curve + 1).xy - renderCoord;
        if (max(max(p12.x, p12.z), p3.x) * pixelsPerEm.x < -0.5) break;
        uint code = calcRootCode(p12.y, p12.w, p3.y);
        if (code != 0u)
        {
            vec2 r = solveHoriz(p12, p3) * pixelsPerEm.x;
            if ((code & 1u) != 0u)
            {
                xcov += clamp(r.x + 0.5, 0.0, 1.0);
                xwgt = max(xwgt, clamp(1.0 - abs(r.x) * 2.0, 0.0, 1.0));
            }
            if (code > 1u)
            {
                xcov -= clamp(r.y + 0.5, 0.0, 1.0);
                xwgt = max(xwgt, clamp(1.0 - abs(r.y) * 2.0, 0.0, 1.0));
            }
        }
    }

    float ycov = 0.0;
    float ywgt = 0.0;
    vec4 vband = texel(start + bandMax.y + 1 + bandIndex.x);
    int vcount = int(vband.x);
    int vlist = int(vband.y);
    for (int k = 0; k < vcount; k++)
    {
        int curve = int(texel(vlist + k).x);
        vec4 p12 = texel(curve) - vec4(renderCoord, renderCoord);
        vec2 p3 = texel(curve + 1).xy - renderCoord;
        if (max(max(p12.y, p12.w), p3.y) * pixelsPerEm.y < -0.5) break;
        uint code = calcRootCode(p12.x, p12.z, p3.x);
        if (code != 0u)
        {
            vec2 r = solveVert(p12, p3) * pixelsPerEm.y;
            if ((code & 1u) != 0u)
            {
                ycov -= clamp(r.x + 0.5, 0.0, 1.0);
                ywgt = max(ywgt, clamp(1.0 - abs(r.x) * 2.0, 0.0, 1.0));
            }
            if (code > 1u)
            {
                ycov += clamp(r.y + 0.5, 0.0, 1.0);
                ywgt = max(ywgt, clamp(1.0 - abs(r.y) * 2.0, 0.0, 1.0));
            }
        }
    }
    float coverage = max(abs(xcov * xwgt + ycov * ywgt) / max(xwgt + ywgt, 1.0 / 65536.0), min(abs(xcov), abs(ycov)));
    return clamp(coverage, 0.0, 1.0);
}

void main()
{
    // the size of an em in pixels along each axis of the em square, from how fast the coordinates change on the screen (right for a rotated quad too)
    vec2 emsPerPixel = vec2(length(vec2(dFdx(fragEm.x), dFdy(fragEm.x))), length(vec2(dFdx(fragEm.y), dFdy(fragEm.y))));
    float coverage = slugCoverage(fragSlot, fragEm, 1.0 / emsPerPixel);
    if (textParams.x != 1.0) coverage = pow(coverage, textParams.x);
    vec4 paint = texel(4096 + fragColor);
    finalColor = vec4(paint.rgb, paint.a * coverage * fragAlpha);
}
