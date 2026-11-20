package ui_default

// The look of a chart (ui/chart.odin): lines across at round numbers with the numbers before them, the names of the x values under the plot, the series in the
// colors of a palette that is told apart by people who do not see every color, a legend when there is more than one series, a ring around the point under the
// pointer and around the picked one with its value next to it.
//
// The palette is the one of Baldr (baldr/chart_palette.odin, Copyright (c) 2026 Lee Fry and Baldr contributors, zlib License): eight colors for a light and eight for a
// dark surface, measured there with a simulation of color blindness. A series keeps its place in it.

import "core:fmt"
import ui ".."

CHART_COLORS_LIGHT :: [8]ui.Color{{42, 120, 214, 255}, {235, 104, 52, 255}, {27, 175, 122, 255}, {237, 161, 0, 255}, {232, 123, 164, 255}, {0, 131, 0, 255}, {74, 58, 167, 255}, {227, 73, 72, 255}}
CHART_COLORS_DARK :: [8]ui.Color{{57, 135, 229, 255}, {217, 89, 38, 255}, {25, 158, 112, 255}, {201, 133, 0, 255}, {213, 81, 129, 255}, {0, 131, 0, 255}, {144, 133, 233, 255}, {230, 103, 103, 255}}

ChartStyleInstall :: proc(style: ^ui.Style) {
    style.procs[.CHART] = DrawChart
}

// The color of a series by its place
ChartColor :: proc(theme: ^Theme, series: int) -> ui.Color {
    colors: [8]ui.Color = CHART_COLORS_DARK if theme.dark else CHART_COLORS_LIGHT
    return colors[series % len(colors)]
}

// A number of an axis: without decimals when the step is whole
@(private)
chartNumber :: proc(buffer: []u8, value: f32, step: f32) -> string {
    if step >= 1 { return fmt.bprintf(buffer, "%.0f", value) }
    if step >= 0.1 { return fmt.bprintf(buffer, "%.1f", value) }
    return fmt.bprintf(buffer, "%.2f", value)
}

DrawChart :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    view: ^ui.ChartView = cast(^ui.ChartView)info.user
    if view == nil { return }
    FocusRing(painter, info)
    small: f32 = info.font_size * 0.8
    plot: ui.Rect = ui.ChartPlotRect(view, info.rect, info.font_size)
    buffer: [32]u8

    // the lines across and their numbers
    for tick in 0 ..< view.y_ticks {
        value: f32 = view.low.y + f32(tick) * view.y_step
        y: f32 = ui.ChartPosition(view, plot, {view.low.x, value}).y
        painter.fill_rect(painter, {plot.x, y, plot.z, 1}, theme.border if value == 0 else theme.border_soft)
        TextRight(painter, chartNumber(buffer[:], value, view.y_step), {info.rect.x, y - small, plot.x - info.rect.x, small * 2}, small, 6, theme.text_dim)
    }
    // the names of the x values: every one that has room
    count: int
    for series in view.series { count = max(count, len(series.points)) }
    if count > 0 && len(view.series) > 0 {
        longest: []ui.ChartPoint = view.series[0].points
        for series in view.series {
            if len(series.points) > len(longest) { longest = series.points }
        }
        last_right: f32 = -1e9
        for value, i in longest {
            index: int = int(value.x + 0.5)
            label: string = view.x_labels[index] if value.x >= 0 && index < len(view.x_labels) else chartNumber(buffer[:], value.x, 1)
            width: f32 = TextWidth(painter, label, small)
            x: f32 = ui.ChartPosition(view, plot, value).x
            if x - width * 0.5 < last_right + 6 && i != 0 { continue }
            TextCentered(painter, label, {x - width * 0.5, plot.y + plot.w + 3, width, small * 1.4}, small, theme.text_dim)
            last_right = x + width * 0.5
        }
    }

    // the series
    for series, s in view.series {
        color: ui.Color = ChartColor(theme, s)
        switch view.kind {
        case .BAR:
            for _, p in series.points {
                bar: ui.Rect = ui.ChartBarRect(view, plot, s, p)
                lit: bool = (view.hover.series == s && view.hover.point == p) || (view.picked.series == s && view.picked.point == p)
                FillRounded(painter, bar, 1, ui.ColorLerp(color, theme.text, 0.25) if lit else color, 3)
            }
        case .LINE, .AREA:
            zero: f32 = ui.ChartPosition(view, plot, {view.low.x, clamp(0, view.low.y, view.high.y)}).y
            previous: ui.Vec2
            for value, p in series.points {
                point: ui.Vec2 = ui.ChartPosition(view, plot, value)
                if p > 0 {
                    if view.kind == .AREA && painter.fill_polygon != nil {
                        // the room under a piece of the line, down to 0: a quad, faint so that the series behind it shows
                        quad: [4]ui.Vec2 = {previous, point, {point.x, zero}, {previous.x, zero}}
                        painter.fill_polygon(painter, quad[:], {color.r, color.g, color.b, 46})
                    }
                    Line(painter, previous, point, 2, color)
                }
                previous = point
            }
            for value in series.points {
                point: ui.Vec2 = ui.ChartPosition(view, plot, value)
                FillRounded(painter, {point.x - 3, point.y - 3, 6, 6}, 1, color)
            }
        case .SCATTER:
            for value in series.points {
                point: ui.Vec2 = ui.ChartPosition(view, plot, value)
                FillRounded(painter, {point.x - 4, point.y - 4, 8, 8}, 1, {color.r, color.g, color.b, 215})
            }
        }
    }

    // the point under the pointer and the picked one: a ring, and the value of the picked one next to it
    marks: [2]ui.ChartHit = {view.hover, view.picked}
    for mark, i in marks {
        if mark.series == ui.CHART_NONE || mark.series >= len(view.series) || view.kind == .BAR { continue }
        point: ui.Vec2 = ui.ChartPosition(view, plot, mark.value)
        RingRounded(painter, {point.x - 7, point.y - 7, 14, 14}, 7, 2, theme.text if i == 1 else theme.text_dim)
    }
    if view.picked.series != ui.CHART_NONE && view.picked.series < len(view.series) {
        point: ui.Vec2 = ui.ChartPosition(view, plot, view.picked.value)
        if view.kind == .BAR {
            bar: ui.Rect = ui.ChartBarRect(view, plot, view.picked.series, view.picked.point)
            point = {bar.x + bar.z * 0.5, bar.y}
        }
        text: string = chartNumber(buffer[:], view.picked.value.y, view.y_step * 0.1)
        width: f32 = TextWidth(painter, text, small, .STRONG) + 12
        box: ui.Rect = {clamp(point.x - width * 0.5, plot.x, plot.x + plot.z - width), max(point.y - small * 1.6 - 10, info.rect.y), width, small * 1.6}
        FillRoundedBorder(painter, box, 1, theme.surface_high, theme.border, theme.border_width, 6)
        TextCentered(painter, text, box, small, theme.text, .STRONG)
    }

    // the legend: a dot and a name per series, at the top
    if len(view.series) > 1 {
        x: f32 = plot.x
        y: f32 = info.rect.y + info.font_size * 0.2
        for series, s in view.series {
            FillRounded(painter, {x, y + small * 0.3, small * 0.7, small * 0.7}, 1, ChartColor(theme, s))
            TextLeft(painter, series.name, {x + small, y, 200, small * 1.3}, small, 0, theme.text_dim)
            x += small + TextWidth(painter, series.name, small) + small * 1.4
        }
    }
}
