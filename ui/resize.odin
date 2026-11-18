package ui

// Resizing by the pointer, with nothing to configure and nothing for the program to keep.
//   UiSplit: a container with two sections and the handle between them. It keeps the proportion itself (so it stays when the container grows or
//   shrinks), builds the handle, sizes the sections, keeps both above their minimum and cuts what does not fit.
//   UiWindowResizable: a floating window with a title bar that is also resized by its edges and corners. It keeps its position and size itself
//   (a program that wants to own them passes pointers), stays inside of the screen, and its body grows with it.
//
//   if ui.UiWindowResizable(&ctx, "Workspace", initial_position = {60, 40}, initial_size = {520, 360}) {
//       if ui.UiSplit(&ctx, "main", .HORIZONTAL, 0.3) {         // side by side; .VERTICAL: one above the other
//           if ui.UiSplitFirst(&ctx) { ... }
//           if ui.UiSplitSecond(&ctx) { ... }                    // a split inside of a section is a three way split
//       }
//   }

// Which way the sections are arranged, which is the way the handle is dragged
SplitDirection :: enum u8 {
    HORIZONTAL,         // side by side (a row): the handle is a vertical bar that moves left and right
    VERTICAL,           // one above the other (a column): the handle is a horizontal bar that moves up and down
}

SPLITTER_THICKNESS :: f32(6)
SPLITTER_KEY_STEP :: f32(10)    // pixels per press of an arrow key when the handle has the focus
SPLIT_RATIO_MIN :: f32(0.02)
GRIP_EDGE :: f32(6)             // how wide the edge of a resizable window takes the pointer
GRIP_CORNER :: f32(14)          // and the square of its corners
WINDOW_KEEP_VISIBLE :: f32(80)  // of a window that is pushed off the screen, this much of its width stays on it
UI_MAX_SPLITS :: 8              // splits inside of splits

@(private)
SplitFrame :: struct {
    id: Id,
    direction: SplitDirection,
    sections: int,              // how many were declared (the missing ones are made empty when the split ends)
    min_first: f32,
    min_second: f32,
    ratio: f32,                 // what the first section has this frame: the stored one, kept between the minimums
    extent: f32,                // the room the container had along the direction in the last frame (0: unknown, the first frame)
    pixels: f32,                // the first section starts with this many pixels until the room is known (0: the ratio is used)
}

// A container with two sections and a handle between them: `UiSplitFirst` and `UiSplitSecond` declare what goes in each. `ratio` is the part
// of the container the first section starts with (0..1), or `first_size` pixels when that is given instead; dragging the handle with the pointer, or the arrow keys when it has the focus,
// changes it, and the split remembers it. The sections keep at least `min_first` and `min_second` pixels, whatever the ratio and the size of the
// container; a content that does not fit is cut at the edge of its section. The container takes all the room it is given unless `size` says
// otherwise. Declared out of order (the second before the first) or not at all, a section is made empty; one too many is not shown
// (and is a `SPLIT_MISUSE` problem): the layout stays right either way.
@(deferred_in = UiSplitEnd)
UiSplit :: proc(ctx: ^Context, name: string, direction: SplitDirection = .HORIZONTAL, ratio: f32 = 0.5, size: Size = {}, min_first: f32 = 40, min_second: f32 = 40, first_size: f32 = 0) -> bool {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    if !state.initialized {
        state.initialized = true
        state.ratio = clamp(ratio, SPLIT_RATIO_MIN, 1 - SPLIT_RATIO_MIN)
        state.split_pixels = max(first_size, 0)
    }
    // a start size in pixels becomes a proportion as soon as the room is known (the first frame has the pixels themselves)
    if state.split_pixels > 0 && splitExtent(state, direction) > 0 {
        state.ratio = clamp(state.split_pixels / splitExtent(state, direction), SPLIT_RATIO_MIN, 1 - SPLIT_RATIO_MIN)
        state.split_pixels = 0
    }
    open: bool = ElementOpen(ctx, {
        id = id,
        layout = {
            size = {growWhenUnset(size.width), growWhenUnset(size.height)},
            direction = .LEFT_TO_RIGHT if direction == .HORIZONTAL else .TOP_TO_BOTTOM,
        },
        clip = {horizontal = true, vertical = true, cut = true},      // what is inside never makes the split bigger than the room it was given
    })
    if ctx.split_count >= UI_MAX_SPLITS {
        ctx.problems += {.SPLIT_MISUSE}
        ctx.split_lost += 1                         // deeper than the stack: its sections are plain boxes, UiSplitEnd only closes it
        return open
    }
    frame: ^SplitFrame = &ctx.split_stack[ctx.split_count]
    ctx.split_count += 1
    frame^ = {id = id, direction = direction, min_first = max(min_first, 0), min_second = max(min_second, 0)}
    // between the minimums of the sections, for the room the container had in the last frame
    frame.ratio = state.ratio
    extent: f32 = splitExtent(state, direction)
    frame.extent = extent
    frame.pixels = state.split_pixels
    if extent > 0 {
        low: f32 = frame.min_first / extent
        high: f32 = max((extent - SPLITTER_THICKNESS - frame.min_second) / extent, low)
        frame.ratio = clamp(state.ratio, low, high)
    }
    return open
}

