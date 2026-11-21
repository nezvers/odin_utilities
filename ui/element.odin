package ui

// The data of the layout: what an element is declared with (Decl) and what the context keeps of it during a frame (Element), the input of
// a frame and the context itself with the buffers it works in. The layout model (sizing fit / grow / fixed / percent, padding, child gap,
// alignment, floating elements, clipping containers, text wrapping) is the one of Clay (https://github.com/nicbarker/clay, MIT, Nic Barker),
// ported to Odin and cut to what a ui needs.

import hm "core:container/handle_map"

// The number of widgets that keep state from one frame to the next (scroll position, text cursor, hover fade): fixed, so no allocations
UI_STATES :: #config(UI_STATES, 512)
// Floating elements (popups, tooltips) and the main root: every one of them is its own layer
UI_MAX_ROOTS :: #config(UI_MAX_ROOTS, 32)
UI_MAX_DEPTH :: 64

// ------------------------------------------------------------------------------------------------------------------------
// Declaration of an element

// A column is the default (the first value): widgets are most often stacked. Clay has them the other way round.
LayoutDirection :: enum u8 {
    TOP_TO_BOTTOM,
    LEFT_TO_RIGHT,
}

AlignX :: enum u8 {
    LEFT,
    RIGHT,
    CENTER,
}

AlignY :: enum u8 {
    TOP,
    BOTTOM,
    CENTER,
}

SizingKind :: enum u8 {
    FIT,        // as big as the children (or the text) need, between min and max
    GROW,       // takes what the parent has left, between min and max
    FIXED,      // exactly this
    PERCENT,    // a part of the parent (0..1) after its padding and gaps
}

SizingAxis :: struct {
    kind: SizingKind,
    min: f32,
    max: f32,           // 0 means no limit
    percent: f32,
    shrink: i8,         // when the container is too small: the elements with the lowest number shrink first, the others only once those are at their minimum (default 0)
}

Fit :: proc(min: f32 = 0, max: f32 = 0) -> SizingAxis {
    return {kind = .FIT, min = min, max = max}
}

Grow :: proc(min: f32 = 0, max: f32 = 0) -> SizingAxis {
    return {kind = .GROW, min = min, max = max}
}

Fixed :: proc(size: f32) -> SizingAxis {
    return {kind = .FIXED, min = size, max = size}
}

// `part` is 0..1: Percent(0.5) is half of what the parent has inside
Percent :: proc(part: f32) -> SizingAxis {
    return {kind = .PERCENT, percent = part}
}

Size :: struct {
    width: SizingAxis,
    height: SizingAxis,
}

Padding :: struct {
    left: f32,
    right: f32,
    top: f32,
    bottom: f32,
}

PaddingAll :: proc(amount: f32) -> Padding {
    return {amount, amount, amount, amount}
}

PaddingXY :: proc(x: f32, y: f32) -> Padding {
    return {x, x, y, y}
}

ChildAlign :: struct {
    x: AlignX,
    y: AlignY,
}

Layout :: struct {
    size: Size,
    padding: Padding,
    gap: f32,                       // between the children
    align: ChildAlign,              // where the children sit in the space that is left
    direction: LayoutDirection,
}

// Where on the parent / on the floating element the two are joined: (LEFT, BOTTOM) of the parent on (LEFT, TOP) of the element puts it under
AttachPoint :: enum u8 {
    LEFT_TOP,
    LEFT_CENTER,
    LEFT_BOTTOM,
    CENTER_TOP,
    CENTER_CENTER,
    CENTER_BOTTOM,
    RIGHT_TOP,
    RIGHT_CENTER,
    RIGHT_BOTTOM,
}

AttachTo :: enum u8 {
    NONE,               // not floating
    PARENT,             // to the element it is declared inside of
    ELEMENT_WITH_ID,    // to an element declared earlier in the frame (Floating.parent)
    ROOT,               // to the screen
}

// An element that does not take part in the layout of its parent but sits on top of everything (popups, tooltips, menus)
Floating :: struct {
    attach_to: AttachTo,
    parent: Id,
    element_point: AttachPoint,
    parent_point: AttachPoint,
    offset: Vec2,
    expand: Vec2,                   // grows the element (and what it catches the pointer with) on every side
    z_index: i16,                   // higher is on top
    capture: bool,                  // the pointer over it is not for what is under it
    clip_to_parent: bool,           // clipped by what clips its parent
}

// A child that is not part of the flow of its parent: it takes no room (the parent neither grows for it nor counts it for the gap and the alignment), sits
// at `offset` from the top left corner of the parent (the padding is not added; a scrolling parent moves it with the rest), and is drawn and hit in the order
// it was declared among its siblings, clipped like any child. Unlike a floating element it is not a root: any number of them cost what the same number
// of ordinary children cost. A size that grows or is a percent takes the size of the parent.
Absolute :: struct {
    enabled: bool,
    offset: Vec2,
}

