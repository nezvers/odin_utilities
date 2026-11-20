package ui

// The output of a program as a terminal shows it: `ui.UiAnsiText(&ctx, output)` draws a text with the colors and styles its escape sequences ask for (the
// "\x1b[1;32m" a compiler, a test runner or git writes). The sequences are read every frame the text is shown, straight into texts with a color: no screen of
// cells is kept, nothing is allocated. For a long log declare only the lines in view (UiVirtual) and call `UiAnsiLine` for each, with the state of the line
// before.
//
// What is read: SGR (the sequences that end in `m`): reset, bold, dim, italic and their ends, the 8 colors and the 8 bright ones, the 256 colors (38;5;n), a
// color by its parts (38;2;r;g;b), the default color, the same for the ground behind the text (40 to 47, 100 to 107, 48;..., 49), underline. Every other
// escape sequence (moving the cursor, clearing) is skipped: this shows a log, it is not a screen.
//
// Limits: SGR only: bold, dim, italic, underline, the 16, 256 and RGB colors and the ground; no reverse video, blink, strike or hidden text, no hyperlinks
//     it is a log: the cursor moves and clears are skipped, and the text is read again every frame it is shown (declare only the lines in view for a long one)
//
// Baldr's terminal screen (examples/25_terminal) was the reason to have it; the code is written for this library.

// The style of the text at a place of the output
AnsiState :: struct {
    color: Color,               // alpha 0: the color of the style
    background: Color,          // alpha 0: none
    bold: bool,
    underline: bool,
    dim: bool,
    italic: bool,
}

// The 16 colors of a terminal for a dark ground and for a light one: black, red, green, yellow, blue, magenta, cyan, white, then the bright ones
ANSI_COLORS_DARK: [16]Color = {
    {110, 118, 129, 255}, {248, 113, 113, 255}, {74, 222, 128, 255}, {250, 204, 21, 255}, {96, 165, 250, 255}, {232, 121, 249, 255}, {34, 211, 238, 255}, {214, 218, 224, 255},
    {148, 156, 168, 255}, {252, 165, 165, 255}, {134, 239, 172, 255}, {253, 224, 71, 255}, {147, 197, 253, 255}, {240, 171, 252, 255}, {103, 232, 249, 255}, {248, 250, 252, 255},
}
ANSI_COLORS_LIGHT: [16]Color = {
    {40, 44, 52, 255}, {200, 40, 41, 255}, {22, 128, 61, 255}, {161, 98, 7, 255}, {29, 78, 216, 255}, {162, 28, 175, 255}, {14, 116, 144, 255}, {100, 108, 120, 255},
    {82, 90, 102, 255}, {220, 38, 38, 255}, {21, 150, 68, 255}, {180, 110, 8, 255}, {37, 99, 235, 255}, {192, 38, 211, 255}, {8, 145, 178, 255}, {30, 34, 42, 255},
}

// One of the 256 colors of a terminal: the 16 of the palette, a cube of 6 x 6 x 6, 24 grays
AnsiColor256 :: proc(index: int, palette: ^[16]Color) -> Color {
    if index < 16 { return palette[clamp(index, 0, 15)] }
    if index < 232 {
        cube: int = index - 16
        part :: proc(step: int) -> u8 { return 0 if step == 0 else u8(55 + step * 40) }
        return {part(cube / 36), part(cube / 6 % 6), part(cube % 6), 255}
    }
    gray: u8 = u8(8 + (min(index, 255) - 232) * 10)
    return {gray, gray, gray, 255}
}

// What the numbers of one SGR sequence do to the state
@(private)
ansiApply :: proc(state: ^AnsiState, numbers: []int, palette: ^[16]Color) {
    if len(numbers) == 0 {
        state^ = {}
        return
    }
    i: int
    for i < len(numbers) {
        number: int = numbers[i]
        switch {
        case number == 0: state^ = {}
        case number == 1: state.bold = true
        case number == 2: state.dim = true
        case number == 3: state.italic = true
        case number == 4: state.underline = true
        case number == 24: state.underline = false
        case number >= 40 && number <= 47: state.background = palette[number - 40]
        case number >= 100 && number <= 107: state.background = palette[number - 100 + 8]
        case number == 49: state.background = {}
        case number == 22: state.bold, state.dim = false, false
        case number == 23: state.italic = false
        case number >= 30 && number <= 37: state.color = palette[number - 30]
        case number >= 90 && number <= 97: state.color = palette[number - 90 + 8]
        case number == 39: state.color = {}
        case number == 38 || number == 48:
            // a color by its number or by its parts, of the text or of its ground
            color: Color
            if i + 2 < len(numbers) && numbers[i + 1] == 5 {
                color = AnsiColor256(numbers[i + 2], palette)
                i += 2
            } else if i + 4 < len(numbers) && numbers[i + 1] == 2 {
                color = {u8(clamp(numbers[i + 2], 0, 255)), u8(clamp(numbers[i + 3], 0, 255)), u8(clamp(numbers[i + 4], 0, 255)), 255}
                i += 4
            } else {
                i = len(numbers)
            }
            if color.a != 0 {
                if number == 38 { state.color = color } else { state.background = color }
            }
        }
        i += 1
    }
}

