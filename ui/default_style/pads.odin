package ui_default

// The drawing of the smaller controls of ui/widgets_pads.odin: range slider, XY pad, wheel, thin scroll bar, piano keyboard and step grid. The pointer arithmetic is in the library
// (`KeyboardKeyRect`, `StepGridCellAt`, `ScrollBarThumb`), so what is drawn is what is pressed.

import ui ".."

DrawRangeSlider :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    rect: ui.Rect = info.rect
    FocusRing(painter, info)
    disabled: bool = .DISABLED in info.flags
    x0: f32 = rect.x + ui.RANGE_HANDLE
    run: f32 = rect.z - ui.RANGE_HANDLE * 2
    center: f32 = rect.y + rect.w * 0.5
    low_x, high_x: f32 = x0 + run * info.value, x0 + run * info.ratio
    FillRounded(painter, {x0, center - 2, run, 4}, 2, theme.track)
    painter.fill_rect(painter, {low_x, center - 2, high_x - low_x, 4}, theme.text_dim if disabled else theme.accent_soft)
    for handle, i in ([2]f32{low_x, high_x}) {
        active: bool = info.cursor == i && info.press > 0.01
        Disc(painter, {handle, center}, ui.RANGE_HANDLE, ui.ColorLerp(theme.border, theme.text, 0.4 if active else 0.1))
        Disc(painter, {handle, center}, ui.RANGE_HANDLE - 1.5, theme.text_dim if disabled else theme.accent)
    }
    if info.text != "" { TextRight(painter, info.text, {rect.x, rect.y, rect.z, rect.w * 0.45}, info.font_size * 0.8, 4, theme.text_dim) }
}

DrawXYPad :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    rect: ui.Rect = info.rect
    FocusRing(painter, info)
    FillRoundedBorder(painter, rect, theme.rounding, theme.track, theme.border, theme.border_width, theme.max_radius)
    for i in 1 ..< 4 {
        t: f32 = f32(i) / 4
        line: ui.Color = theme.border if i != 2 else theme.text_dim
        painter.fill_rect(painter, {rect.x + rect.z * t, rect.y + 1, 1, rect.w - 2}, line)
        painter.fill_rect(painter, {rect.x + 1, rect.y + rect.w * t, rect.z - 2, 1}, line)
    }
    point: ui.Vec2 = {rect.x + rect.z * info.value, rect.y + rect.w * (1 - info.ratio)}
    painter.fill_rect(painter, {point.x, rect.y + 1, 1, rect.w - 2}, ui.Color{theme.accent.r, theme.accent.g, theme.accent.b, 90})
    painter.fill_rect(painter, {rect.x + 1, point.y, rect.z - 2, 1}, ui.Color{theme.accent.r, theme.accent.g, theme.accent.b, 90})
    if len(info.values) >= 2 {
        ghost: ui.Vec2 = {rect.x + rect.z * clamp(info.values[0], 0, 1), rect.y + rect.w * (1 - clamp(info.values[1], 0, 1))}
        Line(painter, point, ghost, 1, ui.Color{theme.text_dim.r, theme.text_dim.g, theme.text_dim.b, 160})
        Disc(painter, ghost, 7, theme.text_dim)
        Disc(painter, ghost, 5, theme.track)
    }
    Disc(painter, point, 8, ui.ColorLerp(theme.border, theme.text, 0.2 + 0.6 * info.press))
    Disc(painter, point, 6, theme.text_dim if .DISABLED in info.flags else theme.accent)
}

DrawWheel :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    rect: ui.Rect = info.rect
    FocusRing(painter, info)
    FillRoundedBorder(painter, rect, theme.rounding, theme.track, theme.border, theme.border_width, theme.max_radius)
    // the ridges of the wheel slide with the value: a wheel turned up moves its ridges up
    inner: ui.Rect = ui.RectShrink(rect, 2)
    shift: f32 = info.value * inner.w * 1.5
    for i in -1 ..< 20 {
        y: f32 = inner.y + f32(i) * 7 + shift - f32(int(shift / 7)) * 7
        if y < inner.y || y > inner.y + inner.w - 2 { continue }
        shade: f32 = 1 - abs((y - inner.y) / inner.w - 0.5) * 1.6
        painter.fill_rect(painter, {inner.x + 2, y, inner.z - 4, 2}, ui.ColorLerp(theme.track, theme.text_dim, clamp(shade, 0, 1) * 0.5))
    }
    rest_y: f32 = rect.y + rect.w * (1 - info.ratio)
    painter.fill_rect(painter, {rect.x, rest_y, rect.z * 0.25, 1}, theme.text_dim)
    painter.fill_rect(painter, {rect.x + rect.z * 0.75, rest_y, rect.z * 0.25, 1}, theme.text_dim)
    value_y: f32 = rect.y + rect.w * (1 - info.value)
    painter.fill_rect(painter, {rect.x + 2, value_y - 1, rect.z - 4, 3}, theme.text_dim if .DISABLED in info.flags else theme.accent)
}

