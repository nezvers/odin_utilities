#+build !js
package ui

import "core:testing"

@(private = "file")
measure :: proc(ctx: ^Context, text: string, font_size: f32) -> Vec2 {
    return {f32(len(text)) * font_size * 0.5, font_size}
}

@(test)
test_the_settings_have_defaults_and_the_double_click_time_can_be_changed :: proc(t: ^testing.T) {
    Test :: struct {
        storage: Storage(64, 128, 32, 1024),
        ctx: Context,
        style: Style,
        doubles: int,
        button: Id,
    }
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    settings: ^Settings = UiSettings(&test.ctx)
    testing.expect_value(t, settings.double_click_seconds, f64(DOUBLE_CLICK_SECONDS))
    testing.expect_value(t, settings.multi_click_limit, 3)
    testing.expect_value(t, settings.drag_start_distance, f32(DRAG_START_DISTANCE))
    testing.expect_value(t, settings.extend_modifier, Modifier.SHIFT)
    frame :: proc(test: ^Test, input: Input, delta_time: f32) {
        UiBegin(&test.ctx, input, delta_time, {800, 600}, &test.style)
        if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(300), {}}) {
            test.button = UiId(&test.ctx, "Go")
            interaction: Interaction = UiInteract(&test.ctx, test.button)
            if interaction.double_clicked { test.doubles += 1 }
            ElementOpen(&test.ctx, {id = test.button, layout = {size = {Fixed(100), Fixed(28)}}, hit = {.INTERACTIVE}})
            ElementClose(&test.ctx)
        }
        UiEnd(&test.ctx)
    }
    // two presses with `gap` seconds between them: is the second a double click
    press_twice :: proc(test: ^Test, gap: f32) -> bool {
        for _ in 0 ..< 3 { frame(test, {mouse_position = {-100, -100}}, 1.0 / 60) }
        rect, _ := UiElementRect(&test.ctx, test.button)
        point: Vec2 = {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5}
        frame(test, {mouse_position = point}, 1.0 / 60)
        frame(test, {mouse_position = point, mouse_down = true, mouse_pressed = true}, 1.0 / 60)
        frame(test, {mouse_position = point, mouse_released = true}, 1.0 / 60)
        before: int = test.doubles
        frame(test, {mouse_position = point}, gap)                                  // the time that goes by before the second press
        frame(test, {mouse_position = point, mouse_down = true, mouse_pressed = true}, 1.0 / 60)
        frame(test, {mouse_position = point, mouse_released = true}, 1.0 / 60)
        return test.doubles > before
    }
    testing.expect(t, press_twice(test, 0.1), "quick: a double click")
    testing.expect(t, !press_twice(test, 0.6), "slow: two clicks with the defaults")
    settings.double_click_seconds = 1.0
    testing.expect(t, press_twice(test, 0.6), "slow hands: the same gap is a double click when the time is longer")
    settings.double_click_seconds = 0.05
    testing.expect(t, !press_twice(test, 0.1), "a short time: a gap that was a double click is not")
}

@(test)
test_the_distance_a_drag_starts_at_is_a_setting :: proc(t: ^testing.T) {
    Test :: struct {
        storage: Storage(64, 128, 32, 1024),
        ctx: Context,
        style: Style,
        source: Id,
        value: int,
    }
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    frame :: proc(test: ^Test, input: Input) {
        UiBegin(&test.ctx, input, 1.0 / 60, {800, 600}, &test.style)
        if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(300), {}}) {
            test.source = UiId(&test.ctx, "Item")
            UiButton(&test.ctx, "Item", {Fixed(100), {}})
            UiDragSourceValue(&test.ctx, "item", &test.value)
        }
        UiEnd(&test.ctx)
    }
    dragging :: proc(test: ^Test, distance: f32) -> bool {
        for _ in 0 ..< 3 { frame(test, {mouse_position = {-100, -100}}) }
        rect, _ := UiElementRect(&test.ctx, test.source)
        from: Vec2 = {rect.x + 10, rect.y + rect.w * 0.5}
        frame(test, {mouse_position = from})
        frame(test, {mouse_position = from, mouse_down = true, mouse_pressed = true})
        frame(test, {mouse_position = from + {distance, 0}, mouse_down = true})
        _, active := UiDragging(&test.ctx)
        frame(test, {mouse_position = from + {distance, 0}, mouse_released = true})
        frame(test, {mouse_position = {-100, -100}})
        return active
    }
    testing.expect(t, dragging(test, 8), "8 pixels: a drag with the default 5")
    testing.expect(t, !dragging(test, 3), "3 pixels: not yet")
    UiSettings(&test.ctx).drag_start_distance = 12
    testing.expect(t, !dragging(test, 8), "8 pixels: not with 12")
    testing.expect(t, dragging(test, 14), "14 pixels")
    UiSettings(&test.ctx).drag_start_distance = 1
    testing.expect(t, dragging(test, 2), "a hair is enough")
}
