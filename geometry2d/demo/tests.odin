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

append_result::proc(result:TestResult){
    append(&overlap_results, result)
}

test_overlap::proc(){
    append_result({name = "Point to Point 1", result = geometry2d.overlaps_point_point({1000.967, 1000.967}, {1000.967, 1000.967})})
    append_result({name = "Point to Point 2", result = !geometry2d.overlaps_point_point({1001.967, 1000.967}, {1000.967, 1000.967})})
    append_result({name = "Line to Point 1", result = geometry2d.overlaps_line_point({1000., 1000., 3000., 3000.,}, {2000., 2000.})})
    append_result({name = "Line to Point 2", result = !geometry2d.overlaps_line_point({1000., 1000., 3004., 3000.,}, {2000., 2000.})})
    append_result({name = "Rectangle to Point 1", result = geometry2d.overlaps_rectangle_point({1000., 1000., 3000., 3000.,}, {3090., 4000.})})
    append_result({name = "Rectangle to Point 2", result = !geometry2d.overlaps_rectangle_point({1000., 1000., 3000., 3000.,}, {4000., 4000.001})})
    append_result({name = "Circle to Point 1", result = geometry2d.overlaps_circle_point({1000., 1000., 3000.,}, {4000., 1000.})})
    append_result({name = "Circle to Point 2", result = !geometry2d.overlaps_circle_point({1000., 1000., 3000.,}, {4000., 1000.8})})

}
