package demo

import geometry2d ".."
import rl "vendor:raylib"

// DEMO STATE
state_tests:State = {
    enter = state_enter_tests,
    exit = state_exit_tests,
    update = state_update_tests,
    draw = state_draw_tests,
}

TestResult :: struct{
    name:cstring,
    result:bool,
}

overlap_results: [dynamic]TestResult
contains_results: [dynamic]TestResult

state_enter_tests :: proc(){
    test_overlap()
    test_contains()
}

state_exit_tests :: proc(){

}

state_update_tests :: proc(){

}

state_draw_tests :: proc(){
    RESULT_OFFSET :: 150
    result_string: []cstring = {
        "FAILED",
        "PASSED",
    }
    result_color: []Color = {rl.RED, rl.LIME}

    x:i32 = 10
    y:i32 = 10
    rl.DrawText("OVERLAP", x, y, 20, rl.WHITE)
    y += 25
    for i in 0..< len(overlap_results){
        y += 15
        result_i := int(overlap_results[i].result)
        rl.DrawText(overlap_results[i].name, x, y, 10, rl.WHITE)
        rl.DrawText(result_string[result_i], x + RESULT_OFFSET, y, 10, result_color[result_i])
    }

    x = 220
    y = 10
    rl.DrawText("CONTAINS", x, y, 20, rl.WHITE)
    y += 25
    for i in 0..< len(contains_results){
        y += 15
        result_i := int(contains_results[i].result)
        rl.DrawText(contains_results[i].name, x, y, 10, rl.WHITE)
        rl.DrawText(result_string[result_i], x + RESULT_OFFSET, y, 10, result_color[result_i])
    }

    
}

append_result::proc(list:^[dynamic]TestResult, result:TestResult){
    append(list, result)
}

