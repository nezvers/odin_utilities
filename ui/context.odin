package ui

// The context of a ui: one per ui (a game may have one for the HUD and one for a menu). It owns no memory: the buffers come from a
// `Storage` of the user, the number of widgets with state is the constant UI_STATES.
//
//     storage: ui.Storage(512, 1024, 128, 8192)       // elements, commands, text lines, bytes of formatted text
//     ctx: ui.Context
//     ui.UiInit(&ctx, &storage, MeasureText)
//
//     // every frame
//     ui.UiBegin(&ctx, input, delta_time, screen_size, &style)
//     if ui.UiPanel(&ctx, "Settings") {
//         if ui.UiButton(&ctx, "Reset") { ... }
//         ui.UiSlider(&ctx, "Volume", &volume, 0, 100)
//     }
//     ui.UiEnd(&ctx)
//     ui.UiRender(&ctx)       // where the frame wants it: the style procs draw into whatever batch is open

import hm "core:container/handle_map"
import "core:fmt"
import "core:math"
import "core:time"

// The memory of a context, sized by the user. `ELEMENTS` is the most elements (a widget is one or two, a text line is one) in a frame,
// `COMMANDS` the most things to draw, `LINES` the most wrapped text lines, `TEXT` the bytes UiFormat may use in a frame.
Storage :: struct($ELEMENTS: int, $COMMANDS: int, $LINES: int, $TEXT: int) {
    elements: [ELEMENTS]Element,
    children: [ELEMENTS]i32,
    child_buffer: [ELEMENTS]i32,
    scratch: [ELEMENTS]i32,
    element_slots: [ELEMENTS * 2]i32,
    hits: [ELEMENTS]HitBox,
    commands: [COMMANDS]Command,
    lines: [LINES]TextLine,
    text: [TEXT]u8,
}

StorageDefault :: Storage(1024, 2048, 256, 16384)

// The element that covers the screen: the container every widget of the frame is in, unless it is declared in another one
ROOT_ID :: Id(0x7a6d426d)       // IdFromString("ui_root"), a test keeps them equal

