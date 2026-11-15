package ui

// Navigation without a pointer: the focus moves from widget to widget by a direction, for a keyboard or a gamepad and for tests that
// drive the ui without a mouse. Nothing here reads a device: the program calls these procs from its own input (arrow keys, a d-pad, a
// stick that went past a dead zone, a script) after UiBegin.
//
//     if pad_down_pressed { ui.UiNavigate(&ctx, .DOWN) }
//     if pad_confirm_pressed { ui.UiActivate(&ctx) }
//
// By default the focus goes to the nearest widget in the direction (like Godot). A widget may send a direction somewhere else or nowhere:
//
//     ui.UiButton(&ctx, "Play")
//     ui.UiNavLink(&ctx, .DOWN, ui.UiId(&ctx, "Quit"))       // jump over what is between
//     ui.UiNavBlock(&ctx, .UP)                               // the top of the menu: up goes nowhere
//
// The default actions of Godot (ui_accept, ui_cancel, ui_focus_next, ui_home, ui_page_down...) are the actions of ui.Action: a glue maps its keys
// and gamepad buttons to Input.actions and UiBegin applies them (UiAction), so a program only reads UiCancelled to close its dialogs.
//
// The focused widget has the FOCUSED flag for the style. A focused slider takes left and right as steps of its value (unless linked).
// A focused text field takes the keyboard: leave it with Escape or with a linked direction.

// A widget the focus can go to. One that is scrolled out of its container counts too: the container shows it when the focus gets there.
@(private)
focusable :: proc(ctx: ^Context, box: ^HitBox) -> bool {
    if ctx.modal_root != 0 && box.root != ctx.modal_root { return false }      // a dialog is open: the focus stays in it
    return .INTERACTIVE in box.kinds && box.id != 0
}

// Moves the focus one step in `direction`. True when the focus moved (or a slider took the step). With nothing focused the first widget is
// focused. The layout of the last frame is used, so it does nothing before the first frame is done.
UiNavigate :: proc(ctx: ^Context, direction: Direction) -> bool {
    if ctx.focus == 0 { return focusEdge(ctx, false) }
    state: ^WidgetState = stateFind(ctx, ctx.focus)
    if state != nil {
        link: Id = state.nav[direction]
        if link == NAV_BLOCK { return false }
        if link != 0 {
            ctx.focus = link
            return true
        }
        if state.adjustable && (direction == .LEFT || direction == .RIGHT) {
            state.pending_adjust += 1 if direction == .RIGHT else -1
            return true
        }
    }
    current: ^HitBox
    for i in 0 ..< ctx.hit_count {
        if ctx.hits[i].id == ctx.focus && focusable(ctx, &ctx.hits[i]) { current = &ctx.hits[i] }
    }
    if current == nil { return focusEdge(ctx, false) }       // the focused widget is not on screen any more: start again
    from: Vec2 = RectCenter(current.rect)
    heading: Vec2 = {0, 0}
    switch direction {
    case .UP: heading = {0, -1}
    case .DOWN: heading = {0, 1}
    case .LEFT: heading = {-1, 0}
    case .RIGHT: heading = {1, 0}
    }
    best: Id = 0
    best_score: f32 = INFINITE
    for i in 0 ..< ctx.hit_count {
        box: ^HitBox = &ctx.hits[i]
        if box.id == ctx.focus || !focusable(ctx, box) { continue }
        delta: Vec2 = RectCenter(box.rect) - from
        along: f32 = delta.x * heading.x + delta.y * heading.y
        if along <= 0.01 { continue }                   // not in that direction
        across: f32 = abs(delta.x * heading.y) + abs(delta.y * heading.x)
        // a widget that overlaps on the other axis is straight ahead, even when its center is off
        overlap: bool = false
        if heading.x == 0 {
            overlap = box.rect.x < current.rect.x + current.rect.z && current.rect.x < box.rect.x + box.rect.z
        } else {
            overlap = box.rect.y < current.rect.y + current.rect.w && current.rect.y < box.rect.y + box.rect.w
        }
        score: f32 = along + across * (0.5 if overlap else 3)
        if score < best_score {
            best_score = score
            best = box.id
        }
    }
    if best == 0 { return false }
    ctx.focus = best
    ctx.reveal = true
    return true
}

// The first (or the last) widget of the layout that the focus can go to
@(private)
focusEdge :: proc(ctx: ^Context, last: bool) -> bool {
    found: Id = 0
    for i in 0 ..< ctx.hit_count {
        if !focusable(ctx, &ctx.hits[i]) { continue }
        found = ctx.hits[i].id
        if !last { break }
    }
    if found == 0 { return false }
    ctx.focus = found
    ctx.reveal = true
    return true
}

// The next (step 1) or previous (step -1) widget in the order of the layout, around the end
@(private)
focusCycle :: proc(ctx: ^Context, step: int) -> bool {
    first, last: int = -1, -1
    current: int = -1
    count: int = 0
    for i in 0 ..< ctx.hit_count {
        if !focusable(ctx, &ctx.hits[i]) { continue }
        if first < 0 { first = i }
        last = i
        count += 1
        if ctx.hits[i].id == ctx.focus { current = i }
    }
    if count == 0 { return false }
    if current < 0 { return focusEdge(ctx, step < 0) }
    target: int = current
    for {
        target += step
        if target < 0 { target = last }
        if target >= ctx.hit_count { target = first }
        if focusable(ctx, &ctx.hits[target]) { break }
    }
    if ctx.hits[target].id == ctx.focus { return false }
    // moving into another window or popup: back to the widget that had the focus there, not to its first one
    if ctx.hits[target].root != ctx.hits[current].root {
        if remembered: Id = focusMemoryOf(ctx, ctx.hits[target].root); remembered != 0 {
            ctx.focus = remembered
            ctx.reveal = true
            return true
        }
    }
    ctx.focus = ctx.hits[target].id
    ctx.reveal = true
    return true
}

