package font

// The Scanline Sweeper (Scuff3D Rook, "The Scanline Sweeper: A Glyph Rendering Algorithm", Rook & Possum, 2026) as data and as an evaluator on the CPU. Written from the description of the
// paper; the coverage of a pixel is the sum of the signed areas that the curves sweep to the right inside of the pixel (raster.odin: CurveSweepArea), over the curves that touch its scanlines.
//
// The glyph is cut into horizontal stripes, and every stripe has a list of the monotonic curves that touch it, the curve data itself with no index in between (the paper found that the
// memory traffic is the cost, so a stripe is read straight on). Curves left of the pixel are as cheap as the ones in it, curves that start right of it are skipped, so a stripe is sorted
// by the smallest x of its curves, and the pixel stops at the first one that begins behind its right edge.
//
// Layout of the data of one glyph, from the `start` of the glyph table:
//   stripes headers   (count of curves, index of the first curve texel)             bottom to top
//   the curves        two texels each: (p1.x, p1.y, p2.x, p2.y) and (p3.x, p3.y, 0, 0), the stripes one after the other

@(private)
scanlineStripeCount :: proc(curve_count: int) -> int {
    return slugBandCount(curve_count)
}

@(private)
scanlineBake :: proc(atlas: ^Atlas, curves: []Curve, slot: int, start: int) -> bool {
    // monotonic pieces without the horizontal ones (they sweep no area)
    pieces: [ATLAS_MAX_CURVES]Curve
    cut: [ATLAS_MAX_CURVES]Curve
    cut_count, cut_ok := CurvesMonotonic(curves, cut[:])
    if !cut_ok { return false }
    piece_count: int
    for curve in cut[:cut_count] {
        if curve.p0.y == curve.p2.y { continue }
        pieces[piece_count] = curve
        piece_count += 1
    }
    if piece_count == 0 { return false }
    low, high := curvesBox(pieces[:piece_count])
    stripes: int = scanlineStripeCount(piece_count)
    size_y: f32 = max(high.y - low.y, 1e-6)

    counts: [ATLAS_MAX_BANDS]int
    total: int
    for stripe in 0 ..< stripes {
        stripe_low: f32 = low.y + size_y * f32(stripe) / f32(stripes)
        stripe_high: f32 = low.y + size_y * f32(stripe + 1) / f32(stripes)
        for curve in pieces[:piece_count] {
            if max(curve.p0.y, curve.p2.y) >= stripe_low - BAND_EPSILON && min(curve.p0.y, curve.p2.y) <= stripe_high + BAND_EPSILON { counts[stripe] += 1 }
        }
        total += counts[stripe]
    }
    needed: int = stripes + 2 * total
    if start + needed > len(atlas.texels) / 4 { return false }

    at: int = start + stripes
    for stripe in 0 ..< stripes {
        stripe_low: f32 = low.y + size_y * f32(stripe) / f32(stripes)
        stripe_high: f32 = low.y + size_y * f32(stripe + 1) / f32(stripes)
        members: [ATLAS_MAX_CURVES]u16
        member_count: int
        for curve, k in pieces[:piece_count] {
            if max(curve.p0.y, curve.p2.y) >= stripe_low - BAND_EPSILON && min(curve.p0.y, curve.p2.y) <= stripe_high + BAND_EPSILON {
                key: f32 = min(curve.p0.x, curve.p2.x)
                position: int = member_count
                for position > 0 && min(pieces[members[position - 1]].p0.x, pieces[members[position - 1]].p2.x) > key {
                    members[position] = members[position - 1]
                    position -= 1
                }
                members[position] = u16(k)
                member_count += 1
            }
        }
        header: []f32 = atlasTexel(atlas, start + stripe)
        header[0], header[1], header[2], header[3] = f32(member_count), f32(at), 0, 0
        for member in members[:member_count] {
            curve: Curve = pieces[member]
            first: []f32 = atlasTexel(atlas, at)
            first[0], first[1], first[2], first[3] = curve.p0.x, curve.p0.y, curve.p1.x, curve.p1.y
            second: []f32 = atlasTexel(atlas, at + 1)
            second[0], second[1], second[2], second[3] = curve.p2.x, curve.p2.y, 0, 0
            at += 2
        }
    }
    atlas.used = start + needed
    atlasWriteSlot(atlas, slot, start, 1, stripes, low, high)
    return true
}

// The coverage of the pixel that is the window [point - half, point + half] (em units, `half` is half a pixel in em units along each axis)
ScanlineCoverage :: proc(atlas: ^Atlas, slot: int, point: Vec2, half: Vec2) -> f32 {
    info: []f32 = atlasTexel(atlas, slot * 2)
    transform: []f32 = atlasTexel(atlas, slot * 2 + 1)
    start: int = int(info[0])
    stripe_max: int = int(info[2])
    low: Vec2 = point - half
    high: Vec2 = point + half
    // the pixel may reach into more than one stripe: each stripe is read with the part of the window that is in it (the areas of parts that do not overlap add up)
    stripe_first: int = clamp(int(low.y * transform[1] + transform[3]), 0, stripe_max)
    stripe_last: int = clamp(int(high.y * transform[1] + transform[3]), 0, stripe_max)
    total: f32
    for stripe in stripe_first ..= stripe_last {
        part_low: Vec2 = low
        part_high: Vec2 = high
        if stripe > stripe_first { part_low.y = (f32(stripe) - transform[3]) / transform[1] }
        if stripe < stripe_last { part_high.y = (f32(stripe + 1) - transform[3]) / transform[1] }
        header: []f32 = atlasTexel(atlas, start + stripe)
        member_count: int = int(header[0])
        at: int = int(header[1])
        for k in 0 ..< member_count {
            first: []f32 = atlasTexel(atlas, at + 2 * k)
            second: []f32 = atlasTexel(atlas, at + 2 * k + 1)
            curve: Curve = {{first[0], first[1]}, {first[2], first[3]}, {second[0], second[1]}}
            if min(curve.p0.x, curve.p2.x) >= part_high.x { break }          // sorted by the smallest x: nothing after this one is left of the pixel
            total += CurveSweepArea(curve, part_low, part_high)
        }
    }
    window: f32 = (high.x - low.x) * (high.y - low.y)
    return clamp(abs(total) / window, 0, 1)
}
