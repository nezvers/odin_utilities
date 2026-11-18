package reports_view

// A report on screen, drawn with odin_utilities/ui: a split with the sections on the left and the blocks of the chosen section on the right.
// Tables are real columns (sized to their text) whose headings sort them, ratio columns carry a bar and a colour (green better, red worse), budgets and
// checks are coloured by status, findings by severity, charts are plotted, and a filter field keeps the rows that contain a text. A heading sorts: the
// first click ascending, the second descending, the third back to the order of the report. It draws what the
// report holds and nothing else, so any report works: a benchmark run, a test run, the comparison of two runs, the findings of a review.
//
//   view: reports_view.View
//   // every frame, between UiBegin and UiEnd:
//   reports_view.ViewDraw(&ctx, &view, &report)                 // takes all the room it is given (a window, a split, the screen)
//
// The view keeps only what the person chose (the section, the filter, the sort); the report is the program's. Widgets are named by their place, so
// a report that changes between frames is fine. Give the ui storage room for the tables: a cell is two to four elements.

import ui "../../ui"
import reports ".."
import "core:fmt"
import "core:math"
import "core:strings"

VIEW_FILTER_MAX :: 64
VIEW_SCRATCH :: 8192            // numbers of charts that are plotted in one frame
VIEW_CELL_PAD :: 16
VIEW_COLUMN_MAX :: 360          // the widest a column may be: a longer text is cut with "..."
VIEW_CHART_WIDTH :: 560         // a plot: the widget sits in a row that fits its content, so it cannot grow into the room that is left
VIEW_CHART_HEIGHT :: 72

View :: struct {
    section: int,                           // the chosen section, -1 for all of them
    filter: [VIEW_FILTER_MAX]u8,            // keeps the rows of a table whose first cell contains this
    filter_length: int,
    sort_block: int,                        // which table is sorted (see blockKey), -1 for none
    sort_column: int,
    sort_descending: bool,
    scratch: [VIEW_SCRATCH]f32,             // the values of the charts of this frame (the ui draws them after the frame is declared)
    scratch_used: int,
    uid: int,                               // names of the widgets of a frame
}

COLOR_OK :: ui.Color{110, 200, 125, 255}
COLOR_WARN :: ui.Color{232, 184, 80, 255}
COLOR_FAIL :: ui.Color{236, 104, 104, 255}
COLOR_DIM :: ui.Color{150, 154, 166, 255}

ViewInit :: proc(view: ^View) {
    view^ = {section = -1, sort_block = -1}
}

StatusColor :: proc(status: reports.Status) -> ui.Color {
    switch status {
    case .OK:
        return COLOR_OK
    case .WARN:
        return COLOR_WARN
    case .FAIL:
        return COLOR_FAIL
    case .NONE:
    }
    return COLOR_DIM
}

SeverityColor :: proc(severity: reports.Severity) -> ui.Color {
    switch severity {
    case .CRITICAL, .HIGH:
        return COLOR_FAIL
    case .MEDIUM:
        return COLOR_WARN
    case .LOW:
        return {120, 170, 235, 255}
    case .INFO:
    }
    return COLOR_DIM
}

VerdictColor :: proc(verdict: reports.Verdict) -> ui.Color {
    switch verdict {
    case .BETTER:
        return COLOR_OK
    case .WORSE:
        return COLOR_FAIL
    case .SAME, .NONE:
    }
    return COLOR_DIM
}

// The whole viewer. `size` is how much room it takes (all of it by default).
ViewDraw :: proc(c: ^ui.Context, view: ^View, report: ^reports.Report, size: ui.Size = {}) {
    view.uid = 0
    view.scratch_used = 0
    if view.section >= len(report.sections) { view.section = -1 }
    if ui.UiSplit(c, "reports", .HORIZONTAL, 0.24, size, 150, 260) {
        if ui.UiSplitFirst(c) {
            if ui.UiPanel(c, "sections", {size = {ui.Grow(), ui.Grow()}}) {
                drawSidebar(c, view, report)
            }
        }
        if ui.UiSplitSecond(c) {
            if ui.UiScroll(c, "content", {ui.Grow(), ui.Grow()}) {
                drawContent(c, view, report)
            }
        }
    }
}

