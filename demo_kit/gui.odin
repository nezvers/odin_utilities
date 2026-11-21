package demo_kit

// A few immediate mode widgets for demos, drawn with the backend and driven by the Input (so a script can click them): the demos
// do not need raygui or a Karl2D ui. Call them from draw, they read the mouse of the context.
//
//     if kit.Button(ctx, {10, 10, 120, 24}, "Reset") { ... }
//     kit.Toggle(ctx, {10, 40, 120, 24}, "Debug", &debug)
//     kit.Slider(ctx, {10, 70, 200, 20}, "Speed", &speed, 0, 10)
//     kit.Spinner(ctx, {10, 100, 200, 24}, "Gravity", &gravity, 1, 1, 1000)
//
// A widget under the kit's demo menu (ctx.ui_hover) does not react. A mouse press that began on a widget belongs to it until it is let go.

GUI_TEXT_SIZE :: 16
GUI_BACKGROUND :: Color{225, 225, 225, 255}
GUI_HOVER :: Color{200, 215, 235, 255}
GUI_PRESSED :: Color{150, 180, 220, 255}
GUI_BORDER :: Color{90, 90, 90, 255}

@(private="file")
gui_active_rect: Rect          // the widget that got the press, a drag that leaves it still belongs to it

@(private="file")
guiHovered :: proc(ctx: ^Context, rect: Rect) -> bool {
    return !ctx.ui_hover && PointInRect(ctx.input.mouse_position, rect)
}

// True on the frame the button is clicked (pressed on it)
Button :: proc(ctx: ^Context, rect: Rect, text: string) -> bool {
    hovered: bool = guiHovered(ctx, rect)
    held: bool = hovered && MouseDown(&ctx.input)
    DrawRect(ctx, rect, GUI_PRESSED if held else GUI_HOVER if hovered else GUI_BACKGROUND)
    DrawRectOutline(ctx, rect, 1, GUI_BORDER)
    DrawTextCentered(ctx, text, {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5}, GUI_TEXT_SIZE, BLACK)
    return hovered && MousePressed(&ctx.input)
}

// A button that stays pressed: flips `value`, returns true when it changed
Toggle :: proc(ctx: ^Context, rect: Rect, text: string, value: ^bool) -> bool {
    hovered: bool = guiHovered(ctx, rect)
    DrawRect(ctx, rect, GUI_PRESSED if value^ else GUI_HOVER if hovered else GUI_BACKGROUND)
    DrawRectOutline(ctx, rect, 1, GUI_BORDER)
    DrawTextCentered(ctx, text, {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5}, GUI_TEXT_SIZE, BLACK)
    if hovered && MousePressed(&ctx.input) {
        value^ = !value^
        return true
    }
    return false
}

// A bar with a handle, dragged with the mouse. The label is on the left of the bar, the value inside. True while it changes.
Slider :: proc(ctx: ^Context, rect: Rect, text: string, value: ^f32, minimum: f32, maximum: f32) -> bool {
    label_width: f32 = MeasureText(ctx, text, GUI_TEXT_SIZE).x + 8
    bar: Rect = {rect.x + label_width, rect.y, max(rect.z - label_width, 10), rect.w}
    DrawText(ctx, text, {rect.x, rect.y + (rect.w - GUI_TEXT_SIZE) * 0.5}, GUI_TEXT_SIZE, BLACK)
    DrawRect(ctx, bar, GUI_BACKGROUND)
    range: f32 = max(maximum - minimum, 0.000001)
    fill: f32 = clamp((value^ - minimum) / range, 0, 1)
    DrawRect(ctx, {bar.x, bar.y, bar.z * fill, bar.w}, GUI_PRESSED)
    DrawRectOutline(ctx, bar, 1, GUI_BORDER)

    if guiHovered(ctx, bar) && MousePressed(&ctx.input) { gui_active_rect = rect }      // by the rectangle the caller gave: the label may change its width every frame
    changed: bool = false
    if gui_active_rect == rect && MouseDown(&ctx.input) {
        t: f32 = clamp((ctx.input.mouse_position.x - bar.x) / bar.z, 0, 1)
        new_value: f32 = minimum + t * range
        changed = new_value != value^
        value^ = new_value
    }
    if gui_active_rect == rect && !MouseDown(&ctx.input) { gui_active_rect = {} }
    return changed
}

// - value + : the two buttons change the value by `step`, inside of [minimum, maximum]. True when it changed.
Spinner :: proc(ctx: ^Context, rect: Rect, text: string, value: ^f32, step: f32, minimum: f32, maximum: f32) -> bool {
    label_width: f32 = MeasureText(ctx, text, GUI_TEXT_SIZE).x + 8
    button: f32 = rect.w
    DrawText(ctx, text, {rect.x, rect.y + (rect.w - GUI_TEXT_SIZE) * 0.5}, GUI_TEXT_SIZE, BLACK)
    minus: Rect = {rect.x + label_width, rect.y, button, rect.w}
    plus: Rect = {rect.x + rect.z - button, rect.y, button, rect.w}
    field: Rect = {minus.x + button, rect.y, plus.x - minus.x - button, rect.w}
    DrawRect(ctx, field, WHITE)
    DrawRectOutline(ctx, field, 1, GUI_BORDER)
    DrawTextCentered(ctx, spinnerText(value^), {field.x + field.z * 0.5, field.y + field.w * 0.5}, GUI_TEXT_SIZE, BLACK)
    before: f32 = value^
    if Button(ctx, minus, "-") { value^ = max(value^ - step, minimum) }
    if Button(ctx, plus, "+") { value^ = min(value^ + step, maximum) }
    return value^ != before
}