// The widget of this window (or popup, a floating root; 0 is the main layer) that had the focus last, when it is still there
@(private)
focusMemoryOf :: proc(ctx: ^Context, root: Id) -> Id {
    for entry in ctx.focus_memory[:ctx.focus_memory_count] {
        if entry.root != root { continue }
        for i in 0 ..< ctx.hit_count {
            box: ^HitBox = &ctx.hits[i]
            if box.id == entry.focus && box.root == root && focusable(ctx, box) { return entry.focus }
        }
    }
    return 0
}

// Enters a window or popup (a floating root: the id of its element, UiIdPath("Window")): the widget that had the focus in it, or its first one.
// With the main layer (root 0) it is the same for what is not in a window.
UiFocusRoot :: proc(ctx: ^Context, root: Id) -> bool {
    if remembered: Id = focusMemoryOf(ctx, root); remembered != 0 {
        ctx.focus = remembered
        ctx.reveal = true
        return true
    }
    for i in 0 ..< ctx.hit_count {
        box: ^HitBox = &ctx.hits[i]
        if box.root == root && focusable(ctx, box) {
            ctx.focus = box.id
            ctx.reveal = true
            return true
        }
    }
    return false
}

// A page up or down: the focus moves through the widgets in that direction until it has gone as far as the container it is in is high
@(private)
focusPage :: proc(ctx: ^Context, direction: Direction) -> bool {
    if ctx.focus == 0 { return focusEdge(ctx, direction == .DOWN) }
    start: Vec2
    view_height: f32 = ctx.screen.y * 0.5
    for i in 0 ..< ctx.hit_count {
        box: ^HitBox = &ctx.hits[i]
        if box.id == ctx.focus {
            start = RectCenter(box.rect)
            // inside of a clipping container the page is the height of its view
            if box.clip_rect.w < INFINITE * 0.1 { view_height = box.clip_rect.w }
        }
    }
    moved: bool = false
    for _ in 0 ..< 64 {
        if !UiNavigate(ctx, direction) { break }
        moved = true
        for i in 0 ..< ctx.hit_count {
            box: ^HitBox = &ctx.hits[i]
            if box.id == ctx.focus && abs(RectCenter(box.rect).y - start.y) >= view_height * 0.9 { return true }
        }
    }
    return moved
}

// One of the default actions (see Action), as if its key had been pressed: UiBegin does this for the actions of the input of the frame, a
// program or a test may call it too. True when it did something.
UiAction :: proc(ctx: ^Context, action: Action) -> bool {
    focused: ^WidgetState = stateFind(ctx, ctx.focus)
    editing: bool = focused != nil && focused.editing
    switch action {
    case .UP: return UiNavigate(ctx, .UP)
    case .DOWN: return UiNavigate(ctx, .DOWN)
    case .LEFT: return !editing && UiNavigate(ctx, .LEFT)
    case .RIGHT: return !editing && UiNavigate(ctx, .RIGHT)
    case .ACCEPT, .SELECT:
        if editing || ctx.focus == 0 { return false }
        ctx.activate = true
        return true
    case .CANCEL:
        ctx.cancel_pending = true
        return true
    case .FOCUS_NEXT: return focusCycle(ctx, 1)
    case .FOCUS_PREV: return focusCycle(ctx, -1)
    case .HOME: return !editing && focusEdge(ctx, false)
    case .END: return !editing && focusEdge(ctx, true)
    case .PAGE_UP: return !editing && focusPage(ctx, .UP)
    case .PAGE_DOWN: return !editing && focusPage(ctx, .DOWN)
    }
    return false
}

// The action came in this frame's input (to tell ACCEPT from SELECT, or to read an action nothing in the ui takes)
UiActionPressed :: proc(ctx: ^Context, action: Action) -> bool {
    return action in ctx.input.actions
}

// The person asked to cancel and nothing of the ui took it (a dropdown that was open closed, a text field with the focus let go, and those
// are not "cancel" any more): a program closes its dialog or its menu. Ask after the widgets of the frame were declared.
UiCancelled :: proc(ctx: ^Context) -> bool {
    return ctx.cancel_pending
}

// The confirm key or button: the focused widget is clicked in this frame (call it after UiBegin, before the widgets are declared)
UiActivate :: proc(ctx: ^Context) {
    ctx.activate = true
}

// Gives the focus to a widget (a menu that opens with its first button focused)
UiFocus :: proc(ctx: ^Context, id: Id) {
    ctx.focus = id
}

UiFocused :: proc(ctx: ^Context) -> Id {
    return ctx.focus
}

UiIsFocused :: proc(ctx: ^Context, id: Id) -> bool {
    return ctx.focus == id
}

// Where `direction` goes from the widget declared last: to the widget `target`. Call it right after the widget.
UiNavLink :: proc(ctx: ^Context, direction: Direction, target: Id) {
    state: ^WidgetState = stateFind(ctx, ctx.last_id)
    if state != nil { state.nav[direction] = target }
}

// From the widget declared last `direction` goes nowhere
UiNavBlock :: proc(ctx: ^Context, direction: Direction) {
    UiNavLink(ctx, direction, NAV_BLOCK)
}
