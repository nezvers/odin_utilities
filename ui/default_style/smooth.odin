package ui_default

// Soft edged shapes through the painter: the geometry is built by ui/aa.odin into the storage of the painter (`painter.mesh`) and handed to `painter.fill_mesh` in one call, which
// the glue puts in the batch that is open (no shader, no texture, nothing that breaks the batch). A painter without a mesh storage (a test painter, a glue that has not got it yet)
// gets the plain shapes: every proc here has that fallback, so a style calls them without asking.

import ui ".."

// Does this painter draw soft edges
SmoothReady :: proc(painter: ^Painter) -> bool {
    return painter.fill_mesh != nil && len(painter.mesh.vertices) > 0
}

// One screen pixel in logical units
SmoothPixel :: proc(painter: ^Painter) -> f32 {
    return 1 / PainterScale(painter)
}

@(private)
smoothBegin :: proc(painter: ^Painter) -> ^ui.AaMesh {
    ui.AaMeshClear(&painter.mesh)
    return &painter.mesh
}

@(private)
smoothEnd :: proc(painter: ^Painter, color: ui.Color) {
    if painter.mesh.count > 0 { painter.fill_mesh(painter, ui.AaMeshTriangles(&painter.mesh), color) }
}

// A line through points, `width` wide, round, square or butt ends, mitered joints
Polyline :: proc(painter: ^Painter, points: []ui.Vec2, closed: bool, width: f32, color: ui.Color, cap: ui.AaCap = .BUTT) {
    if color.a == 0 || len(points) < 2 || width <= 0 { return }
    if !SmoothReady(painter) {
        count: int = len(points) if closed else len(points) - 1
        for i in 0 ..< count { Line(painter, points[i], points[(i + 1) % len(points)], width, color) }
        return
    }
    ui.AaStroke(smoothBegin(painter), points, closed, width, SmoothPixel(painter), cap)
    smoothEnd(painter, color)
}

// A cubic Bezier curve (start, two control points, end), `width` wide
Bezier :: proc(painter: ^Painter, curve: [4]ui.Vec2, width: f32, color: ui.Color, cap: ui.AaCap = .ROUND) {
    points: [130]ui.Vec2
    flat: int = ui.AaFlattenCubic(curve, ui.AA_TOLERANCE * SmoothPixel(painter), points[:])
    Polyline(painter, points[:flat], false, width, color, cap)
}

// A whole cable route (several Bezier segments) as one stroke
RouteLine :: proc(painter: ^Painter, route: ^ui.CableRoute, width: f32, color: ui.Color, cap: ui.AaCap = .ROUND) {
    points: [ui.CABLE_MAX_SEGMENTS * 129]ui.Vec2
    flat: []ui.Vec2 = ui.AaFlattenRoute(route, ui.AA_TOLERANCE * SmoothPixel(painter), points[:])
    Polyline(painter, flat, false, width, color, cap)
}

// A disc (a round head, a dot, a pin)
Disc :: proc(painter: ^Painter, center: ui.Vec2, radius: f32, color: ui.Color) {
    if color.a == 0 || radius <= 0 { return }
    if !SmoothReady(painter) {
        FillRounded(painter, {center.x - radius, center.y - radius, radius * 2, radius * 2}, 1, color)
        return
    }
    ui.AaDisc(smoothBegin(painter), center, radius, SmoothPixel(painter))
    smoothEnd(painter, color)
}

// A convex polygon with a soft edge
PolygonSmooth :: proc(painter: ^Painter, points: []ui.Vec2, color: ui.Color) {
    if color.a == 0 || len(points) < 3 { return }
    if !SmoothReady(painter) {
        if painter.fill_polygon != nil { painter.fill_polygon(painter, points, color) }
        return
    }
    ui.AaFillConvex(smoothBegin(painter), points, SmoothPixel(painter))
    smoothEnd(painter, color)
}
