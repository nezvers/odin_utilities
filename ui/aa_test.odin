package ui

import "core:math"
import "core:testing"

// What a mesh covers: every triangle's area times the mean coverage of its corners (coverage is linear inside a triangle, so this is the exact integral)
@(private = "file")
covered :: proc(mesh: ^AaMesh) -> f32 {
    total: f32
    for i := 0; i + 2 < mesh.count; i += 3 {
        a, b, c: AaVertex = mesh.vertices[i], mesh.vertices[i + 1], mesh.vertices[i + 2]
        area: f32 = abs((b.position.x - a.position.x) * (c.position.y - a.position.y) - (c.position.x - a.position.x) * (b.position.y - a.position.y)) * 0.5
        total += area * (a.coverage + b.coverage + c.coverage) / 3
    }
    return total
}

@(private = "file")
sane :: proc(mesh: ^AaMesh) -> bool {
    for i in 0 ..< mesh.count {
        v: AaVertex = mesh.vertices[i]
        if math.is_nan(v.position.x) || math.is_nan(v.position.y) || v.coverage < 0 || v.coverage > 1 { return false }
    }
    return true
}

@(test)
AaStrokeCoversItsWidthTest :: proc(t: ^testing.T) {
    storage: [4096]AaVertex
    mesh: AaMesh
    AaMeshInit(&mesh, storage[:])
    for width in ([]f32{4, 1.5, 10.25}) {
        AaMeshClear(&mesh)
        points: [2]Vec2 = {{10, 10}, {110, 10}}
        AaStroke(&mesh, points[:], false, width, 1)
        testing.expect(t, sane(&mesh))
        testing.expect(t, abs(covered(&mesh) - width * 100) < width * 1.5, "the area of a straight stroke is its width times its length (the soft ends add up to a pixel)")
    }
    // diagonal and in logical units that are two pixels
    AaMeshClear(&mesh)
    diagonal: [2]Vec2 = {{0, 0}, {30, 40}}
    AaStroke(&mesh, diagonal[:], false, 3, 0.5, .ROUND)
    testing.expect(t, sane(&mesh))
    expected: f32 = 3 * 50 + math.PI * 1.5 * 1.5
    testing.expect(t, abs(covered(&mesh) - expected) < expected * 0.03, "round ends add a disc")
}

@(test)
AaThinStrokeIsFainterTest :: proc(t: ^testing.T) {
    storage: [512]AaVertex
    mesh: AaMesh
    AaMeshInit(&mesh, storage[:])
    points: [2]Vec2 = {{0, 0}, {100, 0}}
    AaStroke(&mesh, points[:], false, 0.25, 1)
    testing.expect(t, sane(&mesh))
    testing.expect(t, abs(covered(&mesh) - 25) < 2.5, "a quarter pixel line has a quarter of the coverage")
}

@(test)
AaRoundedAreaTest :: proc(t: ^testing.T) {
    storage: [4096]AaVertex
    mesh: AaMesh
    AaMeshInit(&mesh, storage[:])
    AaRounded(&mesh, {5, 5, 80, 40}, {12, 12, 12, 12}, 1)
    testing.expect(t, sane(&mesh))
    expected: f32 = 80 * 40 - (4 - math.PI) * 144
    testing.expect(t, abs(covered(&mesh) - expected) < expected * 0.01, "area of a rounded rectangle")
    // sharp corners are a plain rectangle
    AaMeshClear(&mesh)
    AaRounded(&mesh, {0, 0, 10, 10}, {}, 1)
    testing.expect(t, abs(covered(&mesh) - 100) < 1, "a sharp rectangle")
}

@(test)
AaRingAndDiscTest :: proc(t: ^testing.T) {
    storage: [8192]AaVertex
    mesh: AaMesh
    AaMeshInit(&mesh, storage[:])
    AaRoundedRing(&mesh, {0, 0, 60, 40}, 10, 2, 1)
    testing.expect(t, sane(&mesh))
    outer: f32 = 60 * 40 - (4 - math.PI) * 100
    inner: f32 = 56 * 36 - (4 - math.PI) * 64
    testing.expect(t, abs(covered(&mesh) - (outer - inner)) < (outer - inner) * 0.03, "a ring is the difference of two rounded rectangles")
    AaMeshClear(&mesh)
    AaDisc(&mesh, {0, 0}, 20, 1)
    testing.expect(t, abs(covered(&mesh) - math.PI * 400) < math.PI * 400 * 0.01, "a disc")
}

@(test)
AaClosedStrokeAndCurveTest :: proc(t: ^testing.T) {
    storage: [8192]AaVertex
    mesh: AaMesh
    AaMeshInit(&mesh, storage[:])
    square: [5]Vec2 = {{0, 0}, {20, 0}, {20, 20}, {20, 20}, {0, 20}}      // one repeated point
    AaStroke(&mesh, square[:], true, 2, 1)
    testing.expect(t, sane(&mesh))
    testing.expect(t, abs(covered(&mesh) - 2 * 80) < 8, "a closed stroke covers its width times its perimeter (corners cut by the miter)")
    // a curve: the points stay near the curve and a straight one needs two points only
    AaMeshClear(&mesh)
    points: [256]Vec2
    straight: int = AaFlattenCubic({{0, 0}, {10, 0}, {20, 0}, {30, 0}}, AA_TOLERANCE, points[:])
    testing.expect_value(t, straight, 2)
    count: int = AaFlattenCubic({{0, 0}, {0, 100}, {100, 100}, {100, 0}}, AA_TOLERANCE, points[:])
    testing.expect(t, count > 10 && count < 100, "a bent curve gets more points")
    AaStroke(&mesh, points[:count], false, 3, 1, .ROUND)
    testing.expect(t, sane(&mesh) && !mesh.overflow)
}

@(test)
AaMeshOverflowTest :: proc(t: ^testing.T) {
    storage: [30]AaVertex
    mesh: AaMesh
    AaMeshInit(&mesh, storage[:])
    AaRounded(&mesh, {0, 0, 50, 50}, {10, 10, 10, 10}, 1)
    testing.expect(t, mesh.overflow, "a full storage drops the rest and says so")
    testing.expect(t, mesh.count <= 30 && mesh.count % 3 == 0)
}
