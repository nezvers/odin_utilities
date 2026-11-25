package ui

// A piano roll: the notes of a clip on a grid of beats (across) and pitches (down), with the keys on the left, a ruler of bars on top and a lane of velocities under it. The notes
// are the program's data in a storage it gives (`PianoRollInit`, no allocation; a full storage refuses the next note); the view (zoom, scroll, snap, the scale to show) is a small
// struct the program keeps. Where a thing is on the screen is arithmetic (`PianoRollAreas`, `PianoRollNoteRect`...), so a style, a test and the pointer logic agree.
//
//   roll: ui.PianoRoll;  storage: [512]ui.PianoNote;  view: ui.PianoRollView = {snap = 0.25}
//   ui.PianoRollInit(&roll, storage[:]);  ui.PianoRollAdd(&roll, 0, 1, 60, 0.8)
//   ui.UiPianoRoll(&ctx, "Hook", &roll, &view, {Grow(), Grow()})        // every frame; roll.on_event tells what the person did
//
// Pointer: a double click on the grid adds a note (the length of the grid step) and on a note removes it; a press on a note selects it (Shift adds to the selection), a drag moves
// the selected notes in time and pitch on the grid, a drag of its right edge changes its length; a press on the empty grid clears the selection; a drag in the velocity lane sets the
// velocity of the note under the pointer; a press on the ruler moves the playhead; a press on a key plays it (a preview event, a drag glides over the keys). The wheel scrolls the
// pitches, Shift + wheel the time, Ctrl + wheel zooms the time around the pointer, Alt + wheel the height of the rows. Delete removes the selected notes, select all selects them.
//
// Limits: notes do not collide (they may overlap, and the same pitch may start twice at one time); no box selection, no cut, copy and paste, no undo (`roll.serial` grows with every
// change for a program that keeps its own history); one velocity lane (no controllers, bend or pressure); a drag of several notes is limited by the one that reaches the edge first;
// the keys do not scroll apart from the rows; no triplets or swing grids (a snap is a plain step in beats); events are told when a gesture ends, the data changes while it goes on.

import "core:math"

PIANO_KEYS_WIDTH :: 56
PIANO_RULER_HEIGHT :: 22
PIANO_LANE_HEIGHT :: 80
PIANO_DEFAULT_ZOOM :: 48                // pixels of a beat
PIANO_ZOOM_MIN :: 6
PIANO_ZOOM_MAX :: 600
PIANO_ZOOM_STEP :: f32(1.15)
PIANO_DEFAULT_ROW :: 16
PIANO_ROW_MIN :: 6
PIANO_ROW_MAX :: 40
PIANO_EDGE :: 6                         // the part of a note at its right end that resizes it, in pixels
PIANO_MIN_LENGTH :: 1.0 / 16
PIANO_TOP_PITCH :: 85                   // the top edge of a view that starts: the highest row is 84 (C6)
PIANO_MAX_PITCH :: 127

PianoNote :: struct {
    start: f64,                         // beats
    length: f64,
    pitch: int,                         // MIDI, 60 is C4
    velocity: f32,                      // 0 .. 1
    selected: bool,
}

PianoEventKind :: enum u8 {
    ADDED,                              // `note` is its index
    REMOVED,                            // the note as it was (`note` is the index it had)
    MOVED,                              // a drag of the selected notes ended: `delta_beats` and `delta_pitch` (of all of them), `note` the one that was grabbed
    RESIZED,                            // `delta_beats` is the change of the length of the selected notes
    VELOCITY,                           // `note` has a new `velocity`
    SELECTION,                          // the selection changed
    PREVIEW_ON,                         // a key was pressed: play `pitch`
    PREVIEW_OFF,                        // the key was let go (or the drag went to another key): stop `pitch`
    SEEK,                               // the ruler was pressed: `beat`
}

PianoEvent :: struct {
    kind: PianoEventKind,
    note: int,
    pitch: int,
    start: f64,
    length: f64,
    velocity: f32,
    beat: f64,
    delta_beats: f64,
    delta_pitch: int,
}

PianoEventProc :: proc(roll: ^PianoRoll, event: ^PianoEvent)

PianoRoll :: struct {
    notes: []PianoNote,                 // the storage, the program's
    count: int,
    beats_per_bar: int,                 // 0 is 4
    on_event: PianoEventProc,
    user: rawptr,
    serial: u64,                        // grows with every change of the notes
}