// The next run of `text` from `cursor` on that is shown in one style: the escape sequences before it are read into `state` (which is the style of the run when
// this returns) and are not a part of it. A run ends at an escape sequence, at a new line (which is skipped, `line_end` says so) and at the end of the text.
// `ok` is false when nothing is left.
AnsiNext :: proc(text: string, cursor: ^int, state: ^AnsiState, palette: ^[16]Color = nil) -> (run: string, line_end: bool, ok: bool) {
    colors: ^[16]Color = palette if palette != nil else &ANSI_COLORS_DARK
    i: int = cursor^
    for i < len(text) && text[i] == 0x1b {
        // ESC [ numbers and ; ... a letter. Anything else after ESC: the two characters are skipped
        if i + 1 >= len(text) || text[i + 1] != '[' {
            i = min(i + 2, len(text))
            continue
        }
        numbers: [16]int
        count: int
        any_digit: bool
        k: int = i + 2
        for k < len(text) && ((text[k] >= '0' && text[k] <= '9') || text[k] == ';' || text[k] == ':' || text[k] == '?') {
            if text[k] >= '0' && text[k] <= '9' {
                if count < len(numbers) { numbers[count] = min(numbers[count] * 10 + int(text[k] - '0'), 100000) }
                any_digit = true
            } else if text[k] != '?' {
                if count < len(numbers) { count += 1 }
                any_digit = false
            }
            k += 1
        }
        if any_digit && count < len(numbers) { count += 1 }
        if k >= len(text) {
            // a sequence that is not whole yet (an output that still arrives): nothing of it is shown
            cursor^ = len(text)
            return "", false, false
        }
        if text[k] == 'm' { ansiApply(state, numbers[:count], colors) }
        i = k + 1
    }
    if i >= len(text) {
        cursor^ = i
        return "", false, false
    }
    start: int = i
    for i < len(text) && text[i] != 0x1b && text[i] != '\n' { i += 1 }
    run = text[start:i]
    if len(run) > 0 && run[len(run) - 1] == '\r' { run = run[:len(run) - 1] }
    if i < len(text) && text[i] == '\n' {
        line_end = true
        i += 1
    }
    cursor^ = i
    return run, line_end, true
}

// One line of output (no new line in it) as a row of texts in the code face. `state` is the style at its start and is left as it is at its end, for the line
// after it. The texts are parts of `line`: it has to live until the frame is drawn.
UiAnsiLine :: proc(ctx: ^Context, line: string, state: ^AnsiState, palette: ^[16]Color = nil) {
    metrics: ^Metrics = &ctx.style.metrics
    ElementOpen(ctx, {layout = {size = {Grow(), Fit(metrics.font_size)}, direction = .LEFT_TO_RIGHT}})
    cursor: int
    UiPushTag(ctx, "mono")
    for {
        run, _, ok := AnsiNext(line, &cursor, state, palette)
        if !ok { break }
        if len(run) == 0 { continue }
        pushed: int
        if state.bold {
            UiPushTag(ctx, "strong")
            pushed += 1
        }
        if state.italic {
            UiPushTag(ctx, "italic")
            pushed += 1
        }
        if state.dim {
            UiPushTag(ctx, "dim")
            pushed += 1
        }
        if state.underline {
            UiPushTag(ctx, "underline")
            pushed += 1
        }
        // a ground behind the run: an element around its text
        grounded: bool = state.background.a != 0
        if grounded { ElementOpen(ctx, {draw = {kind = .FILL, color = state.background}}) }
        TextOpen(ctx, run, {wrap = .NONE, color = state.color})
        if grounded { ElementClose(ctx) }
        for _ in 0 ..< pushed { UiPopTag(ctx) }
    }
    UiPopTag(ctx)
    ElementClose(ctx)
}

// A text of several lines as a column of UiAnsiLine. Returns the style at its end (for an output that is shown in parts).
UiAnsiText :: proc(ctx: ^Context, text: string, palette: ^[16]Color = nil, start: AnsiState = {}) -> AnsiState {
    state: AnsiState = start
    ElementOpen(ctx, {layout = {size = {Grow(), Fit()}, direction = .TOP_TO_BOTTOM}})
    at: int
    for at < len(text) {
        end: int = at
        for end < len(text) && text[end] != '\n' { end += 1 }
        UiAnsiLine(ctx, text[at:end], &state, palette)
        at = end + 1
    }
    ElementClose(ctx)
    return state
}
