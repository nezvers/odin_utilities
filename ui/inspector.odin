package ui

// A panel for looking at the ui while it runs: the tree of the elements of the last frame (what is where, which kind, which id), what the buffers cost (elements, commands, text, roots,
// states, hits against the sizes of the Storage), the cost of measuring text, and picking: press "Pick", then the element under the pointer is marked and a click selects it in the tree.
//
//     ui.UiInspector(&ctx, "Inspector", {ui.Fixed(420), ui.Fixed(360)})       // anywhere: a window, a side panel
//
// It looks at the elements as they were laid out at the end of the frame it was declared in (shown in the next one), copied into a fixed table of INSPECTOR_ROWS rows, so it costs
// nothing in a frame that does not declare it. The inspector's own elements are left out.

import "core:reflect"
import "core:time"

INSPECTOR_ROWS :: #config(INSPECTOR_ROWS, 1024)
INSPECTOR_LABEL :: 28
INSPECTOR_COMMANDS :: #config(INSPECTOR_COMMANDS, 2048)   // the draw commands of a frame the inspector can list
INSPECTOR_HISTORY :: 120                                  // the frames of the plots

// One draw command of the last frame (what a style gets, in the order it gets it).
InspectorCommand :: struct {
    kind: CommandKind,
    style: StyleKind,
    rect: Rect,
    label: [INSPECTOR_LABEL]u8,
    label_length: u8,
}

