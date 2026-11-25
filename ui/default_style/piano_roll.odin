package ui_default

// The piano roll (ui.UiPianoRoll): the keys, rows of the pitches (black keys and what is outside of the scale darker), lines of bars, beats and the snap grid, the notes (their color
// follows the velocity, a selected note has a bright outline and a grip at its right end), the lane of velocities with a stem and a head per note, the ruler with the numbers of the
// bars, and the playhead. All of it is arithmetic of ui/piano_roll.odin, so the pointer and the picture agree.

import "core:fmt"
import ui ".."

@(private)
isBlackKey :: proc(pitch: int) -> bool {
    pitch_class: int = pitch % 12
    return pitch_class == 1 || pitch_class == 3 || pitch_class == 6 || pitch_class == 8 || pitch_class == 10
}

DrawPianoRoll :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    view: ^ui.PianoRollView = cast(^ui.PianoRollView)info.user
    if view == nil || view.roll == nil { return }
    roll: ^ui.PianoRoll = view.roll
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    areas: ui.PianoAreas = ui.PianoRollAreas(view, info.rect)
    grid: ui.Rect = areas.grid
    row_height: f32 = ui.PianoRollRowHeight(view)
    zoom: f32 = ui.PianoRollZoom(view)
    painter.fill_rect(painter, info.rect, theme.panel)
    painter.fill_rect(painter, grid, theme.track)

    // the rows and the keys
    lowest: int = max(ui.PianoRollPitchAt(view, areas, grid.y + grid.w - 1), 0)
    highest: int = min(ui.PianoRollPitchAt(view, areas, grid.y), ui.PIANO_MAX_PITCH)
    for pitch in lowest ..= highest {
        y: f32 = ui.PianoRollPitchY(view, areas, pitch)
        row: ui.Rect = ui.RectIntersect({grid.x, y, grid.z, row_height}, grid)
        if row.z <= 0 || row.w <= 0 { continue }
        black: bool = isBlackKey(pitch)
        if black { painter.fill_rect(painter, row, {0, 0, 0, 55}) }
        if !ui.PianoRollInScale(view, pitch) { painter.fill_rect(painter, row, {0, 0, 0, 60}) }
        if view.scale_mask != 0 && ((pitch - view.scale_root) % 12 + 12) % 12 == 0 { painter.fill_rect(painter, row, {theme.accent.r, theme.accent.g, theme.accent.b, 26}) }
        painter.fill_rect(painter, {row.x, row.y + row.w - 1, row.z, 1}, theme.border)
        key: ui.Rect = ui.RectIntersect({areas.keys.x, y, areas.keys.z - 2, row_height - 1}, areas.keys)
        if key.z > 0 && key.w > 0 {
            color: ui.Color = theme.panel if black else ui.ColorLerp(theme.track, theme.text, 0.3)
            if view.key_down == pitch { color = theme.accent }
            painter.fill_rect(painter, key, color)
            if pitch % 12 == 0 && row_height >= 11 && key.w >= row_height - 2 {
                painter.draw_text(painter, fmt.tprintf("C%d", pitch / 12 - 1), {key.x + 6, key.y + (key.w - info.font_size) * 0.5}, info.font_size, theme.text_dim)
            }
        }
    }

    // the lines of time: the snap grid when it is wide enough, beats, bars
    bar_beats: int = ui.PianoRollBeatsPerBar(roll)
    first_beat: int = int(view.origin)
    last_beat: int = int(ui.PianoRollBeatAt(view, areas, grid.x + grid.z)) + 1
    if view.snap > 0 && view.snap < 1 && f32(view.snap) * zoom >= 10 {
        subdivisions: int = int(1 / view.snap + 0.5)
        for beat in first_beat ..< last_beat {
            for part in 1 ..< subdivisions {
                x: f32 = ui.PianoRollBeatX(view, areas, f64(beat) + f64(part) * view.snap)
                if x > grid.x && x < grid.x + grid.z { painter.fill_rect(painter, {x, grid.y, 1, grid.w + areas.lane.w}, {theme.border.r, theme.border.g, theme.border.b, 90}) }
            }
        }
    }
    for beat in first_beat ..< last_beat {
        x: f32 = ui.PianoRollBeatX(view, areas, f64(beat))
        if x < grid.x || x > grid.x + grid.z { continue }
        bar: bool = beat % bar_beats == 0
        painter.fill_rect(painter, {x, grid.y, 1, grid.w + areas.lane.w}, theme.text_dim if bar else theme.border)
        if bar { painter.draw_text(painter, fmt.tprintf("%d", beat / bar_beats + 1), {x + 4, areas.ruler.y + (areas.ruler.w - info.font_size) * 0.5}, info.font_size, theme.text) }
        else if zoom >= 36 { painter.draw_text(painter, fmt.tprintf("%d.%d", beat / bar_beats + 1, beat % bar_beats + 1), {x + 3, areas.ruler.y + (areas.ruler.w - info.font_size * 0.8) * 0.5}, info.font_size * 0.8, theme.text_dim) }
    }
    painter.fill_rect(painter, {areas.ruler.x, areas.ruler.y + areas.ruler.w - 1, areas.ruler.z, 1}, theme.border)

    // the notes
    for i in 0 ..< roll.count {
        note: ui.PianoNote = roll.notes[i]
        rect: ui.Rect = ui.PianoRollNoteRect(view, areas, note)
        visible: ui.Rect = ui.RectIntersect({rect.x, rect.y + 1, rect.z - 1, rect.w - 2}, grid)
        if visible.z <= 0 || visible.w <= 0 { continue }
        color: ui.Color = ui.ColorLerp(theme.accent_soft, theme.accent, 0.25 + 0.75 * note.velocity)
        border: ui.Color = theme.text if note.selected else ui.ColorLerp(color, theme.accent, 0.6)
        if i == view.hover_note && !note.selected { border = theme.text_dim }
        FillRoundedBorder(painter, visible, 0.25, color, border, 2 if note.selected else 1)
        if rect.z >= 14 && rect.x + rect.z - 5 < grid.x + grid.z {
            painter.fill_rect(painter, {rect.x + rect.z - 5, rect.y + 4, 1, max(rect.w - 8, 1)}, {border.r, border.g, border.b, 160})
        }
    }

    // the velocities
    if areas.lane.w > 0 {
        lane: ui.Rect = areas.lane
        painter.fill_rect(painter, lane, theme.panel)
        painter.fill_rect(painter, {lane.x, lane.y, lane.z, 1}, theme.border)
        for i in 0 ..< roll.count {
            note: ui.PianoNote = roll.notes[i]
            x: f32 = ui.PianoRollBeatX(view, areas, note.start)
            if x < lane.x || x > lane.x + lane.z { continue }
            height: f32 = (lane.w - 8) * note.velocity
            top: f32 = lane.y + lane.w - 4 - height
            color: ui.Color = theme.text if note.selected else theme.accent
            painter.fill_rect(painter, {x - 1, top, 2, height}, color)
            Disc(painter, {x, top}, 3, color)
        }
    }

    // the playhead
    if view.show_playhead {
        x: f32 = ui.PianoRollBeatX(view, areas, view.playhead)
        if x >= grid.x && x <= grid.x + grid.z {
            head: ui.Color = {250, 180, 60, 255}
            painter.fill_rect(painter, {x, info.rect.y, 1.5, info.rect.w}, head)
        }
    }
    painter.fill_rect(painter, {areas.keys.x + areas.keys.z - 1, areas.keys.y, 1, areas.keys.w}, theme.border)
}
