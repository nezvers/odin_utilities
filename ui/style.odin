package ui

// Styles. The library never draws: for every element that has something to show it calls a style proc of the user with a rectangle and
// what is known about the element (DrawInfo). The user decides how a button, a slider or a progress bar looks, in any framework, with
// any number of draw calls, in the same render batch as the rest of the frame (UiRender is called wherever the frame wants the ui).

// How many tags of the stack a widget keeps
DRAW_TAGS :: 4

// The widget was declared inside of `UiTagged(&ctx, name)` / between UiPushTag and UiPopTag of this name: a style picks colors and shapes by tag
// ("danger", "primary", "flat"...) without a StyleKind for every variant
DrawInfoHasTag :: proc(info: ^DrawInfo, name: string) -> bool {
    wanted: Id = IdFromString(name)
    for tag in info.tags {
        if tag == wanted { return true }
    }
    return false
}

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
    DROPDOWN,           // the closed box: text: the selected option, OPEN flag; icon: a picture instead of the arrow (a date field)
    DROPDOWN_ITEM,      // one option of the open list: SELECTED flag
    SCROLL_AREA,        // the background of a scrolling container
    SCROLLBAR,          // value: position 0..1, ratio: how much of the content is visible 0..1
    COLLAPSING,         // the header of a section: OPEN flag, actual 1 for a tree node (an arrow, no frame)
    RADIO,              // ON flag
    SELECTABLE,         // SELECTED flag: a row of a list
    TAB,                // SELECTED flag
    DRAG,               // a value that is dragged: text is the number, value 0..1 inside of minimum .. maximum when there is a range
    ARROW,              // actual: the Direction, 0 up, 1 down, 2 left, 3 right
    PLOT,               // values, minimum, maximum; actual 0 lines, 1 histogram; text: an overlay
    SWATCH,             // color
    MENU_BAR,           // the strip a menu bar is in
    MENU,               // the title of a menu in a bar (OPEN flag) or a submenu entry (actual 1)
    MENU_ITEM,          // name, text: the shortcut, ON flag: a checked item
    WINDOW_TITLE,       // the title bar of a window: name
    SPLITTER,           // the handle between two sections: actual 0 for sections side by side (a vertical bar), 1 for stacked ones; HOVERED, PRESSED, FOCUSED flags
    RESIZE_GRIP,        // the corner of a window that is resized: HOVERED, PRESSED flags
    BULLET,             // the dot of a bullet text
    SEPARATOR_TEXT,     // a line with a name in it
    BACKDROP,           // what dims the screen behind a modal dialog
    HIGHLIGHT,          // a rectangle that marks something (the inspector's pick): color, the style draws an outline and a faint fill
    TIMELINE,           // a timeline: draw the background, then call TimelineDraw(ctx, info) (lanes, clips, ruler, playhead); user: the frame
    TEXT_AREA,          // the box of a text of several lines: name (shown when it is empty and not focused), text, FOCUSED flag; its lines, selection and caret are children
    TEXT_SELECTION,     // a rectangle of the selected text of a text area
    TEXT_CARET,         // the cursor of a text area (the style blinks it)
    KNOB,               // a round control turned by dragging: value 0..1, actual the number, text that number formatted, ratio where its default is (0..1)
    FADER,              // a slider that stands: the same values, the maximum at the top
    METER,              // a level: value 0..1, ratio the peak mark (negative: none), cursor 1 for a meter that lies
    GRAPH,              // the canvas of a node graph: draw the background, then call GraphDrawLinks(ctx, info) (cables and ties); user: the frame
    GRAPH_OVERLAY,      // above the nodes: call GraphDrawOverlay(ctx, info) (the cable that is dragged, the cut of the tie tool)
    GRAPH_NODE,         // the frame of a node: name, color, SELECTED flag
    GRAPH_PIN,          // a connection point: color, actual: the data type, cursor: 1 for an output, flags: ON connected, PRESSED dragged from, SELECTED a cable that is dragged fits, DISABLED does not fit
    GRAPH_MINIMAP,      // user: ^GraphMinimapData, the style draws the nodes with GraphMinimapTransform and the view rectangle
    COLOR_FIELD,        // the square of a color picker: actual: the hue 0..1, value: saturation, ratio: the value (brightness), color: the pure hue; the marker is at (value, 1 - ratio)
    COLOR_STRIP,        // a bar of a color picker: actual 0 for the hues, 1 for the alpha; value: where the marker is, 0 at the top; color: the color the alpha is of
    ICON,               // a small picture: actual is the Icon, color (alpha 0: the style's own), the rect is square
    SWITCH,             // a toggle drawn as a track with a knob: ON flag, value 0..1 where the knob is on its way, ratio the width of the track, name
    BADGE,              // a few words in a pill: name, actual the Tone
    CHIP,               // a choice in a pill: name, icon, SELECTED flag; actual 1 for a tag with a cross on its right (ratio: the width the cross takes)
    AVATAR,             // a disc with letters: name, color
    SEGMENTED,          // the track of a segmented choice
    SEGMENT,            // one option in it: name, SELECTED flag
    BREADCRUMB,         // a part of a path: name, SELECTED flag for the last one (where the user is)
    SPINNER,            // something is going on: value is the time in seconds
    DATE_CELL,          // a day of the month a date field shows: name the number, SELECTED flag for the day of the date
    CHART,              // a chart: user is the ^ChartView (the series, the range of the axes, the hovered and the picked point); the style draws with ChartPlotRect, ChartPosition, ChartBarRect
    CUSTOM,             // DrawInfo.custom is called instead of a table entry
    FILL,               // a plain rectangle in `color` (the ground of a piece of text)
}

Flag :: enum u8 {
    HOVERED,            // the pointer is over it
    PRESSED,            // it holds the mouse press
    FOCUSED,            // it gets the keyboard
    DISABLED,
    ON,                 // a toggle that is on
    SELECTED,           // the chosen option of a list
    OPEN,               // a dropdown that shows its list
    TRUNCATED,          // a text line that was cut short: DrawInfo.name has the whole text
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
    anchor: int,            // text field: the other end of the selection (the same as `cursor`: nothing is selected)
    tags: [DRAW_TAGS]Id,    // the tags that were pushed when the widget was declared, the innermost first (UiPushTag); DrawInfoHasTag
    values: []f32,          // plots: the numbers (they have to live until the frame is rendered)
    color: Color,           // swatches and colored text
    icon: Icon,             // buttons, chips: a picture before the name (NONE: no picture)
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
    // a zoomed container starts (begin = true: everything up to its end is in its logical space, scaled by `factor` around `origin`) or ends: the style moves its painter. nil: no zoom.
    zoom: proc(ctx: ^Context, origin: Vec2, factor: f32, begin: bool),
    // called when UiRender has gone through its commands: a style that collects something (text for one draw call) draws it. nil: nothing to do.
    render_end: proc(ctx: ^Context),
    // called before every draw command (the procs of the table and custom draws): a style that draws by the tags of a command sets itself up here (the default style:
    // the theme of an area). nil: nothing to do.
    before_draw: proc(ctx: ^Context, info: ^DrawInfo),
    metrics: Metrics,
    graph: GraphStyle,
    timeline: TimelineStyle,        // how the lanes, clips, ruler and playhead of a timeline are drawn (timeline_style.odin)              // routing, bounds, distance and drawing of the cables and ties of a node graph (graph_style.odin)
}
