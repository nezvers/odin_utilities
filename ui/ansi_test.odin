#+build !js
package ui

import "core:testing"

@(private = "file")
measure :: proc(ctx: ^Context, text: string, font_size: f32) -> Vec2 {
    return {f32(len(text)) * font_size * 0.5, font_size}
}

@(test)
test_escape_sequences_set_the_style_of_the_runs :: proc(t: ^testing.T) {
    Expected :: struct { run: string, state: AnsiState, line_end: bool }
    check :: proc(t: ^testing.T, text: string, expected: []Expected, palette: ^[16]Color = nil) -> AnsiState {
        cursor: int
        state: AnsiState
        for want, i in expected {
            run, line_end, ok := AnsiNext(text, &cursor, &state, palette)
            testing.expectf(t, ok, "%q: run %d is there", text, i)
            testing.expectf(t, run == want.run && state == want.state && line_end == want.line_end, "%q: run %d is %q %v %v", text, i, run, state, line_end)
        }
        _, _, more := AnsiNext(text, &cursor, &state, palette)
        testing.expectf(t, !more, "%q: the end", text)
        testing.expect_value(t, cursor, len(text))
        return state
    }
    dark: [16]Color = ANSI_COLORS_DARK
    green, red, bright_blue: Color = dark[2], dark[1], dark[12]
    check(t, "", {})
    check(t, "plain", {{"plain", {}, false}})
    check(t, "\x1b[32mok\x1b[0m done", {{"ok", {color = green}, false}, {" done", {}, false}})
    check(t, "\x1b[1;31merror\x1b[22m: \x1b[39mtext", {{"error", {color = red, bold = true}, false}, {": ", {color = red}, false}, {"text", {}, false}})
    check(t, "\x1b[2mdim\x1b[3m both\x1b[23;22m none", {{"dim", {dim = true}, false}, {" both", {dim = true, italic = true}, false}, {" none", {}, false}})
    check(t, "\x1b[94mbright\x1b[m", {{"bright", {color = bright_blue}, false}})
    // the 256 colors and a color by its parts; a background is read and not kept
    check(t, "\x1b[38;5;2ma\x1b[38;5;196mb\x1b[38;5;244mc", {{"a", {color = green}, false}, {"b", {color = {255, 0, 0, 255}}, false}, {"c", {color = {128, 128, 128, 255}}, false}})
    check(t, "\x1b[38;2;10;20;30mx\x1b[48;5;1my\x1b[48;2;1;2;3;1mz", {{"x", {color = {10, 20, 30, 255}}, false}, {"y", {color = {10, 20, 30, 255}}, false}, {"z", {color = {10, 20, 30, 255}, bold = true}, false}})
    // lines: a new line ends a run and is not a part of it, the style goes on; a carriage return before it is dropped
    last: AnsiState = check(t, "one\x1b[31m\ntwo\r\nthree", {{"one", {}, false}, {"", {color = red}, true}, {"two", {color = red}, true}, {"three", {color = red}, false}})
    testing.expect_value(t, last, AnsiState{color = red})
    // other sequences are skipped: clearing a line, moving the cursor, a private mode, an escape that is no sequence
    check(t, "a\x1b[2Kb\x1b[10;5Hc\x1b[?25ld\x1b7e", {{"a", {}, false}, {"b", {}, false}, {"c", {}, false}, {"d", {}, false}, {"e", {}, false}})
    // numbers that mean nothing here change nothing; too many numbers do no harm
    check(t, "\x1b[4;5;7;999mx", {{"x", {}, false}})
    check(t, "\x1b[1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;31mx", {{"x", {bold = true}, false}})
    // a sequence that is not whole (the output still arrives): what is before it is shown, nothing of it
    check(t, "shown\x1b[3", {{"shown", {}, false}})
    check(t, "shown\x1b", {{"shown", {}, false}})
    check(t, "\x1b[38;5", {})
    // the palette of a light ground
    light: [16]Color = ANSI_COLORS_LIGHT
    check(t, "\x1b[32mok", {{"ok", {color = light[2]}, false}}, &light)
    testing.expect_value(t, AnsiColor256(7, &dark), dark[7])
    testing.expect_value(t, AnsiColor256(16, &dark), Color{0, 0, 0, 255})
    testing.expect_value(t, AnsiColor256(231, &dark), Color{255, 255, 255, 255})
    testing.expect_value(t, AnsiColor256(232, &dark), Color{8, 8, 8, 255})
    testing.expect_value(t, AnsiColor256(255, &dark), Color{238, 238, 238, 255})
}

@(test)
test_output_is_shown_in_its_colors :: proc(t: ^testing.T) {
    Test :: struct {
        storage: Storage(128, 256, 64, 2048),
        ctx: Context,
        style: Style,
        end: AnsiState,
    }
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    OUTPUT :: "\x1b[1;32m   Compiling\x1b[0m ui v0.1\n\x1b[33mwarning\x1b[0m: unused \x1b[3mvalue\x1b[0m\n\n\x1b[31mfailed"
    for _ in 0 ..< 2 {
        UiBegin(&test.ctx, {mouse_position = {-100, -100}}, 1.0 / 60, {800, 600}, &test.style)
        if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(600), {}}) { test.end = UiAnsiText(&test.ctx, OUTPUT) }
        UiEnd(&test.ctx)
    }
    testing.expect_value(t, UiProblems(&test.ctx), Problems{})
    find :: proc(ctx: ^Context, text: string) -> (info: DrawInfo, found: bool) {
        for command in UiCommands(ctx) {
            if command.kind == .DRAW && command.info.kind == .LABEL && command.info.text == text { return command.info, true }
        }
        return
    }
    dark: [16]Color = ANSI_COLORS_DARK
    compiling, compiling_found := find(&test.ctx, "   Compiling")
    name, name_found := find(&test.ctx, " ui v0.1")
    warning, warning_found := find(&test.ctx, "warning")
    value, value_found := find(&test.ctx, "value")
    failed, failed_found := find(&test.ctx, "failed")
    testing.expect(t, compiling_found && name_found && warning_found && value_found && failed_found, "the runs are texts")
    testing.expect(t, compiling.color == dark[2] && DrawInfoHasTag(&compiling, "strong") && DrawInfoHasTag(&compiling, "mono"))
    testing.expect(t, name.color.a == 0 && !DrawInfoHasTag(&name, "strong") && DrawInfoHasTag(&name, "mono"))
    testing.expect(t, warning.color == dark[3] && DrawInfoHasTag(&value, "italic") && failed.color == dark[1])
    // a run after another on its line; a line under the other, an empty line takes its room
    testing.expect(t, name.rect.y == compiling.rect.y && name.rect.x >= compiling.rect.x + compiling.rect.z - 0.5)
    testing.expect(t, warning.rect.y > compiling.rect.y)
    testing.expect(t, failed.rect.y - warning.rect.y >= DEFAULT_METRICS.font_size * 1.9, "the empty line is a line")
    testing.expect_value(t, test.end, AnsiState{color = dark[1]})
}
