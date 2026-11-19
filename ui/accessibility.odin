package ui

import "core:fmt"

// What the screen shows, as a list of things with a role, a name and a state, for a program that reads it to a person (a screen reader bridge), for a test or an agent that drives the ui by
// what it says and not by where it is. It is made from the draw commands and the hit boxes of the last frame, so it costs nothing in a frame that does not ask: call it after UiEnd.
//
//     nodes: [256]ui.AccessNode
//     count := ui.UiAccessNodes(&ctx, nodes[:])           // in the order of the layout (which is the order of the Tab key)
//     text := ui.UiAccessDescribe(&ctx, buffer[:])         // "button \"Save\" [focused]" one per line
//
// Only what carries meaning is listed: text, and every widget that takes the pointer or the keyboard. Decoration (panels, separators, icons without a name, the grips of a window) is left out.

AccessRole :: enum u8 {
    TEXT,
    BUTTON,
    CHECKBOX,           // a toggle: `on`
    RADIO,
    SLIDER,             // a slider, a drag value, a knob, a fader: `value` is 0..1, `text` the number
    TEXT_FIELD,         // a text field or a text area: `text` is the content
    COMBO_BOX,          // a dropdown: `text` is the chosen option, `open`
    OPTION,             // an option of an open dropdown or combo box: `selected`
    TAB,                // `selected`
    LIST_ITEM,          // a selectable row, a row of a list, a table or a tree
    DISCLOSURE,         // a collapsing header or a tree node: `open`
    MENU,
    MENU_ITEM,
    TITLE,              // the title bar of a window
    METER,
    SCROLLBAR,
    COLOR,              // a color square or bar of a picker, a swatch
    CANVAS,             // a timeline, a node graph, a minimap: a surface that is worked on with the pointer
    OTHER,              // takes the pointer, and no better word
}

AccessNode :: struct {
    id: Id,
    role: AccessRole,
    name: string,       // what a person reads: the label of the widget (it lives as long as the frame)
    text: string,       // the content or the shown value
    value: f32,         // sliders, meters, scroll bars: 0..1
    rect: Rect,
    focusable: bool,    // the Tab key stops here
    focused: bool,
    disabled: bool,
    on: bool,           // a checkbox that is checked, a radio that is chosen
    selected: bool,
    open: bool,
}

AccessRoleName :: proc(role: AccessRole) -> string {
    switch role {
    case .TEXT: return "text"
    case .BUTTON: return "button"
    case .CHECKBOX: return "checkbox"
    case .RADIO: return "radio"
    case .SLIDER: return "slider"
    case .TEXT_FIELD: return "textbox"
    case .COMBO_BOX: return "combobox"
    case .OPTION: return "option"
    case .TAB: return "tab"
    case .LIST_ITEM: return "listitem"
    case .DISCLOSURE: return "disclosure"
    case .MENU: return "menu"
    case .MENU_ITEM: return "menuitem"
    case .TITLE: return "title"
    case .METER: return "meter"
    case .SCROLLBAR: return "scrollbar"
    case .COLOR: return "color"
    case .CANVAS: return "canvas"
    case .OTHER: return "other"
    }
    return "other"
}

// The role a style kind has, and whether it is listed when nothing takes the pointer there (text is).
@(private)
accessRole :: proc(kind: StyleKind) -> (role: AccessRole, meaningful: bool) {
    #partial switch kind {
    case .LABEL: return .TEXT, true
    case .BUTTON, .ARROW: return .BUTTON, true
    case .TOGGLE: return .CHECKBOX, true
    case .RADIO: return .RADIO, true
    case .SLIDER, .DRAG, .KNOB, .FADER: return .SLIDER, true
    case .TEXT_FIELD, .TEXT_AREA: return .TEXT_FIELD, true
    case .DROPDOWN: return .COMBO_BOX, true
    case .DROPDOWN_ITEM: return .OPTION, true
    case .TAB: return .TAB, true
    case .SELECTABLE: return .LIST_ITEM, true
    case .COLLAPSING: return .DISCLOSURE, true
    case .MENU: return .MENU, true
    case .MENU_ITEM: return .MENU_ITEM, true
    case .WINDOW_TITLE: return .TITLE, true
    case .METER, .PROGRESS: return .METER, true
    case .SCROLLBAR: return .SCROLLBAR, true
    case .SWATCH, .COLOR_FIELD, .COLOR_STRIP: return .COLOR, true
    case .TIMELINE, .GRAPH, .GRAPH_MINIMAP: return .CANVAS, true
    case .GRAPH_NODE: return .LIST_ITEM, true
    case .SEPARATOR_TEXT: return .TEXT, true
    case .PLOT: return .OTHER, true
    }
    return .OTHER, false
}

