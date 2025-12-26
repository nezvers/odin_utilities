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

state_enter_tests :: proc(){
    test_overlap()
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

    rl.DrawText("OVERLAP", 10, 10, 20, rl.WHITE)
    for i in 0..< len(overlap_results){
        y:i32 = 35 + (i32(i) * 15)
        result_i := int(overlap_results[i].result)
        rl.DrawText(overlap_results[i].name, 10, y, 10, rl.WHITE)
        rl.DrawText(result_string[result_i], 10 + RESULT_OFFSET, y, 10, result_color[result_i])
    }
}

append_result::proc(list:^[dynamic]TestResult, result:TestResult){
    append(list, result)
}

test_overlap::proc(){
    append_result(&overlap_results, {name = "Point to Point 1", result = geometry2d.overlaps_point_point({1000.967, 1000.967}, {1000.967, 1000.967})})
    append_result(&overlap_results, {name = "Point to Point 2", result = !geometry2d.overlaps_point_point({1001.967, 1000.967}, {1000.967, 1000.967})})
    append_result(&overlap_results, {name = "Line to Point 1", result = geometry2d.overlaps_line_point({1000., 1000., 3000., 3000.,}, {2000., 2000.})})
    append_result(&overlap_results, {name = "Line to Point 2", result = !geometry2d.overlaps_line_point({1000., 1000., 3004., 3000.,}, {2000., 2000.})})
    append_result(&overlap_results, {name = "Rectangle to Point 1", result = geometry2d.overlaps_rectangle_point({1000., 1000., 3000., 3000.,}, {3090., 4000.})})
    append_result(&overlap_results, {name = "Rectangle to Point 2", result = !geometry2d.overlaps_rectangle_point({1000., 1000., 3000., 3000.,}, {4000., 4000.001})})
    append_result(&overlap_results, {name = "Circle to Point 1", result = geometry2d.overlaps_circle_point({1000., 1000., 3000.,}, {4000., 1000.})})
    append_result(&overlap_results, {name = "Circle to Point 2", result = !geometry2d.overlaps_circle_point({1000., 1000., 3000.,}, {4000., 1000.8})})
    append_result(&overlap_results, {name = "Triangle to Point 1", result = geometry2d.overlaps_triangle_point({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {1500., 2000.})})
    append_result(&overlap_results, {name = "Triangle to Point 2", result = !geometry2d.overlaps_triangle_point({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {1500., 2000.1})})
    append_result(&overlap_results, {name = "Line to Line 1", result = geometry2d.overlaps_line_line({1000., 1000., 3000., 3000.,}, {1001., 1000., 2000., 3000.,})})
    append_result(&overlap_results, {name = "Line to Line 2", result = geometry2d.overlaps_line_line({1000., 1000., 3000., 3000.,}, {1000., 999., 3000., 3003.,})})
    append_result(&overlap_results, {name = "Line to Line 3", result = !geometry2d.overlaps_line_line({1000., 1000., 3000., 3000.,}, {1000., 1000.01, 3000., 3000.01,})})
    append_result(&overlap_results, {name = "Circle to Line 1", result = geometry2d.overlaps_circle_line({3000., 3000., 2000.,}, {1000., 1000., 3000., 1000.,})})
    append_result(&overlap_results, {name = "Circle to Line 2", result = geometry2d.overlaps_circle_line({3000., 3000., 2000.,}, {1000., 3000., 5000., 3000.,})})
    append_result(&overlap_results, {name = "Circle to Line 3", result = !geometry2d.overlaps_circle_line({3000., 3000., 2000.,}, {5000.01, 3000., 6000., 3000.,})})
    append_result(&overlap_results, {name = "Rectangle to Line 1", result = geometry2d.overlaps_rectangle_line({1000., 1000., 3000., 3000.,}, {999., 1000., 3001., 1000.,})})
    append_result(&overlap_results, {name = "Rectangle to Line 2", result = geometry2d.overlaps_rectangle_line({1000., 1000., 3000., 3000.,}, {1000., 1000., 3000., 900.,})})
    append_result(&overlap_results, {name = "Triangle to Line 1", result = geometry2d.overlaps_triangle_line({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {1000., 3000., 3000., 3000.,})})
    append_result(&overlap_results, {name = "Triangle to Line 2", result = !geometry2d.overlaps_triangle_line({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {1000., 1000.1, 2000., 3000.1,})})
    append_result(&overlap_results, {name = "Circle to Circle 1", result = geometry2d.overlaps_circle_circle({3000., 3000., 2000.,}, {2000., 3000., 500.,})})
    append_result(&overlap_results, {name = "Circle to Circle 2", result = geometry2d.overlaps_circle_circle({3000., 3000., 2000.,}, {7000., 3000., 2000.,})})
    append_result(&overlap_results, {name = "Circle to Circle 3", result = !geometry2d.overlaps_circle_circle({3000., 3000., 2000.,}, {7000.01, 3000., 2000.,})})
    append_result(&overlap_results, {name = "Rectangle to Circle 1", result = geometry2d.overlaps_rectangle_circle({1000., 1000., 3000., 3000.,}, {6000., 2000., 2000.01,})})
    append_result(&overlap_results, {name = "Rectangle to Circle 2", result = !geometry2d.overlaps_rectangle_circle({1000., 1000., 3000., 3000.,}, {6000., 2000., 2000.,})})
    
}

test_intersect::proc(){
}
