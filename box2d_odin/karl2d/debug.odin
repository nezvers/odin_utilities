package box2d_karl2d

import "core:c"
import "base:runtime"

import b2 "vendor:box2d"
Vec2 :: b2.Vec2
HexColor :: b2.HexColor
Transform :: b2.Transform
import b2_odin ".."

import "../../karl2d"
Color :: karl2d.Color

WorldInitDebug :: proc( ctx: ^b2_odin.WorldContext) {
	ctx.debug_draw = b2.DefaultDebugDraw()
	ctx.debug_draw.DrawPolygonFcn = dbg_draw_polygon
	ctx.debug_draw.DrawSolidPolygonFcn = dbg_draw_polygon_solid
	ctx.debug_draw.DrawCircleFcn = dbg_draw_circle
    ctx.debug_draw.DrawSolidCircleFcn = dbg_draw_circle_solid
	// ctx.debug_draw.DrawSolidCapsuleFcn = dbg_draw_capsule
    ctx.debug_draw.DrawSolidCapsuleFcn = dbg_draw_capsule_solid
	ctx.debug_draw.DrawSegmentFcn = dbg_draw_segment
	ctx.debug_draw.DrawStringFcn = dbg_draw_string
	ctx.debug_draw.DrawTransformFcn = dbg_draw_transform
	ctx.debug_draw.DrawPointFcn = dbg_draw_point
	// ctx.debug_draw.drawBounds = true
	ctx.debug_draw.drawShapes = true
	ctx.debug_draw.useDrawingBounds = false
}

dbg_draw_polygon :: proc "c" (
    vertices: [^]Vec2,
    vertexCount: c.int,
    color: HexColor,
    ctx: rawptr,
) {
    context = runtime.default_context()
    b2_color: u32 = u32(color) << 8 | 255
    k2_color: Color = transmute(Color)b2_color
    for i:c.int; i < vertexCount - 1; i += 1 {
		v1 := vertices[i]
		v2 := vertices[i + 1]
        karl2d.draw_line({v1.x, -v1.y}, {v2.x, -v2.y}, 1, k2_color)
	}
    // connect end points
	v1 := vertices[vertexCount - 1]
	v2 := vertices[0]
    karl2d.draw_line({v1.x, -v1.y}, {v2.x, -v2.y}, 1, k2_color)
}

dbg_draw_polygon_solid :: proc "c" (
    transform: Transform, 
    vertices: [^]Vec2, 
    vertexCount: c.int, 
    radius: f32, 
    color: HexColor, 
    ctx: rawptr,
) {
    context = runtime.default_context()
    if vertexCount < 2 { return }

    b2_color: u32 = u32(color) << 8 | 255
    k2_color: Color = transmute(Color)b2_color
    buffer:[258]Vec2
    for i:i32 = 0; i < vertexCount; i += 1 {
        buffer[i] = (transform.p + b2.RotateVector(transform.q, vertices[i]))
        buffer[i].y *= -1
    }
    for i:i32 = 0; i < vertexCount - 1; i += 1 {
        karl2d.draw_line(buffer[i], buffer[i + 1], 1, k2_color)
    }
    karl2d.draw_line(buffer[0], buffer[vertexCount - 1], 1, k2_color)
    
}

dbg_draw_circle :: proc "c" (
    center: Vec2, 
    radius:f32, 
    color: HexColor,
    ctx: rawptr,
) {
    context = runtime.default_context()
    b2_color: u32 = u32(color) << 8 | 255
    k2_color: Color = transmute(Color)b2_color
    karl2d.draw_circle({center.x, -center.y}, radius, k2_color)
}

dbg_draw_circle_solid :: proc "c" (
    transform: Transform,
    radius:f32, 
    color: HexColor,
    ctx: rawptr,
) {
    context = runtime.default_context()
    b2_color: u32 = u32(color) << 8 | 255
    k2_color: Color = transmute(Color)b2_color
    karl2d.draw_circle({transform.p.x, -transform.p.y}, radius, k2_color)
}

dbg_draw_capsule :: proc "c" (
    p1, p2: Vec2, 
    radius: f32, 
    color: HexColor, 
    ctx: rawptr,
){
    context = runtime.default_context()
    b2_color: u32 = u32(color) << 8 | 255
    k2_color: Color = transmute(Color)b2_color
    karl2d.draw_circle_outline({p1.x, -p1.y}, radius, 1, k2_color)
    karl2d.draw_circle_outline({p2.x, -p2.y}, radius, 1, k2_color)
    karl2d.draw_line({p1.x - radius, -p1.y}, {p2.x - radius, -p2.y}, 1, k2_color)
    karl2d.draw_line({p1.x + radius, -p1.y}, {p2.x + radius, -p2.y}, 1, k2_color)
}

dbg_draw_capsule_solid :: proc "c" (
    p1, p2: Vec2, 
    radius: f32, 
    color: HexColor, 
    ctx: rawptr,
){
    context = runtime.default_context()
    b2_color: u32 = u32(color) << 8 | 255
    k2_color: Color = transmute(Color)b2_color
    karl2d.draw_circle({p1.x, -p1.y}, radius, k2_color)
    karl2d.draw_circle({p2.x, -p2.y}, radius, k2_color)
    karl2d.draw_rect({p1.x - radius, -p1.y, radius * 2, p1.y - p2.y}, k2_color)
}

dbg_draw_segment :: proc "c" (
    p1: Vec2, 
    p2: Vec2, 
    color: HexColor,
    ctx: rawptr,
) {
    context = runtime.default_context()
    b2_color: u32 = u32(color) << 8 | 255
    k2_color: Color = transmute(Color)b2_color
    karl2d.draw_line({p1.x, -p1.y}, {p2.x, -p2.y}, 1, k2_color)
}

dbg_draw_string :: proc "c" (
    p: Vec2, 
    s: cstring,
    color: HexColor,
    ctx: rawptr,
) {
    context = runtime.default_context()
    b2_color: u32 = u32(color) << 8 | 255
    k2_color: Color = transmute(Color)b2_color
    text:string = cast(string)s
    karl2d.draw_text(text, {p.x, -p.y}, 10, k2_color)
}

dbg_draw_transform :: proc "c" (transform: Transform, ctx: rawptr) {
    dbg_draw_segment(transform.p, transform.p + b2.RotateVector(transform.q, {10, 0}), cast(HexColor)0xffffff, ctx)
}

dbg_draw_point :: proc "c" (p: Vec2, size: f32, color: HexColor, ctx: rawptr) {
    context = runtime.default_context()
    b2_color: u32 = u32(color) << 8 | 255
    k2_color: Color = transmute(Color)b2_color
    karl2d.draw_rect({p.x, -p.y, 1, 1}, k2_color)
}