// A container that cuts its children at its edge and may scroll them
Clip :: struct {
    horizontal: bool,
    vertical: bool,
    offset: Vec2,                   // where the content is moved (a scroll position, 0 or negative)
    cut: bool,                      // only hides what does not fit: the children are sized as in a container that does not clip (they grow and shrink to the room,
                                    // a content that is bigger does not make them bigger), and what is bigger than the room is cut at the edge
}

// What the mouse cursor looks like over a widget; the glue sets the real one (`UiCursor`)
Cursor :: enum u8 {
    ARROW,
    TEXT,               // over a text field
    HAND,               // over something that opens or follows
    RESIZE_HORIZONTAL,  // over a value that is dragged sideways
    RESIZE_VERTICAL,
    RESIZE_DIAGONAL_NWSE,   // the corners of a window: top left and bottom right
    RESIZE_DIAGONAL_NESW,   // top right and bottom left
    NOT_ALLOWED,        // over a disabled widget
}

// Which pointer events an element takes
HitKind :: enum u8 {
    INTERACTIVE,        // hover, press (buttons, sliders...)
    BLOCKER,            // the pointer over it is not for what is below (panels, popups)
    SCROLL,             // takes the mouse wheel
    HOVER,              // only wants to know that the pointer is over it (ctx.hover_info): a truncated text that shows itself in a tooltip; no focus, no click
    NO_FOCUS,           // with INTERACTIVE: takes the pointer, but the keyboard focus skips it (the edges of a window, its title bar)
}
HitKinds :: bit_set[HitKind; u8]

Decl :: struct {
    id: Id,                         // 0: anonymous (cannot be looked up, no state)
    layout: Layout,
    floating: Floating,
    absolute: Absolute,
    zoom: f32,                      // 0 or 1: none. Else the children are laid out in logical units (the room they have is the size of this element divided by `zoom`, the origin is its top left corner)
                                    // and everything of them is shown `zoom` times bigger around that corner: drawing (through Style.zoom), hit boxes and UiElementRect are in screen space.
                                    // Not for a floating element inside of it, and a scroll area inside of it scrolls in logical units. A zoomed container inside of a zoomed one is not zoomed again.
    clip: Clip,
    aspect_ratio: f32,              // width / height, 0 for none
    hit: HitKinds,
    cursor: Cursor,                 // while the pointer is over it (an interactive element)
    draw: DrawInfo,                 // what the style gets (rect, id and the interaction flags are filled by the context)
}

// ------------------------------------------------------------------------------------------------------------------------
// Text

TextWrap :: enum u8 {
    WORDS,              // at spaces when a line is too wide, and at new lines
    NEWLINES,           // only at new lines
    NONE,               // never (the width is the longest line)
    TRUNCATE,           // one line that shrinks with its container and ends in "..." when the text does not fit
}

TextConfig :: struct {
    font_size: f32,     // 0: the one of the style
    line_height: f32,   // 0: what the text measures
    wrap: TextWrap,
    align: TextAlign,
    kind: StyleKind,    // .LABEL when left as it is
    color: Color,       // alpha 0: the color of the style
    user: rawptr,
    continues: bool,    // this text goes on the text before it after a break of the line (a paragraph made of several texts): a copy of a selection joins them with a space
}

// How a text measures with a font of the framework: the width and the height of one line
MeasureProc :: proc(ctx: ^Context, text: string, font_size: f32) -> Vec2

@(private)
TextLine :: struct {
    start: i32,         // byte offset in the text of the element
    length: i32,
    width: f32,
    ellipsis: bool,     // the line ends in "..." (a truncated text)
}

@(private)
TextData :: struct {
    text: string,
    config: TextConfig,
    preferred: Vec2,    // measured as one line
    contains_newlines: bool,
    line_start: i32,    // into Context.lines
    line_count: i32,
    select_group: Id,   // a row of a list that declares only the rows in view (UiSelectRow): the list and the row, for the selection of read text (select.odin)
    select_row: i32,
    select_cell: i32,   // which of the selectable texts of that row it is, in the order they are declared (-1: it is not selectable)
}

// ------------------------------------------------------------------------------------------------------------------------
// What the context keeps of an element during one frame