@(private)
nextName :: proc(c: ^ui.Context, view: ^View, text: string) -> string {
    view.uid += 1
    return ui.UiFormat(c, "%s##%d", text, view.uid)
}

@(private)
drawSidebar :: proc(c: ^ui.Context, view: ^View, report: ^reports.Report) {
    status: reports.Status = reports.ReportStatus(report)
    ui.UiLabelColored(c, report.title, StatusColor(status) if status != .NONE else ui.Color{220, 224, 235, 255}, .WORDS)
    if status != .NONE { ui.UiLabelColored(c, fmt.tprintf("status: %s", reports.StatusName(status)), StatusColor(status)) }
    ui.UiSeparator(c)
    if ui.UiScroll(c, "section list", {ui.Grow(), ui.Grow()}) {
        if ui.UiSelectable(c, "All sections", view.section == -1, {ui.Grow(), {}}) { view.section = -1 }
        for &section, i in report.sections {
            section_status: reports.Status
            for &block in section.blocks {
                section_status = reports.StatusWorse(section_status, reports.BlockStatus(&block))
            }
            title: string = section.title if section.title != "" else "(untitled)"
            label: string = ui.UiFormat(c, "%s%s##section%d", title, fmt.tprintf("  [%s]", reports.StatusName(section_status)) if section_status != .NONE else "", i)
            if ui.UiSelectable(c, label, view.section == i, {ui.Grow(), {}}) { view.section = i }
        }
    }
    ui.UiSeparator(c)
    ui.UiLabel(c, "filter rows")
    _, _ = ui.UiTextField(c, "filter", view.filter[:], &view.filter_length, {ui.Grow(), {}})
}

@(private)
drawContent :: proc(c: ^ui.Context, view: ^View, report: ^reports.Report) {
    if view.section < 0 {
        ui.UiLabelColored(c, report.title, {230, 234, 245, 255}, .WORDS)
        for meta in report.meta {
            ui.UiLabelf(c, "%s: %s", meta.key, meta.value)
        }
        ui.UiSeparator(c)
    }
    for &section, s in report.sections {
        if view.section >= 0 && view.section != s { continue }
        if section.title != "" || section.subtitle != "" {
            ui.UiLabelColored(c, section.title if section.subtitle == "" else fmt.tprintf("%s: %s", section.title, section.subtitle), {230, 234, 245, 255}, .WORDS)
        }
        for &block, b in section.blocks {
            drawBlock(c, view, &block, s * 1000 + b)
        }
        ui.UiSeparator(c)
    }
}

@(private)
drawBlock :: proc(c: ^ui.Context, view: ^View, block: ^reports.Block, key: int) {
    switch block.kind {
    case .PARAGRAPH:
        ui.UiLabel(c, block.text, .WORDS)
    case .CODE:
        for line in strings.split_lines(block.text, context.temp_allocator) {
            ui.UiLabelColored(c, line, COLOR_DIM)
        }
    case .TABLE:
        if block.table.title != "" { ui.UiLabelColored(c, block.table.title, {200, 205, 220, 255}) }
        drawTable(c, view, &block.table, key)
    case .FACTS:
        if block.title != "" { ui.UiLabelColored(c, block.title, {200, 205, 220, 255}) }
        for fact in block.facts {
            ui.UiLabelColored(c, fmt.tprintf("%s: %s", fact.key, fact.value), StatusColor(fact.status) if fact.status != .NONE else ui.Color{220, 224, 235, 255})
        }
    case .CHECKS:
        if block.title != "" { ui.UiLabelColored(c, block.title, {200, 205, 220, 255}) }
        for check in block.checks {
            tag: string = reports.StatusName(check.status) if check.status != .NONE else "-"
            ui.UiLabelColored(c, fmt.tprintf("[%s] %s%s", tag, check.name, fmt.tprintf(": %s", check.detail) if check.detail != "" else ""), StatusColor(check.status), .WORDS)
        }
    case .FINDINGS:
        if block.title != "" { ui.UiLabelColored(c, block.title, {200, 205, 220, 255}) }
        for finding in block.findings {
            ui.UiLabelColored(c, fmt.tprintf("%s  %s%s%s", reports.SeverityName(finding.severity), finding.title,
                fmt.tprintf("  (%s)", finding.location) if finding.location != "" else "", fmt.tprintf(": %s", finding.detail) if finding.detail != "" else ""), SeverityColor(finding.severity), .WORDS)
        }
    case .CHART:
        drawChart(c, view, &block.chart)
    }
}

