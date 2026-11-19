package font

// The Slug method (Eric Lengyel, "GPU-Centered Font Rendering Directly from Glyph Outlines", JCGT 2017; the patent is dedicated to the public domain, the reference shaders are MIT licensed:
// the shader code of this library is a translation of them, with credit as the license asks) as data and as an evaluator on the CPU.
//
// A glyph is cut into horizontal and vertical bands. Every band holds the curves that touch it, the ones with the largest x (or y) first. A pixel finds its two bands, and for each band
// sums, over the curves, where a ray to the right (and a ray upwards) crosses the curve, as a fraction of the pixel: that is the coverage of the pixel along the ray, and the two are weighed
// against each other. Straight horizontal curves are not in horizontal bands and straight vertical ones not in vertical bands (they cannot be crossed by a ray along them).
//
// Layout of the data of one glyph, from the `start` that is in the glyph table (all numbers are texel indexes of the whole atlas, as floats):
//   bands_y headers   (count of curves, index of the list)                         the horizontal bands, bottom to top
//   bands_x headers   (count of curves, index of the list)                         the vertical bands, left to right
//   the lists         (index of the first texel of a curve) one texel per entry, a list after the other
//   the curves        two texels each: (p1.x, p1.y, p2.x, p2.y) and (p3.x, p3.y, 0, 0)

import "core:math"

@(private)
slugBandCount :: proc(curve_count: int) -> int {
    return clamp(int(math.ceil(math.sqrt(f32(curve_count)) * 0.9)), 1, ATLAS_MAX_BANDS)
}

// Does the curve touch the band [low, high] along `axis` (1: a horizontal band, which is a range of y; 0: a vertical band, a range of x)? A curve that does not move across the band
// (all of its points have the same coordinate of the axis) cannot be crossed by a ray along the band, and is not in it.
@(private)
slugInBand :: proc(curve: Curve, axis: int, low: f32, high: f32) -> bool {
    c0, c1, c2: f32 = curve.p0[axis], curve.p1[axis], curve.p2[axis]
    if c0 == c1 && c1 == c2 { return false }
    return max(c0, c1, c2) >= low - BAND_EPSILON && min(c0, c1, c2) <= high + BAND_EPSILON
}

// The curves are sorted by the largest coordinate along the other axis, the largest first: a pixel stops at the first curve that is behind it
@(private)
slugSortKey :: proc(curve: Curve, axis: int) -> f32 {
    other: int = 1 - axis
    return max(curve.p0[other], curve.p1[other], curve.p2[other])
}

@(private)
slugBake :: proc(atlas: ^Atlas, curves: []Curve, slot: int, start: int) -> bool {
    low, high := curvesBox(curves)
    bands: int = slugBandCount(len(curves))
    size: Vec2 = {max(high.x - low.x, 1e-6), max(high.y - low.y, 1e-6)}

    // how many curves are in each band, to know how much room the glyph needs
    counts: [2][ATLAS_MAX_BANDS]int         // [0] the vertical bands (ranges of x), [1] the horizontal ones (ranges of y)
    entries: int
    for axis in 0 ..< 2 {
        for band in 0 ..< bands {
            band_low: f32 = low[axis] + size[axis] * f32(band) / f32(bands)
            band_high: f32 = low[axis] + size[axis] * f32(band + 1) / f32(bands)
            for curve in curves {
                if slugInBand(curve, axis, band_low, band_high) { counts[axis][band] += 1 }
            }
            entries += counts[axis][band]
        }
    }
    needed: int = 2 * bands + entries + 2 * len(curves)
    if start + needed > len(atlas.texels) / 4 { return false }

    headers_y: int = start                           // the horizontal bands first (the shader reads them at start + band index)
    headers_x: int = start + bands
    list_at: int = start + 2 * bands
    curves_at: int = list_at + entries
    for curve, k in curves {
        first: []f32 = atlasTexel(atlas, curves_at + 2 * k)
        first[0], first[1], first[2], first[3] = curve.p0.x, curve.p0.y, curve.p1.x, curve.p1.y
        second: []f32 = atlasTexel(atlas, curves_at + 2 * k + 1)
        second[0], second[1], second[2], second[3] = curve.p2.x, curve.p2.y, 0, 0
    }
    for axis in 0 ..< 2 {
        for band in 0 ..< bands {
            band_low: f32 = low[axis] + size[axis] * f32(band) / f32(bands)
            band_high: f32 = low[axis] + size[axis] * f32(band + 1) / f32(bands)
            members: [ATLAS_MAX_CURVES]u16
            member_count: int
            for curve, k in curves {
                if slugInBand(curve, axis, band_low, band_high) {
                    // insertion sort, the largest key first
                    key: f32 = slugSortKey(curve, axis)
                    at: int = member_count
                    for at > 0 && slugSortKey(curves[members[at - 1]], axis) < key {
                        members[at] = members[at - 1]
                        at -= 1
                    }
                    members[at] = u16(k)
                    member_count += 1
                }
            }
            header: []f32 = atlasTexel(atlas, (headers_y if axis == 1 else headers_x) + band)
            header[0], header[1], header[2], header[3] = f32(member_count), f32(list_at), 0, 0
            for member in members[:member_count] {
                entry: []f32 = atlasTexel(atlas, list_at)
                entry[0], entry[1], entry[2], entry[3] = f32(curves_at + 2 * int(member)), 0, 0, 0
                list_at += 1
            }
        }
    }
    atlas.used = start + needed
    atlasWriteSlot(atlas, slot, start, bands, bands, low, high)
    return true
}