Context :: struct {
    // buffers of the user's Storage
    elements: []Element,
    element_count: int,
    children: []i32,
    children_count: int,
    child_buffer: []i32,
    child_buffer_count: int,
    scratch: []i32,
    element_slots: []i32,           // element index + 1 by id, 0 for empty
    hits: []HitBox,
    hit_count: int,                 // kept from the last frame
    commands: []Command,
    command_count: int,
    lines: []TextLine,
    line_count: int,
    text_buffer: []u8,
    text_used: int,

    // the stacks of the elements that are open
    open_stack: [UI_MAX_DEPTH]i32,
    seed_stack: [UI_MAX_DEPTH]Id,
    clip_stack: [UI_MAX_DEPTH * 2]i32,
    root_stack: [UI_MAX_DEPTH]i32,
    open_count: int,
    clip_count: int,
    root_stack_count: int,
    split_stack: [UI_MAX_SPLITS]SplitFrame,   // the splits that are open (resize.odin)
    split_count: int,
    split_lost: int,                          // splits opened deeper than the stack: they are plain boxes
    graph_frames: [UI_MAX_GRAPHS]GraphFrame,  // the canvases of this frame (graph_widgets.odin)
    graph_frame_count: int,
    graph_stack: [UI_MAX_GRAPHS]int,
    graph_stack_count: int,
    graph_minimaps: [UI_MAX_GRAPHS]GraphMinimapData,
    graph_minimap_count: int,
    clipboard: Clipboard,
    inspector: Inspector,                           // the snapshot of the inspector panel (inspector.odin)
    timeline_frames: [UI_MAX_TIMELINES]TimelineFrame,   // the timelines of this frame (timeline_widgets.odin)
    timeline_frame_count: int,
    measure_cache: MeasureCache,                    // sizes of texts already measured (measure.odin)
    area_lines: [UI_TEXT_AREA_LINES]AreaLine,        // the rows of the text area that is declared (textarea.odin)
    roots: [UI_MAX_ROOTS]Root,
    root_count: int,

    // widgets that remember something between frames
    states: hm.Static_Handle_Map(UI_STATES, WidgetState, StateHandle),
    state_slots: [UI_STATES * 2]StateSlot,
    dummy_state: WidgetState,

    // the frame
    input: Input,
    delta_time: f32,
    time: f64,
    screen: Vec2,
    frame: u32,
    style: ^Style,
    measure: MeasureProc,
    user: rawptr,                   // for the glue: the painter that knows the framework
    culling: bool,                  // leave out what is outside of the screen and of its clip (on by default)

    // who has the pointer and the keyboard
    hover: Id,                      // the interactive element under the pointer (from the layout of the last frame)
    hover_scroll: Id,               // the scrolling container the wheel is for
    pointer_over_ui: bool,          // the pointer is over something of the ui: a game should not take the click
    active: Id,                     // the widget that holds the mouse press
    focus: Id,                      // the widget that gets the keyboard, the gamepad and the navigation (see nav.odin)
    hover_root: Id,                 // the floating element (popup, window) the hovered widget is in, 0 for the main layer
    focus_memory: [UI_MAX_ROOTS * 2]FocusMemory,     // per window or popup: the widget in it that had the focus last
    focus_memory_count: int,
    drag: DragState,
    press_position: Vec2,           // where the last press was (a drag starts some pixels from it)
    tag_stack: [16]Id,
    tag_count: int,
    disabled_depth: int,            // UiDisabled scopes that are open
    animating: bool,                // some fade of the last frame had not arrived yet (UiAnimating)
    cursor: Cursor,                 // what the pointer is over (UiCursor)
    last_press_id: Id,              // the widget of the last press and when, for double clicks
    last_press_time: f64,
    peak: Usage,                    // the highest use of each buffer so far (UiUsage)
    hover_info: Id,                 // the HOVER element under the pointer
    reveal_open: Id,                // the body of a header that was just opened: a scrolling container shows it (as much as fits) once it is laid out
    modal_root: Id,                 // the dialog that was open at the end of the last frame: navigation stays in it
    modal_next: Id,
    open_menu: Id,                  // the menu of the bar that is open
    menu_close: bool,               // a menu item was used this frame: the menus close
    menu_depth: int,
    menu_opened: [8]bool,
    fold_stack: [UI_MAX_DEPTH]Id,   // the headers whose body is open at the moment (UiCollapsing)
    fold_count: int,
    activate: bool,                 // UiActivate was called this frame
    cancel_pending: bool,           // the cancel action came this frame and nothing took it yet (a dropdown, a text field: UiCancelled is what is left)
    reveal: bool,                   // the focus moved this frame: a scrolling container shows the focused widget
    last_id: Id,                    // the last widget declared (UiNavLink works on it)
    problems: Problems,
    overflow: bool,
}

UiInit :: proc(ctx: ^Context, storage: ^Storage($E, $C, $L, $T), measure: MeasureProc, user: rawptr = nil) {
    assert(measure != nil, "ui needs a text measuring proc")
    ctx^ = {}
    ctx.inspector.command_list.selected = VIRTUAL_NONE
    ctx.elements = storage.elements[:]
    ctx.children = storage.children[:]
    ctx.child_buffer = storage.child_buffer[:]
    ctx.scratch = storage.scratch[:]
    ctx.element_slots = storage.element_slots[:]
    ctx.hits = storage.hits[:]
    ctx.commands = storage.commands[:]
    ctx.lines = storage.lines[:]
    ctx.text_buffer = storage.text[:]
    ctx.measure = measure
    ctx.user = user
    ctx.culling = true
}

