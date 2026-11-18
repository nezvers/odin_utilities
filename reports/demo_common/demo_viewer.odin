#+private file
package demo_common

// A real report on screen: the results of an audio DSP library against C references (`bench_results.report.json`, made from the notes of the project
// with `reports import`). Sections on the left; on the right tables whose headings sort them, ratio columns with a bar and a colour, notes and a
// filter that keeps the rows containing a text. The script chooses a section, sorts a table by its ratio and filters the rows.

import "core:strings"
import kit "../../demo_kit"
import ui "../../ui"
import reports ".."
import view_lib "../view"

@(private="package")
demo_viewer: kit.Demo = {
    name = "viewer",
    init = init,
    draw = draw,
    script = script,
}

screen: Screen
view: view_lib.View
report: reports.Report

SAMPLE :: #load("bench_results.report.json", string)

init :: proc(ctx: ^kit.Context) {
    screen_init(&screen)
    view_lib.ViewInit(&view)
    loaded, ok, message := reports.ReportFromJson(SAMPLE)
    assert(ok, message)
    report = loaded
    ctx.background = {24, 26, 32, 255}
}

draw :: proc(ctx: ^kit.Context) {
    screen_begin(&screen, ctx)
    c: ^ui.Context = &screen.ctx
    if ui.UiWindow(c, "Report", {0, 0}, {ui.Grow(), ui.Grow()}, {padding = ui.PaddingAll(4)}) {
        view_lib.ViewDraw(c, &view, &report)
    }
    screen_end(&screen)
}

script: []kit.Step = {
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return len(report.sections) >= 10 && view.section == -1 }, "the whole report is loaded and all of it is shown"),
    // the section "oscillator" is the second entry of the list on the left (y 113 to 137)
    kit.Click({60, 125}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return view.section == 1 && report.sections[view.section].title == "oscillator" }, "a click on a section shows that section"),
    // the heading of the ratio column (x 821 to 965): a click sorts by it, a second click turns the order round, a third one restores the order of the report
    kit.Click({893, 50}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return view.sort_column == 3 && !view.sort_descending }, "a heading sorts the table by its column"),
    kit.Click({893, 50}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return view.sort_column == 3 && view.sort_descending }, "a second click on it reverses the order"),
    kit.Click({893, 50}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return view.sort_block == -1 && !view.sort_descending }, "a third click puts the table back in the order of the report"),
    // the filter field of the left side
    kit.Click({156, 692}),
    kit.Wait(2),
    kit.Type("saw"),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return string(view.filter[:view.filter_length]) == "saw" }, "what is typed in the filter field is the filter"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&screen.ctx) == {} }, "the frames had no problems"),
}

_ :: strings
