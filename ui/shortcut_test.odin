#+build !js
package ui

import "core:testing"

@(private = "file")
measure :: proc(ctx: ^Context, text: string, font_size: f32) -> Vec2 {
    return {f32(len(text)) * font_size * 0.5, font_size}
}

@(test)
test_a_chord_is_written_as_its_keys :: proc(t: ^testing.T) {
    buffer: [32]u8
    testing.expect_value(t, ChordFormat({}, "S", buffer[:]), "")
    testing.expect_value(t, ChordFormat({key = 7}, "F5", buffer[:]), "F5")
    testing.expect_value(t, ChordFormat({{.CTRL}, 7}, "S", buffer[:]), "Ctrl+S")
    testing.expect_value(t, ChordFormat({{.CTRL, .SHIFT, .ALT}, 7}, "S", buffer[:]), "Ctrl+Alt+Shift+S")
    small: [6]u8
    testing.expect_value(t, ChordFormat({{.CTRL}, 7}, "Space", small[:]), "Ctrl+S")
}

@(test)
test_a_shortcut_is_set_by_pressing_it :: proc(t: ^testing.T) {
    Test :: struct {
        storage: Storage(64, 128, 32, 1024),
        ctx: Context,
        style: Style,
        chord: Chord,
        other: Chord,
        field: Id,
        changes: int,
        listening: bool,
    }
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    test.chord = {{.CTRL}, 19}
    frame :: proc(test: ^Test, input: Input, pressed: Chord = {}) {
        UiBegin(&test.ctx, input, 1.0 / 60, {800, 600}, &test.style)
        if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(400), {}}) {
            test.field = UiId(&test.ctx, "Save##shortcut")
            changed: bool
            changed, test.listening = UiShortcutField(&test.ctx, "Save##shortcut", &test.chord, pressed, proc(key: u16) -> string { return "S" if key == 19 else "other" })
            if changed { test.changes += 1 }
            UiShortcutField(&test.ctx, "Open##shortcut", &test.other, pressed, nil)
        }
        UiEnd(&test.ctx)
    }
    away: Input = {mouse_position = {-100, -100}}
    click :: proc(test: ^Test) {
        rect, _ := UiElementRect(&test.ctx, test.field)
        point: Vec2 = {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5}
        frame(test, {mouse_position = point})
        frame(test, {mouse_position = point, mouse_down = true, mouse_pressed = true})
        frame(test, {mouse_position = point, mouse_released = true})
        frame(test, {mouse_position = {-100, -100}})
    }
    label :: proc(test: ^Test) -> (text: string, filled: bool) {
        for command in UiCommands(&test.ctx) {
            info: DrawInfo = command.info
            if command.kind == .DRAW && info.kind == .BUTTON && info.rect.y < 60 { return info.name, DrawInfoHasTag(&info, "primary") }
        }
        return
    }
    for _ in 0 ..< 3 { frame(test, away) }
    text, filled := label(test)
    testing.expect(t, text == "Ctrl+S" && !filled && !test.listening)
    // a key that is pressed while it does not listen is not for it
    frame(test, away, {{}, 30})
    testing.expect_value(t, test.chord, Chord{{.CTRL}, 19})

    // a click: it listens, the next key with its modifiers is the shortcut
    click(test)
    text, filled = label(test)
    testing.expect(t, test.listening && text == SHORTCUT_LISTENING && filled)
    frame(test, {mouse_position = {-100, -100}, modifiers = {.CTRL, .SHIFT}}, {{.CTRL, .SHIFT}, 42})
    // the new shortcut is shown in the frame it was set, with the name of its key
    text, filled = label(test)
    testing.expect(t, text == "Ctrl+Shift+other" && !filled)
    testing.expect_value(t, test.chord, Chord{{.CTRL, .SHIFT}, 42})
    testing.expect_value(t, test.changes, 1)
    testing.expect(t, !test.listening)
    testing.expect_value(t, test.other, Chord{})               // the other field did not listen

    // Escape lets go without a change
    click(test)
    frame(test, {mouse_position = {-100, -100}, keys = {.ESCAPE}}, {{}, 99})
    testing.expect(t, !test.listening)
    testing.expect_value(t, test.chord, Chord{{.CTRL, .SHIFT}, 42})
    testing.expect(t, !UiCancelled(&test.ctx), "the field took the cancel")

    // Backspace takes the shortcut away
    click(test)
    frame(test, {mouse_position = {-100, -100}, keys = {.BACKSPACE}}, {{}, 98})
    testing.expect_value(t, test.chord, Chord{})
    testing.expect_value(t, test.changes, 2)
    frame(test, away)
    text, _ = label(test)
    testing.expect_value(t, text, SHORTCUT_NONE)

    // the keyboard: the confirm key makes it listen and is not taken as the shortcut, the arrows are keys while it listens
    UiFocus(&test.ctx, test.field)
    frame(test, {mouse_position = {-100, -100}, actions = {.ACCEPT}}, {{}, 13})
    testing.expect(t, test.listening, "the confirm key makes it listen")
    testing.expect_value(t, test.chord, Chord{})
    frame(test, {mouse_position = {-100, -100}, actions = {.DOWN}}, {{}, 50})
    testing.expect_value(t, test.chord, Chord{{}, 50})
    testing.expect_value(t, test.ctx.focus, test.field)         // the arrow did not move the focus
    // a click somewhere else ends the listening
    click(test)
    testing.expect(t, test.listening)
    frame(test, {mouse_position = {700, 500}, mouse_down = true, mouse_pressed = true})
    frame(test, {mouse_position = {700, 500}, mouse_released = true})
    frame(test, away, {{}, 60})
    testing.expect(t, !test.listening)
    testing.expect_value(t, test.chord, Chord{{}, 50})
    testing.expect_value(t, UiProblems(&test.ctx), Problems{})
}
