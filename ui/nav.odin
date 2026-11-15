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
// The focused widget has the FOCUSED flag for the style. A focused slider takes left and right as steps of its value (unless linked).
// A focused text field takes the keyboard: leave it with Escape or with a linked direction.

@(private)
focusable :: proc(box: ^HitBox) -> bool {
    return .INTERACTIVE in box.kinds && box.id != 0 && RectOverlaps(box.rect, box.clip_rect)
}

// Moves the focus one step in `direction`. True when the focus moved (or a slider took the step). With nothing focused the first widget is
// focused. The layout of the last frame is used, so it does nothing before the first frame is done.
UiNavigate :: proc(ctx: ^Context, direction: Direction) -> bool {
    if ctx.focus == 0 {
        for i in 0 ..< ctx.hit_count {
            if focusable(&ctx.hits[i]) {
                ctx.focus = ctx.hits[i].id
                return true
            }
        }
        return false
    }
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
        if ctx.hits[i].id == ctx.focus && focusable(&ctx.hits[i]) { current = &ctx.hits[i] }
    }
    if current == nil { return false }
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
        if box.id == ctx.focus || !focusable(box) { continue }
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
    return true
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
