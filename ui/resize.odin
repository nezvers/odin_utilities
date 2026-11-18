package ui

// Resizing by the pointer.
//   UiSplitter: the handle that sits between two sections and moves the border between them (side by side or stacked). The program keeps the
//   size of the first section, gives that section a fixed size and the other one Grow(): it takes whatever is left, more when the container gets bigger.
//   UiWindowResizable: a floating window with a title bar that is also resized by its edges and corners (the program keeps position and size);
//   what is inside takes the room when it is Grow().
//
//   if UiPanel(ctx, "area", {size = {Grow(), Grow()}, direction = .LEFT_TO_RIGHT}) {
//       if UiPanel(ctx, "list", {size = {Fixed(list_width), Grow()}}) { ... }
//       UiSplitter(ctx, "split", &list_width, .HORIZONTAL)
//       if UiPanel(ctx, "details", {size = {Grow(), Grow()}}) { ... }
//   }

// Which way the sections are arranged, which is the way the handle is dragged
SplitDirection :: enum u8 {
    HORIZONTAL,         // side by side (a row): the handle is a vertical bar that moves left and right
    VERTICAL,           // one above the other (a column): the handle is a horizontal bar that moves up and down
}

SPLITTER_THICKNESS :: f32(6)
SPLITTER_KEY_STEP :: f32(10)    // pixels per press of an arrow key when the splitter has the focus
GRIP_EDGE :: f32(6)             // how wide the edge of a resizable window takes the pointer
GRIP_CORNER :: f32(14)          // and the square of its corners

// The handle between two sections. `size` is the size (along the direction) of the section before it, in pixels, kept by the program and used
// by that section as its Fixed size; the section after the handle is Grow(). Dragging it with the pointer, or the arrow keys when it has the
// focus (left / right, up / down), changes `size` by a step: it stays between `min_before` and the most the container leaves (the container
// minus the handle minus `min_after`; it is known when the container has a name, else only `max_before` limits, 0 for no limit). True when
// `size` changed in this call.
UiSplitter :: proc(ctx: ^Context, name: string, size: ^f32, direction: SplitDirection = .HORIZONTAL, min_before: f32 = 40, min_after: f32 = 40, max_before: f32 = 0, thickness: f32 = SPLITTER_THICKNESS) -> (changed: bool) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id)
    axis: int = 0 if direction == .HORIZONTAL else 1
    limit: f32 = splitLimit(ctx, axis, min_before, min_after, max_before, thickness)
    before: f32 = size^
    if interaction.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) {
        if ctx.input.mouse_pressed {
            state.drag = ctx.input.mouse_position
        } else {
            // the grab point follows only what was really applied: a pointer pushed past a limit does not pull the border away from it
            wanted: f32 = size^ + (ctx.input.mouse_position[axis] - state.drag[axis])
            applied: f32 = clamp(wanted, min_before, limit)
            state.drag[axis] += applied - size^
            size^ = applied
        }
    }
    if direction == .HORIZONTAL {
        state.adjustable = true
    } else {
        state.adjust_vertical = true
    }
    if state.pending_adjust != 0 {
        size^ += f32(state.pending_adjust) * SPLITTER_KEY_STEP
    }
    state.pending_adjust = 0
    size^ = clamp(size^, min_before, limit)
    changed = size^ != before

    flags: Flags
    if interaction.hovered { flags += {.HOVERED} }
    if interaction.pressed { flags += {.PRESSED} }
    if ctx.focus == id { flags += {.FOCUSED} }
    ElementOpen(ctx, {
        id = id,
        layout = {size = {Fixed(thickness), Grow()} if direction == .HORIZONTAL else {Grow(), Fixed(thickness)}},
        hit = {.INTERACTIVE},
        cursor = .RESIZE_HORIZONTAL if direction == .HORIZONTAL else .RESIZE_VERTICAL,
        draw = {kind = .SPLITTER, name = IdSplitName(name), actual = f32(direction), flags = flags, font_size = ctx.style.metrics.font_size},
    })
    ElementClose(ctx)
    return
}

