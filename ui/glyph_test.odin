#+build !js
package ui

import "core:testing"

@(private = "file")
measure :: proc(ctx: ^Context, text: string, font_size: f32) -> Vec2 {
    return {f32(len(text)) * font_size * 0.5, font_size}
}

@(private = "file")
lookup :: proc(user: rawptr, binding: Binding) -> Glyph {
    if binding.device == .GAMEPAD { return {shape = .FACE, label = "A"} }
    return {shape = .KEY, label = "Space"}
}

@(private = "file")
Test :: struct {
    storage: Storage(64, 128, 32, 1024),
    ctx: Context,
    style: Style,
    binding: Binding,
    field: Id,
    changed: int,
    listening: bool,
}

@(private = "file")
frame :: proc(test: ^Test, input: Input, pressed: Binding = {}) {
    UiBegin(&test.ctx, input, 1.0 / 60, {800, 600}, &test.style)
    if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(400), {}}) {
        test.field = UiId(&test.ctx, "bind")
        changed, listening := UiBindingField(&test.ctx, "bind", &test.binding, pressed, lookup)
        if changed { test.changed += 1 }
        test.listening = listening
    }
    UiEnd(&test.ctx)
}

@(test)
test_a_glyph_is_as_wide_as_its_label_and_a_texture_takes_the_size_of_its_part :: proc(t: ^testing.T) {
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    UiBegin(&test.ctx, {}, 1.0 / 60, {800, 600}, &test.style)
    defer UiEnd(&test.ctx)
    height: f32 = DEFAULT_METRICS.control_height * 0.8
    short: Vec2 = GlyphSize(&test.ctx, {shape = .KEY, label = "A"})
    long: Vec2 = GlyphSize(&test.ctx, {shape = .KEY, label = "Space"})
    testing.expect_value(t, short.y, height)
    testing.expect(t, long.x > short.x, "a longer label is a wider cap")
    testing.expect(t, short.x >= short.y, "a cap is never narrower than it is high")
    testing.expect_value(t, GlyphSize(&test.ctx, {shape = .FACE, label = "A"}), Vec2{height, height})
    wide: Vec2 = GlyphSize(&test.ctx, {shape = .SHOULDER, label = "LB"})
    testing.expect(t, wide.x > wide.y * 2, "a bumper lies")
    // a picture takes the shape of its part of the texture
    picture: Vec2 = GlyphSize(&test.ctx, {shape = .FACE, texture = 7, source = {0, 0, 64, 32}})
    testing.expect_value(t, picture, Vec2{height * 2, height})
    testing.expect_value(t, GlyphSize(&test.ctx, {shape = .FACE, texture = 7}), Vec2{height, height})
    testing.expect_value(t, GlyphSize(&test.ctx, {shape = .FACE, label = "A"}, 40), Vec2{40, 40})
}

@(test)
test_a_glyph_is_declared_with_the_style_kind_glyph_and_its_picture :: proc(t: ^testing.T) {
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    UiBegin(&test.ctx, {}, 1.0 / 60, {800, 600}, &test.style)
    if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(400), {}}) {
        UiGlyph(&test.ctx, {shape = .FACE, label = "B", color = {200, 0, 0, 255}, texture = 5, source = {32, 0, 32, 32}})
        UiBindingGlyph(&test.ctx, {device = .KEYBOARD, code = 1}, lookup)
        UiBindingGlyph(&test.ctx, {}, lookup)               // an empty slot is the word None, no glyph
    }
    UiEnd(&test.ctx)
    glyphs: int
    nones: int
    for command in UiCommands(&test.ctx) {
        info: DrawInfo = command.info
        if command.kind != .DRAW { continue }
        if info.kind == .GLYPH {
            glyphs += 1
            if glyphs == 1 {
                testing.expect_value(t, info.text, "B")
                testing.expect_value(t, info.texture, u32(5))
                testing.expect_value(t, info.source, Rect{32, 0, 32, 32})
                testing.expect_value(t, GlyphShape(int(info.actual)), GlyphShape.FACE)
            } else {
                testing.expect_value(t, info.text, "Space")
            }
        }
        if info.kind == .LABEL && info.text == "None" { nones += 1 }
    }
    testing.expect_value(t, glyphs, 2)
    testing.expect_value(t, nones, 1)
}

@(test)
test_a_binding_field_listens_after_a_click_and_takes_the_next_input :: proc(t: ^testing.T) {
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    test.binding = {device = .KEYBOARD, code = 4}
    away: Input = {mouse_position = {-100, -100}}
    for _ in 0 ..< 3 { frame(test, away) }
    rect, _ := UiElementRect(&test.ctx, test.field)
    point: Vec2 = {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5}
    frame(test, {mouse_position = point})
    frame(test, {mouse_position = point, mouse_down = true, mouse_pressed = true})
    frame(test, {mouse_position = point, mouse_released = true})
    testing.expect(t, test.listening, "a click makes it listen")
    // an input that went down in the frame of the click is not the binding: the same frame has the click itself
    frame(test, {mouse_position = point}, {device = .GAMEPAD, code = 9})
    testing.expect_value(t, test.binding, Binding{device = .GAMEPAD, code = 9})
    testing.expect(t, !test.listening, "it lets go after taking one")
    testing.expect_value(t, test.changed, 1)
    // the same input again: nothing changed
    frame(test, {mouse_position = point, mouse_down = true, mouse_pressed = true})
    frame(test, {mouse_position = point, mouse_released = true})
    frame(test, {mouse_position = point}, {device = .GAMEPAD, code = 9})
    testing.expect_value(t, test.changed, 1)
    // Backspace takes the binding away
    frame(test, {mouse_position = point, mouse_down = true, mouse_pressed = true})
    frame(test, {mouse_position = point, mouse_released = true})
    frame(test, {mouse_position = point, keys = {.BACKSPACE}}, {device = .KEYBOARD, code = 3})
    testing.expect_value(t, test.binding, Binding{})
    testing.expect_value(t, test.changed, 2)
    // Escape lets go without a change
    test.binding = {device = .KEYBOARD, code = 4}
    frame(test, {mouse_position = point, mouse_down = true, mouse_pressed = true})
    frame(test, {mouse_position = point, mouse_released = true})
    testing.expect(t, test.listening)
    frame(test, {mouse_position = point, actions = {.CANCEL}})
    frame(test, {mouse_position = {-100, -100}})
    testing.expect(t, !test.listening, "Escape lets go")
    testing.expect_value(t, test.binding, Binding{device = .KEYBOARD, code = 4})
    testing.expect_value(t, UiProblems(&test.ctx), Problems{})
}