PianoGesture :: enum u8 {
    NONE,
    MOVE,
    RESIZE,
    VELOCITY,
    SEEK,
    KEY,
}

PianoRollView :: struct {
    zoom: f32,                          // pixels of a beat (0: PIANO_DEFAULT_ZOOM)
    origin: f64,                        // the beat at the left edge of the grid
    top_pitch: f32,                     // the pitch at the top edge of the grid: the row above it is top_pitch - 1 (a fraction scrolls smoothly); 0 starts at PIANO_TOP_PITCH
    row_height: f32,                    // pixels of a pitch (0: PIANO_DEFAULT_ROW)
    snap: f64,                          // beats; 0: no grid
    default_length: f64,                // of a note that is added (0: the snap, or a beat)
    default_velocity: f32,              // of a note that is added (0: 0.8)
    scale_mask: u16,                    // the pitch classes (bit 0 is the root) that belong to the scale; 0 shows no scale
    scale_root: int,                    // the pitch class of the root (0 is C)
    playhead: f64,                      // beats, shown when `show_playhead`
    show_playhead: bool,
    no_lane: bool,                      // hide the lane of velocities
    // set by the widget
    roll: ^PianoRoll,                   // what the style draws
    rect: Rect,
    started: bool,
    gesture: PianoGesture,
    grab: int,                          // the note a gesture works on
    press: Vec2,
    applied_beats: f64,                 // what the drag has moved the selection by so far
    applied_pitch: int,
    limit_low: f64,                     // the most the selection may go left (beats, negative or 0) ...
    limit_pitch_low: int,               // ... and the most it may go down and up in pitches
    limit_pitch_high: int,
    limit_length: f64,                  // the most the selection may shrink by (a positive number)
    hover_note: int,                    // -1: none
    key_down: int,                      // the key that is played, -1: none
}

PianoAreas :: struct {
    keys: Rect,
    ruler: Rect,
    grid: Rect,
    lane: Rect,                         // zero size without a lane
}

PianoRollInit :: proc(roll: ^PianoRoll, storage: []PianoNote, beats_per_bar: int = 4, user: rawptr = nil) {
    roll^ = {notes = storage, beats_per_bar = beats_per_bar, user = user}
}

PianoRollBeatsPerBar :: proc(roll: ^PianoRoll) -> int {
    return roll.beats_per_bar if roll.beats_per_bar > 0 else 4
}

@(private)
pianoTell :: proc(roll: ^PianoRoll, event: PianoEvent) {
    event := event
    if roll.on_event != nil { roll.on_event(roll, &event) }
}

// Adds a note. False when the storage is full.
PianoRollAdd :: proc(roll: ^PianoRoll, start: f64, length: f64, pitch: int, velocity: f32 = 0.8) -> (index: int, ok: bool) {
    if roll.count >= len(roll.notes) { return -1, false }
    roll.notes[roll.count] = {start = max(start, 0), length = max(length, PIANO_MIN_LENGTH), pitch = clamp(pitch, 0, PIANO_MAX_PITCH), velocity = clamp(velocity, 0, 1)}
    roll.count += 1
    roll.serial += 1
    return roll.count - 1, true
}

// Removes a note (the ones after it move up, so the order stays)
PianoRollRemove :: proc(roll: ^PianoRoll, index: int) {
    if index < 0 || index >= roll.count { return }
    for i in index ..< roll.count - 1 { roll.notes[i] = roll.notes[i + 1] }
    roll.count -= 1
    roll.serial += 1
}

PianoRollSelectAll :: proc(roll: ^PianoRoll, selected: bool = true) {
    for i in 0 ..< roll.count { roll.notes[i].selected = selected }
}

PianoRollSelectedCount :: proc(roll: ^PianoRoll) -> (count: int) {
    for i in 0 ..< roll.count {
        if roll.notes[i].selected { count += 1 }
    }
    return
}

// Removes the selected notes, one event each
PianoRollDeleteSelected :: proc(roll: ^PianoRoll) -> (removed: int) {
    for i := roll.count - 1; i >= 0; i -= 1 {
        note: PianoNote = roll.notes[i]
        if !note.selected { continue }
        PianoRollRemove(roll, i)
        pianoTell(roll, {kind = .REMOVED, note = i, pitch = note.pitch, start = note.start, length = note.length, velocity = note.velocity})
        removed += 1
    }
    return
}

