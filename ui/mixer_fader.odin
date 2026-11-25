package ui

// The channel fader of a mixer: a vertical fader in decibels with the scale beside it (+6 .. -60 dB, written), a stereo level meter next to it that shares the scale (so the level
// reads against the fader marks) with a held peak and a clip mark, and the value written below ("-6.0 dB", "-inf dB" at the bottom). The fader follows the usual mixer taper (the
// middle of the travel is about -10 dB, 0 dB is three quarters up), `MixerFaderPosition` and `MixerFaderDb` are that curve and its inverse.
//
//   levels: ui.MixerLevels = {left, right, peak_left, peak_right}      // dB, the program's (the peak held and let fall by the program, like UiMeter); must live until UiRender
//   ui.UiMixerFader(&ctx, "Drums", &gain_db, &levels)                   // gain_db from -60 (off) to +6
//
// Pointer: a drag on the handle moves it relative to where it was grabbed (Shift: ten times finer, and it passes 0 dB without sticking), a press elsewhere on the travel takes the handle
// there; the value sticks a little at 0 dB; double click or Ctrl + click sets 0 dB (`default_db`); the wheel steps a dB (Shift a tenth); the arrows step a dB.
//
// Limits: the range is fixed (-60 .. +6 dB, the bottom is "-inf"); one stereo meter (no mono, surround or gain reduction meter; a mono channel gives the same level twice); the value cannot
// be typed (use `UiValueBar` for that); no pre / post toggle, no K-weighting or loudness scales.

import "core:fmt"

MIXER_FADER_MIN :: -60
MIXER_FADER_MAX :: 6
MIXER_FADER_SCALE :: 28                 // width of the column of numbers
MIXER_FADER_READOUT :: 22               // height of the written value
MIXER_METER_BAR :: 8                    // width of one meter bar
MIXER_STICK_DB :: 0.4                   // the fader holds at 0 dB inside of this many dB

// left, right, peak left, peak right in dB (anything at or below the minimum is silence, a peak above 0 dB is a clip)
MixerLevels :: [4]f32

MIXER_FADER_TICKS :: [8]f32{6, 0, -6, -12, -24, -36, -48, -60}

@(private)
MIXER_TAPER :: [6][2]f32{{-60, 0}, {-40, 0.12}, {-20, 0.36}, {-10, 0.56}, {0, 0.78}, {6, 1}}

// The place on the travel (0 bottom .. 1 top) of a gain in dB
MixerFaderPosition :: proc(db: f32) -> f32 {
    taper: [6][2]f32 = MIXER_TAPER
    if db <= taper[0][0] { return 0 }
    for i in 1 ..< len(taper) {
        if db <= taper[i][0] {
            t: f32 = (db - taper[i - 1][0]) / (taper[i][0] - taper[i - 1][0])
            return taper[i - 1][1] + t * (taper[i][1] - taper[i - 1][1])
        }
    }
    return 1
}

// The gain in dB at a place on the travel
MixerFaderDb :: proc(position: f32) -> f32 {
    taper: [6][2]f32 = MIXER_TAPER
    if position <= 0 { return taper[0][0] }
    for i in 1 ..< len(taper) {
        if position <= taper[i][1] {
            t: f32 = (position - taper[i - 1][1]) / (taper[i][1] - taper[i - 1][1])
            return taper[i - 1][0] + t * (taper[i][0] - taper[i - 1][0])
        }
    }
    return taper[len(taper) - 1][0]
}

MixerFaderAreas :: struct {
    scale: Rect,                        // the numbers
    track: Rect,                        // the travel of the handle (the handle is inside of it at both ends)
    meter: Rect,                        // zero width without levels
    readout: Rect,
}

MixerFaderLayout :: proc(rect: Rect, has_meter: bool) -> MixerFaderAreas {
    body_height: f32 = max(rect.w - MIXER_FADER_READOUT, 0)
    meter_width: f32 = (MIXER_METER_BAR * 2 + 3) if has_meter else 0
    track_width: f32 = max(rect.z - MIXER_FADER_SCALE - meter_width - (6 if has_meter else 0), 8)
    return {
        scale = {rect.x, rect.y, MIXER_FADER_SCALE, body_height},
        track = {rect.x + MIXER_FADER_SCALE, rect.y, min(track_width, 40), body_height},
        meter = {rect.x + MIXER_FADER_SCALE + min(track_width, 40) + 6, rect.y + 3, meter_width, max(body_height - 6, 0)},
        readout = {rect.x, rect.y + body_height, rect.z, min(MIXER_FADER_READOUT, rect.w)},
    }
}