// Starts a frame. `screen` is the size of the area the ui covers (the window). `style` is used by the widgets for their sizes and
// by UiRender for the drawing, and has to stay alive until the frame is rendered.
UiBegin :: proc(ctx: ^Context, input: Input, delta_time: f32, screen: Vec2, style: ^Style) {
    assert(style != nil)
    ctx.inspector.begin = time.tick_now()
    ctx.frame += 1
    ctx.time += f64(delta_time)
    ctx.delta_time = delta_time
    ctx.screen = screen
    ctx.style = style
    ctx.input = input
    inspectorFilterInput(ctx)
    ctx.element_count = 0
    ctx.children_count = 0
    ctx.child_buffer_count = 0
    ctx.command_count = 0
    ctx.line_count = 0
    ctx.text_used = 0
    ctx.open_count = 0
    ctx.clip_count = 0
    ctx.root_stack_count = 0
    ctx.split_count = 0
    ctx.split_lost = 0
    ctx.graph_frame_count = 0
    ctx.timeline_frame_count = 0
    ctx.graph_stack_count = 0
    ctx.graph_minimap_count = 0
    ctx.root_count = 0
    ctx.problems = {}
    ctx.overflow = false
    ctx.activate = false
    ctx.disabled_depth = 0
    ctx.tag_count = 0
    ctx.menu_close = false
    ctx.menu_depth = 0
    ctx.fold_count = 0
    ctx.cancel_pending = false
    ctx.reveal = false
    for i in 0 ..< len(ctx.element_slots) {
        ctx.element_slots[i] = 0
    }

    // the pointer of this frame against the layout of the last one
    hoverUpdate(ctx)
    if input.mouse_pressed {
        ctx.focus = 0           // a click that lands on a text field gives it the focus back
    }
    if !input.mouse_down && !input.mouse_released {
        ctx.active = 0
    }

    // the default actions of this frame move the focus before any widget is declared, so the widgets of this frame see it
    ctx.cancel_pending = .CANCEL in input.actions || .ESCAPE in input.keys
    for action in Action {
        if action in input.actions { UiAction(ctx, action) }
    }

    // the root covers the screen, every other element is inside of it
    ElementOpen(ctx, {
        id = ROOT_ID,
        layout = {size = {Fixed(screen.x), Fixed(screen.y)}},
    })
    ctx.roots[0] = {element = 0, parent = -1, clip = -1}
    ctx.root_count = 1
    ctx.root_stack[0] = 0
    ctx.root_stack_count = 1
}

// Ends the frame: the layout is calculated and the commands for UiRender are made. The input of the next UiBegin is tested against it.
UiEnd :: proc(ctx: ^Context) {
    ElementClose(ctx)
    if ctx.open_count != 0 {
        ctx.problems += {.UNBALANCED}
        ctx.open_count = 0
    }
    stateSmooth(ctx)
    usageRecord(ctx)
    if !ctx.overflow {
        LayoutCalculate(ctx)
    } else {
        ctx.command_count = 0
    }
    graphAfterLayout(ctx)
    inspectorCapture(ctx)
    stateCollect(ctx)
    focusMemoryRecord(ctx)
    dragEnd(ctx)
    ctx.modal_root, ctx.modal_next = ctx.modal_next, 0
    if ctx.focus != 0 && stateFind(ctx, ctx.focus) == nil {
        ctx.focus = 0           // the focused widget is gone
    }
    if ctx.input.mouse_released {
        ctx.active = 0
    }
}

// True when the pointer is over something of the ui (a widget, a panel, a popup): the game should not use that click
UiPointerOverUi :: proc(ctx: ^Context) -> bool {
    return ctx.pointer_over_ui
}

// What went wrong in the last frame, empty when all is fine
UiProblems :: proc(ctx: ^Context) -> Problems {
    return ctx.problems
}

// The commands of the last frame in draw order, for a user that wants to draw them without a Style
UiCommands :: proc(ctx: ^Context) -> []Command {
    return ctx.commands[:ctx.command_count]
}

// A formatted string that lives until the end of the frame (names and values of widgets are made with it: no allocations)
UiFormat :: proc(ctx: ^Context, format: string, args: ..any) -> string {
    free_space: []u8 = ctx.text_buffer[ctx.text_used:]
    written: string = fmt.bprintf(free_space, format, ..args)
    if len(written) == len(free_space) {
        // full or exactly full: the text may be cut
        ctx.problems += {.TEXT_FULL}
    }
    ctx.text_used += len(written)
    return written
}

// Where an element was in the last frame, false when it was not there. Valid after UiEnd (and until the next UiBegin).
UiElementRect :: proc(ctx: ^Context, id: Id) -> (rect: Rect, found: bool) {
    index: i32 = elementFind(ctx, id)
    if index < 0 { return {}, false }
    return ctx.elements[index].rect, true
}

// ------------------------------------------------------------------------------------------------------------------------
// The pointer

