package ui_default

// The default look of a node graph: a grid canvas, nodes as framed cards, round pins, cables as polylines of quads, zip ties as straps with a head.
// A style of your own replaces single entries (`style.graph.draw_cable = MyCable`) or the whole kind (`style.procs[.GRAPH_NODE] = MyNode`).

import "core:math"
import hm "core:container/handle_map"
import ui ".."

// What a data type looks like when its port has no color of its own: a few distinct hues, repeating.
GRAPH_PALETTE :: [6]ui.Color{
    {110, 190, 255, 255},
    {255, 170, 90, 255},
    {130, 220, 130, 255},
    {230, 120, 200, 255},
    {240, 220, 100, 255},
    {170, 140, 255, 255},
}

GraphTypeColor :: proc(data_type: u32) -> ui.Color {
    palette: [6]ui.Color = GRAPH_PALETTE
    return palette[data_type % len(palette)]
}

@(private)
graphColor :: proc(color: ui.Color, data_type: u32) -> ui.Color {
    return color if color.a > 0 else GraphTypeColor(data_type)
}

// Installs the graph procs into a style made by StyleMake.
GraphStyleInstall :: proc(style: ^ui.Style) {
    style.procs[.GRAPH] = DrawGraph
    style.procs[.GRAPH_OVERLAY] = DrawGraphOverlay
    style.procs[.GRAPH_NODE] = DrawGraphNode
    style.procs[.GRAPH_PIN] = DrawGraphPin
    style.procs[.GRAPH_MINIMAP] = DrawGraphMinimap
    style.graph.draw_cable = DrawCable
    style.graph.draw_tie = DrawTie
}

DrawGraph :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    painter.fill_rect(painter, info.rect, theme.track)
    frame: ^ui.GraphFrame = cast(^ui.GraphFrame)info.user
    if frame == nil { return }
    // a grid that moves with the view
    zoom: f32 = ui.GraphViewZoom(frame.view)
    grid: f32 = frame.style.grid * zoom
    origin: ui.Vec2 = frame.view.origin * zoom
    line: ui.Color = ui.ColorLerp(theme.track, theme.border, 0.35)
    first_x: f32 = grid - math.mod(origin.x, grid)
    for x := first_x; x < info.rect.z; x += grid {
        painter.fill_rect(painter, {info.rect.x + x, info.rect.y, 1, info.rect.w}, line)
    }
    first_y: f32 = grid - math.mod(origin.y, grid)
    for y := first_y; y < info.rect.w; y += grid {
        painter.fill_rect(painter, {info.rect.x, info.rect.y + y, info.rect.z, 1}, line)
    }
    ui.GraphDrawLinks(ctx, info)
}

DrawGraphOverlay :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    ui.GraphDrawOverlay(ctx, info)
}

DrawGraphNode :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    selected: bool = .SELECTED in info.flags
    border: ui.Color = theme.accent if selected else theme.border
    width: f32 = 2 if selected else theme.border_width
    FillRoundedBorder(painter, info.rect, theme.panel_rounding, ui.ColorLerp(theme.panel, ui.Color{0, 0, 0, 255}, 0.15) if info.color.a == 0 else info.color, border, width, theme.max_radius)
    // the band of the title (a node that has a name): inside of the outline, with the corners of the node
    if info.name != "" {
        TitleBand(painter, info.rect, ui.RoundedRadius(info.rect, theme.panel_rounding, theme.max_radius), width, ctx.style.metrics.control_height)
    }
}

DrawGraphPin :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    color: ui.Color = graphColor(info.color, u32(info.actual))
    radius: f32 = min(info.rect.z, info.rect.w) * 0.3
    if .HOVERED in info.flags || .SELECTED in info.flags || .PRESSED in info.flags { radius *= 1.25 }
    if .DISABLED in info.flags { color = ui.ColorLerp(color, theme.track, 0.7) }
    center: ui.Vec2 = ui.RectCenter(info.rect)
    ring: ui.Rect = {center.x - radius, center.y - radius, radius * 2, radius * 2}
    FillRounded(painter, ring, 1, theme.accent if .SELECTED in info.flags else color)
    if .ON not_in info.flags && .PRESSED not_in info.flags {
        inner: ui.Rect = ui.RectShrink(ring, 2)
        FillRounded(painter, inner, 1, theme.track)
    }
}

