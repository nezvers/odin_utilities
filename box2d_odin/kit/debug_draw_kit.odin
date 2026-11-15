package box2d_odin_kit

// Box2D debug draw over the demo kit (odin_utilities/demo_kit): the same drawing as raylib/ and karl2d/, but through kit.Context, so a demo written
// against the kit shows the physics on any backend. The Box2D callbacks have no context of their own (only the camera pointer in
// userContext), so the frame's context is kept here: call Begin(ctx) at the start of the frame that draws.
//
//     box2d_kit.Begin(ctx)
//     box2d_kit.InitDebugDraw(&host.debug_draw, &host.ctx.camera)

import "base:runtime"
import "core:c"
import b2 "vendor:box2d"
import b2_odin ".."
import kit "../../demo_kit"

Vec2 :: b2.Vec2
HexColor :: b2.HexColor
Transform :: b2.Transform

@(private)
frame: ^kit.Context

// The context of the frame that draws
Begin :: proc(ctx: ^kit.Context) {
    frame = ctx
}

WorldInitDebug :: proc(ctx: ^b2_odin.WorldContext, camera: ^b2_odin.Camera = nil) {
    InitDebugDraw(&ctx.debug_draw, camera)
}

// DebugDraw.userContext can point to a b2_odin.Camera. Without it world units are pixels with flipped y.
InitDebugDraw :: proc(debug_draw: ^b2.DebugDraw, camera: ^b2_odin.Camera = nil) {
    debug_draw^ = b2.DefaultDebugDraw()
    debug_draw.DrawPolygonFcn = dbgDrawPolygon
    debug_draw.DrawSolidPolygonFcn = dbgDrawPolygonSolid
    debug_draw.DrawCircleFcn = dbgDrawCircle
    debug_draw.DrawSolidCircleFcn = dbgDrawCircleSolid
    debug_draw.DrawSolidCapsuleFcn = dbgDrawCapsuleSolid
    debug_draw.DrawLineFcn = dbgDrawSegment
    debug_draw.DrawStringFcn = dbgDrawString
    debug_draw.DrawTransformFcn = dbgDrawTransform
    debug_draw.DrawPointFcn = dbgDrawPoint
    debug_draw.DrawBoundsFcn = dbgDrawBounds
    debug_draw.drawShapes = true
    debug_draw.drawingBounds = {{-1e9, -1e9}, {1e9, 1e9}}
    debug_draw.userContext = camera
}

@(private)
toScreen :: proc "contextless" (ctx: rawptr, p: Vec2) -> Vec2 {
    if ctx == nil { return {p.x, -p.y} }
    return b2_odin.CameraWorldToScreen(cast(^b2_odin.Camera)ctx, p)
}

@(private)
toScreenLength :: proc "contextless" (ctx: rawptr, length: f32) -> f32 {
    if ctx == nil { return length }
    return length * (cast(^b2_odin.Camera)ctx).scale
}

@(private)
toColor :: proc "contextless" (color: HexColor, alpha: u8 = 255) -> kit.Color {
    value: u32 = u32(color)
    return {u8(value >> 16), u8(value >> 8), u8(value), alpha}
}

@(private)
transformPoint :: proc "contextless" (transform: Transform, p: Vec2) -> Vec2 {
    return transform.p + b2.RotateVector(transform.q, p)
}

dbgDrawPolygon :: proc "c" (transform: Transform, vertices: [^]Vec2, vertex_count: c.int, color: HexColor, ctx: rawptr) {
    context = frameContext()
    line: kit.Color = toColor(color)
    for i in 0 ..< int(vertex_count) {
        v1: Vec2 = toScreen(ctx, transformPoint(transform, vertices[i]))
        v2: Vec2 = toScreen(ctx, transformPoint(transform, vertices[(i + 1) % int(vertex_count)]))
        kit.DrawLine(frame, v1, v2, 1, line)
    }
}

dbgDrawPolygonSolid :: proc "c" (transform: Transform, vertices: [^]Vec2, vertex_count: c.int, radius: f32, color: HexColor, ctx: rawptr) {
    context = frameContext()
    fill: kit.Color = toColor(color, 128)
    line: kit.Color = toColor(color)
    first: Vec2 = toScreen(ctx, transformPoint(transform, vertices[0]))
    for i in 1 ..< int(vertex_count) - 1 {
        v1: Vec2 = toScreen(ctx, transformPoint(transform, vertices[i]))
        v2: Vec2 = toScreen(ctx, transformPoint(transform, vertices[i + 1]))
        kit.DrawTriangle(frame, first, v2, v1, fill)
    }
    for i in 0 ..< int(vertex_count) {
        v1: Vec2 = toScreen(ctx, transformPoint(transform, vertices[i]))
        v2: Vec2 = toScreen(ctx, transformPoint(transform, vertices[(i + 1) % int(vertex_count)]))
        kit.DrawLine(frame, v1, v2, 1, line)
        if radius > 0 { kit.DrawCircleOutline(frame, v1, toScreenLength(ctx, radius), 1, line) }
    }
}