// ------------------------------------------------------------------------------------------------------------------------
// Where things are

PianoRollZoom :: proc(view: ^PianoRollView) -> f32 {
    return clamp(view.zoom if view.zoom > 0 else PIANO_DEFAULT_ZOOM, PIANO_ZOOM_MIN, PIANO_ZOOM_MAX)
}

PianoRollRowHeight :: proc(view: ^PianoRollView) -> f32 {
    return clamp(view.row_height if view.row_height > 0 else PIANO_DEFAULT_ROW, PIANO_ROW_MIN, PIANO_ROW_MAX)
}

PianoRollAreas :: proc(view: ^PianoRollView, rect: Rect) -> PianoAreas {
    lane: f32 = 0 if view.no_lane else min(PIANO_LANE_HEIGHT, max(rect.w - PIANO_RULER_HEIGHT - 40, 0))
    grid_height: f32 = max(rect.w - PIANO_RULER_HEIGHT - lane, 0)
    return {
        keys = {rect.x, rect.y + PIANO_RULER_HEIGHT, PIANO_KEYS_WIDTH, grid_height},
        ruler = {rect.x + PIANO_KEYS_WIDTH, rect.y, max(rect.z - PIANO_KEYS_WIDTH, 0), PIANO_RULER_HEIGHT},
        grid = {rect.x + PIANO_KEYS_WIDTH, rect.y + PIANO_RULER_HEIGHT, max(rect.z - PIANO_KEYS_WIDTH, 0), grid_height},
        lane = {rect.x + PIANO_KEYS_WIDTH, rect.y + PIANO_RULER_HEIGHT + grid_height, max(rect.z - PIANO_KEYS_WIDTH, 0), lane},
    }
}

PianoRollBeatX :: proc(view: ^PianoRollView, areas: PianoAreas, beat: f64) -> f32 {
    return areas.grid.x + f32((beat - view.origin) * f64(PianoRollZoom(view)))
}

PianoRollBeatAt :: proc(view: ^PianoRollView, areas: PianoAreas, x: f32) -> f64 {
    return view.origin + f64(x - areas.grid.x) / f64(PianoRollZoom(view))
}

// The top of the row of a pitch
PianoRollPitchY :: proc(view: ^PianoRollView, areas: PianoAreas, pitch: int) -> f32 {
    return areas.grid.y + (view.top_pitch - f32(pitch) - 1) * PianoRollRowHeight(view)
}

PianoRollPitchAt :: proc(view: ^PianoRollView, areas: PianoAreas, y: f32) -> int {
    return int(math.floor(view.top_pitch - (y - areas.grid.y) / PianoRollRowHeight(view)))
}

PianoRollNoteRect :: proc(view: ^PianoRollView, areas: PianoAreas, note: PianoNote) -> Rect {
    x: f32 = PianoRollBeatX(view, areas, note.start)
    return {x, PianoRollPitchY(view, areas, note.pitch), max(f32(note.length) * PianoRollZoom(view), 2), PianoRollRowHeight(view)}
}

// A beat moved onto the grid (nearest)
PianoRollSnap :: proc(view: ^PianoRollView, beat: f64) -> f64 {
    if view.snap <= 0 { return beat }
    return math.round(beat / view.snap) * view.snap
}

// The pitch class is in the scale of the view (everything is when no scale is set)
PianoRollInScale :: proc(view: ^PianoRollView, pitch: int) -> bool {
    if view.scale_mask == 0 { return true }
    degree: int = ((pitch - view.scale_root) % 12 + 12) % 12
    return view.scale_mask & (1 << uint(degree)) != 0
}

// The note under a point of the grid (the one drawn last wins), -1 for none
PianoRollNoteAt :: proc(roll: ^PianoRoll, view: ^PianoRollView, areas: PianoAreas, point: Vec2) -> int {
    for i := roll.count - 1; i >= 0; i -= 1 {
        rect: Rect = PianoRollNoteRect(view, areas, roll.notes[i])
        if point.x >= rect.x && point.x < rect.x + rect.z && point.y >= rect.y && point.y < rect.y + rect.w { return i }
    }
    return -1
}

