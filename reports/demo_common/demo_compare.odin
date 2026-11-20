#+private file
package demo_common

// Two runs of the same measurements compared (`ReportCompare`): the numbers side by side with new / old coloured by whether it got better or worse,
// the checks that changed and the findings that appeared or went away. The comparison is a report like any other, so the same viewer shows it.
// The second run is the first with its numbers moved by a fixed pattern (and a few checks and findings added), so the demo needs no second file.

import "core:fmt"
import kit "../../demo_kit"
import ui "../../ui"
import reports ".."
import view_lib "../view"

@(private="package")
demo_compare: kit.Demo = {
    name = "compare",
    init = init,
    draw = draw,
    script = script,
}

screen: Screen
view: view_lib.View
old, new, result: reports.Report
summary: reports.CompareSummary

SAMPLE :: #load("bench_results.report.json", string)

// How much each row of a table changed between the two runs: faster, the same, slower
FACTORS :: [?]f64{0.55, 0.9, 1.0, 1.0, 1.12, 1.45, 0.98}

init :: proc(ctx: ^kit.Context) {
    screen_init(&screen)
    view_lib.ViewInit(&view)
    ok: bool
    message: string
    old, ok, message = reports.ReportFromJson(SAMPLE)
    assert(ok, message)
    new, ok, message = reports.ReportFromJson(SAMPLE)
    assert(ok, message)
    new.title = fmt.aprintf("%s (later run)", old.title)
    // the numbers of the later run
    for &section, s in new.sections {
        for &block in section.blocks {
            if block.kind != .TABLE { continue }
            table: ^reports.Table = &block.table
            for row in 0 ..< reports.TableRowCount(table) {
                for &column, c in table.columns {
                    if column.kind != .NUMBER || column.better == .NONE { continue }
                    cell: ^reports.Cell = reports.TableCell(table, row, c)
                    if !cell.has_number { continue }
                    factors: [len(FACTORS)]f64 = FACTORS
                    cell.number *= factors[(row + s) % len(factors)]
                    cell.text = ""
                }
            }
        }
    }
    // a list of checks and a list of findings in both runs, with a difference
    for report, index in ([?]^reports.Report{&old, &new}) {
        reports.ReportSection(report, "tests")
        reports.ReportChecks(report, "unit tests")
        reports.ReportCheck(report, "biquad", .OK)
        reports.ReportCheck(report, "fft", .FAIL if index == 0 else .OK, "bin 3 off by 1e-3" if index == 0 else "")
        reports.ReportCheck(report, "resample", .OK if index == 0 else .WARN, "" if index == 0 else "slow: 3 s")
        reports.ReportFindings(report, "review")
        reports.ReportFinding(report, .MEDIUM, "name is unclear", "biquad.odin:12")
        if index == 0 {
            reports.ReportFinding(report, .HIGH, "buffer is read after free", "fft.odin:88", "the plan is deleted before the last transform")
        } else {
            reports.ReportFinding(report, .LOW, "a new remark", "wav.odin:3")
        }
    }
    result, summary = reports.ReportCompare(&old, &new)
    ctx.background = {17, 19, 21, 255}        // the background of the dark theme (ui_default.THEME_DARK)
}

draw :: proc(ctx: ^kit.Context) {
    screen_begin(&screen, ctx)
    c: ^ui.Context = &screen.ctx
    if ui.UiWindow(c, "Comparison", {0, 0}, {ui.Grow(), ui.Grow()}, {padding = ui.PaddingAll(4)}) {
        view_lib.ViewDraw(c, &view, &result)
    }
    screen_end(&screen)
}

script: []kit.Step = {
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        return summary.improved > 10 && summary.regressed > 10 && summary.same > 10
    }, "the comparison found numbers that got better, worse and stayed"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        return summary.checks_fixed == 1 && summary.checks_broken == 1 && summary.findings_new == 1 && summary.findings_gone == 1
    }, "one check fixed, one broken, one finding new and one gone"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return result.sections[0].title == "summary" }, "the summary is the first section"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&screen.ctx) == {} }, "the frames had no problems"),
}