MixerFaderHandleHeight :: proc(track: Rect) -> f32 {
    return clamp(track.z * 0.7, 12, 26)
}

// The y of the centre of the handle for a place on the travel
MixerFaderY :: proc(areas: MixerFaderAreas, position: f32) -> f32 {
    handle: f32 = MixerFaderHandleHeight(areas.track)
    return areas.track.y + handle * 0.5 + (1 - clamp(position, 0, 1)) * max(areas.track.w - handle, 1)
}

// The place on the travel for a y on the screen
MixerFaderPositionAt :: proc(areas: MixerFaderAreas, y: f32) -> f32 {
    handle: f32 = MixerFaderHandleHeight(areas.track)
    return clamp(1 - (y - areas.track.y - handle * 0.5) / max(areas.track.w - handle, 1), 0, 1)
}

// The value as it is written
MixerFaderText :: proc(buffer: []u8, db: f32) -> string {
    if db <= MIXER_FADER_MIN { return fmt.bprintf(buffer, "-inf dB") }
    return fmt.bprintf(buffer, "%+.1f dB", db)
}

UiMixerFader :: proc(ctx: ^Context, name: string, value: ^f32, levels: ^MixerLevels = nil, default_db: f32 = 0, size: Size = {}, disabled: bool = false) -> (changed: bool) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, disabled)
    metrics: ^Metrics = &ctx.style.metrics
    value^ = clamp(value^, MIXER_FADER_MIN, MIXER_FADER_MAX)
    set :: proc(value: ^f32, db: f32) -> bool {
        clamped: f32 = clamp(db, MIXER_FADER_MIN, MIXER_FADER_MAX)
        if clamped == value^ { return false }
        value^ = clamped
        return true
    }
    areas: MixerFaderAreas = MixerFaderLayout(state.rect, levels != nil)
    mouse: Vec2 = ctx.input.mouse_position
    fine: bool = .SHIFT in ctx.input.modifiers
    if interaction.double_clicked && !disabled {
        changed = set(value, default_db) || changed
        state.cursor = 1
    } else if interaction.pressed && ctx.input.mouse_pressed && interaction.hovered && state.rect.w > 0 {
        state.cursor = 0
        state.drag.y = mouse.y
        state.anim = MixerFaderPosition(value^)
        if .CTRL in ctx.input.modifiers {
            state.cursor = 1                                // a reset: moving afterwards does not drag
            changed = set(value, default_db) || changed
        } else if mouse.y < areas.readout.y && abs(mouse.y - MixerFaderY(areas, state.anim)) > MixerFaderHandleHeight(areas.track) * 0.5 {
            state.anim = MixerFaderPositionAt(areas, mouse.y)       // a press beside the handle takes it there
            changed = set(value, MixerFaderDb(state.anim)) || changed
        }
    } else if interaction.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) && state.cursor == 0 && state.rect.w > 0 {
        run: f32 = max(areas.track.w - MixerFaderHandleHeight(areas.track), 1)
        delta: f32 = (state.drag.y - mouse.y) / run
        state.drag.y = mouse.y
        state.anim = clamp(state.anim + delta * (0.1 if fine else 1), 0, 1)
        db: f32 = MixerFaderDb(state.anim)
        if !fine && abs(db) < MIXER_STICK_DB { db = 0 }
        changed = set(value, db) || changed
    }
    if interaction.hovered && ctx.input.wheel.y != 0 && !disabled {
        changed = set(value, value^ + ctx.input.wheel.y * (0.1 if fine else 1)) || changed
    }
    state.adjustable = true
    state.adjust_vertical = true
    if state.pending_adjust != 0 {
        changed = set(value, value^ - f32(state.pending_adjust)) || changed
    }
    state.pending_adjust = 0

    buffer: [16]u8
    flags: Flags = {.DISABLED} if disabled else {}
    ElementOpen(ctx, {
        id = id,
        layout = {size = widgetSize(size, metrics.control_height * (2.5 if levels != nil else 1.8), metrics.control_height * 6.5)},
        hit = {} if disabled else {.INTERACTIVE},
        cursor = .RESIZE_VERTICAL,
        draw = {
            kind = .MIXER_FADER, name = IdSplitName(name), text = UiFormat(ctx, "%s", MixerFaderText(buffer[:], value^)),
            value = MixerFaderPosition(value^), actual = value^, minimum = MIXER_FADER_MIN, maximum = MIXER_FADER_MAX,
            ratio = MixerFaderPosition(default_db), values = levels[:] if levels != nil else nil,
            font_size = metrics.font_size, flags = flags,
        },
    })
    ElementClose(ctx)
    return
}