@(private)
pianoPointIn :: proc(rect: Rect, point: Vec2) -> bool {
    return rect.z > 0 && rect.w > 0 && point.x >= rect.x && point.x < rect.x + rect.z && point.y >= rect.y && point.y < rect.y + rect.w
}

// ------------------------------------------------------------------------------------------------------------------------
// The widget

UiPianoRoll :: proc(ctx: ^Context, name: string, roll: ^PianoRoll, view: ^PianoRollView, size: Size = {}) -> (changed: bool) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id)
    if !view.started {
        view.started = true
        view.top_pitch = PIANO_TOP_PITCH if view.top_pitch == 0 else view.top_pitch
        view.hover_note, view.key_down, view.grab = -1, -1, -1
    }
    view.roll = roll
    view.rect = state.rect
    areas: PianoAreas = PianoRollAreas(view, view.rect)
    mouse: Vec2 = ctx.input.mouse_position
    shift: bool = .SHIFT in ctx.input.modifiers
    serial_before: u64 = roll.serial
    hovering: bool = ctx.hover == id && ctx.disabled_depth == 0 && view.gesture == .NONE

    if hovering && ctx.input.wheel.y != 0 {
        wheel: f32 = ctx.input.wheel.y
        if .CTRL in ctx.input.modifiers {
            before: f32 = PianoRollZoom(view)
            after: f32 = clamp(before * math.pow(PIANO_ZOOM_STEP, wheel), PIANO_ZOOM_MIN, PIANO_ZOOM_MAX)
            view.origin += f64(mouse.x - areas.grid.x) * (1 / f64(before) - 1 / f64(after))
            view.zoom = after
        } else if .ALT in ctx.input.modifiers {
            view.row_height = clamp(PianoRollRowHeight(view) * math.pow(PIANO_ZOOM_STEP, wheel), PIANO_ROW_MIN, PIANO_ROW_MAX)
        } else if shift {
            view.origin -= f64(wheel * 60 / PianoRollZoom(view))
        } else {
            view.top_pitch += wheel * 3
        }
    }
    // the view stays on the keyboard and in front of the end of time
    visible_rows: f32 = areas.grid.w / PianoRollRowHeight(view)
    view.top_pitch = clamp(view.top_pitch, min(visible_rows, PIANO_MAX_PITCH + 1), PIANO_MAX_PITCH + 1)
    view.origin = max(view.origin, 0)
    areas = PianoRollAreas(view, view.rect)

    if interaction.pressed && ctx.input.mouse_pressed && interaction.hovered && view.gesture == .NONE && ctx.disabled_depth == 0 {
        pianoPress(ctx, roll, view, areas, interaction.double_clicked)
    } else if view.gesture != .NONE && interaction.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) {
        pianoDrag(roll, view, areas, mouse, ctx.input.mouse_released)
    }
    if view.gesture != .NONE && !interaction.pressed { pianoEnd(roll, view) }     // the button went up where the widget did not see it

    if ctx.focus == id && ctx.disabled_depth == 0 && view.gesture == .NONE {
        if .DELETE in ctx.input.keys || .BACKSPACE in ctx.input.keys { PianoRollDeleteSelected(roll) }
        if .SELECT_ALL in ctx.input.actions {
            PianoRollSelectAll(roll)
            pianoTell(roll, {kind = .SELECTION})
        }
    }

    view.hover_note = -1
    cursor: Cursor = .ARROW
    if ctx.hover == id && view.gesture == .NONE && pianoPointIn(areas.grid, mouse) {
        view.hover_note = PianoRollNoteAt(roll, view, areas, mouse)
        if view.hover_note >= 0 {
            rect: Rect = PianoRollNoteRect(view, areas, roll.notes[view.hover_note])
            cursor = .RESIZE_HORIZONTAL if mouse.x >= rect.x + rect.z - PIANO_EDGE else .HAND
        }
    } else if view.gesture == .RESIZE {
        cursor = .RESIZE_HORIZONTAL
    } else if view.gesture == .VELOCITY {
        cursor = .RESIZE_VERTICAL
    }
    ElementOpen(ctx, {
        id = id,
        layout = {size = {size.width if size.width != {} else Grow(), size.height if size.height != {} else Grow()}},
        clip = {horizontal = true, vertical = true, cut = true},
        hit = {.INTERACTIVE, .SCROLL},
        cursor = cursor,
        draw = {kind = .PIANO_ROLL, name = IdSplitName(name), user = view, font_size = ctx.style.metrics.font_size},
    })
    ElementClose(ctx)
    return roll.serial != serial_before
}