UiSplitEnd :: proc(ctx: ^Context, name: string, direction: SplitDirection = .HORIZONTAL, ratio: f32 = 0.5, size: Size = {}, min_first: f32 = 40, min_second: f32 = 40, first_size: f32 = 0) {
    if ctx.split_lost > 0 {
        ctx.split_lost -= 1
        ElementClose(ctx)
        return
    }
    if ctx.split_count > 0 {
        frame: ^SplitFrame = &ctx.split_stack[ctx.split_count - 1]
        if frame.sections == 0 {
            splitSectionOpen(ctx, frame, false)
            ElementClose(ctx)
            frame.sections = 1
        }
        if frame.sections == 1 {
            splitHandle(ctx, frame)
            splitSectionOpen(ctx, frame, true)
            ElementClose(ctx)
        }
        ctx.split_count -= 1
    }
    ElementClose(ctx)
}

// What goes in the first section (the left one, or the top one).
@(deferred_in = UiSplitSectionEnd)
UiSplitFirst :: proc(ctx: ^Context) -> bool {
    frame: ^SplitFrame = splitFrame(ctx)
    if frame == nil || frame.sections >= 1 {
        return splitMisuse(ctx, frame != nil)
    }
    frame.sections = 1
    return splitSectionOpen(ctx, frame, false)
}

// What goes in the second section (the right one, or the bottom one). The handle is put in front of it by the split.
@(deferred_in = UiSplitSectionEnd)
UiSplitSecond :: proc(ctx: ^Context) -> bool {
    frame: ^SplitFrame = splitFrame(ctx)
    if frame == nil || frame.sections >= 2 {
        return splitMisuse(ctx, frame != nil)
    }
    if frame.sections == 0 {
        splitSectionOpen(ctx, frame, false)         // the first was left out: an empty one
        ElementClose(ctx)
    }
    frame.sections = 2
    splitHandle(ctx, frame)
    return splitSectionOpen(ctx, frame, true)
}

UiSplitSectionEnd :: proc(ctx: ^Context) {
    ElementClose(ctx)
}

// The proportion of a split (0..1: the part of the container the first section has), to save it or to set it: `UiSplitRatio(ctx, UiIdPath("Workspace", "main"))`.
UiSplitRatio :: proc(ctx: ^Context, id: Id) -> f32 {
    state: ^WidgetState = stateFind(ctx, id)
    return state.ratio if state != nil else 0
}

UiSplitSetRatio :: proc(ctx: ^Context, id: Id, ratio: f32) {
    state: ^WidgetState = stateFind(ctx, id)
    if state != nil {
        state.ratio = clamp(ratio, SPLIT_RATIO_MIN, 1 - SPLIT_RATIO_MIN)
        state.initialized = true
    }
}

@(private)
growWhenUnset :: proc(axis: SizingAxis) -> SizingAxis {
    if axis.kind == .FIT && axis.min == 0 && axis.max == 0 { return Grow() }
    return axis
}

@(private)
splitFrame :: proc(ctx: ^Context) -> ^SplitFrame {
    if ctx.split_lost > 0 || ctx.split_count == 0 { return nil }
    return &ctx.split_stack[ctx.split_count - 1]
}

// A section where there should not be one. Outside of a split: a plain box that takes the room it is given. A third one inside of a split: a box
// with no size that cuts everything (its widgets exist, nothing of them is shown), so that it cannot disturb the sections that are right.
@(private)
splitMisuse :: proc(ctx: ^Context, inside: bool) -> bool {
    ctx.problems += {.SPLIT_MISUSE}
    if inside {
        return ElementOpen(ctx, {layout = {size = {Fixed(0), Fixed(0)}}, clip = {horizontal = true, vertical = true, cut = true}})
    }
    return ElementOpen(ctx, {layout = {size = {Grow(), Grow()}}})
}