// Column widths from the text they hold.
@(private)
columnWidths :: proc(c: ^ui.Context, table: ^reports.Table, order: []int, options: reports.RenderOptions) -> []f32 {
    font: f32 = c.style.metrics.font_size
    widths: []f32 = make([]f32, len(table.columns), context.temp_allocator)
    for &column, i in table.columns {
        widths[i] = c.measure(c, reports.ColumnHeading(&column), font).x + 22                 // room for the sort arrow
        for row in order {
            text: string = reports.CellDisplay(&column, reports.TableCell(table, row, i), options)
            widths[i] = max(widths[i], c.measure(c, text, font).x)
        }
        if column.kind == .RATIO { widths[i] += 66 }                                          // the bar
        widths[i] = min(widths[i] + VIEW_CELL_PAD, VIEW_COLUMN_MAX)
    }
    return widths
}

@(private)
drawTable :: proc(c: ^ui.Context, view: ^View, table: ^reports.Table, key: int) {
    options: reports.RenderOptions
    if view.sort_block == key && view.sort_column >= 0 && view.sort_column < len(table.columns) {
        options.sort_column = table.columns[view.sort_column].name
        options.sort_descending = view.sort_descending
    }
    // the rows in the order of the sort, with the ones that do not match the filter left out
    order: [dynamic]int
    order.allocator = context.temp_allocator
    filter: string = strings.to_lower(string(view.filter[:view.filter_length]), context.temp_allocator)
    for row in reports.TableRowOrder(table, options) {
        if filter != "" && !strings.contains(strings.to_lower(reports.TableRowLabel(table, row), context.temp_allocator), filter) { continue }
        append(&order, row)
    }
    widths: []f32 = columnWidths(c, table, order[:], options)
    if ui.UiRow(c, {gap = 0}) {
        for &column, i in table.columns {
            arrow: string
            if view.sort_block == key && view.sort_column == i { arrow = " v" if view.sort_descending else " ^" }
            if ui.UiButton(c, nextName(c, view, fmt.tprintf("%s%s", reports.ColumnHeading(&column), arrow)), {ui.Fixed(widths[i]), {}}) {
                // the same heading again: ascending, then descending, then back to the order of the report
                if view.sort_block == key && view.sort_column == i {
                    if view.sort_descending {
                        view.sort_block, view.sort_column, view.sort_descending = -1, 0, false
                    } else {
                        view.sort_descending = true
                    }
                } else {
                    view.sort_block, view.sort_column, view.sort_descending = key, i, false
                }
            }
        }
    }
    for row in order {
        if ui.UiRow(c, {gap = 0}) {
            for &column, i in table.columns {
                cell: ^reports.Cell = reports.TableCell(table, row, i)
                layout: ui.Layout = {size = {ui.Fixed(widths[i]), ui.Fit()}, direction = .LEFT_TO_RIGHT, padding = ui.PaddingXY(8, 2), gap = 6, align = {x = .RIGHT if column.kind != .TEXT else .LEFT, y = .CENTER}}
                if ui.UiBox(c, {layout = layout}) {
                    drawCell(c, view, &column, cell)
                }
            }
        }
    }
}

@(private)
drawCell :: proc(c: ^ui.Context, view: ^View, column: ^reports.Column, cell: ^reports.Cell) {
    text: string = reports.CellDisplay(column, cell, {})
    switch {
    case column.kind == .RATIO && cell.has_number:
        // a bar from 0 to 2 (1 is equal) and the number in the colour of the verdict
        ui.UiProgress(c, nextName(c, view, "ratio"), f32(clamp(cell.number, 0, 2)), 0, 2, {ui.Fixed(56), ui.Fixed(10)}, "")
        ui.UiLabelColored(c, text, VerdictColor(reports.RatioVerdict(cell.number, column.better)) if cell.status == .NONE else StatusColor(cell.status))
    case cell.status != .NONE:
        ui.UiLabelColored(c, text, StatusColor(cell.status))
    case text == "":
    case:
        ui.UiLabel(c, text, .TRUNCATE)
    }
}

