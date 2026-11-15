package ui

// Drag and drop between widgets, with a small payload kept by the ui (a fixed buffer: no allocations). The widget that is dragged calls UiDragSource
// right after it was declared, a widget that accepts what is dragged calls UiDropTarget right after it:
//
//     ui.UiButton(&ctx, "Item 3")
//     ui.UiDragSource(&ctx, "item", &index)                          // a value of any (small) type, or bytes
//     ...
//     ui.UiSelectable(&ctx, "Slot 2", false)
//     if payload, dropped := ui.UiDropTarget(&ctx, "item"); dropped { slot = (^int)(raw_data(payload))^ }
//     ui.UiDragPreview(&ctx, "Item 3")                               // a label that follows the pointer while something is dragged
//
// `kind` is the name of what is dragged: a target only takes its own kind. A drag starts when the pointer has moved 5 pixels from the press on the source,
// ends when the button goes up (a target that was under the pointer takes it) or on cancel.

DRAG_PAYLOAD_BYTES :: 64
DRAG_START_DISTANCE :: 5

@(private)
DragState :: struct {
    active: bool,
    source: Id,
    kind: Id,
    data: [DRAG_PAYLOAD_BYTES]u8,
    size: int,
}

// Call right after the widget that can be dragged. True while this widget is the one being dragged (a style or the program can draw it differently).
UiDragSource :: proc(ctx: ^Context, kind: string, payload: []u8) -> bool {
    id: Id = ctx.last_id
    if id == 0 { return false }
    if !ctx.drag.active && ctx.active == id && ctx.input.mouse_down {
        moved: Vec2 = ctx.input.mouse_position - ctx.press_position
        if moved.x * moved.x + moved.y * moved.y >= DRAG_START_DISTANCE * DRAG_START_DISTANCE {
            ctx.drag = {active = true, source = id, kind = IdFromString(kind)}
            ctx.drag.size = min(len(payload), DRAG_PAYLOAD_BYTES)
            copy(ctx.drag.data[:], payload[:ctx.drag.size])
        }
    }
    return ctx.drag.active && ctx.drag.source == id
}

// The same for a value: its bytes are the payload (at most DRAG_PAYLOAD_BYTES of it)
UiDragSourceValue :: proc(ctx: ^Context, kind: string, value: ^$T) -> bool where size_of(T) <= DRAG_PAYLOAD_BYTES {
    return UiDragSource(ctx, kind, mem_bytes(value))
}

@(private)
mem_bytes :: proc(value: ^$T) -> []u8 {
    return ([^]u8)(value)[:size_of(T)]
}

// Call right after the widget that takes what is dragged. `hovered` is true while something of this kind is over the widget (draw it as a target);
// `dropped` in the frame it was released over it, with the payload (valid until the next frame).
UiDropTarget :: proc(ctx: ^Context, kind: string) -> (payload: []u8, dropped: bool) {
    return dropTarget(ctx, kind)
}

@(private)
dropTarget :: proc(ctx: ^Context, kind: string) -> (payload: []u8, dropped: bool) {
    id: Id = ctx.last_id
    if id == 0 || !ctx.drag.active || ctx.drag.kind != IdFromString(kind) { return nil, false }
    if ctx.hover == id && ctx.input.mouse_released {
        return ctx.drag.data[:ctx.drag.size], true
    }
    return nil, false
}

// Something of this kind is being dragged and the pointer is over the widget declared just before
UiDropHover :: proc(ctx: ^Context, kind: string) -> bool {
    return ctx.drag.active && ctx.drag.kind == IdFromString(kind) && ctx.hover == ctx.last_id
}

// Is something dragged, and which widget it comes from
UiDragging :: proc(ctx: ^Context) -> (source: Id, active: bool) {
    return ctx.drag.source, ctx.drag.active
}

// The bytes that are dragged (valid until the next frame)
UiDragPayload :: proc(ctx: ^Context) -> []u8 {
    return ctx.drag.data[:ctx.drag.size]
}

// A label at the pointer while something is dragged
UiDragPreview :: proc(ctx: ^Context, text: string) {
    if !ctx.drag.active { return }
    ElementOpen(ctx, {
        layout = {padding = PaddingXY(8, 5)},
        floating = {attach_to = .ROOT, offset = ctx.input.mouse_position + {12, 12}, z_index = 450},
        draw = {kind = .PANEL, name = "drag", font_size = ctx.style.metrics.font_size},
    })
    TextOpen(ctx, text)
    ElementClose(ctx)
}

// The drag ends with the press: called by UiEnd after the targets of the frame had their say
@(private)
dragEnd :: proc(ctx: ^Context) {
    if ctx.drag.active && (ctx.input.mouse_released || !ctx.input.mouse_down) {
        ctx.drag = {}
    }
}
