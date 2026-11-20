package ui

// A chart: one or more series of points as lines, areas, bars or a scatter, with axes that pick round numbers. The pointer finds the nearest point (a click picks it), the
// arrows of the navigation walk the points of the picked series when the chart has the focus. The library does the numbers (the range, the ticks, where a point is, which
// one the pointer means); the style draws (ui_default: default_style/chart.odin).
//
//     view: ui.ChartView                                       // kept by the program: what is picked, and what the style needs
//     series: [2]ui.ChartSeries = {{name = "Sales", points = sales[:]}, {name = "Costs", points = costs[:]}}
//     if hit, picked := ui.UiChart(&ctx, "Sales by month", &view, series[:], .LINE, months[:]); picked { ... hit.series, hit.point, hit.value ... }
//
// The series and the labels have to live until the frame is drawn (the view keeps the slices, not the numbers). The chart of Baldr (baldr/widget_chart.odin) was the model
// for what a chart does; the code is written for this library.

import "core:math"

ChartKind :: enum u8 {
    LINE,
    AREA,               // lines with the room under them filled
    BAR,                // a bar per point, the series side by side
    SCATTER,            // only the points
}

ChartPoint :: [2]f32            // x, y

ChartSeries :: struct {
    name: string,
    points: []ChartPoint,
}

// A point of a chart: which series, which of its points, and the numbers of that point
ChartHit :: struct {
    series: int,
    point: int,
    value: ChartPoint,
}

CHART_NONE :: -1
CHART_TICKS_MAX :: 12

// What a chart keeps between frames (the picked point) and what the style draws from: start with `{picked = {series = ui.CHART_NONE}}` or ChartViewInit
ChartView :: struct {
    picked: ChartHit,               // series CHART_NONE: nothing is picked
    hover: ChartHit,                // the point under the pointer in this frame (series CHART_NONE: none)
    // for the style, set by UiChart every frame
    kind: ChartKind,
    series: []ChartSeries,
    x_labels: []string,             // the names of the x values 0, 1, 2... (months); empty: the numbers
    low: ChartPoint,                // the range of the axes
    high: ChartPoint,
    y_step: f32,                    // the distance of the lines across
    y_ticks: int,
}

ChartViewInit :: proc(view: ^ChartView) {
    view^ = {picked = {series = CHART_NONE}, hover = {series = CHART_NONE}}
}

// A round distance for the lines of an axis that covers `span` with about `wanted` lines: 1, 2 or 5 times a power of ten
ChartStep :: proc(span: f32, wanted: int = 5) -> f32 {
    if span <= 0 || wanted <= 0 { return 1 }
    raw: f32 = span / f32(wanted)
    power: f32 = math.pow(10, math.floor(math.log10(raw)))
    fraction: f32 = raw / power
    switch {
    case fraction <= 1:
        return power
    case fraction <= 2:
        return 2 * power
    case fraction <= 5:
        return 5 * power
    }
    return 10 * power
}

// The range of the axes for the series: x from the first to the last value, y from a round number under the lowest to one over the highest (bars and areas stand on 0)
ChartBounds :: proc(view: ^ChartView) {
    low: ChartPoint = {max(f32), max(f32)}
    high: ChartPoint = {min(f32), min(f32)}
    any: bool
    for series in view.series {
        for point in series.points {
            low = {min(low.x, point.x), min(low.y, point.y)}
            high = {max(high.x, point.x), max(high.y, point.y)}
            any = true
        }
    }
    if !any { low, high = {0, 0}, {1, 1} }
    if view.kind == .BAR || view.kind == .AREA { low.y = min(low.y, 0) }
    if high.y - low.y < 1e-6 { high.y = low.y + 1 }
    if high.x - low.x < 1e-6 { high.x = low.x + 1 }
    step: f32 = ChartStep(high.y - low.y)
    low.y = math.floor(low.y / step) * step
    high.y = math.ceil(high.y / step) * step
    view.low, view.high, view.y_step = low, high, step
    view.y_ticks = min(int((high.y - low.y) / step + 0.5) + 1, CHART_TICKS_MAX)
}

// Where the series are drawn inside of the rectangle of the chart: room on the left for the numbers of the y axis, at the bottom for the names of the x axis, at the top
// for the legend (two series or more)
ChartPlotRect :: proc(view: ^ChartView, rect: Rect, font_size: f32) -> Rect {
    left: f32 = font_size * 2.6
    bottom: f32 = font_size * 1.5
    top: f32 = font_size * 1.6 if len(view.series) > 1 else font_size * 0.5
    right: f32 = font_size * 0.8
    return {rect.x + left, rect.y + top, max(rect.z - left - right, 1), max(rect.w - top - bottom, 1)}
}