@(private)
hoverUpdate :: proc(ctx: ^Context) {
    ctx.hover = 0
    ctx.hover_info = 0
    ctx.cursor = .ARROW
    ctx.hover_root = 0
    ctx.hover_scroll = 0
    ctx.pointer_over_ui = false
    point: Vec2 = ctx.input.mouse_position
    i: int = ctx.hit_count - 1
    for ; i >= 0; i -= 1 {
        box: ^HitBox = &ctx.hits[i]
        if !RectContains(box.rect, point) || !RectContains(box.clip_rect, point) { continue }
        ctx.pointer_over_ui = true
        if .HOVER in box.kinds && ctx.hover_info == 0 { ctx.hover_info = box.id }
        if .INTERACTIVE in box.kinds && ctx.hover == 0 {
            ctx.hover = box.id
            ctx.hover_root = box.root
            ctx.cursor = box.cursor
        }
        if .SCROLL in box.kinds && ctx.hover_scroll == 0 {
            ctx.hover_scroll = box.id
        }
        if .BLOCKER in box.kinds {
            if ctx.hover == 0 { ctx.hover_root = box.root }
            break           // what is below is covered
        }
    }
}

// ------------------------------------------------------------------------------------------------------------------------
// The state of widgets: a handle map of fixed size, found by id through a small table (rebuilt at the end of every frame)

@(private)
stateFind :: proc(ctx: ^Context, id: Id) -> ^WidgetState {
    if id == 0 { return nil }
    slot: int = int(u32(id) % u32(len(ctx.state_slots)))
    for _ in 0 ..< len(ctx.state_slots) {
        entry: StateSlot = ctx.state_slots[slot]
        if entry.id == 0 { return nil }
        if entry.id == id {
            state, ok := hm.get(&ctx.states, entry.handle)
            if ok { return state }
            return nil
        }
        slot = (slot + 1) % len(ctx.state_slots)
    }
    return nil
}

// The state of a widget, made when it is not there yet. It lives while the widget is declared every frame.
@(private)
stateGet :: proc(ctx: ^Context, id: Id) -> ^WidgetState {
    state: ^WidgetState = stateFind(ctx, id)
    if state == nil {
        handle, ok := hm.add(&ctx.states, WidgetState{id = id})
        if !ok {
            ctx.problems += {.STATES_FULL}
            ctx.dummy_state = {}
            return &ctx.dummy_state
        }
        slot: int = int(u32(id) % u32(len(ctx.state_slots)))
        for ctx.state_slots[slot].id != 0 {
            slot = (slot + 1) % len(ctx.state_slots)
        }
        ctx.state_slots[slot] = {id, handle}
        state = hm.get(&ctx.states, handle)
    }
    state.last_frame = ctx.frame
    return state
}

// The hover and press values that fade with time, for styles that animate
@(private)
stateSmooth :: proc(ctx: ^Context) {
    step: f32 = animationStep(ctx.delta_time, ANIMATION_RATE)
    ctx.animating = false
    it := hm.iterator_make(&ctx.states)
    for state, _ in hm.iterate(&it) {
        hover_target: f32 = 1 if ctx.hover == state.id && (ctx.active == 0 || ctx.active == state.id) else 0
        press_target: f32 = 1 if ctx.active == state.id else 0
        if follow(&state.hover, hover_target, step) { ctx.animating = true }
        if follow(&state.press, press_target, step) { ctx.animating = true }
    }
}

// How fast the fades of widgets arrive: the distance left is cut in half this many times a second
ANIMATION_RATE :: 18

// The part of the distance a value covers in `dt` seconds: independent of the frame rate (two frames of half the time arrive at the same place)
animationStep :: proc(dt: f32, rate: f32) -> f32 {
    return 1 - math.pow(2, -rate * max(dt, 0))
}

// Moves `value` towards `target` by `step` of the distance, and snaps when it is near. True while it is still moving.
@(private)
follow :: proc(value: ^f32, target: f32, step: f32) -> bool {
    if abs(target - value^) < 0.004 {
        value^ = target
        return false
    }
    value^ += (target - value^) * step
    return true
}

@(private)
FocusMemory :: struct {
    root: Id,
    focus: Id,
}

