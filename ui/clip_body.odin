package ui

// What a clip shows inside of itself: the notes of a MIDI clip as small dashes, the peaks of an audio clip as a mirrored wave, the cells of a pattern clip. The data is the program's (slices that live
// as long as the clip shows them): the library copies nothing and the clip only keeps the slice headers.
//
//     TimelineClipSetBody(&timeline, clip, {kind = .NOTES, notes = notes[:], content_length = 4})        // a pattern of one bar that repeats along the clip
//     TimelineClipSetBody(&timeline, clip, {kind = .WAVEFORM, peaks = peaks[:]})                         // peaks of the whole audio, 0..1, spread over the clip (or over `content_length`)
//     TimelineClipSetBody(&timeline, clip, {kind = .STEPS, steps = cells[:], rows = 2, content_length = 2})
//
// `content_length` is how long the content is in the units of the timeline: the clip shows it again and again when it is longer than that (a loop); 0 is the length of the clip, so the content is
// stretched over the clip. The times of notes are inside of the content (0 at its start).
//
// Limits: the content is not offset (no start inside of the content, so a clip that is cut at its left edge shows the content from its start), no velocity shading, no pitch names, the waveform is
//     mono peaks, a drum row has no names; the style draws only what is inside of the clip and in view.

ClipBodyKind :: enum u8 {
    NONE,
    NOTES,
    WAVEFORM,
    STEPS,
}

ClipBodyNote :: struct {
    start: f64,                 // inside of the content
    length: f64,
    pitch: u8,
}

ClipBody :: struct {
    kind: ClipBodyKind,
    content_length: f64,
    notes: []ClipBodyNote,      // NOTES
    peaks: []f32,               // WAVEFORM: 0..1, evenly spread over the content
    steps: []f32,               // STEPS: rows * (len / rows) cells, a value above 0 is on (its size is the strength)
    rows: int,
}

TimelineClipSetBody :: proc(timeline: ^Timeline, handle: ClipHandle, body: ClipBody) -> bool {
    clip: ^TimelineClip = TimelineClipGet(timeline, handle)
    if clip == nil { return false }
    clip.body = body
    return true
}

// The room inside of a clip rect for its content: under the name, with a little margin
ClipBodyArea :: proc(rect: Rect, name_height: f32) -> Rect {
    top: f32 = min(name_height, rect.w * 0.5)
    return {rect.x + 2, rect.y + top, max(rect.z - 4, 0), max(rect.w - top - 2, 0)}
}

// The lowest and the highest pitch of the notes (an empty list gives 60, 60)
ClipBodyPitchRange :: proc(body: ^ClipBody) -> (low: int, high: int) {
    if len(body.notes) == 0 { return 60, 60 }
    low, high = 127, 0
    for note in body.notes {
        low, high = min(low, int(note.pitch)), max(high, int(note.pitch))
    }
    return
}

// How many times the content is shown along a clip of `length`
ClipBodyRepeats :: proc(body: ^ClipBody, length: f64) -> int {
    if body.content_length <= 0 || length <= 0 { return 1 }
    return max(int(length / body.content_length + 0.999999), 1)
}

// A note of repeat `repeat` as a rectangle in `area`; `length` is the length of the clip, `low` and `high` the pitch range. ok is false when the note starts after the end of the clip.
// The note is cut at the end of the clip.
ClipBodyNoteRect :: proc(body: ^ClipBody, area: Rect, length: f64, note: ClipBodyNote, repeat: int, low: int, high: int) -> (rect: Rect, ok: bool) {
    if length <= 0 || area.z <= 0 { return }
    content: f64 = body.content_length if body.content_length > 0 else length
    start: f64 = f64(repeat) * content + note.start
    if start >= length { return }
    end: f64 = min(start + note.length, length)
    rows: int = high - low + 1
    row_height: f32 = area.w / f32(rows)
    height: f32 = clamp(row_height, 1.5, 4)
    x0: f32 = area.x + f32(start / length) * area.z
    x1: f32 = area.x + f32(end / length) * area.z
    center: f32 = area.y + (f32(high - int(note.pitch)) + 0.5) * row_height
    return {x0, center - height * 0.5, max(x1 - x0, 1), height}, true
}

// The peak of the waveform under the pixel column `index` of `columns` that span the clip (the largest of the peaks the column covers)
ClipBodyPeak :: proc(body: ^ClipBody, length: f64, index: int, columns: int) -> f32 {
    count: int = len(body.peaks)
    if count == 0 || columns <= 0 || length <= 0 { return 0 }
    content: f64 = body.content_length if body.content_length > 0 else length
    column_start: f64 = f64(index) / f64(columns) * length
    column_length: f64 = length / f64(columns)
    // inside of the content: the clip repeats it
    from_time: f64 = column_start - content * f64(int(column_start / content))
    to_time: f64 = from_time + column_length
    first: int = clamp(int(from_time / content * f64(count)), 0, count - 1)
    last: int = clamp(int(to_time / content * f64(count) - 1e-9), first, count - 1)       // a column that ends on the edge of a peak does not take the next one
    peak: f32
    for i in first ..= last { peak = max(peak, abs(body.peaks[i])) }
    return min(peak, 1)
}

// The cell of the pattern at a row and step of repeat `repeat`, as a rectangle in `area`. `length` is the length of the clip.
ClipBodyStepRect :: proc(body: ^ClipBody, area: Rect, length: f64, row: int, step: int, repeat: int) -> (rect: Rect, ok: bool) {
    if body.rows <= 0 || length <= 0 { return }
    per_row: int = len(body.steps) / body.rows
    if per_row <= 0 || row >= body.rows || step >= per_row { return }
    content: f64 = body.content_length if body.content_length > 0 else length
    step_time: f64 = content / f64(per_row)
    start: f64 = f64(repeat) * content + f64(step) * step_time
    if start >= length { return }
    end: f64 = min(start + step_time, length)
    row_height: f32 = area.w / f32(body.rows)
    x0: f32 = area.x + f32(start / length) * area.z
    x1: f32 = area.x + f32(end / length) * area.z
    return {x0 + 0.5, area.y + f32(row) * row_height + 0.5, max(x1 - x0 - 1, 1), max(row_height - 1, 1)}, true
}