@(private)
Element :: struct {
    id: Id,
    decl: Decl,
    is_text: bool,
    text: TextData,
    size: Vec2,
    min_size: Vec2,
    children_start: i32,            // into Context.children
    children_count: i32,
    floating_children: i32,
    parent: i32,
    clip: i32,                      // the element that clips this one, -1 for none
    root: i32,
    rect: Rect,                     // final
    clip_rect: Rect,                // the part of the screen it may show in
    content_size: Vec2,             // a clipping container: how big its children are together
    transform: Transform,           // the zoom it was placed in (inactive: none): its rect is on the screen, its place and size are in logical units of this
    child_transform: Transform,     // the zoom of its children: the same, or the one of the container when this one is zoomed (a floating child is placed in it)
}

@(private)
Root :: struct {
    element: i32,
    parent: i32,                    // the element a floating root is attached to
    clip: i32,
    z_index: i16,
    effective_z: i16,
}

CommandKind :: enum u8 {
    DRAW,               // call the style proc of `info.kind`
    CLIP_BEGIN,         // `info.rect` is the area to keep
    CLIP_END,
    ZOOM_BEGIN,         // everything up to ZOOM_END is in the layout space of a zoomed container: `info.rect` is {origin.x, origin.y, factor, 0}; the style moves its painter (Style.zoom)
    ZOOM_END,
}

Command :: struct {
    kind: CommandKind,
    info: DrawInfo,
}

// Where the pointer can land, in draw order, kept from one frame to the next: the pointer of the next frame is tested against it
@(private)
HitBox :: struct {
    id: Id,
    rect: Rect,
    clip_rect: Rect,
    kinds: HitKinds,
    cursor: Cursor,
    root: Id,                       // the floating element it lives in (0: the main layer): what tells that the pointer is inside of a popup
}

// ------------------------------------------------------------------------------------------------------------------------
// Input

Key :: enum u8 {
    BACKSPACE,
    DELETE,
    LEFT,
    RIGHT,
    HOME,
    END,
    ENTER,
    ESCAPE,
    TAB,
}
Keys :: bit_set[Key; u16]

// The default actions of a ui, named like the ones of Godot (the project settings input map): a glue maps the keys and the buttons of a
// gamepad to them (see ui/kit and the glue packages), the ui does the rest. Directions and pages repeat while the key is held.
Action :: enum u8 {
    ACCEPT,         // ui_accept: Enter, Space, the A button: clicks the focused widget (a button, a toggle, opens a dropdown)
    SELECT,         // ui_select: Space: the same, for apps that tell the two apart (UiActionPressed)
    CANCEL,         // ui_cancel: Escape, the B button: closes a dropdown, leaves a text field, and is what UiCancelled tells an app to close its dialog
    FOCUS_NEXT,     // ui_focus_next: Tab, the right shoulder: the next widget in the order of the layout (wraps around)
    FOCUS_PREV,     // ui_focus_prev: Shift + Tab, the left shoulder
    UP,             // ui_up, ui_down, ui_left, ui_right: the arrows, the d-pad: the nearest widget that way (UiNavigate)
    DOWN,
    LEFT,
    RIGHT,
    PAGE_UP,        // ui_page_up, ui_page_down: a page of widgets in a scrolling list
    PAGE_DOWN,
    HOME,           // ui_home, ui_end: the first and the last widget
    END,
    COPY,           // ui_copy, ui_cut, ui_paste, ui_text_select_all: Ctrl + C, X, V, A (the command key on a Mac): the text field takes them
    CUT,
    PASTE,
    SELECT_ALL,
    DUPLICATE,      // ui_duplicate: Ctrl + D: a copy of what is selected, put right after it (the timeline)
    UNDO,           // Ctrl + Z
    REDO,           // Ctrl + Y, Ctrl + Shift + Z
    INVERT,         // Alt + I: the selected automation points upside down (the timeline)
    REVERSE,        // Alt + R: the selected points played backwards
    REPEAT,         // Alt + D: a copy of the selected points after them
    RENAME,         // F2: the tree edits the name of the selected node
    ROTATE_LEFT,    // Alt + Left, Alt + Right: the selected automation points move around the timeline by a step (instead of the focus going left or right)
    ROTATE_RIGHT,
}
Actions :: bit_set[Action; u32]

// Keys that change what another key means: Shift extends a selection, Ctrl moves by a word
Modifier :: enum u8 {
    SHIFT,
    CTRL,           // the command key on a Mac
    ALT,
}
Modifiers :: bit_set[Modifier; u8]

INPUT_TEXT_CAPACITY :: 32

