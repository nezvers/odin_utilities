#+private file
package demo_common

// A report that a program (or an agent) builds with the API, not from a file: the status of a piece of work with facts, a list of checks, a table
// with budgets (a number past its limit is a warning or a failure), a chart of how a measurement went over the last runs, findings of a review and
// a log. Nothing in it is a benchmark: this is what reporting to a person looks like.

import "core:math"
import kit "../../demo_kit"
import ui "../../ui"
import reports ".."
import view_lib "../view"

@(private="package")
demo_status: kit.Demo = {
    name = "status",
    init = init,
    draw = draw,
    script = script,
}

screen: Screen
view: view_lib.View
report: reports.Report

init :: proc(ctx: ^kit.Context) {
    screen_init(&screen)
    view_lib.ViewInit(&view)
    reports.ReportInit(&report, "Status: the resampler port")
    reports.ReportMeta(&report, "branch", "resampler")
    reports.ReportMeta(&report, "date", "2026-11-18")

    reports.ReportSection(&report, "summary")
    reports.ReportParagraph(&report, "The kernels are ported and tested. Two budgets are missed and one test fails: the stopband check of the low quality mode.")
    reports.ReportFacts(&report, "run")
    reports.ReportFact(&report, "commits", "14")
    reports.ReportFact(&report, "files changed", "9")
    reports.ReportFact(&report, "peak memory of the tests", "3.1 MB", .WARN)

    reports.ReportSection(&report, "tests")
    reports.ReportChecks(&report, "unit tests")
    reports.ReportCheck(&report, "kernel table is symmetric", .OK)
    reports.ReportCheck(&report, "output is the same for any block size", .OK)
    reports.ReportCheck(&report, "stopband of LOW, -88 dB", .FAIL, "measured -81 dB at 96 -> 44.1 kHz")
    reports.ReportCheck(&report, "96 -> 44.1 kHz against the reference", .WARN, "3 of 4096 samples differ by 1e-5")
    reports.ReportCheck(&report, "wav decoding", .NONE, "not run yet")

    reports.ReportSection(&report, "budgets")
    reports.ReportTable(&report, "time per output sample", {
        {name = "mode"},
        {name = "ns", kind = .NUMBER, better = .LOWER, limits = true, warn = 30, fail = 60, precision = 1},
        {name = "memory", unit = "KB", kind = .NUMBER, better = .LOWER, limits = true, warn = 200, fail = 400, precision = -1},
    })
    reports.ReportRowNumbers(&report, "LOW 44.1 -> 48", 15.5, 40)
    reports.ReportRowNumbers(&report, "MEDIUM 44.1 -> 48", 25.8, 90)
    reports.ReportRowNumbers(&report, "HIGH 44.1 -> 48", 38.2, 180)
    reports.ReportRowNumbers(&report, "HIGH 96 -> 44.1", 71.0, 260)

    reports.ReportSection(&report, "history")
    runs: [12]f64
    odin_time: [12]f64
    reference_time: [12]f64
    for i in 0 ..< len(runs) {
        runs[i] = f64(i + 1)
        odin_time[i] = 74 - f64(i) * 3.1 + math.sin(f64(i) * 1.3) * 1.5
        reference_time[i] = 30.5
    }
    reports.ReportChart(&report, "HIGH quality over the last runs", runs[:], "run", "ns per output sample")
    reports.ReportSeries(&report, "this port", odin_time[:])
    reports.ReportSeries(&report, "reference", reference_time[:])

    reports.ReportSection(&report, "review")
    reports.ReportFindings(&report, "found in the diff")
    reports.ReportFinding(&report, .HIGH, "the history buffer is read before it is filled", "resample.odin:212", "the first block of a stream reads garbage for the first taps")
    reports.ReportFinding(&report, .MEDIUM, "table size is a magic number", "resample.odin:40")
    reports.ReportFinding(&report, .LOW, "comment explains what, not why", "resample.odin:97")
    reports.ReportCode(&report, "odin test dsp -test-name:ResampleStopband\n[ERROR] stopband -81 dB, expected below -88 dB", "text")
    ctx.background = {17, 19, 21, 255}        // the background of the dark theme (ui_default.THEME_DARK)
}

draw :: proc(ctx: ^kit.Context) {
    screen_begin(&screen, ctx)
    c: ^ui.Context = &screen.ctx
    if ui.UiWindow(c, "Status", {0, 0}, {ui.Grow(), ui.Grow()}, {padding = ui.PaddingAll(4)}) {
        view_lib.ViewDraw(c, &view, &report)
    }
    screen_end(&screen)
}

script: []kit.Step = {
    kit.Wait(3),
    // the history section is the fifth entry of the list: its chart is a picture that is kept (captures/), so a change of how it looks is seen
    kit.Click({60, 207}),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return view.section == 3 && report.sections[view.section].title == "history" }, "a click on history shows the history section"),
    kit.Capture("status_history"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return reports.ReportStatus(&report) == .FAIL }, "the report fails: a check and a finding are bad, two budgets are missed"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        table: ^reports.Table = &report.sections[2].blocks[0].table
        return reports.TableCell(table, 3, 1).status == .FAIL && reports.TableCell(table, 0, 1).status == .OK && reports.TableCell(table, 2, 2).status == .OK
    }, "the budgets gave their statuses"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&screen.ctx) == {} }, "the frames had no problems"),
}