// How wide the slot of one x value is in a bar chart (the bars of the series share it), in pixels
ChartSlotWidth :: proc(view: ^ChartView, plot: Rect) -> f32 {
    count: int
    for series in view.series { count = max(count, len(series.points)) }
    return plot.z / f32(max(count, 1))
}

// Where a value is in the plot. In a bar chart the x values sit in the middle of their slots, so the first and the last bar are whole.
ChartPosition :: proc(view: ^ChartView, plot: Rect, value: ChartPoint) -> Vec2 {
    tx: f32 = (value.x - view.low.x) / (view.high.x - view.low.x)
    ty: f32 = (value.y - view.low.y) / (view.high.y - view.low.y)
    x: f32 = plot.x + tx * plot.z
    if view.kind == .BAR {
        slot: f32 = ChartSlotWidth(view, plot)
        x = plot.x + slot * 0.5 + tx * (plot.z - slot)
    }
    return {x, plot.y + plot.w - ty * plot.w}
}

// The rectangle of a bar: the series stand side by side in the slot of their x value, from the line of 0 to the value
ChartBarRect :: proc(view: ^ChartView, plot: Rect, series: int, point: int) -> Rect {
    value: ChartPoint = view.series[series].points[point]
    slot: f32 = ChartSlotWidth(view, plot)
    group: f32 = slot * 0.72
    bar: f32 = group / f32(max(len(view.series), 1))
    center: Vec2 = ChartPosition(view, plot, value)
    zero: f32 = ChartPosition(view, plot, {value.x, clamp(0, view.low.y, view.high.y)}).y
    x: f32 = center.x - group * 0.5 + bar * f32(series)
    return {x, min(center.y, zero), max(bar - 1, 1), abs(center.y - zero)}
}

// The point the pointer means: the nearest one within `reach` pixels (a bar: the one the pointer is over)
@(private)
chartPointAt :: proc(view: ^ChartView, plot: Rect, pointer: Vec2, reach: f32) -> (hit: ChartHit) {
    hit.series = CHART_NONE
    if !RectContains({plot.x - reach, plot.y - reach, plot.z + 2 * reach, plot.w + 2 * reach}, pointer) { return }
    best: f32 = reach * reach
    for series, s in view.series {
        for value, p in series.points {
            if view.kind == .BAR {
                if RectContains(ChartBarRect(view, plot, s, p), pointer) { return {series = s, point = p, value = value} }
                continue
            }
            delta: Vec2 = ChartPosition(view, plot, value) - pointer
            distance: f32 = delta.x * delta.x + delta.y * delta.y
            if distance <= best {
                best = distance
                hit = {series = s, point = p, value = value}
            }
        }
    }
    return
}

// A chart of `series`. `picked` is true in the frame a point was picked (a click on it, or the arrows of the navigation): `hit` is that point. `x_labels` name the x
// values 0, 1, 2... The size is the control width and a third of it unless `size` says otherwise.
UiChart :: proc(ctx: ^Context, name: string, view: ^ChartView, series: []ChartSeries, kind: ChartKind = .LINE, x_labels: []string = nil, size: Size = {}) -> (hit: ChartHit, picked: bool) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id)
    metrics: ^Metrics = &ctx.style.metrics
    view.kind, view.series, view.x_labels = kind, series, x_labels
    ChartBounds(view)
    // a picked point that is not there any more (the program changed its data) is forgotten
    if view.picked.series >= len(series) || (view.picked.series >= 0 && view.picked.point >= len(series[view.picked.series].points)) { view.picked.series = CHART_NONE }

    view.hover.series = CHART_NONE
    if interaction.rect.z > 0 && (interaction.hovered || interaction.pressed) {
        plot: Rect = ChartPlotRect(view, interaction.rect, metrics.font_size)
        view.hover = chartPointAt(view, plot, ctx.input.mouse_position, metrics.font_size * 1.5)
    }
    if interaction.clicked && view.hover.series != CHART_NONE {
        view.picked = view.hover
        hit, picked = view.picked, true
    }
    // left and right of the navigation walk the points of the picked series (the first series when nothing is picked)
    state.adjustable = true
    if state.pending_adjust != 0 && len(series) > 0 {
        walked: int = max(view.picked.series, 0)
        count: int = len(series[walked].points)
        if count > 0 {
            point: int = clamp(view.picked.point + int(state.pending_adjust), 0, count - 1) if view.picked.series != CHART_NONE else 0
            view.picked = {series = walked, point = point, value = series[walked].points[point]}
            hit, picked = view.picked, true
        }
    }
    state.pending_adjust = 0

    width: f32 = metrics.control_width * 3
    ElementOpen(ctx, {
        id = id,
        layout = {size = widgetSize(size, width, width / 3)},
        hit = {.INTERACTIVE},
        draw = {kind = .CHART, name = IdSplitName(name), font_size = metrics.font_size, user = view},
    })
    ElementClose(ctx)
    return
}