// The room the container had along the direction in the last frame (0: not known yet).
@(private)
splitExtent :: proc(state: ^WidgetState, direction: SplitDirection) -> f32 {
    return state.rect.z if direction == .HORIZONTAL else state.rect.w
}

// A section: the first has its part of the container (a percent, so it is right in the very first frame too) and never less than its minimum;
// the second takes what is left, never less than its minimum. Both cut what does not fit. The second is also a percent (the rest of the
// container, minus the handle) once the room is known, because a Grow section would be as wide as its content when that is wider than the
// room, and push what is inside of it out of the split.
@(private)
splitSectionOpen :: proc(ctx: ^Context, frame: ^SplitFrame, second: bool) -> bool {
    along: SizingAxis
    if second {
        if frame.extent > 0 {
            along = Percent(max(1 - frame.ratio - SPLITTER_THICKNESS / frame.extent, 0))
        } else {
            along = Grow(frame.min_second)
        }
    } else if frame.pixels > 0 && frame.extent == 0 {
        along = Fixed(max(frame.pixels, frame.min_first))      // the first frame: the room is not known, so no percent yet
    } else {
        along = Percent(frame.ratio)
        along.min = frame.min_first
    }
    size: Size = {along, Grow()} if frame.direction == .HORIZONTAL else {Grow(), along}
    return ElementOpen(ctx, {layout = {size = size}, clip = {horizontal = true, vertical = true, cut = true}})
}

// The handle between the sections: dragging it (or the arrow keys) changes the stored proportion. The pointer moves the border by what it
// moved; a pointer pushed past a limit does not pull the border away from it, the border follows again from where it is.
@(private)
splitHandle :: proc(ctx: ^Context, frame: ^SplitFrame) {
    id: Id = IdFromString("handle", frame.id)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id)
    container: ^WidgetState = stateFind(ctx, frame.id)
    horizontal: bool = frame.direction == .HORIZONTAL
    axis: int = 0 if horizontal else 1
    extent: f32 = splitExtent(container, frame.direction) if container != nil else 0
    if container != nil && extent > 0 {
        shown: f32 = frame.ratio * extent
        smallest: f32 = frame.min_first
        largest: f32 = max(extent - SPLITTER_THICKNESS - frame.min_second, smallest)
        wanted: f32 = shown
        if interaction.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) {
            if ctx.input.mouse_pressed {
                state.drag = ctx.input.mouse_position
            } else {
                wanted = shown + (ctx.input.mouse_position[axis] - state.drag[axis])
            }
        }
        if state.pending_adjust != 0 {
            wanted = shown + f32(state.pending_adjust) * SPLITTER_KEY_STEP
        }
        if wanted != shown {
            applied: f32 = clamp(wanted, smallest, largest)
            state.drag[axis] += applied - shown       // the grab point follows only what was applied
            container.ratio = clamp(applied / extent, SPLIT_RATIO_MIN, 1 - SPLIT_RATIO_MIN)
        }
    }
    state.pending_adjust = 0
    if horizontal {
        state.adjustable = true
    } else {
        state.adjust_vertical = true
    }
    flags: Flags
    if interaction.hovered { flags += {.HOVERED} }
    if interaction.pressed { flags += {.PRESSED} }
    if ctx.focus == id { flags += {.FOCUSED} }
    ElementOpen(ctx, {
        id = id,
        layout = {size = {Fixed(SPLITTER_THICKNESS), Grow()} if horizontal else {Grow(), Fixed(SPLITTER_THICKNESS)}},
        hit = {.INTERACTIVE},
        cursor = .RESIZE_HORIZONTAL if horizontal else .RESIZE_VERTICAL,
        draw = {kind = .SPLITTER, name = "split", actual = f32(frame.direction), flags = flags, font_size = ctx.style.metrics.font_size},
    })
    ElementClose(ctx)
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