// One element of the last frame.
InspectorRow :: struct {
    depth: u16,
    index: i32,                 // among the elements of that frame without the inspector's own (so it is the same from one frame to the next, whatever the marks of the inspector add)
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

// How the selected element was declared: what the layout was told (not what the strings of its draw info said: those live only in their frame).
InspectorDetail :: struct {
    found: bool,
    index: i32,
    layout: Layout,
    floating: Floating,
    absolute: Absolute,
    clip: Clip,
    zoom: f32,
    aspect_ratio: f32,
    size: Vec2,                 // the size the layout gave it
    min_size: Vec2,
    content_size: Vec2,
    cursor: Cursor,
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
    selected_element: i32,      // the element that is selected, plus one (by its place in the frame, so that a filter or the texts coming in do not change which one it is); 0 for none
    detail: InspectorDetail,
    filter: [INSPECTOR_LABEL]u8,
    filter_length: int,
    collapsed: [INSPECTOR_ROWS]bool,    // by the place of an element in the frame: its children are left out of the tree
    show_commands: bool,        // the list shows the draw commands of the frame and not the elements
    show_history: bool,         // the plots of the last frames
    commands: [INSPECTOR_COMMANDS]InspectorCommand,
    command_count: int,
    commands_cut_off: bool,
    command_list: VirtualList,
    begin: time.Tick,           // UiBegin: the time of the frame (declaring and layout) is the time to UiEnd
    build_ms: [INSPECTOR_HISTORY]f32,       // the last frames, the newest at the end
    measure_hits, measure_misses: u64,      // the totals of the cache at the last panel: the difference is one frame's
    frame_hits, frame_misses: u64,
    fixed_ms: f32,              // more than 0: the build time that is recorded instead of the measured one (UiInspectorFixedTime)
    element_history: [INSPECTOR_HISTORY]f32,
    command_history: [INSPECTOR_HISTORY]f32,
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

// Chooses what the inspector shows: the draw commands of the frame instead of the tree of the elements, the plots of the last frames above.
UiInspectorView :: proc(ctx: ^Context, commands: bool, history: bool) {
    ctx.inspector.show_commands, ctx.inspector.show_history = commands, history
}

// For a picture that is compared with a stored one: the build time of every frame, the ones in the history too, is `milliseconds` from now on and not the measured
// time, which differs from run to run. 0 measures again.
UiInspectorFixedTime :: proc(ctx: ^Context, milliseconds: f32) {
    ctx.inspector.fixed_ms = milliseconds
    if milliseconds > 0 {
        for &value in ctx.inspector.build_ms { value = milliseconds }
    }
}

// The draw commands of the last snapshot (valid until the next UiEnd).
InspectorCommands :: proc(ctx: ^Context) -> []InspectorCommand {
    return ctx.inspector.commands[:ctx.inspector.command_count]
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

// The place of an element among the elements without the inspector's own (those between `first` and `end`).
@(private)
stable :: proc(i: int, first: int, end: int) -> int {
    return i if i < first else i - (end - first)
}

// Called by UiEnd, after the layout: copies the elements of the frame when an inspector was declared in it.
@(private)
inspectorCapture :: proc(ctx: ^Context) {
    inspector: ^Inspector = &ctx.inspector
    if !inspector.requested { return }
    inspector.requested = false
    inspector.row_count = 0
    inspector.cut_off = false
    filter: string = string(inspector.filter[:inspector.filter_length])
    inspector.usage, _ = UiUsage(ctx)
    // the history: the plots move one frame to the left
    copy(inspector.build_ms[:INSPECTOR_HISTORY - 1], inspector.build_ms[1:])
    copy(inspector.element_history[:INSPECTOR_HISTORY - 1], inspector.element_history[1:])
    copy(inspector.command_history[:INSPECTOR_HISTORY - 1], inspector.command_history[1:])
    inspector.build_ms[INSPECTOR_HISTORY - 1] = inspector.fixed_ms if inspector.fixed_ms > 0 else f32(time.duration_microseconds(time.tick_since(inspector.begin))) / 1000
    inspector.element_history[INSPECTOR_HISTORY - 1] = f32(ctx.element_count)
    inspector.command_history[INSPECTOR_HISTORY - 1] = f32(ctx.command_count)
    // the commands
    inspector.command_count, inspector.commands_cut_off = 0, false
    for i in 0 ..< ctx.command_count {
        if inspector.command_count >= len(inspector.commands) {
            inspector.commands_cut_off = true
            break
        }
        command: ^Command = &ctx.commands[i]
        entry: ^InspectorCommand = &inspector.commands[inspector.command_count]
        inspector.command_count += 1
        entry^ = {kind = command.kind, style = command.info.kind, rect = command.info.rect}
        label: string = command.info.name if command.info.name != "" else command.info.text
        count: int = min(len(label), INSPECTOR_LABEL)
        copy(entry.label[:count], label[:count])
        entry.label_length = u8(count)
    }
    depths: [UI_INSPECTOR_DEPTH]u16
    skip_below: int = -1                 // the elements deeper than this are under a collapsed one
    for i in 0 ..< ctx.element_count {
        element: ^Element = &ctx.elements[i]
        depth: u16
        if element.parent >= 0 && int(element.parent) < len(depths) && int(element.parent) < i { depth = depths[element.parent] + 1 }
        if i < len(depths) { depths[i] = depth }
        if i >= inspector.first && i < inspector.end { continue }
        if skip_below >= 0 {
            if int(depth) > skip_below { continue }
            skip_below = -1
        }
        place: int = stable(i, inspector.first, inspector.end)
        if place < len(inspector.collapsed) && inspector.collapsed[place] && element.children_count > 0 { skip_below = int(depth) }
        if element.is_text && !inspector.show_text { continue }
        if filter != "" && !inspectorMatches(element, filter) && i32(stable(i, inspector.first, inspector.end)) + 1 != inspector.selected_element { continue }
        if inspector.row_count >= len(inspector.rows) {
            inspector.cut_off = true
            break
        }
        row: ^InspectorRow = &inspector.rows[inspector.row_count]
        inspector.row_count += 1
        row^ = {
            depth = depth, index = i32(stable(i, inspector.first, inspector.end)), id = element.id, rect = element.rect, kind = element.decl.draw.kind, hit = element.decl.hit,
            is_text = element.is_text, floating = element.decl.floating.attach_to != .NONE,
            clips = element.decl.clip.horizontal || element.decl.clip.vertical, children = element.children_count,
        }
        label: string = element.decl.draw.name
        if label == "" && element.is_text { label = element.text.text }
        count: int = min(len(label), INSPECTOR_LABEL)
        copy(row.label[:count], label[:count])
        row.label_length = u8(count)
    }
    // the selection follows its element into the new rows, and its details are taken
    inspector.list.selected = VIRTUAL_NONE
    inspector.detail = {}
    for i in 0 ..< inspector.row_count {
        if inspector.rows[i].index + 1 == inspector.selected_element {
            inspector.list.selected = i
            wanted: int = int(inspector.selected_element) - 1
            element: ^Element = &ctx.elements[wanted if wanted < inspector.first else wanted + (inspector.end - inspector.first)]
            inspector.detail = {
                found = true, index = inspector.selected_element - 1, layout = element.decl.layout, floating = element.decl.floating, absolute = element.decl.absolute,
                clip = element.decl.clip, zoom = element.decl.zoom, aspect_ratio = element.decl.aspect_ratio, size = element.size, min_size = element.min_size,
                content_size = element.content_size, cursor = element.decl.cursor,
            }
        }
    }
}

// Does the element match the filter text (without regard to case): its name, its text, the name of its kind?
@(private)
inspectorMatches :: proc(element: ^Element, filter: string) -> bool {
    label: string = element.decl.draw.name
    if label == "" && element.is_text { label = element.text.text }
    if containsFold(label, filter) { return true }
    return element.decl.draw.kind != .NONE && containsFold(reflect.enum_string(element.decl.draw.kind), filter)
}

@(private)
containsFold :: proc(text: string, part: string) -> bool {
    if len(part) == 0 { return true }
    lower :: proc(c: u8) -> u8 { return c + 32 if c >= 'A' && c <= 'Z' else c }
    for start in 0 ..= len(text) - len(part) {
        matched: bool = true
        for i in 0 ..< len(part) {
            if lower(text[start + i]) != lower(part[i]) {
                matched = false
                break
            }
        }
        if matched { return true }
    }
    return false
}

// What the layout of the selected element was told.
UiInspectorDetail :: proc(ctx: ^Context) -> (detail: InspectorDetail, found: bool) {
    return ctx.inspector.detail, ctx.inspector.detail.found
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
            inspector.selected_element = inspector.rows[hovered].index + 1
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
        // the cache answers a text it has seen: a frame of a quiet ui is all hits. The numbers of this very panel change every frame, so each of its lines that holds a counter is a
        // miss by nature (about four a frame): the misses that stay are those, not the ui next to it
        hits, misses := UiMeasureCacheStats(ctx)
        inspector.frame_hits, inspector.frame_misses = hits - inspector.measure_hits, misses - inspector.measure_misses
        inspector.measure_hits, inspector.measure_misses = hits, misses
        UiLabel(ctx, UiFormat(ctx, "measure cache last frame %d hits, %d misses (the counters of this panel are misses by nature)    frame %.2f ms%s", inspector.frame_hits, inspector.frame_misses, ctx.delta_time * 1000, "    TABLE FULL" if inspector.cut_off else ""))
        if ElementOpen(ctx, {layout = {size = {Grow(), Fit()}, direction = .LEFT_TO_RIGHT, gap = metrics.gap, align = {y = .CENTER}}}) {
            UiToggle(ctx, "Pick", &inspector.pick)
            UiToggle(ctx, "Text", &inspector.show_text)
            UiToggle(ctx, "Commands", &inspector.show_commands)
            UiToggle(ctx, "History", &inspector.show_history)
            ElementClose(ctx)
        }
        if inspector.show_history {
            UiPlotLines(ctx, "build time##inspector history", inspector.build_ms[:], UiFormat(ctx, "%.2f ms", inspector.build_ms[INSPECTOR_HISTORY - 1]), 0, 0, {Fixed(300), Fixed(36)})
            UiPlotLines(ctx, "elements##inspector history", inspector.element_history[:], UiFormat(ctx, "%d elements", int(inspector.element_history[INSPECTOR_HISTORY - 1])), 0, 0, {Fixed(300), Fixed(36)})
            UiPlotLines(ctx, "commands##inspector history", inspector.command_history[:], UiFormat(ctx, "%d commands", int(inspector.command_history[INSPECTOR_HISTORY - 1])), 0, 0, {Fixed(300), Fixed(36)})
        }
        if inspector.show_commands {
            inspectorCommandList(ctx, inspector, metrics.control_height * 0.8)
            ElementClose(ctx)
            inspector.end = ctx.element_count
            return
        }
        list: ^VirtualList = &inspector.list
        UiTextField(ctx, "Filter##inspector filter", inspector.filter[:], &inspector.filter_length, {Grow(), {}})
        if UiVirtual(ctx, "tree", list, inspector.row_count, metrics.control_height * 0.8, {Grow(), Grow()}) {
            if list.changed && list.selected != VIRTUAL_NONE && list.selected < inspector.row_count { inspector.selected_element = inspector.rows[list.selected].index + 1 }
            // a double click or Enter opens and closes the element: its children are left out of the tree (the table of the next frame)
            if list.activated && list.selected != VIRTUAL_NONE && list.selected < inspector.row_count {
                place: int = int(inspector.rows[list.selected].index)
                if place < len(inspector.collapsed) && inspector.rows[list.selected].children > 0 { inspector.collapsed[place] = !inspector.collapsed[place] }
            }
            for row_index in list.first ..< list.last {
                row: ^InspectorRow = &inspector.rows[row_index]
                if UiVirtualRow(ctx, list, row_index) {
                    kind: string = reflect.enum_string(row.kind) if row.kind != .NONE else "layout"
                    mark: string = ""
                    if row.children > 0 { mark = "[+] " if int(row.index) < len(inspector.collapsed) && inspector.collapsed[row.index] else "[-] " }
                    UiLabel(ctx, UiFormat(ctx, "%*s%s%s %s%s", int(row.depth) * 2, "", mark, kind, InspectorRowLabel(row), "  (text)" if row.is_text else ""))
                }
            }
        }
        selected: int = list.selected
        if selected != VIRTUAL_NONE && selected < inspector.row_count {
            row: ^InspectorRow = &inspector.rows[selected]
            UiLabel(ctx, UiFormat(ctx, "id %x    index %d    children %d", u32(row.id), row.index, row.children))
            UiLabel(ctx, UiFormat(ctx, "rect %.0f, %.0f   %.0f x %.0f%s%s", row.rect.x, row.rect.y, row.rect.z, row.rect.w, "   floating" if row.floating else "", "   clips" if row.clips else ""))
            UiLabel(ctx, UiFormat(ctx, "hit %s", hitKindsText(ctx, row.hit)))
            if detail := inspector.detail; detail.found {
                layout: Layout = detail.layout
                UiLabel(ctx, UiFormat(ctx, "width %s    height %s", axisText(ctx, layout.size.width), axisText(ctx, layout.size.height)))
                UiLabel(ctx, UiFormat(ctx, "padding %.0f %.0f %.0f %.0f    gap %.0f    %s", layout.padding.left, layout.padding.right, layout.padding.top, layout.padding.bottom, layout.gap, reflect.enum_string(layout.direction)))
                UiLabel(ctx, UiFormat(ctx, "size %.0f x %.0f (least %.0f x %.0f)    content %.0f x %.0f", detail.size.x, detail.size.y, detail.min_size.x, detail.min_size.y, detail.content_size.x, detail.content_size.y))
                extras: string = detailExtras(ctx, &detail)
                if extras != "" { UiLabel(ctx, extras) }
            }
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

// The draw commands of the last frame as a list: what the style is asked to draw, in order (clips and zooms too).
@(private)
inspectorCommandList :: proc(ctx: ^Context, inspector: ^Inspector, row_height: f32) {
    list: ^VirtualList = &inspector.command_list
    UiLabel(ctx, UiFormat(ctx, "%d draw commands%s", inspector.command_count, " (TABLE FULL)" if inspector.commands_cut_off else ""))
    if UiVirtual(ctx, "commands", list, inspector.command_count, row_height, {Grow(), Grow()}) {
        for row_index in list.first ..< list.last {
            command: ^InspectorCommand = &inspector.commands[row_index]
            if UiVirtualRow(ctx, list, row_index) {
                what: string = reflect.enum_string(command.style) if command.kind == .DRAW else reflect.enum_string(command.kind)
                UiLabel(ctx, UiFormat(ctx, "%4d  %s  %.0f, %.0f  %.0f x %.0f  %s", row_index, what, command.rect.x, command.rect.y, command.rect.z, command.rect.w, string(command.label[:command.label_length])))
            }
        }
    }
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

// A sizing as a line of text: GROW, FIXED 28, FIT 10..200, PERCENT 50 %.
@(private)
axisText :: proc(ctx: ^Context, axis: SizingAxis) -> string {
    kind: string = reflect.enum_string(axis.kind)
    switch axis.kind {
    case .FIXED: return UiFormat(ctx, "%s %.0f", kind, axis.min)
    case .PERCENT: return UiFormat(ctx, "%s %.0f %%", kind, axis.percent * 100)
    case .FIT, .GROW:
        if axis.min > 0 && axis.max > 0 && axis.max < INFINITE { return UiFormat(ctx, "%s %.0f .. %.0f", kind, axis.min, axis.max) }
        if axis.min > 0 { return UiFormat(ctx, "%s from %.0f", kind, axis.min) }
        if axis.max > 0 && axis.max < INFINITE { return UiFormat(ctx, "%s up to %.0f", kind, axis.max) }
        return kind
    }
    return kind
}

// What is special about the element: floating, absolute, zoomed, clipping.
@(private)
detailExtras :: proc(ctx: ^Context, detail: ^InspectorDetail) -> string {
    text: [160]u8
    length: int
    add :: proc(text: []u8, length: ^int, part: string) {
        if length^ + len(part) + 3 > len(text) { return }
        if length^ > 0 {
            copy(text[length^:], "   ")
            length^ += 3
        }
        copy(text[length^:], part)
        length^ += len(part)
    }
    if detail.floating.attach_to != .NONE {
        add(text[:], &length, UiFormat(ctx, "floating to %s, z %d, offset %.0f %.0f", reflect.enum_string(detail.floating.attach_to), detail.floating.z_index, detail.floating.offset.x, detail.floating.offset.y))
    }
    if detail.absolute.enabled { add(text[:], &length, UiFormat(ctx, "absolute at %.0f %.0f", detail.absolute.offset.x, detail.absolute.offset.y)) }
    if detail.zoom > 0 && detail.zoom != 1 { add(text[:], &length, UiFormat(ctx, "zoom %.2f", detail.zoom)) }
    if detail.clip.horizontal || detail.clip.vertical {
        add(text[:], &length, UiFormat(ctx, "clips%s%s, scroll %.0f %.0f", " x" if detail.clip.horizontal else "", " y" if detail.clip.vertical else "", detail.clip.offset.x, detail.clip.offset.y))
    }
    if detail.aspect_ratio != 0 { add(text[:], &length, UiFormat(ctx, "aspect %.2f", detail.aspect_ratio)) }
    return UiFormat(ctx, "%s", string(text[:length]))
}
