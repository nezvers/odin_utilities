package ui

// Edit mode: the user or the developer points at an element of the ui to choose it for editing (its style, see default_style/style_editor.odin). It needs nothing from the program but
// the call that turns it on:
//
//     ui.UiEditMode(&ctx, editing, rect_of_the_editor_panel)     // every frame (the rectangle is the panel's own: the pointer there is for the panel)
//     if target, found := ui.UiEditPicked(&ctx); found { ... }   // the element that was pressed
//
// While it is on, the library masks the ui: a press outside of the panel does not reach any widget (it is the pick, like the picking of the inspector), and after the layout the element under the pointer
// is covered by one more command, `EDIT_COVER`, put in the list just before the commands of the editing panel (at the end when there is none): above the ui that is edited and behind the panel (the style gives it a color: `Theme.edit_overlay`, a light veil of white, and
// `Theme.edit_selected` for the picked one; a style of your own draws it the way it wants). The element is the topmost thing that was drawn at the pointer, inside of the clips it lives in.

EditTarget :: struct {
    found: bool,
    kind: StyleKind,        // what the style draws it as
    id: Id,                 // 0: the element has none (a text, a decoration)
    rect: Rect,             // where it is, cut by the clips around it
    name: [EDIT_NAME_LENGTH]u8,
    name_length: int,
}

EDIT_NAME_LENGTH :: 40

EditMode :: struct {
    on: bool,
    panel: Rect,            // the panel of the editor in the last frame
    panel_id: Id,           // or the element of the panel: its rectangle is read after every layout
    pressed: bool,          // a press of this frame that was kept from the widgets
    hover: EditTarget,
    picked: EditTarget,
}

// The name of a target (the name of the widget that was drawn: a button's label, a field's name), empty when it has none
EditTargetName :: proc(target: ^EditTarget) -> string {
    return string(target.name[:target.name_length])
}

// Turns edit mode on or off; the panel is the editing window (the pointer inside of it works the window, not the mask): a rectangle, or better the id of its element (`UiId(ctx, "Style editor")`:
// the library reads where it is after every layout). Call every frame, or only when it changes.
UiEditMode :: proc(ctx: ^Context, on: bool, panel: Rect = {}, panel_id: Id = 0) {
    ctx.edit.on = on
    if panel_id != 0 {
        ctx.edit.panel_id = panel_id
    } else {
        ctx.edit.panel, ctx.edit.panel_id = panel, 0
    }
    if !on {
        ctx.edit.hover = {}
        ctx.edit.pressed = false
    }
}

UiEditHover :: proc(ctx: ^Context) -> (target: EditTarget, found: bool) {
    return ctx.edit.hover, ctx.edit.hover.found
}

UiEditPicked :: proc(ctx: ^Context) -> (target: EditTarget, found: bool) {
    return ctx.edit.picked, ctx.edit.picked.found
}

UiEditClear :: proc(ctx: ^Context) {
    ctx.edit.picked = {}
}

// Called by UiBegin: a press outside of the panel is the pick, not a click on what is under the pointer.
@(private)
editFilterInput :: proc(ctx: ^Context) {
    edit: ^EditMode = &ctx.edit
    edit.pressed = false
    if !edit.on || RectContains(edit.panel, ctx.input.mouse_position) { return }
    edit.pressed = ctx.input.mouse_pressed
    ctx.input.mouse_pressed, ctx.input.mouse_down, ctx.input.mouse_released = false, false, false
}

@(private)
editTargetOf :: proc(command: ^Command, area: Rect) -> EditTarget {
    target: EditTarget = {found = true, kind = command.info.kind, id = command.info.id, rect = area}
    name: string = command.info.name
    if name == "" { name = command.info.text }
    target.name_length = copy(target.name[:], name)
    return target
}

// Called by UiEnd, after the layout: finds the element under the pointer, takes the pick, and adds the covers at the end of the commands.
@(private)
editResolve :: proc(ctx: ^Context) {
    edit: ^EditMode = &ctx.edit
    if !edit.on { return }
    if edit.panel_id != 0 {
        if rect, found := UiElementRect(ctx, edit.panel_id); found { edit.panel = rect }
    }
    point: Vec2 = ctx.input.mouse_position
    edit.hover = {}
    clips: [UI_MAX_DEPTH * 2]Rect
    clip_count: int
    picked_seen: bool
    for i in 0 ..< ctx.command_count {
        command: ^Command = &ctx.commands[i]
        switch command.kind {
        case .CLIP_BEGIN:
            area: Rect = command.info.rect
            if clip_count > 0 { area = RectIntersect(clips[clip_count - 1], area) }
            if clip_count < len(clips) {
                clips[clip_count] = area
                clip_count += 1
            }
        case .CLIP_END:
            if clip_count > 0 { clip_count -= 1 }
        case .DRAW:
            #partial switch command.info.kind {
            case .NONE, .TEXT_CARET, .TEXT_SELECTION, .HIGHLIGHT, .BACKDROP, .GRAPH_OVERLAY, .EDIT_COVER:
                continue
            }
            area: Rect = command.info.rect
            if clip_count > 0 { area = RectIntersect(clips[clip_count - 1], area) }
            // the picked element is followed by its id when it has one: it moves and resizes with the ui
            if edit.picked.found && edit.picked.id != 0 && command.info.id == edit.picked.id {
                edit.picked.rect, edit.picked.kind = area, command.info.kind
                picked_seen = true
            }
            if area.z > 0 && area.w > 0 && !RectContains(edit.panel, point) && RectContains(area, point) {
                edit.hover = editTargetOf(command, area)
            }
        case .ZOOM_BEGIN, .ZOOM_END:
        }
    }
    _ = picked_seen
    if edit.pressed && edit.hover.found { edit.picked = edit.hover }
    // the covers: the element under the pointer (when it is not the picked one), then the picked one
    covers: [2]Command
    count: int
    if edit.hover.found && !(edit.picked.found && edit.picked.rect == edit.hover.rect && edit.picked.kind == edit.hover.kind) {
        covers[count] = {kind = .DRAW, info = {kind = .EDIT_COVER, rect = edit.hover.rect}}
        count += 1
    }
    if edit.picked.found {
        covers[count] = {kind = .DRAW, info = {kind = .EDIT_COVER, rect = edit.picked.rect, flags = {.SELECTED}}}
        count += 1
    }
    if count == 0 || ctx.command_count + count > len(ctx.commands) { return }
    // above everything of the page, behind the editing panel: just before the first command of the panel (a panel that is not found, or none: at the end)
    at: int = ctx.command_count
    if edit.panel_id != 0 {
        for i in 0 ..< ctx.command_count {
            if ctx.commands[i].kind == .DRAW && ctx.commands[i].info.id == edit.panel_id {
                at = i
                break
            }
        }
    }
    for i := ctx.command_count - 1; i >= at; i -= 1 { ctx.commands[i + count] = ctx.commands[i] }
    for i in 0 ..< count { ctx.commands[at + i] = covers[i] }
    ctx.command_count += count
}
