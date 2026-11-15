package raylib_glue

import b2 "vendor:box2d"
import rl "vendor:raylib"
import "core:c"
import b2_odin ".."

Vec2 :: b2.Vec2
HexColor :: b2.HexColor
Transform :: b2.Transform

// DebugDraw.userContext can point to a b2_odin.Camera. Without it world units are pixels with flipped y.
WorldInitDebug :: proc( ctx: ^b2_odin.WorldContext, camera: ^b2_odin.Camera = nil) {
	InitDebugDraw(&ctx.debug_draw, camera)
}

InitDebugDraw :: proc(debug_draw: ^b2.DebugDraw, camera: ^b2_odin.Camera = nil) {
	debug_draw^ = b2.DefaultDebugDraw()
	debug_draw.DrawPolygonFcn = dbg_draw_polygon
	debug_draw.DrawSolidPolygonFcn = dbg_draw_polygon_solid
	debug_draw.DrawCircleFcn = dbg_draw_circle
	debug_draw.DrawSolidCircleFcn = dbg_draw_circle_solid
	debug_draw.DrawSolidCapsuleFcn = dbg_draw_capsule_solid
	debug_draw.DrawLineFcn = dbg_draw_segment
	debug_draw.DrawStringFcn = dbg_draw_string
	debug_draw.DrawTransformFcn = dbg_draw_transform
	debug_draw.DrawPointFcn = dbg_draw_point
	debug_draw.DrawBoundsFcn = dbg_draw_bounds
	debug_draw.drawShapes = true
	debug_draw.drawingBounds = {{-1e9, -1e9}, {1e9, 1e9}}
	debug_draw.userContext = camera
}

@(private="file")
ToScreen :: proc "contextless" (ctx: rawptr, p: Vec2) -> Vec2 {
	if ctx == nil {
		return {p.x, -p.y}
	}
	return b2_odin.CameraWorldToScreen(cast(^b2_odin.Camera)ctx, p)
}

@(private="file")
ToScreenLength :: proc "contextless" (ctx: rawptr, length: f32) -> f32 {
	if ctx == nil {
		return length
	}
	return length * (cast(^b2_odin.Camera)ctx).scale
}

@(private="file")
ToColor :: proc "contextless" (color: HexColor, alpha: u8 = 255) -> rl.Color {
	value: u32 = u32(color)
	return {u8(value >> 16), u8(value >> 8), u8(value), alpha}
}

@(private="file")
TransformPoint :: proc "contextless" (transform: Transform, p: Vec2) -> Vec2 {
	return transform.p + b2.RotateVector(transform.q, p)
}

dbg_draw_polygon :: proc "c" (
    transform: Transform,
    vertices: [^]Vec2,
    vertexCount: c.int,
    color: HexColor,
    ctx: rawptr,
) {
    rl_color: = ToColor(color)
    for i:c.int = 0; i < vertexCount; i += 1 {
        v1: = ToScreen(ctx, TransformPoint(transform, vertices[i]))
        v2: = ToScreen(ctx, TransformPoint(transform, vertices[(i + 1) % vertexCount]))
        rl.DrawLineV(v1, v2, rl_color)
    }
}

dbg_draw_polygon_solid :: proc "c" (
    transform: Transform,
    vertices: [^]Vec2,
    vertexCount: c.int,
    radius: f32,
    color: HexColor,
    ctx: rawptr,
) {
    fill: = ToColor(color, 128)
    line: = ToColor(color)
    first: = ToScreen(ctx, TransformPoint(transform, vertices[0]))
    for i:c.int = 1; i < vertexCount - 1; i += 1 {
        v1: = ToScreen(ctx, TransformPoint(transform, vertices[i]))
        v2: = ToScreen(ctx, TransformPoint(transform, vertices[i + 1]))
        // Screen y is flipped, so winding is reversed
        rl.DrawTriangle(first, v2, v1, fill)
    }
    for i:c.int = 0; i < vertexCount; i += 1 {
        v1: = ToScreen(ctx, TransformPoint(transform, vertices[i]))
        v2: = ToScreen(ctx, TransformPoint(transform, vertices[(i + 1) % vertexCount]))
        rl.DrawLineV(v1, v2, line)
        if radius > 0 {
            rl.DrawCircleLinesV(v1, ToScreenLength(ctx, radius), line)
        }
    }
}