// Every series as a plotted line (or bars). The plots of one chart share one range, so they can be compared; each has a line above it with the name
// of the series, its last value and its range. (The plot widget writes its own name next to the plot: the names given here have no visible part.)
@(private)
drawChart :: proc(c: ^ui.Context, view: ^View, chart: ^reports.Chart) {
    if chart.title != "" { ui.UiLabelColored(c, ui.UiFormat(c, "%s%s", chart.title, fmt.tprintf(" (%s)", chart.y_label) if chart.y_label != "" else ""), {200, 205, 220, 255}) }
    points: int = reports.ChartPoints(chart)
    if points == 0 { return }
    // the numbers as they are plotted (a log scale as logarithms), and the range of all of them
    low, high: f32 = math.INF_F32, -math.INF_F32
    plotted :: proc(chart: ^reports.Chart, series: reports.Series, i: int) -> (value: f32, ok: bool) {
        if i >= len(series.ys) || math.is_nan(series.ys[i]) { return 0, false }
        shown: f64 = math.log10(max(series.ys[i], 1e-9)) if chart.log_y else series.ys[i]
        return f32(shown), true
    }
    for series in chart.series {
        for i in 0 ..< points {
            if value, ok := plotted(chart, series, i); ok {
                low, high = min(low, value), max(high, value)
            }
        }
    }
    if high < low { return }                                              // nothing to plot
    if chart.kind == .BARS { low = min(low, 0) }
    pad: f32 = (high - low) * 0.06 if high > low else 1
    low, high = low - pad if chart.kind == .LINE else low, high + pad
    for series in chart.series {
        if view.scratch_used + points > len(view.scratch) { return }
        values: []f32 = view.scratch[view.scratch_used:view.scratch_used + points]
        view.scratch_used += points
        last: f32 = low
        first_value, last_value: f64 = math.nan_f64(), math.nan_f64()
        series_low, series_high: f64 = math.INF_F64, -math.INF_F64
        for i in 0 ..< points {
            value, ok := plotted(chart, series, i)
            if ok {
                last = value
                y: f64 = series.ys[i]
                if math.is_nan(first_value) { first_value = y }
                last_value = y
                series_low, series_high = min(series_low, y), max(series_high, y)
            }
            values[i] = last                                              // a gap keeps the line where it was
        }
        ui.UiLabelColored(c, ui.UiFormat(c, "%s: %s   (%s to %s)", series.name, reports.FormatNumber(last_value, 0, context.temp_allocator), reports.FormatNumber(series_low, 0, context.temp_allocator), reports.FormatNumber(series_high, 0, context.temp_allocator)), {220, 224, 235, 255})
        name: string = nextName(c, view, "")                              // "##n": nothing to show next to the plot
        if chart.kind == .BARS {
            ui.UiPlotHistogram(c, name, values, "", low, high, {ui.Fixed(VIEW_CHART_WIDTH), ui.Fixed(VIEW_CHART_HEIGHT)})
        } else {
            ui.UiPlotLines(c, name, values, "", low, high, {ui.Fixed(VIEW_CHART_WIDTH), ui.Fixed(VIEW_CHART_HEIGHT)})
        }
    }
    if len(chart.labels) > 0 {
        ui.UiLabelColored(c, strings.join(chart.labels[:], "  ", context.temp_allocator), COLOR_DIM, .WORDS)
    } else if len(chart.xs) > 0 {
        ui.UiLabelColored(c, ui.UiFormat(c, "%s: %s to %s%s", chart.x_label if chart.x_label != "" else "x", reports.FormatNumber(chart.xs[0], 0, context.temp_allocator), reports.FormatNumber(chart.xs[len(chart.xs) - 1], 0, context.temp_allocator), " (log scale)" if chart.log_y else ""), COLOR_DIM)
    }
}