// Like UiWindowTitled (dragged by its title bar) and resized by its four edges and its four corners. The window keeps its own position and
// size: it starts at `initial_position` with `initial_size` (and `UiWindowPosition` / `UiWindowSize` tell where it is now), or the program
// owns them and passes `position` and `size` (both, or neither). Whatever is passed, the size stays between `min_size` and `max_size` (0:
// no limit on that axis) and never above the screen, and the window cannot be pushed off the screen: its title bar stays reachable. The body
// below the title bar fills the rest of the window and cuts what does not fit: widgets that are `Grow()` take the room a bigger window gives.
@(deferred_in = UiWindowResizableEnd)
UiWindowResizable :: proc(ctx: ^Context, title: string, position: ^Vec2 = nil, size: ^Vec2 = nil, min_size: Vec2 = {160, 100}, max_size: Vec2 = {}, layout: Layout = {}, z_index: i16 = 0, initial_position: Vec2 = {40, 40}, initial_size: Vec2 = {320, 240}) -> bool {
    id: Id = UiId(ctx, title)
    window: ^WidgetState = stateGet(ctx, id)
    if !window.initialized {
        window.initialized = true
        window.window_position = initial_position
        window.window_size = initial_size
    }
    where_: ^Vec2 = position if position != nil && size != nil else &window.window_position
    how_big: ^Vec2 = size if position != nil && size != nil else &window.window_size
    largest: Vec2 = windowLargest(ctx, max_size)
    how_big.x = windowAxis(how_big.x, min_size.x, largest.x)
    how_big.y = windowAxis(how_big.y, min_size.y, largest.y)
    windowKeepOnScreen(ctx, where_, how_big^)

    title_id: Id = IdFromString("title", id)
    title_state: ^WidgetState = stateGet(ctx, title_id)
    interaction: Interaction = widgetBehavior(ctx, title_id)
    if interaction.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) {
        if ctx.input.mouse_pressed {
            title_state.drag = ctx.input.mouse_position
        } else {
            where_^ += ctx.input.mouse_position - title_state.drag
            title_state.drag = ctx.input.mouse_position
            windowKeepOnScreen(ctx, where_, how_big^)
        }
    }
    metrics: ^Metrics = &ctx.style.metrics
    ElementOpen(ctx, {
        id = id,
        layout = {size = {Fixed(how_big.x), Fixed(how_big.y)}, direction = .TOP_TO_BOTTOM},
        floating = {attach_to = .ROOT, parent_point = .LEFT_TOP, element_point = .LEFT_TOP, offset = where_^, z_index = z_index, capture = true},
        hit = {.BLOCKER},
        draw = {kind = .PANEL, name = IdSplitName(title), font_size = metrics.font_size},
    })
    windowGrips(ctx, id, where_, how_big, min_size, largest)
    ElementOpen(ctx, {
        id = title_id,
        layout = {size = {Grow(), Fixed(metrics.control_height)}},
        hit = {.INTERACTIVE, .NO_FOCUS},
        draw = {kind = .WINDOW_TITLE, name = IdSplitName(title), font_size = metrics.font_size, flags = {.FOCUSED} if ctx.focus == title_id else {}},
    })
    ElementClose(ctx)
    body: Layout = layoutOrDefault(ctx, layout)
    body.size = {Grow(), Grow()}
    return ElementOpen(ctx, {layout = body, clip = {horizontal = true, vertical = true, cut = true}})
}

UiWindowResizableEnd :: proc(ctx: ^Context, title: string, position: ^Vec2 = nil, size: ^Vec2 = nil, min_size: Vec2 = {160, 100}, max_size: Vec2 = {}, layout: Layout = {}, z_index: i16 = 0, initial_position: Vec2 = {40, 40}, initial_size: Vec2 = {320,240}) {
    ElementClose(ctx)       // the body
    ElementClose(ctx)       // the window
}

// Where a window that keeps its own position is now (0 when there is no such window).
UiWindowPosition :: proc(ctx: ^Context, title: string) -> Vec2 {
    state: ^WidgetState = stateFind(ctx, UiId(ctx, title))
    return state.window_position if state != nil else {}
}

UiWindowSize :: proc(ctx: ^Context, title: string) -> Vec2 {
    state: ^WidgetState = stateFind(ctx, UiId(ctx, title))
    return state.window_size if state != nil else {}
}

// A window is never made bigger than the screen (when there is one), nor than `max_size`
@(private)
windowLargest :: proc(ctx: ^Context, max_size: Vec2) -> Vec2 {
    result: Vec2 = max_size
    for axis in 0 ..< 2 {
        if ctx.screen[axis] > 0 {
            result[axis] = min(result[axis], ctx.screen[axis]) if result[axis] > 0 else ctx.screen[axis]
        }
    }
    return result
}

// The title bar stays reachable: the window is not above the screen, and at least WINDOW_KEEP_VISIBLE of it is inside on the sides
@(private)
windowKeepOnScreen :: proc(ctx: ^Context, position: ^Vec2, size: Vec2) {
    if ctx.screen.x <= 0 || ctx.screen.y <= 0 { return }
    keep: f32 = min(WINDOW_KEEP_VISIBLE, size.x)
    position.x = clamp(position.x, keep - size.x, max(ctx.screen.x - keep, keep - size.x))
    position.y = clamp(position.y, 0, max(ctx.screen.y - ctx.style.metrics.control_height, 0))
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