// The most the section before the handle may have: what the container had inside of it in the last frame, minus the handle, the gaps and the
// room the section after it keeps. Unknown (the container has no name, or this is the first frame): `max_before`, 0 for no limit.
@(private)
splitLimit :: proc(ctx: ^Context, axis: int, min_before: f32, min_after: f32, max_before: f32, thickness: f32) -> f32 {
    limit: f32 = max_before if max_before > 0 else INFINITE
    if ctx.open_count > 0 {
        parent: ^Element = &ctx.elements[ctx.open_stack[ctx.open_count - 1]]
        state: ^WidgetState = stateFind(ctx, parent.id)
        if state != nil && state.rect.z > 0 && state.rect.w > 0 {
            padding: f32 = parent.decl.layout.padding.left + parent.decl.layout.padding.right if axis == 0 else parent.decl.layout.padding.top + parent.decl.layout.padding.bottom
            extent: f32 = state.rect.z if axis == 0 else state.rect.w
            gaps: f32 = parent.decl.layout.gap * 2
            limit = min(limit, extent - padding - gaps - thickness - min_after)
        }
    }
    return max(limit, min_before)
}

// ------------------------------------------------------------------------------------------------------------------------
// A window that is resized

@(private)
ResizeEdge :: enum u8 {
    LEFT,
    RIGHT,
    TOP,
    BOTTOM,
}
@(private)
ResizeEdges :: bit_set[ResizeEdge; u8]

// Like UiWindowTitled (dragged by its title bar, `position` is kept by the program) and the program keeps `size` too: the window is resized by
// dragging its edges and its corners, and never gets smaller than `min_size` (or bigger than `max_size`, 0 for no limit on an axis). The body
// below the title bar fills the rest of the window and cuts what does not fit: widgets that are Grow() take the room a bigger window gives.
// The top edge stays below the top of the screen (y >= 0) like the title bar does.
@(deferred_in = UiWindowResizableEnd)
UiWindowResizable :: proc(ctx: ^Context, title: string, position: ^Vec2, size: ^Vec2, min_size: Vec2 = {160, 100}, max_size: Vec2 = {}, layout: Layout = {}, z_index: i16 = 0) -> bool {
    id: Id = UiId(ctx, title)
    _ = stateGet(ctx, id)
    size.x = windowAxis(size.x, min_size.x, max_size.x)
    size.y = windowAxis(size.y, min_size.y, max_size.y)
    title_id: Id = IdFromString("title", id)
    state: ^WidgetState = stateGet(ctx, title_id)
    interaction: Interaction = widgetBehavior(ctx, title_id)
    if interaction.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) {
        if ctx.input.mouse_pressed {
            state.drag = ctx.input.mouse_position
        } else {
            position^ += ctx.input.mouse_position - state.drag
            state.drag = ctx.input.mouse_position
            position.y = max(position.y, 0)
        }
    }
    metrics: ^Metrics = &ctx.style.metrics
    ElementOpen(ctx, {
        id = id,
        layout = {size = {Fixed(size.x), Fixed(size.y)}, direction = .TOP_TO_BOTTOM},
        floating = {attach_to = .ROOT, parent_point = .LEFT_TOP, element_point = .LEFT_TOP, offset = position^, z_index = z_index, capture = true},
        hit = {.BLOCKER},
        draw = {kind = .PANEL, name = IdSplitName(title), font_size = metrics.font_size},
    })
    windowGrips(ctx, id, position, size, min_size, max_size)
    ElementOpen(ctx, {
        id = title_id,
        layout = {size = {Grow(), Fixed(metrics.control_height)}},
        hit = {.INTERACTIVE, .NO_FOCUS},
        draw = {kind = .WINDOW_TITLE, name = IdSplitName(title), font_size = metrics.font_size, flags = {.FOCUSED} if ctx.focus == title_id else {}},
    })
    ElementClose(ctx)
    body: Layout = layoutOrDefault(ctx, layout)
    body.size = {Grow(), Grow()}
    return ElementOpen(ctx, {layout = body, clip = {horizontal = true, vertical = true}})
}

UiWindowResizableEnd :: proc(ctx: ^Context, title: string, position: ^Vec2, size: ^Vec2, min_size: Vec2 = {160, 100}, max_size: Vec2 = {}, layout: Layout = {}, z_index: i16 = 0) {
    ElementClose(ctx)       // the body
    ElementClose(ctx)       // the window
}

@(private)
windowAxis :: proc(value: f32, minimum: f32, maximum: f32) -> f32 {
    result: f32 = max(value, minimum)
    if maximum > 0 { result = min(result, max(maximum, minimum)) }
    return result
}

