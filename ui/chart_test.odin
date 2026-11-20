#+build !js
package ui

import "core:testing"

@(private = "file")
measure :: proc(ctx: ^Context, text: string, font_size: f32) -> Vec2 {
    return {f32(len(text)) * font_size * 0.5, font_size}
}

@(test)
test_chart_steps_are_round_numbers :: proc(t: ^testing.T) {
    testing.expect_value(t, ChartStep(100), 20)
    testing.expect_value(t, ChartStep(7), 2)
    testing.expect_value(t, ChartStep(42), 10)
    testing.expect_value(t, ChartStep(5), 1)
    testing.expect(t, abs(ChartStep(0.9) - 0.2) < 1e-6)
    testing.expect_value(t, ChartStep(3000), 1000)
    testing.expect_value(t, ChartStep(0), 1)
    testing.expect_value(t, ChartStep(-5), 1)
}

@(test)
test_chart_axes_cover_the_series_with_round_numbers :: proc(t: ^testing.T) {
    points: [4]ChartPoint = {{0, 12}, {1, 87}, {2, 40}, {3, 55}}
    series: [1]ChartSeries = {{name = "a", points = points[:]}}
    view: ChartView
    ChartViewInit(&view)
    view.series = series[:]
    view.kind = .LINE
    ChartBounds(&view)
    testing.expect_value(t, view.low, ChartPoint{0, 0})
    testing.expect_value(t, view.high, ChartPoint{3, 100})
    testing.expect_value(t, view.y_step, 20)
    testing.expect_value(t, view.y_ticks, 6)

    // the corners of the plot are the corners of the range, y goes up
    plot: Rect = {100, 50, 300, 200}
    testing.expect_value(t, ChartPosition(&view, plot, {0, 0}), Vec2{100, 250})
    testing.expect_value(t, ChartPosition(&view, plot, {3, 100}), Vec2{400, 50})
    testing.expect_value(t, ChartPosition(&view, plot, {1.5, 50}), Vec2{250, 150})

    // a line that does not come near 0 does not start there, a bar chart does: its bars stand on 0
    high_points: [3]ChartPoint = {{0, 1010}, {1, 1040}, {2, 1090}}
    series[0].points = high_points[:]
    ChartBounds(&view)
    testing.expect_value(t, view.low.y, 1000)
    testing.expect_value(t, view.high.y, 1100)
    view.kind = .BAR
    ChartBounds(&view)
    testing.expect_value(t, view.low.y, 0)
    // values under 0 are in the range, one value alone and no value at all still give an axis
    low_points: [2]ChartPoint = {{0, -30}, {1, 20}}
    series[0].points = low_points[:]
    view.kind = .LINE
    ChartBounds(&view)
    testing.expect(t, view.low.y <= -30 && view.high.y >= 20)
    series[0].points = low_points[:1]
    ChartBounds(&view)
    testing.expect(t, view.high.y > view.low.y && view.high.x > view.low.x)
    view.series = nil
    ChartBounds(&view)
    testing.expect(t, view.high.y > view.low.y && view.y_ticks >= 2)

    // the plot leaves room for the numbers, the names and (two series or more) the legend
    view.series = series[:]
    one: Rect = ChartPlotRect(&view, {0, 0, 400, 300}, 16)
    testing.expect(t, one.x > 30 && one.y > 0 && one.x + one.z < 400 && one.y + one.w < 290)
    two_series: [2]ChartSeries = {series[0], series[0]}
    view.series = two_series[:]
    two: Rect = ChartPlotRect(&view, {0, 0, 400, 300}, 16)
    testing.expect(t, two.y > one.y, "the legend takes room at the top")
}

@(test)
test_bars_of_the_series_stand_side_by_side_on_zero :: proc(t: ^testing.T) {
    a: [3]ChartPoint = {{0, 10}, {1, 20}, {2, 30}}
    b: [3]ChartPoint = {{0, 30}, {1, -10}, {2, 15}}
    series: [2]ChartSeries = {{name = "a", points = a[:]}, {name = "b", points = b[:]}}
    view: ChartView
    ChartViewInit(&view)
    view.series = series[:]
    view.kind = .BAR
    ChartBounds(&view)
    plot: Rect = {0, 0, 300, 200}
    testing.expect_value(t, ChartSlotWidth(&view, plot), 100)
    zero: f32 = ChartPosition(&view, plot, {0, 0}).y
    first: Rect = ChartBarRect(&view, plot, 0, 0)
    second: Rect = ChartBarRect(&view, plot, 1, 0)
    // both in the first slot, the second one right of the first, both on the line of 0
    testing.expect(t, first.x >= 0 && second.x + second.z <= 100)
    testing.expect(t, second.x >= first.x + first.z)
    testing.expect(t, abs(first.y + first.w - zero) < 0.01 && abs(second.y + second.w - zero) < 0.01)
    testing.expect(t, second.w > first.w * 2.9, "30 is three times as high as 10")
    // a value under 0 hangs from the line of 0
    under: Rect = ChartBarRect(&view, plot, 1, 1)
    testing.expect(t, abs(under.y - zero) < 0.01 && under.w > 0)
    // the last bar is inside of the plot
    last: Rect = ChartBarRect(&view, plot, 1, 2)
    testing.expect(t, last.x + last.z <= 300)
}

