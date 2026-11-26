#+build !js
package ui_figma

import "core:os"
import "core:strings"
import "core:testing"

FIXTURES :: #directory + "fixtures/"

@(private = "file")
generated :: proc(t: ^testing.T, options: Options) -> (source: string, warnings: []string, ok: bool) {
    bytes, read_error := os.read_entire_file(FIXTURES + "login.json", context.temp_allocator)
    testing.expect(t, read_error == nil, "the fixture is there")
    document, parsed := Parse(bytes, context.temp_allocator)
    testing.expect(t, parsed, "the fixture parses")
    if !parsed { return "", nil, false }
    source, warnings = Generate(document, options, context.temp_allocator)
    return source, warnings, true
}

@(test)
test_the_fixture_generates_the_committed_source_and_it_compiles :: proc(t: ^testing.T) {
    source, warnings, ok := generated(t, {package_name = "login", ui_import = "../../../..", source_label = "login.json"})
    if !ok { return }
    golden, golden_error := os.read_entire_file(FIXTURES + "generated/login/login.odin", context.temp_allocator)
    testing.expect(t, golden_error == nil)
    normalized, _ := strings.replace_all(string(golden), "\r\n", "\n", context.temp_allocator)
    testing.expect(t, source == normalized, "the generated source is the committed one (run: odin run ui/figma/tool -- --in ui/figma/fixtures/login.json --package login --ui ../../../.. --out ui/figma/fixtures/generated/login/login.odin)")
    testing.expect_value(t, len(warnings), 3)
    check, _, check_errors, check_error := os.process_exec({command = {"odin", "check", FIXTURES + "generated/login", "-no-entry-point", "-strict-style", "-vet"}}, context.temp_allocator)
    testing.expect(t, check_error == nil && check.exit_code == 0, string(check_errors))
}

@(test)
test_the_layout_and_the_widgets_follow_the_design :: proc(t: ^testing.T) {
    source, _, ok := generated(t, {package_name = "login", ui_import = "../ui"})
    if !ok { return }
    testing.expect(t, strings.contains(source, `padding = {16, 16, 20, 20}, gap = 12`), "padding and gap")
    testing.expect(t, strings.contains(source, `align = {x = .CENTER, y = .TOP}`), "counter axis center of a column is x")
    testing.expect(t, strings.contains(source, `direction = .LEFT_TO_RIGHT`), "a horizontal frame")
    testing.expect(t, strings.contains(source, `width = ui.Grow(), height = ui.Fixed(32)`), "fill and fixed sizing")
    testing.expect(t, strings.contains(source, `s.button_primary_clicked = ui.UiButton(c, "Sign in##1:11"`), "a button takes the text inside it")
    testing.expect(t, strings.contains(source, `ui.UiSlider(c, "Volume Slider##1:6", &s.volume_slider_value`), "the kind at the end of a name")
    testing.expect(t, strings.contains(source, `"Sign in to \"Odin\""`), "quotes in text are escaped")
    testing.expect(t, !strings.contains(source, "not shown"), "a hidden layer is left out")
    testing.expect(t, strings.contains(source, `import ui "../ui"`))
    testing.expect(t, strings.count(source, "ui.UiLabelColored") == 0, "the theme's text color unless asked")
}

@(test)
test_text_colors_and_the_frame_filter :: proc(t: ^testing.T) {
    colored, _, ok := generated(t, {text_colors = true})
    if !ok { return }
    testing.expect(t, strings.contains(colored, `ui.UiLabelColored(c, "Sign in to \"Odin\"", ui.Color{255, 255, 255, 255}`), "a solid text fill with the colors asked")
    _, missing, _ := generated(t, {frames = {"No Such Frame"}})
    testing.expect(t, len(missing) == 1 && strings.contains(missing[0], "no frame found"))
}

@(test)
test_a_nodes_answer_and_an_old_file_without_layout_sizing :: proc(t: ^testing.T) {
    text := `{"nodes": {"1:2": {"document": {"id": "1:2", "name": "Bar", "type": "FRAME", "layoutMode": "HORIZONTAL", "primaryAxisSizingMode": "AUTO", "counterAxisSizingMode": "FIXED",
        "absoluteBoundingBox": {"width": 200, "height": 40},
        "children": [{"id": "1:3", "name": "Fill", "type": "RECTANGLE", "layoutGrow": 1, "layoutAlign": "STRETCH", "absoluteBoundingBox": {"width": 10, "height": 10}}]}}}}`
    document, parsed := Parse(transmute([]u8)text, context.temp_allocator)
    testing.expect(t, parsed)
    source, _ := Generate(document, {}, context.temp_allocator)
    testing.expect(t, strings.contains(source, "Bar :: proc(c: ^ui.Context)"), "no state struct without widgets")
    testing.expect(t, strings.contains(source, `size = ui.Size{width = ui.Fit(), height = ui.Fixed(40)}`), "automatic length along the layout")
    testing.expect(t, strings.contains(source, `size = ui.Size{width = ui.Grow(), height = ui.Grow()}`), "layoutGrow and STRETCH of old files")
    _, not_a_file := Parse(transmute([]u8)string(`{"hello": 1}`), context.temp_allocator)
    testing.expect(t, !not_a_file)
}