@(private)
pianoStartGesture :: proc(view: ^PianoRollView, gesture: PianoGesture, grab: int, mouse: Vec2) {
    view.gesture, view.grab, view.press = gesture, grab, mouse
    view.applied_beats, view.applied_pitch = 0, 0
}

@(private)
pianoPress :: proc(ctx: ^Context, roll: ^PianoRoll, view: ^PianoRollView, areas: PianoAreas, double: bool) {
    mouse: Vec2 = ctx.input.mouse_position
    shift: bool = .SHIFT in ctx.input.modifiers
    if pianoPointIn(areas.keys, mouse) {
        pitch: int = clamp(PianoRollPitchAt(view, areas, mouse.y), 0, PIANO_MAX_PITCH)
        view.key_down = pitch
        pianoStartGesture(view, .KEY, -1, mouse)
        pianoTell(roll, {kind = .PREVIEW_ON, pitch = pitch})
    } else if pianoPointIn(areas.ruler, mouse) {
        beat: f64 = max(PianoRollSnap(view, PianoRollBeatAt(view, areas, mouse.x)), 0)
        view.playhead, view.show_playhead = beat, true
        pianoStartGesture(view, .SEEK, -1, mouse)
        pianoTell(roll, {kind = .SEEK, beat = beat})
    } else if pianoPointIn(areas.grid, mouse) {
        index: int = PianoRollNoteAt(roll, view, areas, mouse)
        if index >= 0 {
            note: ^PianoNote = &roll.notes[index]
            if double {
                gone: PianoNote = note^
                PianoRollRemove(roll, index)
                pianoTell(roll, {kind = .REMOVED, note = index, pitch = gone.pitch, start = gone.start, length = gone.length, velocity = gone.velocity})
                return
            }
            if shift {
                note.selected = !note.selected
            } else if !note.selected {
                PianoRollSelectAll(roll, false)
                note.selected = true
            }
            pianoTell(roll, {kind = .SELECTION})
            if !note.selected { return }
            rect: Rect = PianoRollNoteRect(view, areas, note^)
            pianoStartGesture(view, .RESIZE if mouse.x >= rect.x + rect.z - PIANO_EDGE else .MOVE, index, mouse)
            view.limit_low, view.limit_pitch_low, view.limit_pitch_high, view.limit_length = 1e30, 1e9, -1e9, 1e30
            for i in 0 ..< roll.count {
                if !roll.notes[i].selected { continue }
                view.limit_low = min(view.limit_low, roll.notes[i].start)
                view.limit_pitch_low = min(view.limit_pitch_low, roll.notes[i].pitch)
                view.limit_pitch_high = max(view.limit_pitch_high, roll.notes[i].pitch)
                view.limit_length = min(view.limit_length, roll.notes[i].length - pianoMinLength(view))
            }
        } else if double {
            step: f64 = view.default_length if view.default_length > 0 else (view.snap if view.snap > 0 else 1)
            beat: f64 = PianoRollBeatAt(view, areas, mouse.x)
            if view.snap > 0 { beat = math.floor(beat / view.snap) * view.snap }
            pitch: int = clamp(PianoRollPitchAt(view, areas, mouse.y), 0, PIANO_MAX_PITCH)
            velocity: f32 = view.default_velocity if view.default_velocity > 0 else 0.8
            PianoRollSelectAll(roll, false)
            if added, ok := PianoRollAdd(roll, beat, step, pitch, velocity); ok {
                roll.notes[added].selected = true
                pianoTell(roll, {kind = .ADDED, note = added, pitch = pitch, start = roll.notes[added].start, length = step, velocity = velocity})
            }
        } else if !shift {
            PianoRollSelectAll(roll, false)
            pianoTell(roll, {kind = .SELECTION})
        }
    } else if pianoPointIn(areas.lane, mouse) {
        // the stem that is nearest in time, within a few pixels
        best: int = -1
        best_distance: f32 = 8
        for i in 0 ..< roll.count {
            distance: f32 = abs(PianoRollBeatX(view, areas, roll.notes[i].start) - mouse.x)
            if distance <= best_distance {
                best_distance = distance
                best = i
            }
        }
        if best >= 0 {
            pianoStartGesture(view, .VELOCITY, best, mouse)
            pianoVelocity(roll, view, areas, mouse)
        }
    }
}