@(private = "file")
ChartTest :: struct {
    storage: Storage(64, 128, 32, 1024),
    ctx: Context,
    style: Style,
    view: ChartView,
    picked: int,
    last: ChartHit,
    sales: [4]ChartPoint,
    costs: [4]ChartPoint,
    series: [2]ChartSeries,         // kept here: the view holds the slice until the frame is drawn, and the test reads it after the frame
    kind: ChartKind,
}

@(private = "file")
chartFrame :: proc(test: ^ChartTest, input: Input) {
    UiBegin(&test.ctx, input, 1.0 / 60, {800, 600}, &test.style)
    if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(700), {}}) {
        test.series = {{name = "Sales", points = test.sales[:]}, {name = "Costs", points = test.costs[:]}}
        if hit, picked := UiChart(&test.ctx, "chart", &test.view, test.series[:], test.kind, nil, {Fixed(600), Fixed(300)}); picked {
            test.picked += 1
            test.last = hit
        }
    }
    UiEnd(&test.ctx)
}

@(test)
test_a_chart_picks_the_point_under_a_click_and_walks_with_the_arrows :: proc(t: ^testing.T) {
    test: ^ChartTest = new(ChartTest)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    ChartViewInit(&test.view)
    test.sales = {{0, 10}, {1, 40}, {2, 30}, {3, 80}}
    test.costs = {{0, 20}, {1, 25}, {2, 60}, {3, 35}}
    away: Input = {mouse_position = {-100, -100}}
    for _ in 0 ..< 3 { chartFrame(test, away) }
    id: Id = UiIdPath("window", "chart")
    rect, found := UiElementRect(&test.ctx, id)
    testing.expect(t, found && rect.z == 600 && rect.w == 300)
    // the style gets the view
    for command in UiCommands(&test.ctx) {
        if command.kind == .DRAW && command.info.kind == .CHART { testing.expect(t, command.info.user == rawptr(&test.view)) }
    }
    plot: Rect = ChartPlotRect(&test.view, rect, DEFAULT_METRICS.font_size)

    // the pointer near the third point of Costs: it is the hovered one; a click picks it
    at: Vec2 = ChartPosition(&test.view, plot, test.costs[2]) + {3, -2}
    chartFrame(test, {mouse_position = at})
    chartFrame(test, {mouse_position = at})
    testing.expect_value(t, test.view.hover.series, 1)
    testing.expect_value(t, test.view.hover.point, 2)
    testing.expect_value(t, test.picked, 0)
    chartFrame(test, {mouse_position = at, mouse_down = true, mouse_pressed = true})
    chartFrame(test, {mouse_position = at, mouse_released = true})
    testing.expect_value(t, test.picked, 1)
    testing.expect_value(t, test.last, ChartHit{series = 1, point = 2, value = {2, 60}})
    testing.expect_value(t, test.view.picked, test.last)

    // far from every point: nothing is hovered, a click picks nothing and what was picked stays
    empty: Vec2 = {plot.x + plot.z * 0.5, plot.y + 4}
    chartFrame(test, {mouse_position = empty})
    chartFrame(test, {mouse_position = empty})
    testing.expect_value(t, test.view.hover.series, CHART_NONE)
    chartFrame(test, {mouse_position = empty, mouse_down = true, mouse_pressed = true})
    chartFrame(test, {mouse_position = empty, mouse_released = true})
    testing.expect_value(t, test.picked, 1)
    testing.expect_value(t, test.view.picked.point, 2)

    // the chart has the focus after the click: right and left walk the points of the picked series, and stop at its ends
    chartFrame(test, {mouse_position = {-100, -100}, actions = {.RIGHT}})
    chartFrame(test, away)
    testing.expect_value(t, test.picked, 2)
    testing.expect_value(t, test.last, ChartHit{series = 1, point = 3, value = {3, 35}})
    chartFrame(test, {mouse_position = {-100, -100}, actions = {.RIGHT}})
    chartFrame(test, away)
    testing.expect_value(t, test.view.picked.point, 3)
    for _ in 0 ..< 5 {
        chartFrame(test, {mouse_position = {-100, -100}, actions = {.LEFT}})
        chartFrame(test, away)
    }
    testing.expect_value(t, test.view.picked.point, 0)
    testing.expect_value(t, test.view.picked.series, 1)

    // bars: the bar under the pointer is the hit
    test.kind = .BAR
    chartFrame(test, away)
    bar: Rect = ChartBarRect(&test.view, plot, 0, 3)
    over: Vec2 = {bar.x + bar.z * 0.5, bar.y + bar.w * 0.5}
    chartFrame(test, {mouse_position = over})
    chartFrame(test, {mouse_position = over})
    testing.expect_value(t, test.view.hover.series, 0)
    testing.expect_value(t, test.view.hover.point, 3)

    // data that got shorter: a picked point that is gone is forgotten
    test.view.picked = {series = 1, point = 3, value = {3, 35}}
    test.kind = .LINE
    UiBegin(&test.ctx, away, 1.0 / 60, {800, 600}, &test.style)
    if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(700), {}}) {
        test.series[0] = {name = "Sales", points = test.sales[:2]}
        UiChart(&test.ctx, "chart", &test.view, test.series[:1], .LINE, nil, {Fixed(600), Fixed(300)})
    }
    UiEnd(&test.ctx)
    testing.expect_value(t, test.view.picked.series, CHART_NONE)
    testing.expect_value(t, UiProblems(&test.ctx), Problems{})
}
