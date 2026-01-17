package demo

import geometry2d ".."
import rl "vendor:raylib"
Color :: rl.Color

// DEMO STATE
state_draw_shapes:State = {
    enter = state_enter_draw_shapes,
    exit = state_exit_draw_shapes,
    update = state_update_draw_shapes,
    draw = state_draw_draw_shapes,
}

state_enter_draw_shapes :: proc(){

}

state_exit_draw_shapes :: proc(){

}

state_update_draw_shapes :: proc(){

}

state_draw_draw_shapes :: proc(){
    line:Line = geometry2d.LineNew({100., 100.}, { 200., 100.})
    draw_line(line, rl.WHITE)

    circle:Circle = geometry2d.CircleNew({50., 15.}, 5)
    draw_circle(circle, rl.WHITE)

    rect:Rect = geometry2d.rect_new({70., 10.}, {10., 10.})
    draw_rect(rect, rl.WHITE)

    triangle:Triangle = geometry2d.triangle_new({90., 10.}, {105., 10.}, {97., 20.})
    draw_triangle(triangle, rl.WHITE)

    ray:Ray = geometry2d.RayNew({115., 10.}, {10., 10.})
    draw_ray(ray, rl.WHITE)
}

// DRAW SHAPES
draw_line :: proc(line:Line, color:Color){
    rl.DrawLineV(line.xy, line.zw, color)
}

draw_circle :: proc(circle:Circle, color:Color){
    rl.DrawRingLines(circle.xy, circle.z, circle.z, 0., 360., 20, rl.WHITE)
}

draw_rect :: proc(rect:Rect, color:Color){
    rl.DrawRectangleLines(i32(rect.x), i32(rect.y), i32(rect.z), i32(rect.w), color)
}

draw_triangle :: proc(t:Triangle, color:Color){
    rl.DrawLineV(t[0], t[1], color)
    rl.DrawLineV(t[1], t[2], color)
    rl.DrawLineV(t[2], t[0], color)
}

draw_ray :: proc(ray:Ray, color:Color){
    rl.DrawLineV(ray.xy, ray.xy + ray.zw, color)
}