// What the ui needs of a frame of input, plain data: a glue (or a test) fills it
Input :: struct {
    mouse_position: Vec2,
    mouse_down: bool,               // the left button is held
    mouse_pressed: bool,            // went down this frame
    mouse_released: bool,           // went up this frame
    wheel: Vec2,                    // scrolled lines this frame, up is positive
    keys: Keys,                     // pressed this frame (key repeat counts)
    modifiers: Modifiers,           // held now
    actions: Actions,               // the default actions pressed this frame (key repeat counts for directions and pages)
    text: [INPUT_TEXT_CAPACITY]u8,  // typed this frame, UTF-8
    text_count: u8,
}

// ------------------------------------------------------------------------------------------------------------------------
// State that lives from one frame to the next

StateHandle :: hm.Handle32

@(private)
WidgetState :: struct {
    handle: StateHandle,            // the handle map needs this field
    id: Id,
    last_frame: u32,
    rect: Rect,                     // where the widget was at the end of the last frame
    content_size: Vec2,
    scroll: Vec2,
    hover: f32,
    press: f32,
    cursor: int,
    open: bool,
    nav: [Direction]Id,             // where navigation goes from here: 0 the nearest widget, NAV_BLOCK nowhere, else that widget
    adjustable: bool,               // a slider: left and right of the navigation change its value
    adjust_vertical: bool,          // a splitter between sections that are stacked: up and down change it
    adjust_both: bool,              // a square that is moved on both axes (a color picker): left and right fill `pending_adjust`, up and down `pending_adjust_y`
    pending_adjust_y: int,
    pending_adjust: int,            // steps asked by UiNavigate, taken by the widget in its next call
    editing: bool,                  // a text field that has the focus: it keeps left, right, home and end for the caret
    initialized: bool,              // the widget was declared before (a header that starts open sets its state once)
    own_vertical: bool,             // a text area, a list: up and down are for the cursor or the selection, not for the navigation
    column: f32,                    // a text area: the distance from the start of the row the cursor keeps while it goes up and down
    last_cursor: int,               // a text area: where the cursor was when the column was taken
    shown_cursor: int,              // a text area: where the cursor was when the view last followed it
    caret: Vec2,                    // a text area or field: where the caret is inside of the widget, the bottom of its row
    caret_top: f32,                 // the top of that row (a field: its top)
    anchor: int,                    // a text field: the other end of the selection (the cursor is one end; the same as the cursor: nothing is selected)
    hsv: [3]f32,                    // a color picker: hue, saturation and value as the person set them (a gray has no hue in RGB: this keeps it)
    lch: [3]f32,                    // a color picker: lightness, chroma and hue (degrees) as the person set them (chroma that sRGB cannot show is lost in the color, kept here)
    held: [3]f32,                   // a color picker: the color it gave last, to see that the program set another one
    mode: int,                      // a color picker: the ColorMode that is shown
    drag: Vec2,                     // where the pointer was in the last frame of a drag (a drag widget, a window title)
    press_time: f32,                // seconds the widget has been held (a button that repeats)
    anim: f32,                      // UiAnimate: a value that follows a target
    ratio: f32,                     // UiSplit: the part of the container the first section has
    split_pixels: f32,              // UiSplit started with a size in pixels: kept until the room of the container is known, then it becomes the ratio
    window_position: Vec2,          // UiWindowResizable that keeps its own position and size
    window_size: Vec2,
    zoom: f32,                      // the zoom of the children of this widget in the last frame (0 or 1: none): a scroll offset is in logical units, the wheel moves it by a step of the screen divided by this
}

@(private)
StateSlot :: struct {
    id: Id,
    handle: StateHandle,
}

// A way to move the focus
Direction :: enum u8 {
    UP,
    DOWN,
    LEFT,
    RIGHT,
}

// In nav links: no widget is reached from here in this direction
NAV_BLOCK :: Id(0xFFFFFFFF)

// What can go wrong in a frame: the ui carries on and tells here, so a frame is never lost to a crash
Problem :: enum u8 {
    ELEMENTS_FULL,      // more elements than the storage has
    COMMANDS_FULL,
    LINES_FULL,
    TEXT_FULL,          // UiFormat ran out of its buffer
    STATES_FULL,        // more widgets with state than UI_STATES
    ROOTS_FULL,
    DUPLICATE_ID,       // two elements with the same id in one frame: add ## to the name
    PARENT_NOT_FOUND,   // a floating element asked for an element that was not declared before it
    NO_MEASURE,         // text without a MeasureProc
    UNBALANCED,         // a container that was not closed (or closed twice)
    GRAPH_MISUSE,       // a graph node or pin outside of a UiGraph canvas, or more canvases than UI_MAX_GRAPHS
    SPLIT_MISUSE,       // a split section outside of a split, a third one, or a split nested deeper than UI_MAX_SPLITS (an extra section is not shown, one outside of a split is a plain box)
}
Problems :: bit_set[Problem; u16]