// A pill: the track is faint, the thumb stronger under the pointer or a press
DrawScrollBarThin :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    rect: ui.Rect = info.rect
    horizontal: bool = info.cursor == 1
    length: f32 = rect.z if horizontal else rect.w
    content: f32 = 1
    visible: f32 = info.ratio
    offset: f32 = info.value * (content - visible)
    start, thumb := ui.ScrollBarThumb(length, offset, content, visible)
    track: ui.Rect = {rect.x + 3, rect.y + 3, rect.z - 6, rect.w - 6} if !horizontal else {rect.x + 3, rect.y + 3, rect.z - 6, rect.w - 6}
    FillRounded(painter, track, min(track.z, track.w) * 0.5, ui.Color{theme.track.r, theme.track.g, theme.track.b, 180})
    if .DISABLED in info.flags { return }
    pill: ui.Rect = {track.x, track.y + start, track.z, max(thumb - 6, 4)} if !horizontal else {track.x + start, track.y, max(thumb - 6, 4), track.w}
    FillRounded(painter, pill, min(pill.z, pill.w) * 0.5, ui.ColorLerp(theme.text_dim, theme.text, max(info.hover * 0.5, info.press)))
}

DrawKeyboard :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    rect: ui.Rect = info.rect
    first, last: int = int(info.minimum), int(info.maximum)
    lit: ^[128]bool = cast(^[128]bool)info.user
    FocusRing(painter, info)
    painter.fill_rect(painter, rect, theme.border)
    for pass in 0 ..< 2 {
        for pitch in first ..= last {
            black: bool = ui.KeyboardIsBlack(pitch)
            if black != (pass == 1) { continue }
            key: ui.Rect = ui.KeyboardKeyRect(rect, first, last, pitch)
            if key.z <= 0 { continue }
            body: ui.Rect = {key.x + 0.5, key.y, max(key.z - 1, 1), max(key.w - 1, 1)}
            color: ui.Color = ui.ColorLerp(theme.panel, theme.border, 0.2) if black else ui.ColorLerp(theme.text, theme.panel, 0.08)
            if pitch == info.cursor { color = ui.ColorLerp(color, theme.accent, 0.7) }
            else if lit != nil && lit[pitch] { color = ui.ColorLerp(theme.accent, ui.Color{0, 0, 0, 255}, 0.35) if black else theme.accent }
            // a black key is outlined, so that a lit one does not run into the lit white keys behind it
            if black { FillRounded(painter, {body.x - 1, body.y, body.z + 2, body.w + 1}, 2, theme.border) }
            FillRounded(painter, body, 2 if black else 1.5, color)
            // the root: an outline under the key (a bar across its foot)
            if info.anchor >= 0 && pitch % 12 == info.anchor % 12 {
                painter.fill_rect(painter, {body.x + 2, body.y + body.w - 5, max(body.z - 4, 1), 3}, theme.warning)
            }
        }
    }
}

DrawStepGrid :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    rect: ui.Rect = info.rect
    rows, steps: int = info.anchor, info.cursor
    if rows <= 0 || steps <= 0 { return }
    FocusRing(painter, info)
    painter.fill_rect(painter, rect, theme.panel)
    cell_width, cell_height: f32 = rect.z / f32(steps), rect.w / f32(rows)
    beat: int = max(int(info.minimum), 1)
    playhead: int = int(info.actual)
    for step in 0 ..< steps {
        if playhead == step { painter.fill_rect(painter, {rect.x + f32(step) * cell_width, rect.y, cell_width, rect.w}, ui.Color{theme.accent.r, theme.accent.g, theme.accent.b, 40}) }
        for row in 0 ..< rows {
            cell: ui.Rect = {rect.x + f32(step) * cell_width + 1.5, rect.y + f32(row) * cell_height + 1.5, cell_width - 3, cell_height - 3}
            level: f32 = info.values[row * steps + step] if row * steps + step < len(info.values) else 0
            color: ui.Color = theme.track if (step / beat) % 2 == 0 else ui.ColorLerp(theme.track, theme.border, 0.5)
            if level > 0 { color = ui.ColorLerp(theme.accent_soft, theme.accent, clamp(level, 0, 1)) }
            detail: ui.StepDetail = stepDetail(info, row * steps + step)
            if level > 0 && detail.ratchet > 1 {
                // a ratchet is drawn as that many strikes side by side
                count: f32 = f32(min(detail.ratchet, ui.STEP_RATCHET_MAX))
                piece: f32 = max((cell.z - (count - 1) * 2) / count, 1)
                for strike in 0 ..< int(count) {
                    FillRounded(painter, {cell.x + f32(strike) * (piece + 2), cell.y, piece, cell.w}, theme.rounding * 0.4, color)
                }
            } else {
                FillRounded(painter, cell, theme.rounding * 0.6, color)
            }
        }
    }
    // the tail of a long step, over the cells it covers
    for row in 0 ..< rows {
        for step in 0 ..< steps {
            index: int = row * steps + step
            detail: ui.StepDetail = stepDetail(info, index)
            if detail.length < 2 || index >= len(info.values) || info.values[index] <= 0 { continue }
            covered: int = min(int(detail.length), steps - step)
            tail: ui.Rect = {rect.x + f32(step + 1) * cell_width, rect.y + f32(row) * cell_height + cell_height * 0.5 - 2, f32(covered - 1) * cell_width - 1.5, 4}
            FillRounded(painter, tail, 2, ui.ColorLerp(theme.accent_soft, theme.accent, clamp(info.values[index], 0, 1)))
        }
    }
}

@(private = "file")
stepDetail :: proc(info: ^ui.DrawInfo, index: int) -> ui.StepDetail {
    if info.user == nil { return {} }
    return (cast([^]ui.StepDetail)info.user)[index]
}
