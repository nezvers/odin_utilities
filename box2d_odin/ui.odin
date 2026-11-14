package box2d_odin

import "core:fmt"
import "core:testing"

Color :: [4]u8

// Drawing a framework has to provide for the UI and screen text
Backend :: struct {
    rect: proc(rect: Rect, color: Color),
    rect_outline: proc(rect: Rect, color: Color),
    text: proc(text: string, position: Vec2, size: f32, color: Color),
    text_width: proc(text: string, size: f32) -> f32,
}

UI_COLOR_PANEL :: Color{30, 30, 36, 220}
UI_COLOR_WIDGET :: Color{70, 70, 80, 255}
UI_COLOR_HOVER :: Color{100, 100, 120, 255}
UI_COLOR_ACTIVE :: Color{80, 140, 220, 255}
UI_COLOR_TEXT :: Color{235, 235, 235, 255}
UI_COLOR_TITLE :: Color{240, 200, 100, 255}

// Small immediate mode UI that is the same for every framework.
// Widgets are laid out top to bottom inside of the panel rectangle.
Ui :: struct {
    backend: ^Backend,
    input: ^Input,
    panel: Rect,
    cursor: Vec2,
    font_size: f32,
    row_height: f32,
    active: rawptr,         // slider that is being dragged
}

UiInit :: proc(ui: ^Ui, backend: ^Backend, input: ^Input, font_size: f32 = 16) {
    ui^ = {
        backend = backend,
        input = input,
        font_size = font_size,
        row_height = font_size + 8,
    }
}

// Start a panel, draws the background
UiBegin :: proc(ui: ^Ui, panel: Rect, title: string = "") {
    ui.panel = panel
    ui.cursor = {panel.x + 6, panel.y + 6}
    ui.backend.rect(panel, UI_COLOR_PANEL)
    if len(title) > 0 {
        UiLabel(ui, title, UI_COLOR_TITLE)
    }
    if !ui.input.mouse_down[.LEFT] {
        ui.active = nil
    }
}

UiHovering :: proc(ui: ^Ui) -> bool {
    return RectContains(ui.panel, ui.input.mouse)
}

RectContains :: proc "contextless" (rect: Rect, point: Vec2) -> bool {
    return point.x >= rect.x && point.x < rect.x + rect.w && point.y >= rect.y && point.y < rect.y + rect.h
}

// Next widget rectangle, advances the cursor
UiNextRect :: proc(ui: ^Ui, height: f32 = 0) -> Rect {
    h: f32 = height if height > 0 else ui.row_height
    rect: Rect = {ui.cursor.x, ui.cursor.y, ui.panel.w - 12, h}
    ui.cursor.y += h + 3
    return rect
}

UiSpace :: proc(ui: ^Ui, space: f32 = 8) {
    ui.cursor.y += space
}

UiLabel :: proc(ui: ^Ui, text: string, color: Color = UI_COLOR_TEXT) {
    rect: Rect = UiNextRect(ui, ui.font_size + 4)
    ui.backend.text(text, {rect.x, rect.y}, ui.font_size, color)
}

UiLabelf :: proc(ui: ^Ui, format: string, args: ..any) {
    buffer: [256]byte
    UiLabel(ui, fmt.bprintf(buffer[:], format, ..args))
}

UiButton :: proc(ui: ^Ui, label: string, selected: bool = false) -> (pressed: bool) {
    rect: Rect = UiNextRect(ui)
    hovered: bool = RectContains(rect, ui.input.mouse)
    color: Color = UI_COLOR_ACTIVE if selected else (UI_COLOR_HOVER if hovered else UI_COLOR_WIDGET)
    ui.backend.rect(rect, color)
    ui.backend.text(label, {rect.x + 6, rect.y + 4}, ui.font_size, UI_COLOR_TEXT)
    return hovered && ui.input.mouse_pressed[.LEFT]
}

UiCheckbox :: proc(ui: ^Ui, label: string, value: ^bool) -> (changed: bool) {
    rect: Rect = UiNextRect(ui)
    hovered: bool = RectContains(rect, ui.input.mouse)
    box: Rect = {rect.x, rect.y + 2, rect.h - 4, rect.h - 4}
    ui.backend.rect(box, UI_COLOR_HOVER if hovered else UI_COLOR_WIDGET)
    if value^ {
        ui.backend.rect({box.x + 3, box.y + 3, box.w - 6, box.h - 6}, UI_COLOR_ACTIVE)
    }
    ui.backend.text(label, {rect.x + rect.h, rect.y + 4}, ui.font_size, UI_COLOR_TEXT)
    if hovered && ui.input.mouse_pressed[.LEFT] {
        value^ = !value^
        changed = true
    }
    return
}

