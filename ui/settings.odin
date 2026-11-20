package ui

// What a program or a person may want to change about how the ui behaves: the time between presses of a double click, how many presses chain, the distance a drag
// starts at. `ui.UiSettings(&ctx)` gives the settings of a context; a program that has an accessibility page (or a game that has a settings screen) writes them, and
// the widgets read them every frame.
//
//     ui.UiSettings(&ctx).double_click_seconds = 0.6       // slower hands
//     ui.UiSettings(&ctx).multi_click_limit = 2            // a third quick press is a first press again: no selection of a paragraph by a triple click
//
// Hotkeys (which key is "copy", which is "accept") are a `KeyMap`, see keymap.odin.
//
// Limits: the settings are plain numbers read per frame (no events when they change, nothing is saved: a program stores them with its own settings); a double click is
//     by time and place only, a press by another button counts like the first; the key of a gamepad or a mouse button cannot be set here (a KeyMap does it)

Settings :: struct {
    double_click_seconds: f64,      // the longest time between presses that makes a double (and a triple) click
    multi_click_limit: int,         // how many presses count in a row: 3 (a triple click selects a paragraph), 2 (a third quick press starts again), 1 (no double click selection)
    drag_start_distance: f32,       // pixels the pointer moves from a press before it is a drag (drag and drop)
    drag_rest_distance: f32,        // pixels a drag may move and still stand still (UiDragRest)
    extend_modifier: Modifier,      // held with a click or an arrow it extends a selection of read text (Shift)
}

// The defaults of every context (UiInit sets them)
SettingsDefault :: proc "contextless" () -> Settings {
    return {
        double_click_seconds = DOUBLE_CLICK_SECONDS,
        multi_click_limit = 3,
        drag_start_distance = DRAG_START_DISTANCE,
        drag_rest_distance = DRAG_REST_DISTANCE,
        extend_modifier = .SHIFT,
    }
}

// The settings of a context, to read and to write
UiSettings :: proc(ctx: ^Context) -> ^Settings {
    return &ctx.settings
}