// ------------------------------------------------------------------------------------------------------------------------
// The pixel shader on the CPU (a translation of the reference shader to this layout), the model of the shaders of the glue and the test of the data

// Which roots of a curve that is relative to the sample make a contribution, from the signs of the three y coordinates: bit 0 for the first root, bit 8 for the second
@(private)
slugRootCode :: proc(y1: f32, y2: f32, y3: f32) -> u32 {
    i1: u32 = transmute(u32)y1 >> 31
    i2: u32 = transmute(u32)y2 >> 30
    i3: u32 = transmute(u32)y3 >> 29
    shift: u32 = (i2 & 2) | (i1 & ~u32(2))
    shift = (i3 & 4) | (shift & ~u32(4))
    return (u32(0x2E74) >> shift) & 0x0101
}

// Where a curve (relative to the sample) crosses the line y = 0: the x coordinates at the two roots (the polynomial a t^2 - 2b t + c, a double root where the discriminant is negative)
@(private)
slugSolve :: proc(p12: [4]f32, p3: Vec2, axis: int) -> Vec2 {
    other: int = 1 - axis
    a: Vec2 = {p12[0] - p12[2] * 2 + p3.x, p12[1] - p12[3] * 2 + p3.y}
    b: Vec2 = {p12[0] - p12[2], p12[1] - p12[3]}
    c: f32 = p12[axis]
    ra: f32 = 1 / a[axis]
    rb: f32 = 0.5 / b[axis]
    d: f32 = math.sqrt(max(b[axis] * b[axis] - a[axis] * c, 0))
    t1: f32 = (b[axis] - d) * ra
    t2: f32 = (b[axis] + d) * ra
    if abs(a[axis]) < 1.0 / 65536 {
        t1 = c * rb
        t2 = t1
    }
    return {(a[other] * t1 - b[other] * 2) * t1 + p12[other], (a[other] * t2 - b[other] * 2) * t2 + p12[other]}
}

@(private)
slugSaturate :: proc(value: f32) -> f32 {
    return clamp(value, 0, 1)
}

// The coverage of a pixel centered on `point` (em units) when one em is `pixels_per_em` pixels across (x, y: they differ under a stretch)
SlugCoverage :: proc(atlas: ^Atlas, slot: int, point: Vec2, pixels_per_em: Vec2) -> f32 {
    info: []f32 = atlasTexel(atlas, slot * 2)
    transform: []f32 = atlasTexel(atlas, slot * 2 + 1)
    start: int = int(info[0])
    band_max: [2]int = {int(info[1]), int(info[2])}
    band: [2]int = {
        clamp(int(point.x * transform[0] + transform[2]), 0, band_max.x),
        clamp(int(point.y * transform[1] + transform[3]), 0, band_max.y),
    }

    cover: [2]f32           // along x (a horizontal ray), along y
    weight: [2]f32
    for axis in 0 ..< 2 {
        // the horizontal bands come first (axis 0 of the loop is the ray along x, which looks at a band of y)
        header_index: int = start + band[1] if axis == 0 else start + band_max.y + 1 + band[0]
        header: []f32 = atlasTexel(atlas, header_index)
        member_count: int = int(header[0])
        list_at: int = int(header[1])
        scale: f32 = pixels_per_em.x if axis == 0 else pixels_per_em.y
        for k in 0 ..< member_count {
            curve_at: int = int(atlasTexel(atlas, list_at + k)[0])
            first: []f32 = atlasTexel(atlas, curve_at)
            p12: [4]f32 = {first[0] - point.x, first[1] - point.y, first[2] - point.x, first[3] - point.y}
            second: []f32 = atlasTexel(atlas, curve_at + 1)
            p3: Vec2 = {second[0] - point.x, second[1] - point.y}
            if axis == 0 {
                if max(p12[0], p12[2], p3.x) * scale < -0.5 { break }
            } else {
                if max(p12[1], p12[3], p3.y) * scale < -0.5 { break }
            }
            code: u32
            roots: Vec2
            if axis == 0 {
                code = slugRootCode(p12[1], p12[3], p3.y)
                if code != 0 { roots = slugSolve(p12, p3, 1) * scale }
            } else {
                code = slugRootCode(p12[0], p12[2], p3.x)
                if code != 0 { roots = slugSolve(p12, p3, 0) * scale }
            }
            if code == 0 { continue }
            sign: f32 = 1 if axis == 0 else -1
            if code & 1 != 0 {
                cover[axis] += sign * slugSaturate(roots.x + 0.5)
                weight[axis] = max(weight[axis], slugSaturate(1 - abs(roots.x) * 2))
            }
            if code > 1 {
                cover[axis] -= sign * slugSaturate(roots.y + 0.5)
                weight[axis] = max(weight[axis], slugSaturate(1 - abs(roots.y) * 2))
            }
        }
    }
    // the two rays are weighed by how near to the pixel their crossings were; either direction of the contours works
    coverage: f32 = max(abs(cover[0] * weight[0] + cover[1] * weight[1]) / max(weight[0] + weight[1], 1.0 / 65536), min(abs(cover[0]), abs(cover[1])))
    return slugSaturate(coverage)
}