@(private="file")
spinner_buffer: [32]u8

// the value as text without importing fmt into the kit: whole numbers without decimals, else two
@(private="file")
spinnerText :: proc(value: f32) -> string {
    negative: bool = value < 0
    scaled: int = int(abs(value) * 100 + 0.5)
    whole: int = scaled / 100
    fraction: int = scaled % 100
    length: int = 0
    digits: [20]u8
    count: int = 0
    for {
        digits[count] = u8('0' + whole % 10)
        count += 1
        whole /= 10
        if whole == 0 { break }
    }
    if negative { spinner_buffer[length] = '-'; length += 1 }
    for i := count - 1; i >= 0; i -= 1 { spinner_buffer[length] = digits[i]; length += 1 }
    if fraction != 0 {
        spinner_buffer[length] = '.'; length += 1
        spinner_buffer[length] = u8('0' + fraction / 10); length += 1
        if fraction % 10 != 0 { spinner_buffer[length] = u8('0' + fraction % 10); length += 1 }
    }
    return string(spinner_buffer[:length])
}

// A line of text, for symmetry with the widgets
Label :: proc(ctx: ^Context, position: Vec2, text: string, color: Color = BLACK) {
    DrawText(ctx, text, position, GUI_TEXT_SIZE, color)
}

// A line of text that the keyboard types into. `focused` is where the focus is kept (the field takes it when it is clicked and gives it up when something else is): the characters typed this frame
// are added, Backspace removes one, Ctrl+V pastes the clipboard (one line, no control characters), Ctrl+C copies, Enter is `submitted`. `buffer` is the text (`length` of it is used); what does
// not fit is not added. A long text shows its end.
//
//     kit.TextField(ctx, {10, 10, 300, 28}, name[:], &name_length, &focus_name, "your name")
TextField :: proc(ctx: ^Context, rect: Rect, buffer: []u8, length: ^int, focused: ^bool, placeholder: string = "") -> (submitted: bool) {
    hovered: bool = guiHovered(ctx, rect)
    if MousePressed(&ctx.input) { focused^ = hovered }
    DrawRect(ctx, rect, WHITE)
    DrawRectOutline(ctx, rect, 2 if focused^ else 1, DARK_BLUE if focused^ else GUI_BORDER)
    if focused^ {
        for i in 0 ..< int(ctx.input.text_count) {
            character: u8 = ctx.input.text[i]
            if character >= 32 && character < 127 && length^ < len(buffer) {
                buffer[length^] = character
                length^ += 1
            }
        }
        if KeyPressed(&ctx.input, .BACKSPACE) && length^ > 0 { length^ -= 1 }
        control: bool = KeyDown(&ctx.input, .LEFT_CTRL) || KeyDown(&ctx.input, .RIGHT_CTRL)
        if control && KeyPressed(&ctx.input, .V) { TextFieldPaste(ctx, buffer, length) }
        if control && KeyPressed(&ctx.input, .C) { ClipboardSet(ctx, string(buffer[:length^])) }
        submitted = KeyPressed(&ctx.input, .ENTER)
    }
    shown: string = string(buffer[:length^])
    if len(shown) == 0 && !focused^ {
        DrawText(ctx, placeholder, {rect.x + 6, rect.y + (rect.w - GUI_TEXT_SIZE) * 0.5}, GUI_TEXT_SIZE, GRAY)
        return
    }
    // the end of a long text: drop letters from the start until it fits
    for len(shown) > 1 && MeasureText(ctx, shown, GUI_TEXT_SIZE).x > rect.z - 14 { shown = shown[1:] }
    DrawText(ctx, shown, {rect.x + 6, rect.y + (rect.w - GUI_TEXT_SIZE) * 0.5}, GUI_TEXT_SIZE, BLACK)
    if focused^ && int(ctx.time * 2) % 2 == 0 {
        width: f32 = MeasureText(ctx, shown, GUI_TEXT_SIZE).x
        DrawRect(ctx, {rect.x + 7 + width, rect.y + 4, 2, rect.w - 8}, BLACK)
    }
    return
}

// Adds the clipboard to a text field's buffer (the first line of it, printable characters only)
TextFieldPaste :: proc(ctx: ^Context, buffer: []u8, length: ^int) {
    scratch: [CLIPBOARD_LOCAL]u8
    pasted: string = ClipboardGet(ctx, scratch[:])
    for i in 0 ..< len(pasted) {
        character: u8 = pasted[i]
        if character == '\n' || character == '\r' { break }
        if character >= 32 && character < 127 && length^ < len(buffer) {
            buffer[length^] = character
            length^ += 1
        }
    }
}
