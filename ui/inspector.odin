package ui

// A panel for looking at the ui while it runs: the tree of the elements of the last frame (what is where, which kind, which id), what the buffers cost (elements, commands, text, roots,
// states, hits against the sizes of the Storage), the cost of measuring text, and picking: press "Pick", then the element under the pointer is marked and a click selects it in the tree.
//
//     ui.UiInspector(&ctx, "Inspector", {ui.Fixed(420), ui.Fixed(360)})       // anywhere: a window, a side panel
//
// It looks at the elements as they were laid out at the end of the frame it was declared in (shown in the next one), copied into a fixed table of INSPECTOR_ROWS rows, so it costs
// nothing in a frame that does not declare it. The inspector's own elements are left out.

import "core:reflect"

INSPECTOR_ROWS :: #config(INSPECTOR_ROWS, 1024)
INSPECTOR_LABEL :: 28

// One element of the last frame.
InspectorRow :: struct {
    depth: u16,
    index: i32,                 // in the elements of that frame
    id: Id,                     // 0: the element has none
    rect: Rect,                 // where it was drawn (on the screen)
    kind: StyleKind,            // what it asked the style to draw (NONE: only layout)
    hit: HitKinds,
    is_text: bool,
    floating: bool,
    clips: bool,
    children: i32,
    label: [INSPECTOR_LABEL]u8, // its name, or the start of its text
    label_length: u8,
}

@(private)
Inspector :: struct {
    rows: [INSPECTOR_ROWS]InspectorRow,
    row_count: int,
    requested: bool,            // UiInspector was declared in this frame: UiEnd takes the snapshot
    first: int,                 // the elements of the inspector itself, first ..< end: left out
    end: int,
    show_text: bool,
    pick: bool,
    rect: Rect,                 // where the panel was in the last frame
    pressed: bool,              // the press of this frame while picking (the widgets do not get it)
    list: VirtualList,
    cut_off: bool,              // the frame had more elements than the table has rows
    usage: Usage,               // the buffers at the end of that frame
}

InspectorRowLabel :: proc(row: ^InspectorRow) -> string {
    return string(row.label[:row.label_length])
}

// The rows of the last snapshot (valid until the next UiEnd).
InspectorRows :: proc(ctx: ^Context) -> []InspectorRow {
    return ctx.inspector.rows[:ctx.inspector.row_count]
}

// Starts (or ends) the picking from the program, a key for example: the next press outside of the panel selects the element under the pointer.
UiInspectorPick :: proc(ctx: ^Context, on: bool = true) {
    ctx.inspector.pick = on
}

// The element that is selected in the tree.
UiInspectorSelected :: proc(ctx: ^Context) -> (row: InspectorRow, found: bool) {
    selected: int = ctx.inspector.list.selected
    if selected < 0 || selected >= ctx.inspector.row_count { return {}, false }
    return ctx.inspector.rows[selected], true
}

// Called by UiBegin: while picking, a press outside of the panel is the pick, not a click on what is under the pointer.
@(private)
inspectorFilterInput :: proc(ctx: ^Context) {
    inspector: ^Inspector = &ctx.inspector
    inspector.pressed = false
    if !inspector.pick || RectContains(inspector.rect, ctx.input.mouse_position) { return }
    inspector.pressed = ctx.input.mouse_pressed
    ctx.input.mouse_pressed, ctx.input.mouse_down, ctx.input.mouse_released = false, false, false
}

// Called by UiEnd, after the layout: copies the elements of the frame when an inspector was declared in it.
@(private)
inspectorCapture :: proc(ctx: ^Context) {
    inspector: ^Inspector = &ctx.inspector
    if !inspector.requested { return }
    inspector.requested = false
    inspector.row_count = 0
    inspector.cut_off = false
    inspector.usage, _ = UiUsage(ctx)
    depths: [UI_INSPECTOR_DEPTH]u16
    for i in 0 ..< ctx.element_count {
        element: ^Element = &ctx.elements[i]
        depth: u16
        if element.parent >= 0 && int(element.parent) < len(depths) && int(element.parent) < i { depth = depths[element.parent] + 1 }
        if i < len(depths) { depths[i] = depth }
        if i >= inspector.first && i < inspector.end { continue }
        if element.is_text && !inspector.show_text { continue }
        if inspector.row_count >= len(inspector.rows) {
            inspector.cut_off = true
            break
        }
        row: ^InspectorRow = &inspector.rows[inspector.row_count]
        inspector.row_count += 1
        row^ = {
            depth = depth, index = i32(i), id = element.id, rect = element.rect, kind = element.decl.draw.kind, hit = element.decl.hit,
            is_text = element.is_text, floating = element.decl.floating.attach_to != .NONE,
            clips = element.decl.clip.horizontal || element.decl.clip.vertical, children = element.children_count,
        }
        label: string = element.decl.draw.name
        if label == "" && element.is_text { label = element.text.text }
        count: int = min(len(label), INSPECTOR_LABEL)
        copy(row.label[:count], label[:count])
        row.label_length = u8(count)
    }
}

UI_INSPECTOR_DEPTH :: 4096          // elements whose depth is followed (the storage is never bigger by default)

// The row of the element under a point (the last one that holds it: the deepest, the one drawn on top), VIRTUAL_NONE for none.
@(private)
inspectorRowAt :: proc(ctx: ^Context, point: Vec2) -> int {
    found: int = VIRTUAL_NONE
    for i in 0 ..< ctx.inspector.row_count {
        row: ^InspectorRow = &ctx.inspector.rows[i]
        if row.kind != .NONE && RectContains(row.rect, point) { found = i }
    }
    return found
}