// Label with the value is drawn on the slider
UiSlider :: proc(ui: ^Ui, label: string, value: ^f32, low: f32, high: f32) -> (changed: bool) {
    rect: Rect = UiNextRect(ui)
    hovered: bool = RectContains(rect, ui.input.mouse)
    if hovered && ui.input.mouse_pressed[.LEFT] {
        ui.active = rawptr(value)
    }
    if ui.active == rawptr(value) && ui.input.mouse_down[.LEFT] {
        t: f32 = clamp((ui.input.mouse.x - rect.x) / rect.w, 0, 1)
        new_value: f32 = low + (high - low) * t
        if new_value != value^ {
            value^ = new_value
            changed = true
        }
    }

    ui.backend.rect(rect, UI_COLOR_HOVER if hovered else UI_COLOR_WIDGET)
    t: f32 = clamp((value^ - low) / (high - low), 0, 1)
    ui.backend.rect({rect.x, rect.y, rect.w * t, rect.h}, UI_COLOR_ACTIVE)
    buffer: [128]byte
    ui.backend.text(fmt.bprintf(buffer[:], "%s: %.2f", label, value^), {rect.x + 6, rect.y + 4}, ui.font_size, UI_COLOR_TEXT)
    return
}

UiSliderInt :: proc(ui: ^Ui, label: string, value: ^i32, low: i32, high: i32) -> (changed: bool) {
    as_float: f32 = f32(value^)
    // Same look as UiSlider but with integer text
    rect: Rect = UiNextRect(ui)
    hovered: bool = RectContains(rect, ui.input.mouse)
    if hovered && ui.input.mouse_pressed[.LEFT] {
        ui.active = rawptr(value)
    }
    if ui.active == rawptr(value) && ui.input.mouse_down[.LEFT] {
        t: f32 = clamp((ui.input.mouse.x - rect.x) / rect.w, 0, 1)
        new_value: i32 = low + i32(f32(high - low) * t + 0.5)
        if new_value != value^ {
            value^ = new_value
            changed = true
        }
    }
    ui.backend.rect(rect, UI_COLOR_HOVER if hovered else UI_COLOR_WIDGET)
    t: f32 = clamp((as_float - f32(low)) / f32(high - low), 0, 1)
    ui.backend.rect({rect.x, rect.y, rect.w * t, rect.h}, UI_COLOR_ACTIVE)
    buffer: [128]byte
    ui.backend.text(fmt.bprintf(buffer[:], "%s: %d", label, value^), {rect.x + 6, rect.y + 4}, ui.font_size, UI_COLOR_TEXT)
    return
}

// Row of buttons, one per option, selected one is highlighted
UiSelect :: proc(ui: ^Ui, options: []string, value: ^i32) -> (changed: bool) {
    for option, i in options {
        if UiButton(ui, option, int(value^) == i) {
            value^ = i32(i)
            changed = true
        }
    }
    return
}

// --- Tests ---

@(private="file", thread_local)
log_rects: [32]Rect
@(private="file", thread_local)
log_rect_colors: [32]Color
@(private="file", thread_local)
log_rect_count: int
@(private="file", thread_local)
log_texts: [16][64]u8
@(private="file", thread_local)
log_text_lengths: [16]int
@(private="file", thread_local)
log_text_count: int

@(private="file")
recording_backend :: proc() -> Backend {
    log_rect_count = 0
    log_text_count = 0
    return {
        rect = proc(rect: Rect, color: Color) {
            if log_rect_count < len(log_rects) {
                log_rects[log_rect_count] = rect
                log_rect_colors[log_rect_count] = color
                log_rect_count += 1
            }
        },
        rect_outline = proc(rect: Rect, color: Color) {},
        text = proc(text: string, position: Vec2, size: f32, color: Color) {
            if log_text_count < len(log_texts) {
                log_text_lengths[log_text_count] = copy(log_texts[log_text_count][:], text)
                log_text_count += 1
            }
        },
        text_width = proc(text: string, size: f32) -> f32 { return f32(len(text)) * 8 },
    }
}

@(private="file")
logged_text :: proc(index: int) -> string {
    return string(log_texts[index][:log_text_lengths[index]])
}

@(test)
test_rect_contains :: proc(t: ^testing.T) {
    rect: Rect = {10, 20, 30, 40}
    testing.expect(t, RectContains(rect, {10, 20}), "the top left corner is inside")
    testing.expect(t, RectContains(rect, {39.9, 59.9}))
    testing.expect(t, !RectContains(rect, {40, 30}), "the right edge is outside")
    testing.expect(t, !RectContains(rect, {20, 60}), "and so is the bottom edge")
    testing.expect(t, !RectContains(rect, {9, 30}))
}