@(private)
accessInteractive :: proc(ctx: ^Context, id: Id) -> (interactive: bool, focusable: bool) {
    if id == 0 { return }
    for i in 0 ..< ctx.hit_count {
        box: ^HitBox = &ctx.hits[i]
        if box.id != id || .INTERACTIVE not_in box.kinds { continue }
        return true, .NO_FOCUS not_in box.kinds
    }
    return
}

// The nodes of the last frame into `out`: how many (what does not fit is left out). Call after UiEnd.
UiAccessNodes :: proc(ctx: ^Context, out: []AccessNode) -> (count: int) {
    for index in 0 ..< ctx.command_count {
        command: ^Command = &ctx.commands[index]
        if command.kind != .DRAW || count >= len(out) { continue }
        info: ^DrawInfo = &command.info
        role, meaningful := accessRole(info.kind)
        if !meaningful { continue }
        interactive, focusable := accessInteractive(ctx, info.id)
        name: string = info.name
        text: string = info.text
        if role == .TEXT {
            // a label has its text in `name` (the text of a line)
            if len(name) == 0 && len(text) == 0 { continue }
        } else if role == .TITLE || role == .OPTION || role == .LIST_ITEM || role == .TAB {
            if len(name) == 0 && len(text) == 0 { continue }
        } else if !interactive && role != .METER && role != .CANVAS {
            continue                // a drawn thing that nobody can use (a swatch in a row, a plot, the bar of a scroll area that is only shown)
        }
        node: AccessNode = {
            id = info.id, role = role, name = name, text = text, value = info.value, rect = info.rect,
            focusable = focusable, focused = .FOCUSED in info.flags, disabled = .DISABLED in info.flags,
            on = .ON in info.flags, selected = .SELECTED in info.flags, open = .OPEN in info.flags,
        }
        if info.kind == .COLLAPSING { node.open = .OPEN in info.flags }
        out[count] = node
        count += 1
    }
    return
}

// The node that has the keyboard focus, if it is listed
UiAccessFocused :: proc(ctx: ^Context) -> (node: AccessNode, found: bool) {
    nodes: [UI_ACCESS_SCAN]AccessNode
    count: int = UiAccessNodes(ctx, nodes[:])
    for i in 0 ..< count {
        if nodes[i].focused { return nodes[i], true }
    }
    return {}, false
}

UI_ACCESS_SCAN :: 512

// A line for every node, `role "name" text [states]`, into `buffer` (what does not fit is left out): for a log, for a test that reads the screen, for an agent. The result points into the buffer.
UiAccessDescribe :: proc(ctx: ^Context, buffer: []u8) -> string {
    nodes: [UI_ACCESS_SCAN]AccessNode
    count: int = UiAccessNodes(ctx, nodes[:])
    used: int
    for i in 0 ..< count {
        node: ^AccessNode = &nodes[i]
        states: [64]u8
        state_count: int
        add :: proc(states: ^[64]u8, count: ^int, word: string) {
            if count^ + len(word) + 1 > len(states) { return }
            if count^ > 0 { states[count^] = ' '; count^ += 1 }
            copy(states[count^:], word)
            count^ += len(word)
        }
        if node.focused { add(&states, &state_count, "focused") }
        if node.disabled { add(&states, &state_count, "disabled") }
        if node.on { add(&states, &state_count, "on") }
        if node.selected { add(&states, &state_count, "selected") }
        if node.open { add(&states, &state_count, "open") }
        line: string
        if node.role == .TEXT {
            line = fmt.bprintf(buffer[used:], "text %q", node.name if len(node.name) > 0 else node.text)
        } else if len(node.text) > 0 && node.text != node.name {
            line = fmt.bprintf(buffer[used:], "%s %q = %q", AccessRoleName(node.role), node.name, node.text)
        } else {
            line = fmt.bprintf(buffer[used:], "%s %q", AccessRoleName(node.role), node.name)
        }
        used += len(line)
        if state_count > 0 {
            suffix: string = fmt.bprintf(buffer[used:], " [%s]", string(states[:state_count]))
            used += len(suffix)
        }
        if used < len(buffer) {
            buffer[used] = '\n'
            used += 1
        }
        if used >= len(buffer) { break }
    }
    return string(buffer[:used])
}