// The inspector panel.
UiInspector :: proc(ctx: ^Context, name: string, size: Size = {}) {
    inspector: ^Inspector = &ctx.inspector
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    metrics: ^Metrics = &ctx.style.metrics
    inspector.requested = true
    inspector.rect = state.rect
    inspector.first = ctx.element_count
    inside: bool = RectContains(state.rect, ctx.input.mouse_position)

    // picking: the element under the pointer is the one marked; a press outside of the panel selects it
    hovered: int = VIRTUAL_NONE
    if inspector.pick && !inside {
        hovered = inspectorRowAt(ctx, ctx.input.mouse_position)
        if inspector.pressed && hovered != VIRTUAL_NONE {
            inspector.list.selected = hovered
            inspector.list.reveal = true
            inspector.pick = false
        }
    }

    if ElementOpen(ctx, {
        id = id,
        layout = {size = {size.width if size.width != {} else Grow(), size.height if size.height != {} else Grow()}, direction = .TOP_TO_BOTTOM, padding = PaddingAll(metrics.gap), gap = metrics.gap},
        hit = {.BLOCKER},
        draw = {kind = .PANEL, name = IdSplitName(name), font_size = metrics.font_size},
    }) {
        now: Usage = inspector.usage
        _, peak := UiUsage(ctx)
        storage_elements: int = len(ctx.elements)
        UiLabel(ctx, UiFormat(ctx, "elements %d (peak %d) of %d    commands %d of %d", now.elements, peak.elements, storage_elements, now.commands, len(ctx.commands)))
        UiLabel(ctx, UiFormat(ctx, "text %d of %d bytes    lines %d    roots %d    states %d    hits %d", now.text_bytes, len(ctx.text_buffer), now.lines, now.roots, now.states, now.hits))
        hits, misses := UiMeasureCacheStats(ctx)
        UiLabel(ctx, UiFormat(ctx, "measure cache %d hits, %d misses    frame %.2f ms%s", hits, misses, ctx.delta_time * 1000, "    TABLE FULL" if inspector.cut_off else ""))
        if ElementOpen(ctx, {layout = {size = {Grow(), Fit()}, direction = .LEFT_TO_RIGHT, gap = metrics.gap, align = {y = .CENTER}}}) {
            UiToggle(ctx, "Pick", &inspector.pick)
            UiToggle(ctx, "Text", &inspector.show_text)
            ElementClose(ctx)
        }
        list: ^VirtualList = &inspector.list
        if UiVirtual(ctx, "tree", list, inspector.row_count, metrics.control_height * 0.8, {Grow(), Grow()}) {
            for row_index in list.first ..< list.last {
                row: ^InspectorRow = &inspector.rows[row_index]
                if UiVirtualRow(ctx, list, row_index) {
                    kind: string = reflect.enum_string(row.kind) if row.kind != .NONE else "layout"
                    UiLabel(ctx, UiFormat(ctx, "%*s%s %s%s", int(row.depth) * 2, "", kind, InspectorRowLabel(row), "  (text)" if row.is_text else ""))
                }
            }
        }
        selected: int = list.selected
        if selected != VIRTUAL_NONE && selected < inspector.row_count {
            row: ^InspectorRow = &inspector.rows[selected]
            UiLabel(ctx, UiFormat(ctx, "id %x    index %d    children %d", u32(row.id), row.index, row.children))
            UiLabel(ctx, UiFormat(ctx, "rect %.0f, %.0f   %.0f x %.0f%s%s", row.rect.x, row.rect.y, row.rect.z, row.rect.w, "   floating" if row.floating else "", "   clips" if row.clips else ""))
            UiLabel(ctx, UiFormat(ctx, "hit %s", hitKindsText(ctx, row.hit)))
        } else {
            UiLabel(ctx, "no element selected")
        }
        ElementClose(ctx)
    }
    // the marks: the element under the pointer while picking, the selected one in the tree
    mark :: proc(ctx: ^Context, row: ^InspectorRow, color: Color) {
        if row.rect.z <= 0 || row.rect.w <= 0 { return }
        ElementOpen(ctx, {
            layout = {size = {Fixed(row.rect.z), Fixed(row.rect.w)}},
            floating = {attach_to = .ROOT, offset = {row.rect.x, row.rect.y}, z_index = 900},
            draw = {kind = .HIGHLIGHT, color = color},
        })
        ElementClose(ctx)
    }
    if hovered != VIRTUAL_NONE { mark(ctx, &inspector.rows[hovered], {255, 190, 60, 255}) }
    if inspector.list.selected != VIRTUAL_NONE && inspector.list.selected < inspector.row_count && inspector.list.selected != hovered {
        mark(ctx, &inspector.rows[inspector.list.selected], {90, 190, 255, 255})
    }
    inspector.end = ctx.element_count
}

@(private)
hitKindsText :: proc(ctx: ^Context, kinds: HitKinds) -> string {
    if kinds == {} { return "none" }
    text: [96]u8
    length: int
    for kind in HitKind {
        if kind not_in kinds { continue }
        name: string = reflect.enum_string(kind)
        if length + len(name) + 1 > len(text) { break }
        if length > 0 {
            text[length] = ' '
            length += 1
        }
        copy(text[length:], name)
        length += len(name)
    }
    return UiFormat(ctx, "%s", string(text[:length]))
}
