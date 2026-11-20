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