// Remembers which widget of which window (or popup: a floating root, 0 for the main layer) has the focus now
@(private)
focusMemoryRecord :: proc(ctx: ^Context) {
    if ctx.focus == 0 { return }
    for i in 0 ..< ctx.hit_count {
        box: ^HitBox = &ctx.hits[i]
        if box.id != ctx.focus { continue }
        for &entry in ctx.focus_memory[:ctx.focus_memory_count] {
            if entry.root == box.root {
                entry.focus = ctx.focus
                return
            }
        }
        if ctx.focus_memory_count < len(ctx.focus_memory) {
            ctx.focus_memory[ctx.focus_memory_count] = {box.root, ctx.focus}
            ctx.focus_memory_count += 1
        } else {
            ctx.focus_memory[int(ctx.frame) % len(ctx.focus_memory)] = {box.root, ctx.focus}     // full: replaces one
        }
        return
    }
}

// Frames a widget may be left out of before the ui forgets its state
STATE_GRACE_FRAMES :: 2

// Forgets the widgets that were not declared for a few frames and rebuilds the table that finds the rest
@(private)
stateCollect :: proc(ctx: ^Context) {
    for i in 0 ..< len(ctx.state_slots) {
        ctx.state_slots[i] = {}
    }
    it := hm.iterator_make(&ctx.states)
    for state, handle in hm.iterate(&it) {
        // a widget that is absent for a frame or two keeps its state (a list that scrolls a row out, a header that flickers)
        if ctx.frame - state.last_frame > STATE_GRACE_FRAMES {
            hm.remove(&ctx.states, handle)
            continue
        }
        slot: int = int(u32(state.id) % u32(len(ctx.state_slots)))
        for ctx.state_slots[slot].id != 0 {
            slot = (slot + 1) % len(ctx.state_slots)
        }
        ctx.state_slots[slot] = {state.id, handle}
    }
}

// How much of each buffer a frame used: for sizing a Storage (the numbers are in the units of its parameters)
Usage :: struct {
    elements: int,
    commands: int,
    lines: int,
    text_bytes: int,
    roots: int,
    states: int,
    hits: int,
}

// What the last frame used, and the highest of every frame so far (`peak`). Compare with the capacities of the Storage and UI_STATES.
UiUsage :: proc(ctx: ^Context) -> (now: Usage, peak: Usage) {
    now = {
        elements = ctx.element_count, commands = ctx.command_count, lines = ctx.line_count, text_bytes = ctx.text_used,
        roots = ctx.root_count, states = stateCount(ctx), hits = ctx.hit_count,
    }
    return now, ctx.peak
}

@(private)
usageRecord :: proc(ctx: ^Context) {
    now: Usage = {
        elements = ctx.element_count, commands = ctx.command_count, lines = ctx.line_count, text_bytes = ctx.text_used,
        roots = ctx.root_count, states = stateCount(ctx),
    }
    ctx.peak.elements = max(ctx.peak.elements, now.elements)
    ctx.peak.text_bytes = max(ctx.peak.text_bytes, now.text_bytes)
    ctx.peak.roots = max(ctx.peak.roots, now.roots)
    ctx.peak.states = max(ctx.peak.states, now.states)
}

// True while some fade of the widgets (hover, press) has not arrived: a host that draws on demand keeps drawing frames while it is true and
// then waits for the next input
UiAnimating :: proc(ctx: ^Context) -> bool {
    return ctx.animating
}

// What the mouse cursor should look like now: the glue sets the real one (raylib: SetMouseCursor)
UiCursor :: proc(ctx: ^Context) -> Cursor {
    return ctx.cursor
}

// A value that follows `target` in time (a fade, a slide) kept by the ui under `id` (a widget id or one made with IdFromString); a style gets the id from
// `DrawInfo.id` and the target from what it knows. The first call starts at the target.
UiAnimate :: proc(ctx: ^Context, id: Id, target: f32, rate: f32 = ANIMATION_RATE) -> f32 {
    state: ^WidgetState = stateGet(ctx, id)
    if !state.initialized {
        state.initialized = true
        state.anim = target
    }
    if follow(&state.anim, target, animationStep(ctx.delta_time, rate)) { ctx.animating = true }
    return state.anim
}

@(private)
stateCount :: proc(ctx: ^Context) -> int {
    return max(int(ctx.states.used_len) - int(ctx.states.unused_len) - 1, 0)       // slot 0 is the empty handle
}
