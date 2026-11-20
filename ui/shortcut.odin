package ui

// A shortcut that is set by pressing it: `ui.UiShortcutField(&ctx, "Save##shortcut", &chord, pressed, key_name)`. A click (or the confirm key) makes the field
// listen; the next key that goes down, with the modifiers that are held, is written into `chord`. While it listens Escape lets go without a change and Backspace
// takes the shortcut away.
//
// The ui does not know the keys of a framework: a key is a number of the program (its key code, never 0), the program says which key went down in this frame
// (`pressed`) and how a key is called (`key_name`, a proc: the field asks for the name of the key it has after the frame's change). A key that only is a modifier (Shift, Ctrl, Alt) is not a key of a chord: do not pass it.
//
// Limits: one chord, no sequences; a modifier alone is not a chord; what the operating system takes (Alt + Tab) never arrives; no conflict check (the program does it, as the demo does)
//     the keys are numbers of the program: the ui has no key names and no layout of the keyboard
//
// Baldr's shortcut capture (examples/20_shortcuts) was the reason to have one; the code is written for this library.

Chord :: struct {
    modifiers: Modifiers,
    key: u16,                   // 0: no shortcut
}

// What the field shows while it waits for the keys
SHORTCUT_LISTENING :: "Press the keys"
SHORTCUT_NONE :: "None"

// A chord as text: "Ctrl+Shift+" and the name of the key, written into `out` (what does not fit is cut). Empty for no shortcut.
ChordFormat :: proc(chord: Chord, key_name: string, out: []u8) -> string {
    if chord.key == 0 { return "" }
    count: int
    put :: proc(out: []u8, count: ^int, text: string) {
        count^ += copy(out[count^:], text)
    }
    if .CTRL in chord.modifiers { put(out, &count, "Ctrl+") }
    if .ALT in chord.modifiers { put(out, &count, "Alt+") }
    if .SHIFT in chord.modifiers { put(out, &count, "Shift+") }
    put(out, &count, key_name)
    return string(out[:count])
}

// The field of a shortcut. `pressed`: the key that went down in this frame and the modifiers held with it (key 0: none). `key_name`: gives the name of a key (a text that lives until the frame is drawn; nil: no name).
// True in the frame the chord changed (set or taken away). `listening` is true while it waits for the keys: the program keeps its own shortcuts off then.
UiShortcutField :: proc(ctx: ^Context, name: string, chord: ^Chord, pressed: Chord, key_name: proc(key: u16) -> string, size: Size = {}, disabled: bool = false) -> (changed: bool, listening: bool) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, disabled)
    metrics: ^Metrics = &ctx.style.metrics
    opened_now: bool
    if interaction.clicked {
        state.open = !state.open
        opened_now = state.open
        if state.open { ctx.focus = id }
    }
    // it listens as long as it has the focus
    if state.open && (ctx.focus != id || disabled) { state.open = false }
    if state.open && !opened_now {
        // the key that made it listen (the confirm key) is not the shortcut: the frame after it is the first that counts
        if ctx.cancel_pending {
            state.open = false
            ctx.cancel_pending = false
        } else if .BACKSPACE in ctx.input.keys && pressed.modifiers == {} {
            changed = chord.key != 0
            chord^ = {}
            state.open = false
        } else if pressed.key != 0 {
            changed = chord^ != pressed
            chord^ = pressed
            state.open = false
        }
    }
    listening = state.open
    // while it listens the keys are its own: the arrows and the confirm key do not move the focus or click
    state.editing = listening
    state.own_vertical = listening
    // the text of the chord lives until the frame is drawn: it is written into the text memory of the frame
    free_space: []u8 = ctx.text_buffer[ctx.text_used:]
    shown: string = SHORTCUT_LISTENING if listening else ChordFormat(chord^, key_name(chord.key) if key_name != nil && chord.key != 0 else "", free_space[:min(len(free_space), 48)])
    if !listening { ctx.text_used += len(shown) }
    if shown == "" { shown = SHORTCUT_NONE }
    // drawn as a button: an outline, filled while it listens
    UiPushTag(ctx, "primary" if listening else "outline")
    ElementOpen(ctx, {
        id = id,
        layout = {size = widgetSize(size, max(textWidth(ctx, shown), textWidth(ctx, SHORTCUT_LISTENING)) + metrics.padding.x * 2, metrics.control_height)},
        hit = {} if disabled else {.INTERACTIVE},
        draw = {kind = .BUTTON, name = shown, font_size = metrics.font_size, flags = {.DISABLED} if disabled else {}},
    })
    ElementClose(ctx)
    UiPopTag(ctx)
    return
}
