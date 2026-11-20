package ui

// Hotkeys that a person or a program can change: which input does which `Action` (accept, cancel, copy, undo, the arrows of the navigation ...). A glue turns the keys of
// a frame into `Input.actions`; with a `KeyMap` it does that by a table that is data, so a program can rebind it, save it and show it.
//
//     map := ui_kit.KeyMapDefault()                                   // the table of the kit: the keys that were fixed before
//     ui.KeyMapSet(&map, .COPY, 0, {device = .KEYBOARD, code = u16(kit.Key.C), ctrl = .YES})
//     ui.KeyMapSet(&map, .ACCEPT, 2, {device = .GAMEPAD, code = u16(kit.PadButton.START)})
//
// An action has `KEYMAP_SLOTS` bindings: any one of them does it. A binding is an input (a key, a mouse button, a gamepad button, by the numbers of the program: the ui has no
// names for them) and what has to be held: `ctrl`, `alt` and `shift` are ANY (does not matter), YES (held) or NO (not held), so Tab and Shift + Tab are two actions.
//
// The kit (`ui/kit`) uses it for every demo and keeps the table in `ui_kit.KeyMapOf()`. The raylib and Karl2D glues of this library still have their fixed keys: a program
// that wants a table there calls `KeyMapActions` with its own `InputProbe`.
//
// Limits: a binding is one input with modifiers (no sequences, no two inputs at once, no hold or double press); the actions are the fixed list of `Action`; a table is not
//     saved (the program stores the bindings it has set); two actions on one input both fire, a program that does not want that checks it when it rebinds (KeyMapConflict)

InputDevice :: enum u8 {
    NONE,               // an empty slot
    KEYBOARD,
    MOUSE,
    GAMEPAD,
}

// What a modifier has to be for a binding to count
Tri :: enum u8 {
    ANY,
    YES,
    NO,
}

Binding :: struct {
    device: InputDevice,
    code: u16,          // the key, the button or the pad button, as the program numbers them
    ctrl: Tri,
    alt: Tri,
    shift: Tri,
}

KEYMAP_SLOTS :: 4

KeyMap :: struct {
    slots: [Action][KEYMAP_SLOTS]Binding,
}

// Did this input go down in this frame (the program's own answer: its keys, its buttons)
InputProbe :: proc(user: rawptr, device: InputDevice, code: u16) -> bool

KeyMapSet :: proc "contextless" (map_: ^KeyMap, action: Action, slot: int, binding: Binding) {
    if slot < 0 || slot >= KEYMAP_SLOTS { return }
    map_.slots[action][slot] = binding
}

// Takes every binding of the action away
KeyMapClear :: proc "contextless" (map_: ^KeyMap, action: Action) {
    map_.slots[action] = {}
}

// The first free slot of an action, -1 when there is none
KeyMapFreeSlot :: proc "contextless" (map_: ^KeyMap, action: Action) -> int {
    for binding, i in map_.slots[action] {
        if binding.device == .NONE { return i }
    }
    return -1
}

@(private)
triOk :: proc "contextless" (want: Tri, held: bool) -> bool {
    switch want {
    case .ANY: return true
    case .YES: return held
    case .NO: return !held
    }
    return true
}

// Does `binding` take what is held (the modifiers) and what went down
KeyMapBindingMatches :: proc(binding: Binding, probe: InputProbe, user: rawptr, modifiers: Modifiers) -> bool {
    if binding.device == .NONE { return false }
    return triOk(binding.ctrl, .CTRL in modifiers) && triOk(binding.alt, .ALT in modifiers) && triOk(binding.shift, .SHIFT in modifiers) && probe(user, binding.device, binding.code)
}

// The actions of this frame: every action that has a binding that matches. `probe` answers for the inputs that went down in this frame, `modifiers` are the ones held.
KeyMapActions :: proc(map_: ^KeyMap, probe: InputProbe, user: rawptr, modifiers: Modifiers) -> (actions: Actions) {
    for action in Action {
        for binding in map_.slots[action] {
            if KeyMapBindingMatches(binding, probe, user, modifiers) {
                actions += {action}
                break
            }
        }
    }
    return
}

// The other action that has this binding exactly (NONE slot excluded), for a program that wants one input to do one thing: `found` is false when it is free
KeyMapConflict :: proc "contextless" (map_: ^KeyMap, binding: Binding, except: Action) -> (other: Action, found: bool) {
    if binding.device == .NONE { return }
    for action in Action {
        if action == except { continue }
        for existing in map_.slots[action] {
            if existing == binding { return action, true }
        }
    }
    return
}

// The key numbers of a framework for the keys the default table needs; 0 is a key the framework does not have (it is left out)
DefaultKeys :: struct {
    enter, keypad_enter, space, escape, tab: u16,
    up, down, left, right, page_up, page_down, home, end: u16,
    f2, c, x, v, a, d, z, y, i, r: u16,
}

