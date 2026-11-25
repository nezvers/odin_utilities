package ui_default

// The frequency response graph (ui.UiFreqGraph): grid of decades and decibels with labels, the spectrum as a fill from the bottom, the curve of all bands with a tint between it and the
// 0 dB line, a node per band (the selected one bright) and a readout of the band under the pointer. The arithmetic is ui/freq_graph.odin, so the pointer and the picture agree.

import "core:fmt"
import "core:math"
import ui ".."

@(private)
freqText :: proc(frequency: f32) -> string {
    if frequency >= 1000 { return fmt.tprintf("%.2f kHz", frequency / 1000) }
    return fmt.tprintf("%.0f Hz", frequency)
}

DrawFreqGraph :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    view: ^ui.FreqGraphView = cast(^ui.FreqGraphView)info.user
    if view == nil || view.graph == nil { return }
    graph: ^ui.FreqGraph = view.graph
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    areas: ui.FreqAreas = ui.FreqGraphAreas(info.rect)
    grid: ui.Rect = areas.grid
    if grid.z <= 0 || grid.w <= 0 { return }
    range: f32 = ui.FreqGraphRange(view)
    size: f32 = info.font_size * 0.85
    painter.fill_rect(painter, info.rect, theme.panel)
    painter.fill_rect(painter, grid, theme.track)

    // decibel lines
    step: f32 = 6 if range > 12 else (3 if range > 6 else 1)
    for db: f32 = -math.floor(range / step) * step; db <= range + 0.001; db += step {
        y: f32 = ui.FreqGraphY(view, areas, db)
        painter.fill_rect(painter, {grid.x, y, grid.z, 1}, theme.text_dim if db == 0 else theme.border)
        label: string = fmt.tprintf("%+.0f", db) if db != 0 else "0"
        painter.draw_text(painter, label, {grid.x - 6 - painter.measure_text(painter, label, size).x, y - size * 0.55}, size, theme.text_dim)
    }
    // frequency lines: every 1 2 .. 9 of a decade, the decades strong, 1 2 5 labelled
    for decade: f32 = 10; decade <= 10000; decade *= 10 {
        for m in 1 ..= 9 {
            frequency: f32 = decade * f32(m)
            if frequency < ui.FreqGraphFrequencyAt(view, areas, grid.x) * 0.999 || frequency > ui.FreqGraphFrequencyAt(view, areas, grid.x + grid.z) * 1.001 { continue }
            x: f32 = ui.FreqGraphX(view, areas, frequency)
            painter.fill_rect(painter, {x, grid.y, 1, grid.w}, theme.border if m != 1 else theme.text_dim)
            if m == 1 || m == 2 || m == 5 {
                label: string = fmt.tprintf("%.0fk", frequency / 1000) if frequency >= 1000 else fmt.tprintf("%.0f", frequency)
                painter.draw_text(painter, label, {x + 3, areas.axis_bottom.y + 2}, size, theme.text_dim)
            }
        }
    }

    // the spectrum from the bottom up (0 dB is the top)
    if len(graph.spectrum) > 1 {
        rate: f32 = graph.sample_rate if graph.sample_rate > 0 else 48000
        floor_db: f32 = view.spectrum_floor if view.spectrum_floor < 0 else -90
        bins_per_hz: f32 = f32(len(graph.spectrum) - 1) / (rate * 0.5)
        fill: ui.Color = {theme.accent.r, theme.accent.g, theme.accent.b, 55}
        for x: f32 = grid.x; x < grid.x + grid.z; x += 2 {
            first: int = int(ui.FreqGraphFrequencyAt(view, areas, x) * bins_per_hz)
            last: int = max(int(ui.FreqGraphFrequencyAt(view, areas, x + 2) * bins_per_hz), first)
            level: f32 = floor_db
            for bin in clamp(first, 0, len(graph.spectrum) - 1) ..= clamp(last, 0, len(graph.spectrum) - 1) { level = max(level, graph.spectrum[bin]) }
            height: f32 = clamp((level - floor_db) / -floor_db, 0, 1) * grid.w
            if height >= 1 { painter.fill_rect(painter, {x, grid.y + grid.w - height, min(2, grid.x + grid.z - x), height}, fill) }
        }
    }

    // the curve, with a tint between it and the 0 dB line
    POINTS :: 400
    points: [POINTS]ui.Vec2
    count: int = min(int(grid.z / 2) + 1, POINTS)
    zero: f32 = ui.FreqGraphY(view, areas, 0)
    tint: ui.Color = {theme.accent.r, theme.accent.g, theme.accent.b, 40}
    for i in 0 ..< count {
        x: f32 = grid.x + grid.z * f32(i) / f32(max(count - 1, 1))
        y: f32 = ui.FreqGraphY(view, areas, ui.FreqGraphResponse(graph, ui.FreqGraphFrequencyAt(view, areas, x)))
        points[i] = {x, y}
        if i > 0 {
            top, bottom: f32 = min(y, zero), max(y, zero)
            if bottom - top >= 0.5 { painter.fill_rect(painter, {points[i - 1].x, top, x - points[i - 1].x, bottom - top}, tint) }
        }
    }
    if count > 1 { Polyline(painter, points[:count], false, 2, theme.accent) }

    // the nodes
    for i in 0 ..< graph.count {
        band: ui.FreqBand = graph.bands[i]
        node: ui.Vec2 = ui.FreqGraphNode(view, areas, band)
        color: ui.Color = theme.text if band.selected else theme.accent
        if !band.enabled { color = theme.text_dim }
        if i == view.hover_band { Disc(painter, node, ui.FREQ_NODE_RADIUS + 3, {color.r, color.g, color.b, 60}) }
        Disc(painter, node, ui.FREQ_NODE_RADIUS + 1.5, theme.panel)
        Disc(painter, node, ui.FREQ_NODE_RADIUS, color)
        label: string = fmt.tprintf("%d", i + 1)
        painter.draw_text(painter, label, {node.x - painter.measure_text(painter, label, size * 0.85).x * 0.5, node.y - size * 0.5}, size * 0.85, theme.panel)
    }

    // the readout of the band under the pointer, or of the pointer
    text: string
    if view.hover_band >= 0 && view.hover_band < graph.count {
        band: ui.FreqBand = graph.bands[view.hover_band]
        q: f32 = band.q if band.q > 0 else 0.707
        if band.kind == .BELL || band.kind == .LOW_SHELF || band.kind == .HIGH_SHELF {
            text = fmt.tprintf("%s  %+.1f dB  Q %.2f", freqText(band.frequency), band.gain, q)
        } else {
            text = fmt.tprintf("%s  Q %.2f", freqText(band.frequency), q)
        }
        node: ui.Vec2 = ui.FreqGraphNode(view, areas, band)
        width: f32 = painter.measure_text(painter, text, size).x + 12
        box: ui.Rect = {clamp(node.x - width * 0.5, grid.x + 2, grid.x + grid.z - width - 2), node.y - 34 if node.y - 34 > grid.y + 2 else node.y + 14, width, size + 8}
        FillRoundedBorder(painter, box, theme.rounding, theme.panel, theme.border, 1)
        painter.draw_text(painter, text, {box.x + 6, box.y + 4}, size, theme.text)
    } else if view.inside {
        frequency: f32 = ui.FreqGraphFrequencyAt(view, areas, view.mouse.x)
        text = fmt.tprintf("%s  %+.1f dB", freqText(frequency), ui.FreqGraphGainAt(view, areas, view.mouse.y))
        width: f32 = painter.measure_text(painter, text, size).x
        painter.draw_text(painter, text, {grid.x + grid.z - width - 6, grid.y + 4}, size, theme.text_dim)
    }
    painter.fill_rect(painter, {grid.x, grid.y + grid.w, grid.z, 1}, theme.border)
}