@(private)
pianoMinLength :: proc(view: ^PianoRollView) -> f64 {
    return max(view.snap, PIANO_MIN_LENGTH) if view.snap > 0 else PIANO_MIN_LENGTH
}

@(private)
pianoVelocity :: proc(roll: ^PianoRoll, view: ^PianoRollView, areas: PianoAreas, mouse: Vec2) {
    if view.grab < 0 || view.grab >= roll.count { return }
    height: f32 = max(areas.lane.w - 8, 1)
    velocity: f32 = clamp((areas.lane.y + areas.lane.w - 4 - mouse.y) / height, 0, 1)
    if velocity != roll.notes[view.grab].velocity {
        roll.notes[view.grab].velocity = velocity
        roll.serial += 1
    }
}

@(private)
pianoDrag :: proc(roll: ^PianoRoll, view: ^PianoRollView, areas: PianoAreas, mouse: Vec2, released: bool) {
    switch view.gesture {
    case .NONE:
    case .MOVE:
        raw: f64 = f64(mouse.x - view.press.x) / f64(PianoRollZoom(view))
        beats: f64 = max(PianoRollSnap(view, raw), -view.limit_low)
        pitches: int = clamp(int(math.round((view.press.y - mouse.y) / PianoRollRowHeight(view))), -view.limit_pitch_low, PIANO_MAX_PITCH - view.limit_pitch_high)
        step_beats: f64 = beats - view.applied_beats
        step_pitch: int = pitches - view.applied_pitch
        if step_beats != 0 || step_pitch != 0 {
            for i in 0 ..< roll.count {
                if !roll.notes[i].selected { continue }
                roll.notes[i].start = max(roll.notes[i].start + step_beats, 0)
                roll.notes[i].pitch += step_pitch
            }
            view.applied_beats, view.applied_pitch = beats, pitches
            roll.serial += 1
        }
    case .RESIZE:
        raw: f64 = f64(mouse.x - view.press.x) / f64(PianoRollZoom(view))
        beats: f64 = max(PianoRollSnap(view, raw), -view.limit_length)
        step_beats: f64 = beats - view.applied_beats
        if step_beats != 0 {
            for i in 0 ..< roll.count {
                if roll.notes[i].selected { roll.notes[i].length += step_beats }
            }
            view.applied_beats = beats
            roll.serial += 1
        }
    case .VELOCITY:
        pianoVelocity(roll, view, areas, mouse)
    case .SEEK:
        view.playhead = max(PianoRollSnap(view, PianoRollBeatAt(view, areas, mouse.x)), 0)
    case .KEY:
        pitch: int = clamp(PianoRollPitchAt(view, areas, mouse.y), 0, PIANO_MAX_PITCH)
        if pitch != view.key_down {
            pianoTell(roll, {kind = .PREVIEW_OFF, pitch = view.key_down})
            view.key_down = pitch
            pianoTell(roll, {kind = .PREVIEW_ON, pitch = pitch})
        }
    }
    if released { pianoEnd(roll, view) }
}

// The gesture is over: the events that tell what it did
@(private)
pianoEnd :: proc(roll: ^PianoRoll, view: ^PianoRollView) {
    gesture: PianoGesture = view.gesture
    view.gesture = .NONE
    switch gesture {
    case .NONE, .SEEK:
    case .MOVE:
        if view.applied_beats != 0 || view.applied_pitch != 0 {
            pianoTell(roll, {kind = .MOVED, note = view.grab, delta_beats = view.applied_beats, delta_pitch = view.applied_pitch})
        }
    case .RESIZE:
        if view.applied_beats != 0 { pianoTell(roll, {kind = .RESIZED, note = view.grab, delta_beats = view.applied_beats}) }
    case .VELOCITY:
        if view.grab >= 0 && view.grab < roll.count {
            pianoTell(roll, {kind = .VELOCITY, note = view.grab, velocity = roll.notes[view.grab].velocity})
        }
    case .KEY:
        pianoTell(roll, {kind = .PREVIEW_OFF, pitch = view.key_down})
        view.key_down = -1
    }
    view.grab = -1
}