// The eight places of a window that take the pointer: floating children of the window (they take no room in it), the corners last so they win
// where they meet an edge. Only the bottom right corner draws something (a grip that shows the window can be resized).
@(private)
windowGrips :: proc(ctx: ^Context, window: Id, position: ^Vec2, size: ^Vec2, min_size: Vec2, max_size: Vec2) {
    Grip :: struct {
        name: string,
        edges: ResizeEdges,
        point: AttachPoint,
        size: Size,
        cursor: Cursor,
    }
    grips: [8]Grip = {
        {"grip.left", {.LEFT}, .LEFT_TOP, {Fixed(GRIP_EDGE), Grow()}, .RESIZE_HORIZONTAL},
        {"grip.right", {.RIGHT}, .RIGHT_TOP, {Fixed(GRIP_EDGE), Grow()}, .RESIZE_HORIZONTAL},
        {"grip.top", {.TOP}, .LEFT_TOP, {Grow(), Fixed(GRIP_EDGE)}, .RESIZE_VERTICAL},
        {"grip.bottom", {.BOTTOM}, .LEFT_BOTTOM, {Grow(), Fixed(GRIP_EDGE)}, .RESIZE_VERTICAL},
        {"grip.top_left", {.TOP, .LEFT}, .LEFT_TOP, {Fixed(GRIP_CORNER), Fixed(GRIP_CORNER)}, .RESIZE_DIAGONAL_NWSE},
        {"grip.top_right", {.TOP, .RIGHT}, .RIGHT_TOP, {Fixed(GRIP_CORNER), Fixed(GRIP_CORNER)}, .RESIZE_DIAGONAL_NESW},
        {"grip.bottom_left", {.BOTTOM, .LEFT}, .LEFT_BOTTOM, {Fixed(GRIP_CORNER), Fixed(GRIP_CORNER)}, .RESIZE_DIAGONAL_NESW},
        {"grip.bottom_right", {.BOTTOM, .RIGHT}, .RIGHT_BOTTOM, {Fixed(GRIP_CORNER), Fixed(GRIP_CORNER)}, .RESIZE_DIAGONAL_NWSE},
    }
    for grip in grips {
        id: Id = IdFromString(grip.name, window)
        state: ^WidgetState = stateGet(ctx, id)
        interaction: Interaction = widgetBehavior(ctx, id)
        if interaction.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) {
            if ctx.input.mouse_pressed {
                state.drag = ctx.input.mouse_position
            } else {
                gripDrag(state, grip.edges, position, size, min_size, max_size, ctx.input.mouse_position)
            }
        }
        flags: Flags
        if interaction.hovered { flags += {.HOVERED} }
        if interaction.pressed { flags += {.PRESSED} }
        ElementOpen(ctx, {
            id = id,
            layout = {size = grip.size},
            floating = {attach_to = .PARENT, parent_point = grip.point, element_point = grip.point},
            hit = {.INTERACTIVE, .NO_FOCUS},
            cursor = grip.cursor,
            draw = {kind = .RESIZE_GRIP if grip.name == "grip.bottom_right" else .NONE, name = grip.name, flags = flags},
        })
        ElementClose(ctx)
    }
}

// One step of a drag at an edge or a corner. The edge that moves follows the pointer; the opposite edge stays where it is: dragging the left
// or the top edge changes the position by what the size changed. The grab point moves by what was applied only, so a window that is at its
// smallest does not follow the pointer past that, and grows again only when the pointer is back at its edge.
@(private)
gripDrag :: proc(state: ^WidgetState, edges: ResizeEdges, position: ^Vec2, size: ^Vec2, min_size: Vec2, max_size: Vec2, pointer: Vec2) {
    delta: Vec2 = pointer - state.drag
    if .RIGHT in edges {
        applied: f32 = windowAxis(size.x + delta.x, min_size.x, max_size.x)
        state.drag.x += applied - size.x
        size.x = applied
    }
    if .LEFT in edges {
        applied: f32 = windowAxis(size.x - delta.x, min_size.x, max_size.x)
        state.drag.x += size.x - applied
        position.x += size.x - applied
        size.x = applied
    }
    if .BOTTOM in edges {
        applied: f32 = windowAxis(size.y + delta.y, min_size.y, max_size.y)
        state.drag.y += applied - size.y
        size.y = applied
    }
    if .TOP in edges {
        // the top does not go above the screen
        applied: f32 = min(windowAxis(size.y - delta.y, min_size.y, max_size.y), size.y + position.y)
        applied = max(applied, min(min_size.y, size.y))
        state.drag.y += size.y - applied
        position.y += size.y - applied
        size.y = applied
    }
}