test_overlap::proc(){
    append_result(&overlap_results, {name = "Point: Point 1", result = geometry2d.overlaps_point_point({1000.967, 1000.967}, {1000.967, 1000.967})})
    append_result(&overlap_results, {name = "Point: Point 2", result = !geometry2d.overlaps_point_point({1001.967, 1000.967}, {1000.967, 1000.967})})
    append_result(&overlap_results, {name = "Line: Point 1", result = geometry2d.overlaps_line_point({1000., 1000., 3000., 3000.,}, {2000., 2000.})})
    append_result(&overlap_results, {name = "Line: Point 2", result = !geometry2d.overlaps_line_point({1000., 1000., 3004., 3000.,}, {2000., 2000.})})
    append_result(&overlap_results, {name = "Line: Line 1", result = geometry2d.overlaps_line_line({1000., 1000., 3000., 3000.,}, {1001., 1000., 2000., 3000.,})})
    append_result(&overlap_results, {name = "Line: Line 2", result = geometry2d.overlaps_line_line({1000., 1000., 3000., 3000.,}, {1000., 999., 3000., 3003.,})})
    append_result(&overlap_results, {name = "Line: Line 3", result = !geometry2d.overlaps_line_line({1000., 1000., 3000., 3000.,}, {1000., 1000.01, 3000., 3000.01,})})
    append_result(&overlap_results, {name = "Circle: Point 1", result = geometry2d.overlaps_circle_point({1000., 1000., 3000.,}, {4000., 1000.})})
    append_result(&overlap_results, {name = "Circle: Point 2", result = !geometry2d.overlaps_circle_point({1000., 1000., 3000.,}, {4000., 1000.8})})
    append_result(&overlap_results, {name = "Circle: Line 1", result = geometry2d.overlaps_circle_line({3000., 3000., 2000.,}, {1000., 1000., 3000., 1000.,})})
    append_result(&overlap_results, {name = "Circle: Line 2", result = geometry2d.overlaps_circle_line({3000., 3000., 2000.,}, {1000., 3000., 5000., 3000.,})})
    append_result(&overlap_results, {name = "Circle: Line 3", result = !geometry2d.overlaps_circle_line({3000., 3000., 2000.,}, {5000.01, 3000., 6000., 3000.,})})
    append_result(&overlap_results, {name = "Circle: Circle 1", result = geometry2d.overlaps_circle_circle({3000., 3000., 2000.,}, {2000., 3000., 500.,})})
    append_result(&overlap_results, {name = "Circle: Circle 2", result = geometry2d.overlaps_circle_circle({3000., 3000., 2000.,}, {7000., 3000., 2000.,})})
    append_result(&overlap_results, {name = "Circle: Circle 3", result = !geometry2d.overlaps_circle_circle({3000., 3000., 2000.,}, {7000.01, 3000., 2000.,})})
    // TODO: Circle Rectangle
    // TODO: Circle Triangle
    append_result(&overlap_results, {name = "Rectangle: Point 1", result = geometry2d.overlaps_rectangle_point({1000., 1000., 3000., 3000.,}, {3090., 4000.})})
    append_result(&overlap_results, {name = "Rectangle: Point 2", result = !geometry2d.overlaps_rectangle_point({1000., 1000., 3000., 3000.,}, {4000., 4000.001})})
    append_result(&overlap_results, {name = "Rectangle: Line 1", result = geometry2d.overlaps_rectangle_line({1000., 1000., 3000., 3000.,}, {999., 1000., 3001., 1000.,})})
    append_result(&overlap_results, {name = "Rectangle: Line 2", result = geometry2d.overlaps_rectangle_line({1000., 1000., 3000., 3000.,}, {1000., 1000., 3000., 900.,})})
    append_result(&overlap_results, {name = "Rectangle: Circle 1", result = geometry2d.overlaps_rectangle_circle({1000., 1000., 3000., 3000.,}, {6000., 2000., 2000.01,})})
    append_result(&overlap_results, {name = "Rectangle: Circle 2", result = !geometry2d.overlaps_rectangle_circle({1000., 1000., 3000., 3000.,}, {6000., 2000., 2000.,})})
    // TODO: Rectangle Triangle
    append_result(&overlap_results, {name = "Triangle: Point 1", result = geometry2d.overlaps_triangle_point({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {1500., 2000.})})
    append_result(&overlap_results, {name = "Triangle: Point 2", result = !geometry2d.overlaps_triangle_point({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {1500., 2000.1})})
    append_result(&overlap_results, {name = "Triangle: Line 1", result = geometry2d.overlaps_triangle_line({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {1000., 3000., 3000., 3000.,})})
    append_result(&overlap_results, {name = "Triangle: Line 2", result = !geometry2d.overlaps_triangle_line({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {1000., 1000.1, 2000., 3000.1,})})
    append_result(&overlap_results, {name = "Triangle: Line 3", result = !geometry2d.overlaps_triangle_line({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, geometry2d.rect_left({3000.1, 999., 3000., 3000.,}))})
    append_result(&overlap_results, {name = "Triangle: Circle 1", result = geometry2d.overlaps_triangle_circle({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {5000., 1000., 2000.,})})
    append_result(&overlap_results, {name = "Triangle: Circle 2", result = !geometry2d.overlaps_triangle_circle({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {5000.01, 1000., 2000.,})})
    append_result(&overlap_results, {name = "Triangle: Rectangle 1", result = geometry2d.overlaps_triangle_rectangle({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {3000., 999., 3000., 3000.,})})
    append_result(&overlap_results, {name = "Triangle: Rectangle 2", result = !geometry2d.overlaps_triangle_rectangle({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {3000.1, 999., 3000., 3000.,})})
    append_result(&overlap_results, {name = "Triangle: Triangle 1", result = geometry2d.overlaps_triangle_triangle({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {{3000., 1000.}, {5000., 1000.}, {4000., 3000.}, })})
    append_result(&overlap_results, {name = "Triangle: Triangle 2", result = !geometry2d.overlaps_triangle_triangle({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {{3000.01, 1000.}, {5000., 1000.}, {4000., 3000.}, })})
}

test_contains::proc(){
    append_result(&contains_results, {name = "Point: Point 1", result = geometry2d.contains_point_point({1000.967, 1000.967}, {1000.967, 1000.967})})
    append_result(&contains_results, {name = "Point: Point 2", result = !geometry2d.contains_point_point({1000.967, 1000.967}, {1000.867, 1000.967})})
    append_result(&contains_results, {name = "Line: Point 1", result = geometry2d.contains_line_point({1000., 1000., 3000., 3000.,}, {2000., 2000.})})
    append_result(&contains_results, {name = "Line: Point 2", result = !geometry2d.contains_line_point({1000., 1000., 3000., 3000.,}, {2000.01, 2000.})})
    append_result(&contains_results, {name = "Line: Line 1", result = geometry2d.contains_line_line({1000., 1000., 3000., 3000.,}, {1001., 1001., 2000., 2000.,})})
    append_result(&contains_results, {name = "Line: Line 2", result = !geometry2d.contains_line_line({1000., 1000., 3000., 3000.,}, {1001., 1001., 2000., 2000.01,})})
    append_result(&contains_results, {name = "Circle: Point 1", result = geometry2d.contains_circle_point({1000., 1000., 3000.,}, {4000., 1000.})})
    append_result(&contains_results, {name = "Circle: Point 2", result = !geometry2d.contains_circle_point({1000., 1000., 3000.,}, {4000., 1000.8})})
    append_result(&contains_results, {name = "Circle: Line 1", result = geometry2d.contains_circle_line({3000., 3000., 2000.,}, {1000., 3000., 5000., 3000.,})})
    append_result(&contains_results, {name = "Circle: Line 2", result = !geometry2d.contains_circle_line({3000., 3000., 2000.,}, {1000., 3001., 5000., 3001.,})})
    append_result(&contains_results, {name = "Circle: Circle 1", result = geometry2d.contains_circle_circle({3000., 3000., 2000.,}, {2000., 3000., 500.,})})
    append_result(&contains_results, {name = "Circle: Circle 2", result = !geometry2d.contains_circle_circle({3000., 3000., 2000.,}, {2000., 3000., 2000.,})})
    append_result(&contains_results, {name = "Circle: Circle 3", result = !geometry2d.contains_circle_circle({3000., 3000., 2000.,}, {5001., 3000., 2000.,})})
    // TODO: Circle Rectangle
    // TODO: Circle Triangle
    append_result(&contains_results, {name = "Rectangle: Point 1", result = geometry2d.contains_rectangle_point({1000., 1000., 3000., 3000.,}, {3090., 4000.})})
    append_result(&contains_results, {name = "Rectangle: Point 2", result = !geometry2d.contains_rectangle_point({1000., 1000., 3000., 3000.,}, {4000., 4000.001})})
    append_result(&contains_results, {name = "Rectangle: Line 1", result = geometry2d.contains_rectangle_line({1000., 1000., 3000., 3000.,}, {1000., 1000., 4000., 4000.,})})
    append_result(&contains_results, {name = "Rectangle: Line 2", result = geometry2d.contains_rectangle_line({1000., 1000., 3000., 3000.,}, {1000., 1000., 4000., 1000.,})})
    append_result(&contains_results, {name = "Rectangle: Line 3", result = !geometry2d.contains_rectangle_line({1000., 1000., 3000., 3000.,}, {1000., 1000., 4000.01, 1000.,})})
    append_result(&contains_results, {name = "Rectangle: Circle 1", result = geometry2d.contains_rectangle_circle({1000., 1000., 3000., 3000.,}, {2000., 2000., 1000.,})})
    append_result(&contains_results, {name = "Rectangle: Circle 2", result = !geometry2d.contains_rectangle_circle({1000., 1000., 3000., 3000.,}, {2000., 2000., 2000.,})})
    // TODO: Rectangle Triangle
    append_result(&contains_results, {name = "Triangle: Point 1", result = geometry2d.contains_triangle_point({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {1500., 2000.})})
    append_result(&contains_results, {name = "Triangle: Point 2", result = !geometry2d.contains_triangle_point({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {1500., 2000.1})})
    append_result(&contains_results, {name = "Triangle: Line 1", result = geometry2d.contains_triangle_line({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {1000., 1000., 3000., 1000.,})})
    append_result(&contains_results, {name = "Triangle: Line 2", result = !geometry2d.contains_triangle_line({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {1000., 1000., 3000., 1000.01,})})
    append_result(&contains_results, {name = "Triangle: Circle 1", result = geometry2d.contains_triangle_circle({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {2000., 2000., 500.,})})
    append_result(&contains_results, {name = "Triangle: Circle 2", result = !geometry2d.contains_triangle_circle({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {5000.01, 1000., 2000.,})})
    append_result(&contains_results, {name = "Triangle: Rectangle 1", result = geometry2d.contains_triangle_rectangle({{1000., 1000.}, {3000., 1000.}, {1000., 3000.}, }, {1000., 1000., 1000., 1000.,})})
    append_result(&contains_results, {name = "Triangle: Rectangle 2", result = !geometry2d.contains_triangle_rectangle({{1000., 1000.}, {3000., 1000.}, {1000., 3000.}, }, {1000., 1000., 1000., 2000.,})})
    append_result(&contains_results, {name = "Triangle: Triangle 1", result = geometry2d.contains_triangle_triangle({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {{1000., 1000.}, {3000., 1000.}, {2000., 2999.}, })})
    append_result(&contains_results, {name = "Triangle: Triangle 2", result = !geometry2d.contains_triangle_triangle({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {{1000., 1000.}, {3000., 1000.}, {2000., 3001.}, })})
}
