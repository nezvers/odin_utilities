package ui

// Styles. The library never draws: for every element that has something to show it calls a style proc of the user with a rectangle and
// what is known about the element (DrawInfo). The user decides how a button, a slider or a progress bar looks, in any framework, with
// any number of draw calls, in the same render batch as the rest of the frame (UiRender is called wherever the frame wants the ui).

// What kind of thing an element is, so Style.procs picks the proc that draws it
StyleKind :: enum u8 {
    NONE,               // layout only, nothing to draw
    PANEL,              // a background behind children
    LABEL,              // one line of text (a wrapped text is one LABEL per line)
    BUTTON,
    TOGGLE,             // check box / switch: ON flag, value 0 or 1
    SLIDER,             // value 0..1, actual: the number the user edits, text: that number formatted
    PROGRESS,           // value 0..1, actual: the number it shows
    TEXT_FIELD,         // text: the content, cursor: byte offset, FOCUSED flag
    SEPARATOR,
    DROPDOWN,           // the closed box: text: the selected option, OPEN flag
    DROPDOWN_ITEM,      // one option of the open list: SELECTED flag
    SCROLL_AREA,        // the background of a scrolling container
    SCROLLBAR,          // value: position 0..1, ratio: how much of the content is visible 0..1
    CUSTOM,             // DrawInfo.custom is called instead of a table entry
}

Flag :: enum u8 {
    HOVERED,            // the pointer is over it
    PRESSED,            // it holds the mouse press
    FOCUSED,            // it gets the keyboard
    DISABLED,
    ON,                 // a toggle that is on
    SELECTED,           // the chosen option of a list
    OPEN,               // a dropdown that shows its list
}
Flags :: bit_set[Flag; u8]

TextAlign :: enum u8 {
    LEFT,
    CENTER,
    RIGHT,
}

// Everything a style proc may want to know. `rect` is where to draw in pixels of the screen.
DrawInfo :: struct {
    kind: StyleKind,
    id: Id,
    rect: Rect,
    flags: Flags,
    name: string,           // the name of the widget, "Volume" (what a person reads)
    text: string,           // extra text: the formatted value, the content of a text field, one line of a label
    value: f32,             // 0.0 .. 1.0 for sliders, progress bars and scrollbars
    actual: f32,            // the real value the user works with (a slider from 0 to 200 at 50 has value 0.25 and actual 50)
    minimum: f32,           // the range of `actual`
    maximum: f32,
    ratio: f32,             // scrollbar: the visible part of the content, 0..1
    hover: f32,             // 0..1 smoothed over time, for a style that fades on hover
    press: f32,             // 0..1 the same for the press
    font_size: f32,
    align: TextAlign,
    cursor: int,            // text field: byte offset of the cursor
    custom: StyleProc,      // kind == .CUSTOM: the user's own draw proc
    user: rawptr,           // anything of the user: it is passed through to the style
}

// Draws one element. `ctx.user` is where a glue keeps its painter (the thing that knows the framework).
StyleProc :: proc(ctx: ^Context, info: ^DrawInfo)

// What the widgets need to know to give themselves a size before the style draws anything
Metrics :: struct {
    font_size: f32,
    padding: Vec2,          // inside of a control: x on the sides, y above and below the text
    gap: f32,               // between the widgets of a column or a row
    control_height: f32,    // the height of a button, a slider, a text field...
    control_width: f32,     // the width of a slider or a text field that is not given one
    scrollbar_width: f32,
}

DEFAULT_METRICS :: Metrics{
    font_size = 16,
    padding = {10, 6},
    gap = 6,
    control_height = 28,
    control_width = 160,
    scrollbar_width = 8,
}

Style :: struct {
    procs: [StyleKind]StyleProc,    // nil: nothing is drawn for that kind
    // sets the scissor to `rect` (begin = true: it replaces the one that is set, UiRender tells the area that is left of nested clips) or
    // switches it off (begin = false): nothing outside of the scissor is drawn. nil: no clipping.
    clip: proc(ctx: ^Context, rect: Rect, begin: bool),
    metrics: Metrics,
}