@(test)
test_ui_layout_stacks_widgets :: proc(t: ^testing.T) {
    backend: Backend = recording_backend()
    input: Input
    ui: Ui
    UiInit(&ui, &backend, &input, 16)
    testing.expect_value(t, ui.row_height, f32(24))

    UiBegin(&ui, {10, 10, 200, 300}, "Title")
    testing.expect_value(t, log_rects[0], Rect{10, 10, 200, 300})                          // the panel background
    testing.expect_value(t, logged_text(0), "Title")
    testing.expect_value(t, ui.cursor.x, f32(16))                                          // widgets are inset by the padding

    first: Rect = UiNextRect(&ui)
    second: Rect = UiNextRect(&ui)
    testing.expect_value(t, first.w, f32(188))
    testing.expect_value(t, first.h, f32(24))
    testing.expect_value(t, second.y, first.y + 27)                                        // a row plus a 3 px gap

    before: f32 = ui.cursor.y
    UiSpace(&ui, 10)
    testing.expect_value(t, ui.cursor.y, before + 10)

    UiLabelf(&ui, "%d of %d", 3, 7)
    testing.expect_value(t, logged_text(1), "3 of 7")

    input.mouse = {20, 20}
    testing.expect(t, UiHovering(&ui))
    input.mouse = {500, 500}
    testing.expect(t, !UiHovering(&ui))
}

@(test)
test_ui_button_and_checkbox :: proc(t: ^testing.T) {
    backend: Backend = recording_backend()
    input: Input
    ui: Ui
    UiInit(&ui, &backend, &input)
    panel: Rect = {0, 0, 200, 300}

    input.mouse = {20, 14}                                                                 // over the first row
    UiBegin(&ui, panel)
    testing.expect(t, !UiButton(&ui, "Go"), "hovering alone does not press")

    input.mouse_pressed[.LEFT] = true
    UiBegin(&ui, panel)
    testing.expect(t, UiButton(&ui, "Go"), "pressed while hovering")

    UiBegin(&ui, panel)
    UiNextRect(&ui)                                                                        // move to the second row, the pointer stays on the first
    testing.expect(t, !UiButton(&ui, "Elsewhere"), "pressed away from the button")

    checked: bool
    UiBegin(&ui, panel)
    testing.expect(t, UiCheckbox(&ui, "Enable", &checked))
    testing.expect(t, checked)
    UiBegin(&ui, panel)
    testing.expect(t, UiCheckbox(&ui, "Enable", &checked))
    testing.expect(t, !checked, "a second press unchecks it")

    input.mouse_pressed[.LEFT] = false
    UiBegin(&ui, panel)
    testing.expect(t, !UiCheckbox(&ui, "Enable", &checked))
    testing.expect(t, !checked)
}

@(test)
test_ui_slider_dragging :: proc(t: ^testing.T) {
    backend: Backend = recording_backend()
    input: Input
    ui: Ui
    UiInit(&ui, &backend, &input)
    panel: Rect = {0, 0, 200, 300}                                                         // the slider spans x 6 to 194
    value: f32 = 0

    input.mouse = {100, 14}
    input.mouse_down[.LEFT] = true
    input.mouse_pressed[.LEFT] = true
    UiBegin(&ui, panel)
    testing.expect(t, UiSlider(&ui, "Speed", &value, 0, 10))
    testing.expect(t, abs(value - 5) < 0.2, "the pressed position sets the value")

    input.mouse_pressed[.LEFT] = false
    input.mouse = {50, 200}                                                                // dragged far off the widget, still held
    UiBegin(&ui, panel)
    UiSlider(&ui, "Speed", &value, 0, 10)
    testing.expect(t, abs(value - 2.3) < 0.3, "the drag keeps control outside the rectangle")

    input.mouse = {1000, 200}
    UiBegin(&ui, panel)
    UiSlider(&ui, "Speed", &value, 0, 10)
    testing.expect_value(t, value, f32(10))                                                // clamped to the range

    input.mouse_down[.LEFT] = false
    input.mouse = {50, 14}
    UiBegin(&ui, panel)
    testing.expect(t, !UiSlider(&ui, "Speed", &value, 0, 10), "released: no more changes")
    testing.expect_value(t, value, f32(10))
    testing.expect(t, ui.active == nil)
}

@(test)
test_ui_integer_slider_and_select :: proc(t: ^testing.T) {
    backend: Backend = recording_backend()
    input: Input
    ui: Ui
    UiInit(&ui, &backend, &input)
    panel: Rect = {0, 0, 200, 300}

    count: i32 = 0
    input.mouse = {100, 14}
    input.mouse_down[.LEFT] = true
    input.mouse_pressed[.LEFT] = true
    UiBegin(&ui, panel)
    testing.expect(t, UiSliderInt(&ui, "Count", &count, 0, 10))
    testing.expect(t, count == 5, "half way on 0 to 10")
    testing.expect_value(t, logged_text(log_text_count - 1), "Count: 5")

    input.mouse_down[.LEFT] = false
    input.mouse_pressed[.LEFT] = false
    mode: i32 = 0
    options: []string = {"One", "Two", "Three"}
    input.mouse = {20, 6 + 27 + 4}                                                         // second option
    input.mouse_pressed[.LEFT] = true
    UiBegin(&ui, panel)
    testing.expect(t, UiSelect(&ui, options, &mode))
    testing.expect_value(t, mode, i32(1))
    UiBegin(&ui, panel)
    testing.expect(t, UiSelect(&ui, options, &mode))                                       // same press is still on the same option
    testing.expect_value(t, mode, i32(1))
}