// The buttons of a gamepad for the default table: the d-pad, the confirm and cancel buttons and the two shoulders. `present` is false for a framework or a program
// without a pad (button number 0 is a real button).
DefaultPad :: struct {
    present: bool,
    up, down, left, right, accept, cancel, previous, next: u16,
}

// The table that was fixed in the glues before it was data: Godot's default input map and the shortcuts of the editors, for the key numbers of one framework. Every glue and the
// kit make theirs with it, so they all start the same and a program changes the one it uses.
KeyMapFromCodes :: proc "contextless" (keys: DefaultKeys, pad: DefaultPad = {}) -> KeyMap {
    table: KeyMap
    next: [Action]int
    put :: proc "contextless" (table: ^KeyMap, next: ^[Action]int, action: Action, binding: Binding) {
        if (binding.code == 0 && binding.device == .KEYBOARD) || next[action] >= KEYMAP_SLOTS { return }
        table.slots[action][next[action]] = binding
        next[action] += 1
    }
    key :: proc "contextless" (table: ^KeyMap, next: ^[Action]int, action: Action, code: u16, ctrl: Tri = .ANY, alt: Tri = .ANY, shift: Tri = .ANY) {
        put(table, next, action, {device = .KEYBOARD, code = code, ctrl = ctrl, alt = alt, shift = shift})
    }
    button :: proc "contextless" (table: ^KeyMap, next: ^[Action]int, action: Action, code: u16, present: bool) {
        if !present { return }
        put(table, next, action, {device = .GAMEPAD, code = code})
    }
    key(&table, &next, .ACCEPT, keys.enter)
    key(&table, &next, .ACCEPT, keys.keypad_enter)
    key(&table, &next, .ACCEPT, keys.space)
    button(&table, &next, .ACCEPT, pad.accept, pad.present)
    key(&table, &next, .SELECT, keys.space)
    button(&table, &next, .SELECT, pad.accept, pad.present)
    key(&table, &next, .CANCEL, keys.escape)
    button(&table, &next, .CANCEL, pad.cancel, pad.present)
    key(&table, &next, .FOCUS_NEXT, keys.tab, shift = .NO)
    button(&table, &next, .FOCUS_NEXT, pad.next, pad.present)
    key(&table, &next, .FOCUS_PREV, keys.tab, shift = .YES)
    button(&table, &next, .FOCUS_PREV, pad.previous, pad.present)
    key(&table, &next, .UP, keys.up)
    button(&table, &next, .UP, pad.up, pad.present)
    key(&table, &next, .DOWN, keys.down)
    button(&table, &next, .DOWN, pad.down, pad.present)
    // Alt + left and right turn (the timeline); with Ctrl as well they are plain arrows again
    key(&table, &next, .LEFT, keys.left, alt = .NO)
    key(&table, &next, .LEFT, keys.left, ctrl = .YES, alt = .YES)
    button(&table, &next, .LEFT, pad.left, pad.present)
    key(&table, &next, .RIGHT, keys.right, alt = .NO)
    key(&table, &next, .RIGHT, keys.right, ctrl = .YES, alt = .YES)
    button(&table, &next, .RIGHT, pad.right, pad.present)
    key(&table, &next, .PAGE_UP, keys.page_up)
    key(&table, &next, .PAGE_DOWN, keys.page_down)
    key(&table, &next, .HOME, keys.home)
    key(&table, &next, .END, keys.end)
    key(&table, &next, .RENAME, keys.f2)
    key(&table, &next, .COPY, keys.c, ctrl = .YES)
    key(&table, &next, .CUT, keys.x, ctrl = .YES)
    key(&table, &next, .PASTE, keys.v, ctrl = .YES)
    key(&table, &next, .SELECT_ALL, keys.a, ctrl = .YES)
    key(&table, &next, .DUPLICATE, keys.d, ctrl = .YES)
    key(&table, &next, .UNDO, keys.z, ctrl = .YES, shift = .NO)
    key(&table, &next, .REDO, keys.z, ctrl = .YES, shift = .YES)
    key(&table, &next, .REDO, keys.y, ctrl = .YES)
    key(&table, &next, .INVERT, keys.i, ctrl = .NO, alt = .YES)
    key(&table, &next, .REVERSE, keys.r, ctrl = .NO, alt = .YES)
    key(&table, &next, .REPEAT, keys.d, ctrl = .NO, alt = .YES)
    key(&table, &next, .ROTATE_LEFT, keys.left, ctrl = .NO, alt = .YES)
    key(&table, &next, .ROTATE_RIGHT, keys.right, ctrl = .NO, alt = .YES)
    return table
}
