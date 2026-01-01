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
intersects_results: [dynamic]TestResult

state_enter_tests :: proc(){
    test_overlap()
    test_contains()
    test_intersects()
}

state_exit_tests :: proc(){

}

state_update_tests :: proc(){

}

state_draw_tests :: proc(){
    RESULT_OFFSET :: 120
    COLUMN_OFFSET :: 200
    ROW_OFFSET_TITLE :: 25
    ROW_OFFSET_TEST :: 15
    TOP_Y :: 10
    FONT_SIZE_TITLE :: 20
    FONT_SIZE_TEST :: 10
    result_string: []cstring = {
        "FAILED",
        "PASSED",
    }
    result_color: []Color = {rl.RED, rl.LIME}

    x:i32 = 10
    y:i32 = TOP_Y
    rl.DrawText("OVERLAP", x, y, FONT_SIZE_TITLE, rl.WHITE)
    y += ROW_OFFSET_TITLE
    for i in 0..< len(overlap_results){
        y += ROW_OFFSET_TEST
        result_i := int(overlap_results[i].result)
        rl.DrawText(overlap_results[i].name, x, y, FONT_SIZE_TEST, rl.WHITE)
        rl.DrawText(result_string[result_i], x + RESULT_OFFSET, y, FONT_SIZE_TEST, result_color[result_i])
    }

    x += COLUMN_OFFSET
    y = TOP_Y
    rl.DrawText("CONTAINS", x, y, FONT_SIZE_TITLE, rl.WHITE)
    y += ROW_OFFSET_TITLE
    for i in 0..< len(contains_results){
        y += ROW_OFFSET_TEST
        result_i := int(contains_results[i].result)
        rl.DrawText(contains_results[i].name, x, y, FONT_SIZE_TEST, rl.WHITE)
        rl.DrawText(result_string[result_i], x + RESULT_OFFSET, y, FONT_SIZE_TEST, result_color[result_i])
    }

    x += COLUMN_OFFSET
    y = TOP_Y
    rl.DrawText("INTERSECTS", x, y, FONT_SIZE_TITLE, rl.WHITE)
    y += ROW_OFFSET_TITLE
    for i in 0..< len(intersects_results){
        y += ROW_OFFSET_TEST
        result_i := int(intersects_results[i].result)
        rl.DrawText(intersects_results[i].name, x, y, FONT_SIZE_TEST, rl.WHITE)
        rl.DrawText(result_string[result_i], x + RESULT_OFFSET, y, FONT_SIZE_TEST, result_color[result_i])
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
    append_result(&overlap_results, {name = "Circle: Rectangle 1", result = geometry2d.overlaps_circle_rectangle({3000., 3000., 2000.,}, {4900., 2000., 2000., 2000.,})})
    append_result(&overlap_results, {name = "Circle: Rectangle 2", result = !geometry2d.overlaps_circle_rectangle({3000., 3000., 2000.,}, {5000.01, 2000., 2000., 2000.,})})
    append_result(&overlap_results, {name = "Circle: Triangle 1", result = geometry2d.overlaps_circle_triangle({3000., 3000., 2000.,}, {{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, })})
    append_result(&overlap_results, {name = "Circle: Triangle 2", result = !geometry2d.overlaps_circle_triangle({5000.01, 1000., 2000.,}, {{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, })})
    append_result(&overlap_results, {name = "Rectangle: Point 1", result = geometry2d.overlaps_rectangle_point({1000., 1000., 3000., 3000.,}, {3090., 4000.})})
    append_result(&overlap_results, {name = "Rectangle: Point 2", result = !geometry2d.overlaps_rectangle_point({1000., 1000., 3000., 3000.,}, {4000., 4000.001})})
    append_result(&overlap_results, {name = "Rectangle: Line 1", result = geometry2d.overlaps_rectangle_line({1000., 1000., 3000., 3000.,}, {999., 1000., 3001., 1000.,})})
    append_result(&overlap_results, {name = "Rectangle: Line 2", result = geometry2d.overlaps_rectangle_line({1000., 1000., 3000., 3000.,}, {1000., 1000., 3000., 900.,})})
    append_result(&overlap_results, {name = "Rectangle: Circle 1", result = geometry2d.overlaps_rectangle_circle({1000., 1000., 3000., 3000.,}, {6000., 2000., 2000.01,})})
    append_result(&overlap_results, {name = "Rectangle: Circle 2", result = !geometry2d.overlaps_rectangle_circle({1000., 1000., 3000., 3000.,}, {6000., 2000., 2000.,})})
    append_result(&overlap_results, {name = "Rectangle: Triangle 1", result = geometry2d.overlaps_rectangle_triangle({1000., 1000., 3000., 3000.,}, {{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, })})
    append_result(&overlap_results, {name = "Rectangle: Triangle 2", result = !geometry2d.overlaps_rectangle_triangle({3000.01, 1000., 3000., 3000.,}, {{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, })})
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
    append_result(&contains_results, {name = "Circle: Rectangle 1", result = geometry2d.contains_circle_rectangle({3000., 3000., 2000.,}, {2000., 2000., 2000., 2000.,})})
    append_result(&contains_results, {name = "Circle: Rectangle 2", result = !geometry2d.contains_circle_rectangle({3000., 3000., 2000.,}, {1200., 2000., 2000., 2000.,})})
    append_result(&contains_results, {name = "Circle: Triangle 1", result = geometry2d.contains_circle_triangle({2000., 3000., 3000.,}, {{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, })})
    append_result(&contains_results, {name = "Circle: Triangle 2", result = !geometry2d.contains_circle_triangle({3000., 3000., 2000.,}, {{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, })})
    append_result(&contains_results, {name = "Rectangle: Point 1", result = geometry2d.contains_rectangle_point({1000., 1000., 3000., 3000.,}, {3090., 4000.})})
    append_result(&contains_results, {name = "Rectangle: Point 2", result = !geometry2d.contains_rectangle_point({1000., 1000., 3000., 3000.,}, {4000., 4000.001})})
    append_result(&contains_results, {name = "Rectangle: Line 1", result = geometry2d.contains_rectangle_line({1000., 1000., 3000., 3000.,}, {1000., 1000., 4000., 4000.,})})
    append_result(&contains_results, {name = "Rectangle: Line 2", result = geometry2d.contains_rectangle_line({1000., 1000., 3000., 3000.,}, {1000., 1000., 4000., 1000.,})})
    append_result(&contains_results, {name = "Rectangle: Line 3", result = !geometry2d.contains_rectangle_line({1000., 1000., 3000., 3000.,}, {1000., 1000., 4000.01, 1000.,})})
    append_result(&contains_results, {name = "Rectangle: Circle 1", result = geometry2d.contains_rectangle_circle({1000., 1000., 3000., 3000.,}, {2000., 2000., 1000.,})})
    append_result(&contains_results, {name = "Rectangle: Circle 2", result = !geometry2d.contains_rectangle_circle({1000., 1000., 3000., 3000.,}, {2000., 2000., 2000.,})})
    append_result(&contains_results, {name = "Rectangle: Triangle 1", result = geometry2d.contains_rectangle_triangle({1000., 1000., 3000., 3000.,}, {{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, })})
    append_result(&contains_results, {name = "Rectangle: Triangle 2", result = !geometry2d.contains_rectangle_triangle({1000., 1000., 1900., 3000.,}, {{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, })})
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

// TODO: intersect filter duplicate
test_intersects::proc(){
    point_count:int
    _, point_count = geometry2d.intersects_point_point({1000.967, 1000.967}, {1000.967, 1000.967})
    append_result(&intersects_results, {name = "Point: Point 1",        result = point_count == 1})
    _, point_count = geometry2d.intersects_point_point({1000.967, 1000.967}, {1000.867, 1000.967})
    append_result(&intersects_results, {name = "Point: Point 2",        result = point_count == 0})
    _, point_count = geometry2d.intersects_line_point({1000., 1000., 3000., 3000.,}, {2000., 2000.})
    append_result(&intersects_results, {name = "Line: Point 1",         result = point_count == 1})
    _, point_count = geometry2d.intersects_line_point({1000., 1000., 3000., 3000.,}, {2000.01, 2000.})
    append_result(&intersects_results, {name = "Line: Point 2",         result = point_count == 0})
    _, point_count = geometry2d.intersects_line_line({1000., 1000., 3000., 3000.,}, {1001., 1001., 2000., 2000.,})
    append_result(&intersects_results, {name = "Line: Line 1",          result = point_count == 0})
    _, point_count = geometry2d.intersects_line_line({1000., 1000., 3000., 3000.,}, {1000., 1000.01, 2000., 2000.01,})
    append_result(&intersects_results, {name = "Line: Line 2",          result = point_count == 0})

    _, point_count = geometry2d.intersects_line_line({2000., 2000., 4000., 2000.,}, {1000., 3000., 5000., 3000.,})
    append_result(&intersects_results, {name = "Line: Line 3",          result = point_count == 0})
    _, point_count = geometry2d.intersects_line_line({2000., 2000., 2000., 4000.,}, {1000., 3000., 5000., 3000.,})
    append_result(&intersects_results, {name = "Line: Line 4",          result = point_count == 1})
    _, point_count = geometry2d.intersects_line_line({4000., 2000., 4000., 4000.,}, {1000., 3000., 5000., 3000.,})
    append_result(&intersects_results, {name = "Line: Line 5",          result = point_count == 1})
    _, point_count = geometry2d.intersects_line_line({2000., 4000., 4000., 4000.,}, {1000., 3000., 5000., 3000.,})
    append_result(&intersects_results, {name = "Line: Line 6",          result = point_count == 0})

    _, point_count = geometry2d.intersects_circle_point({1000., 1000., 3000.,}, {4000., 1000.})
    append_result(&intersects_results, {name = "Circle: Point 1",       result = point_count == 1})
    _, point_count = geometry2d.intersects_circle_point({1000., 1000., 3000.,}, {4000.01, 1000.})
    append_result(&intersects_results, {name = "Circle: Point 2",       result = point_count == 0})
    _, point_count = geometry2d.intersects_circle_line({3000., 3000., 2000.,}, {1000., 2000., 5000., 2000.,})
    append_result(&intersects_results, {name = "Circle: Line 1",        result = point_count == 2})
    _, point_count = geometry2d.intersects_circle_line({3000., 3000., 2000.,}, {1000., 5000., 5000., 5000.01,})
    append_result(&intersects_results, {name = "Circle: Line 2",        result = point_count == 0})
    _, point_count = geometry2d.intersects_circle_circle({3000., 3000., 2000.,}, {1000., 3000., 2000.,})
    append_result(&intersects_results, {name = "Circle: Circle 1",      result = point_count == 2})
    _, point_count = geometry2d.intersects_circle_circle({3000., 3000., 2000.,}, {3000., 3000., 1000.,})
    append_result(&intersects_results, {name = "Circle: Circle 2",      result = point_count == 0})
    _, point_count = geometry2d.intersects_circle_rectangle({3000., 3000., 2000.,}, {3000., 3000., 3000., 3000.,})
    append_result(&intersects_results, {name = "Circle: Rectangle 1",   result = point_count == 2})
    _, point_count = geometry2d.intersects_circle_rectangle({3000., 3000., 3000.,}, {2000., 2000., 2000., 2000.,})
    append_result(&intersects_results, {name = "Circle: Rectangle 2",   result = point_count == 0})
    _, point_count = geometry2d.intersects_circle_triangle({2000., 3000., 1000.,}, {{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, })
    append_result(&intersects_results, {name = "Circle: Triangle 1",    result = point_count == 2})
    _, point_count = geometry2d.intersects_circle_triangle({3000., 3000., 4000.,}, {{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, })
    append_result(&intersects_results, {name = "Circle: Triangle 2",    result = point_count == 0})
    _, point_count = geometry2d.intersects_rectangle_point({1000., 1000., 3000., 3000.,}, {2000., 2000.})
    append_result(&intersects_results, {name = "Rectangle: Point 1",    result = point_count == 1})
    _, point_count = geometry2d.intersects_rectangle_point({1000., 1000., 3000., 3000.,}, {4000.01, 2000.})
    append_result(&intersects_results, {name = "Rectangle: Point 2",    result = point_count == 0})
    _, point_count = geometry2d.intersects_rectangle_line({2000., 2000., 2000., 2000.,}, {1000., 3000., 5000., 2000.,})
    append_result(&intersects_results, {name = "Rectangle: Line 1",     result = point_count == 2})
    _, point_count = geometry2d.intersects_rectangle_line({1000., 1000., 3000., 3000.,}, {2000., 2000., 3000., 3000.,})
    append_result(&intersects_results, {name = "Rectangle: Line 2",     result = point_count == 0})
    append_result(&intersects_results, {name = "Rectangle: Circle 1",   result = false}) //geometry2d.intersects_rectangle_circle({1000., 1000., 3000., 3000.,}, {2000., 2000., 1000.,})})
    append_result(&intersects_results, {name = "Rectangle: Circle 2",   result = false}) //!geometry2d.intersects_rectangle_circle({1000., 1000., 3000., 3000.,}, {2000., 2000., 2000.,})})
    append_result(&intersects_results, {name = "Rectangle: Triangle 1", result = false}) //geometry2d.intersects_rectangle_triangle({1000., 1000., 3000., 3000.,}, {{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, })})
    append_result(&intersects_results, {name = "Rectangle: Triangle 2", result = false}) //!geometry2d.intersects_rectangle_triangle({1000., 1000., 1900., 3000.,}, {{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, })})
    append_result(&intersects_results, {name = "Triangle: Point 1",     result = false}) //geometry2d.intersects_triangle_point({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {1500., 2000.})})
    append_result(&intersects_results, {name = "Triangle: Point 2",     result = false}) //!geometry2d.intersects_triangle_point({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {1500., 2000.1})})
    append_result(&intersects_results, {name = "Triangle: Line 1",      result = false}) //geometry2d.intersects_triangle_line({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {1000., 1000., 3000., 1000.,})})
    append_result(&intersects_results, {name = "Triangle: Line 2",      result = false}) //!geometry2d.intersects_triangle_line({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {1000., 1000., 3000., 1000.01,})})
    append_result(&intersects_results, {name = "Triangle: Circle 1",    result = false}) //geometry2d.intersects_triangle_circle({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {2000., 2000., 500.,})})
    append_result(&intersects_results, {name = "Triangle: Circle 2",    result = false}) //!geometry2d.intersects_triangle_circle({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {5000.01, 1000., 2000.,})})
    append_result(&intersects_results, {name = "Triangle: Rectangle 1", result = false}) //geometry2d.intersects_triangle_rectangle({{1000., 1000.}, {3000., 1000.}, {1000., 3000.}, }, {1000., 1000., 1000., 1000.,})})
    append_result(&intersects_results, {name = "Triangle: Rectangle 2", result = false}) //!geometry2d.intersects_triangle_rectangle({{1000., 1000.}, {3000., 1000.}, {1000., 3000.}, }, {1000., 1000., 1000., 2000.,})})
    append_result(&intersects_results, {name = "Triangle: Triangle 1",  result = false}) //geometry2d.intersects_triangle_triangle({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {{1000., 1000.}, {3000., 1000.}, {2000., 2999.}, })})
    append_result(&intersects_results, {name = "Triangle: Triangle 2",  result = false}) //!geometry2d.intersects_triangle_triangle({{1000., 1000.}, {3000., 1000.}, {2000., 3000.}, }, {{1000., 1000.}, {3000., 1000.}, {2000., 3001.}, })})
}