dbg_draw_circle :: proc "c" (
    center: Vec2,
    radius:f32,
    color: HexColor,
    ctx: rawptr,
) {
    rl.DrawCircleLinesV(ToScreen(ctx, center), ToScreenLength(ctx, radius), ToColor(color))
}

dbg_draw_circle_solid :: proc "c" (
    transform: Transform,
    center: Vec2,
    radius:f32,
    color: HexColor,
    ctx: rawptr,
) {
    position: = ToScreen(ctx, TransformPoint(transform, center))
    screen_radius: = ToScreenLength(ctx, radius)
    rl.DrawCircleV(position, screen_radius, ToColor(color, 128))
    rl.DrawCircleLinesV(position, screen_radius, ToColor(color))
    // Line shows rotation
    edge: = ToScreen(ctx, TransformPoint(transform, center + {radius, 0}))
    rl.DrawLineV(position, edge, ToColor(color))
}

dbg_draw_capsule_solid :: proc "c" (
    p1, p2: Vec2,
    radius: f32,
    color: HexColor,
    ctx: rawptr,
){
    fill: = ToColor(color, 128)
    line: = ToColor(color)
    s1: = ToScreen(ctx, p1)
    s2: = ToScreen(ctx, p2)
    screen_radius: = ToScreenLength(ctx, radius)

    axis: = s2 - s1
    length: = rl_length(axis)
    if length > 0 {
        normal: rl.Vector2 = {-axis.y / length, axis.x / length} * screen_radius
        a: = s1 + normal
        b: = s1 - normal
        c1: = s2 - normal
        d: = s2 + normal
        rl.DrawTriangle(a, b, c1, fill)
        rl.DrawTriangle(a, c1, d, fill)
        rl.DrawTriangle(a, c1, b, fill)
        rl.DrawTriangle(a, d, c1, fill)
        rl.DrawLineV(a, d, line)
        rl.DrawLineV(b, c1, line)
    }
    rl.DrawCircleV(s1, screen_radius, fill)
    rl.DrawCircleV(s2, screen_radius, fill)
    rl.DrawCircleLinesV(s1, screen_radius, line)
    rl.DrawCircleLinesV(s2, screen_radius, line)
}

@(private="file")
rl_length :: proc "contextless" (v: rl.Vector2) -> f32 {
    return b2.Length(v)
}

dbg_draw_segment :: proc "c" (
    p1: Vec2,
    p2: Vec2,
    color: HexColor,
    ctx: rawptr,
) {
	rl.DrawLineV(ToScreen(ctx, p1), ToScreen(ctx, p2), ToColor(color))
}

dbg_draw_string :: proc "c" (
    p: Vec2,
    s: cstring,
    color: HexColor,
    ctx: rawptr,
) {
    position: = ToScreen(ctx, p)
    rl.DrawText(s, cast(c.int)position.x, cast(c.int)position.y, 10, ToColor(color))
}

dbg_draw_transform :: proc "c" (transform: Transform, ctx: rawptr) {
    axis_length: f32 = 10 if ctx == nil else 0.5
    origin: = ToScreen(ctx, transform.p)
    rl.DrawLineV(origin, ToScreen(ctx, transform.p + b2.RotateVector(transform.q, {axis_length, 0})), ToColor(.Red))
    rl.DrawLineV(origin, ToScreen(ctx, transform.p + b2.RotateVector(transform.q, {0, axis_length})), ToColor(.Green))
}

dbg_draw_point :: proc "c" (p: Vec2, size: f32, color: HexColor, ctx: rawptr) {
    rl.DrawCircleV(ToScreen(ctx, p), max(size * 0.5, 1), ToColor(color))
}

dbg_draw_bounds :: proc "c" (aabb: b2.AABB, color: HexColor, ctx: rawptr) {
    lower: = ToScreen(ctx, aabb.lowerBound)
    upper: = ToScreen(ctx, aabb.upperBound)
    rect: rl.Rectangle = {min(lower.x, upper.x), min(lower.y, upper.y), abs(upper.x - lower.x), abs(upper.y - lower.y)}
    rl.DrawRectangleLinesEx(rect, 1, ToColor(color))
}
