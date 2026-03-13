package raylib_glue

import b2 "vendor:box2d"
import rl "vendor:raylib"
import "core:c"
import b2_odin ".."

Vec2 :: b2.Vec2
HexColor :: b2.HexColor
Transform :: b2.Transform

WorldInitDebug :: proc( ctx: ^b2_odin.WorldContext) {
	ctx.debug_draw = b2.DefaultDebugDraw()
	ctx.debug_draw.DrawPolygonFcn = dbg_draw_polygon
	ctx.debug_draw.DrawSolidPolygonFcn = dbg_draw_polygon_solid
	ctx.debug_draw.DrawCircleFcn = dbg_draw_circle
	ctx.debug_draw.DrawSegmentFcn = dbg_draw_segment
	ctx.debug_draw.DrawSolidCapsuleFcn = dbg_draw_capsule
	ctx.debug_draw.DrawStringFcn = dbg_draw_string
	ctx.debug_draw.drawBounds = true
	ctx.debug_draw.drawShapes = true
	ctx.debug_draw.useDrawingBounds = false
}

dbg_draw_polygon :: proc "c" (
    vertices: [^]Vec2,
    vertexCount: c.int,
    color: HexColor,
    ctx: rawptr,
) {
    b2_color: u32 = u32(color) << 8 | 255
    rl_color: = rl.GetColor(b2_color)
    for i:c.int; i < vertexCount - 1; i += 1 {
		v1 := vertices[i]
		v2 := vertices[i + 1]
		rl.DrawLineV({v1.x, -v1.y}, {v2.x, -v2.y}, rl_color)
	}
    // connect end points
	v1 := vertices[vertexCount - 1]
	v2 := vertices[0]
	rl.DrawLineV({v1.x, -v1.y}, {v2.x, -v2.y}, rl_color)
}

dbg_draw_polygon_solid :: proc "c" (
    transform: Transform, 
    vertices: [^]Vec2, 
    vertexCount: c.int, 
    radius: f32, 
    color: HexColor, 
    ctx: rawptr,
) {
    b2_color: u32 = u32(color) << 8 | 255
    rl_color: = rl.GetColor(b2_color)
    buffer:[258]rl.Vector2
    for i:i32 = 0; i < vertexCount; i += 1 {
        buffer[i] = (transform.p + b2.RotateVector(transform.q, vertices[i]))
        buffer[i].y *= -1
    }
    rl.DrawTriangle(buffer[0], buffer[1], buffer[2], rl_color)
    rl.DrawTriangle(buffer[0], buffer[2], buffer[3], rl_color)
}

dbg_draw_circle :: proc "c" (
    center: Vec2, 
    radius:f32, 
    color: HexColor,
    ctx: rawptr,
) {
    b2_color: u32 = u32(color) << 8 | 255
    rl_color: = rl.GetColor(b2_color)
    rl.DrawCircleV({center.x, -center.y}, radius, rl_color)
}

dbg_draw_capsule :: proc "c" (
    p1, p2: Vec2, 
    radius: f32, 
    color: HexColor, 
    ctx: rawptr,
){
    b2_color: u32 = u32(color) << 8 | 255
    rl_color: = rl.GetColor(b2_color)
    rl.DrawCircleLinesV({p1.x, -p1.y}, radius, rl_color)
    rl.DrawCircleLinesV({p2.x, -p2.y}, radius, rl_color)
    rl.DrawLineV({p1.x - radius, -p1.y}, {p2.x - radius, -p2.y}, rl_color)
    rl.DrawLineV({p1.x + radius, -p1.y}, {p2.x + radius, -p2.y}, rl_color)
}

dbg_draw_segment :: proc "c" (
    p1: Vec2, 
    p2: Vec2, 
    color: HexColor,
    ctx: rawptr,
) {
    b2_color: u32 = u32(color) << 8 | 255
    rl_color: = rl.GetColor(b2_color)
	rl.DrawLineV({p1.x, -p1.y}, {p2.x, -p2.y}, rl_color)
}

dbg_draw_string :: proc "c" (
    p: Vec2, 
    s: cstring,
    color: HexColor,
    ctx: rawptr,
) {
    b2_color: u32 = u32(color) << 8 | 255
    rl_color: = rl.GetColor(b2_color)
    rl.DrawText(s, cast(c.int)p.x, cast(c.int)-p.y, 10, rl_color)
}