DrawGraphMinimap :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    FillRoundedBorder(painter, info.rect, theme.panel_rounding, theme.track, theme.border, theme.border_width, theme.max_radius)
    data: ^ui.GraphMinimapData = cast(^ui.GraphMinimapData)info.user
    if data == nil { return }
    scale, offset := ui.GraphMinimapTransform(data.content, info.rect)
    inner: ui.Rect = ui.RectShrink(info.rect, 1)
    // the cables first (thin lines between the pins), then the nodes
    it := hm.iterator_make(&data.graph.links)
    for link, _ in hm.iterate(&it) {
        from, to: ^ui.Port = ui.GraphPort(data.graph, link.from), ui.GraphPort(data.graph, link.to)
        if from == nil || to == nil || !from.anchor_known || !to.anchor_known { continue }
        a: ui.Vec2 = offset + (from.anchor - {data.content.x, data.content.y}) * scale
        b: ui.Vec2 = offset + (to.anchor - {data.content.x, data.content.y}) * scale
        Line(painter, a, b, 1, ui.ColorLerp(graphColor(from.color, from.data_type), theme.track, 0.3))
    }
    nodes := hm.iterator_make(&data.graph.nodes)
    for node, _ in hm.iterate(&nodes) {
        rect: ui.Rect = {offset.x + (node.position.x - data.content.x) * scale, offset.y + (node.position.y - data.content.y) * scale, max(node.size.x * scale, 2), max(node.size.y * scale, 2)}
        painter.fill_rect(painter, ui.RectIntersect(rect, inner), ui.ColorLerp(theme.control_hover, theme.accent, 0.4 if node.selected else 0))
    }
    view: ui.Rect = {offset.x + (data.viewport.x - data.content.x) * scale, offset.y + (data.viewport.y - data.content.y) * scale, data.viewport.z * scale, data.viewport.w * scale}
    edge: ui.Color = theme.accent
    painter.fill_rect(painter, ui.RectIntersect({view.x, view.y, view.z, 1.5}, inner), edge)
    painter.fill_rect(painter, ui.RectIntersect({view.x, view.y + view.w - 1.5, view.z, 1.5}, inner), edge)
    painter.fill_rect(painter, ui.RectIntersect({view.x, view.y, 1.5, view.w}, inner), edge)
    painter.fill_rect(painter, ui.RectIntersect({view.x + view.z - 1.5, view.y, 1.5, view.w}, inner), edge)
}

// A cable as straight quads along its route (the flattened pieces): wider while it is hovered, selected or dragged, faint while its end is picked up.
DrawCable :: proc(ctx: ^ui.Context, cable: ^ui.CableDraw) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    color: ui.Color = graphColor(cable.color, cable.from_type)
    width: f32 = cable.width
    if .HOVERED in cable.flags || .PRESSED in cable.flags { width *= 1.4 }
    if .SELECTED in cable.flags {
        width *= 1.4
        color = ui.ColorLerp(color, ui.Color{255, 255, 255, 255}, 0.5)
    }
    if .DISABLED in cable.flags { color.a = 70 }
    points: [ui.CABLE_MAX_SEGMENTS * ui.CABLE_PIECES + 1]ui.Vec2
    flat: []ui.Vec2 = ui.CableFlatten(cable.route, points[:])
    if SmoothReady(painter) {
        RouteLine(painter, cable.route, width, color)     // one soft edged stroke, round ends, as many pieces as the curve needs
    } else {
        for i in 1 ..< len(flat) {
            Line(painter, flat[i - 1], flat[i], width, color)
        }
    }
    // the text on the cable, on a small plate at the middle of its length
    if cable.label != "" && len(flat) >= 2 {
        total: f32
        for i in 1 ..< len(flat) { total += math.sqrt(math.pow(flat[i].x - flat[i - 1].x, 2) + math.pow(flat[i].y - flat[i - 1].y, 2)) }
        walked: f32
        middle: ui.Vec2 = flat[len(flat) / 2]
        for i in 1 ..< len(flat) {
            piece: f32 = math.sqrt(math.pow(flat[i].x - flat[i - 1].x, 2) + math.pow(flat[i].y - flat[i - 1].y, 2))
            if walked + piece >= total * 0.5 && piece > 0 {
                middle = flat[i - 1] + (flat[i] - flat[i - 1]) * ((total * 0.5 - walked) / piece)
                break
            }
            walked += piece
        }
        size: f32 = ctx.style.metrics.font_size * 0.85
        measured: ui.Vec2 = painter.measure_text(painter, cable.label, size)
        plate: ui.Rect = {middle.x - measured.x * 0.5 - 4, middle.y - measured.y * 0.5 - 1, measured.x + 8, measured.y + 2}
        painter.fill_rect(painter, plate, ui.ColorLerp(theme.panel, ui.Color{0, 0, 0, 255}, 0.2))
        painter.draw_text(painter, cable.label, {plate.x + 4, plate.y + 1}, size, theme.text_dim)
    }
}

// A strap across the cables with a round head at its +normal end (the handle that turns it); lanes show as small marks.
DrawTie :: proc(ctx: ^ui.Context, tie: ^ui.TieDraw) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    color: ui.Color = tie.color if tie.color.a > 0 else theme.text_dim
    if .SELECTED in tie.flags { color = theme.accent }
    else if .HOVERED in tie.flags { color = theme.text }
    if painter.fill_polygon != nil {
        corners: [4]ui.Vec2 = tie.corners
        painter.fill_polygon(painter, corners[:], color)
    } else {
        painter.fill_rect(painter, {tie.center.x - tie.half_length, tie.center.y - tie.half_length, tie.half_length * 2, tie.half_length * 2}, color)
    }
    head: ui.Vec2 = tie.center + tie.normal * tie.half_length
    radius: f32 = tie.width * 0.8
    Disc(painter, head, radius, color)
}