dbgDrawCircle :: proc "c" (center: Vec2, radius: f32, color: HexColor, ctx: rawptr) {
    context = frameContext()
    kit.DrawCircleOutline(frame, toScreen(ctx, center), toScreenLength(ctx, radius), 1, toColor(color))
}

dbgDrawCircleSolid :: proc "c" (transform: Transform, center: Vec2, radius: f32, color: HexColor, ctx: rawptr) {
    context = frameContext()
    position: Vec2 = toScreen(ctx, transformPoint(transform, center))
    screen_radius: f32 = toScreenLength(ctx, radius)
    kit.DrawCircle(frame, position, screen_radius, toColor(color, 128))
    kit.DrawCircleOutline(frame, position, screen_radius, 1, toColor(color))
    // a line shows the rotation
    edge: Vec2 = toScreen(ctx, transformPoint(transform, center + {radius, 0}))
    kit.DrawLine(frame, position, edge, 1, toColor(color))
}

dbgDrawCapsuleSolid :: proc "c" (p1, p2: Vec2, radius: f32, color: HexColor, ctx: rawptr) {
    context = frameContext()
    fill: kit.Color = toColor(color, 128)
    line: kit.Color = toColor(color)
    s1: Vec2 = toScreen(ctx, p1)
    s2: Vec2 = toScreen(ctx, p2)
    screen_radius: f32 = toScreenLength(ctx, radius)
    axis: Vec2 = s2 - s1
    length: f32 = b2.Length(axis)
    if length > 0 {
        normal: Vec2 = {-axis.y / length, axis.x / length} * screen_radius
        a: Vec2 = s1 + normal
        b: Vec2 = s1 - normal
        c1: Vec2 = s2 - normal
        d: Vec2 = s2 + normal
        kit.DrawTriangle(frame, a, b, c1, fill)
        kit.DrawTriangle(frame, a, c1, d, fill)
        kit.DrawLine(frame, a, d, 1, line)
        kit.DrawLine(frame, b, c1, 1, line)
    }
    kit.DrawCircle(frame, s1, screen_radius, fill)
    kit.DrawCircle(frame, s2, screen_radius, fill)
    kit.DrawCircleOutline(frame, s1, screen_radius, 1, line)
    kit.DrawCircleOutline(frame, s2, screen_radius, 1, line)
}

dbgDrawSegment :: proc "c" (p1: Vec2, p2: Vec2, color: HexColor, ctx: rawptr) {
    context = frameContext()
    kit.DrawLine(frame, toScreen(ctx, p1), toScreen(ctx, p2), 1, toColor(color))
}

dbgDrawString :: proc "c" (p: Vec2, s: cstring, color: HexColor, ctx: rawptr) {
    context = frameContext()
    kit.DrawText(frame, string(s), toScreen(ctx, p), 10, toColor(color))
}

dbgDrawTransform :: proc "c" (transform: Transform, ctx: rawptr) {
    context = frameContext()
    axis_length: f32 = 10 if ctx == nil else 0.5
    origin: Vec2 = toScreen(ctx, transform.p)
    kit.DrawLine(frame, origin, toScreen(ctx, transform.p + b2.RotateVector(transform.q, {axis_length, 0})), 1, toColor(.Red))
    kit.DrawLine(frame, origin, toScreen(ctx, transform.p + b2.RotateVector(transform.q, {0, axis_length})), 1, toColor(.Green))
}

dbgDrawPoint :: proc "c" (p: Vec2, size: f32, color: HexColor, ctx: rawptr) {
    context = frameContext()
    kit.DrawCircle(frame, toScreen(ctx, p), max(size * 0.5, 1), toColor(color))
}

dbgDrawBounds :: proc "c" (aabb: b2.AABB, color: HexColor, ctx: rawptr) {
    context = frameContext()
    lower: Vec2 = toScreen(ctx, aabb.lowerBound)
    upper: Vec2 = toScreen(ctx, aabb.upperBound)
    kit.DrawRectOutline(frame, {min(lower.x, upper.x), min(lower.y, upper.y), abs(upper.x - lower.x), abs(upper.y - lower.y)}, 1, toColor(color))
}

// the callbacks are "c" procs: a context to call the kit with. The temp allocator is the one text formatting would use
@(private)
frameContext :: proc "contextless" () -> (result: runtime.Context) {
    return runtime.default_context()
}
