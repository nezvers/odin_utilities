#+build !js
package reports

import "base:runtime"
import "core:math"
import "core:mem/virtual"
import "core:strings"
import "core:testing"

// A report with one block of every kind, the way a benchmark run, a test run and a review would fill it.
@(private = "file")
makeSample :: proc(report: ^Report, allocator: runtime.Allocator) {
    ReportInit(report, "Sample run", allocator)
    ReportMeta(report, "machine", "Windows 10, 8 cores")
    ReportMeta(report, "date", "2026-11-17")
    ReportSection(report, "biquad", "against the RBJ cookbook in C")
    ReportTable(report, "", {
        {name = "case"},
        {name = "Odin", unit = "ns", kind = .NUMBER, better = .LOWER},
        {name = "C", unit = "ns", kind = .NUMBER, better = .LOWER},
        {name = "ratio", kind = .RATIO, better = .LOWER},
    })
    ReportRowNumbers(report, "f32 block of 512", 1.79, 1.80, 0.99)
    ReportRowNumbers(report, "design of one peaking filter", 2.9, 19.0, 0.15)
    ReportRowNumbers(report, "stereo, both channels", 1.91, 1.88, 1.02)
    ReportRowNumbers(report, "section after section", 7.10, 5.0, 1.42)
    ReportParagraph(report, "Reading: equally fast loops. Second sentence.")
    ReportSection(report, "tests")
    ReportChecks(report, "unit tests")
    ReportCheck(report, "biquad", .OK)
    ReportCheck(report, "fft", .FAIL, "bin 3 off by 1e-3")
    ReportCheck(report, "resample", .WARN, "slow: 3 s")
    ReportCheck(report, "wav", .NONE)
    ReportFacts(report, "run")
    ReportFact(report, "files", "12")
    ReportFact(report, "peak memory", "3.1 MB", .WARN)
    ReportSection(report, "review")
    ReportFindings(report, "found")
    ReportFinding(report, .LOW, "name is unclear", "biquad.odin:12")
    ReportFinding(report, .HIGH, "buffer is read after free", "fft.odin:88", "the plan is deleted before the last transform")
    ReportCode(report, "odin test dsp\n  3 failed", "text")
    ReportSection(report, "sweep")
    ReportChart(report, "fft time", {256, 1024, 4096}, "size", "ns", .LINE, true)
    ReportSeries(report, "Odin", {149, 669, 3570})
    ReportSeries(report, "KissFFT", {898, 4180, math.nan_f64()})
    ReportChartLabels(report, "per case", {"a", "b"}, "ns")
    ReportSeries(report, "Odin", {1, 2})
}

// A report lives in one arena: everything goes away together.
@(private = "file")
arenaOpen :: proc(arena: ^virtual.Arena) -> runtime.Allocator {
    _ = virtual.arena_init_growing(arena)
    return virtual.arena_allocator(arena)
}

@(test)
test_numbers_are_formatted_with_about_three_significant_digits :: proc(t: ^testing.T) {
    testing.expect_value(t, FormatNumber(1.79), "1.79")
    testing.expect_value(t, FormatNumber(7.1), "7.10")
    testing.expect_value(t, FormatNumber(12.54), "12.5")
    testing.expect_value(t, FormatNumber(118.4), "118")
    testing.expect_value(t, FormatNumber(25000), "25000")
    testing.expect_value(t, FormatNumber(0), "0")
    testing.expect_value(t, FormatNumber(3.14159, 3), "3.142")
    testing.expect_value(t, FormatNumber(3.9, -1), "4")
    testing.expect_value(t, FormatNumber(math.nan_f64()), "nan")
}

@(test)
test_a_ratio_is_judged_against_the_direction_of_its_column :: proc(t: ^testing.T) {
    testing.expect_value(t, RatioVerdict(0.5, .LOWER), Verdict.BETTER)
    testing.expect_value(t, RatioVerdict(1.5, .LOWER), Verdict.WORSE)
    testing.expect_value(t, RatioVerdict(1.03, .LOWER), Verdict.SAME)             // within 5%
    testing.expect_value(t, RatioVerdict(1.03, .LOWER, 0.01), Verdict.WORSE)
    testing.expect_value(t, RatioVerdict(0.5, .HIGHER), Verdict.WORSE)
    testing.expect_value(t, RatioVerdict(0.5, .NONE), Verdict.NONE)
    testing.expect_value(t, RatioVerdict(math.nan_f64(), .LOWER), Verdict.NONE)
}

@(test)
test_a_budget_turns_a_number_into_a_status :: proc(t: ^testing.T) {
    arena: virtual.Arena
    allocator: runtime.Allocator = arenaOpen(&arena)
    defer virtual.arena_destroy(&arena)
    report: Report
    ReportInit(&report, "budgets", allocator)
    ReportSection(&report, "time")
    ReportTable(&report, "", {{name = "case"}, {name = "ms", kind = .NUMBER, better = .LOWER, limits = true, warn = 10, fail = 20},
        {name = "fps", kind = .NUMBER, better = .HIGHER, limits = true, warn = 60, fail = 30}})
    ReportRowNumbers(&report, "fast", 4, 144)
    ReportRowNumbers(&report, "slowish", 12, 45)
    ReportRowNumbers(&report, "slow", 25, 20)
    table: ^Table = &report.sections[0].blocks[0].table
    testing.expect_value(t, TableCell(table, 0, 1).status, Status.OK)
    testing.expect_value(t, TableCell(table, 1, 1).status, Status.WARN)
    testing.expect_value(t, TableCell(table, 2, 1).status, Status.FAIL)
    testing.expect_value(t, TableCell(table, 1, 2).status, Status.WARN)                // higher is better: below 60 warns, below 30 fails
    testing.expect_value(t, TableCell(table, 2, 2).status, Status.FAIL)
    testing.expect_value(t, ReportStatus(&report), Status.FAIL)
    // statuses of the other kinds count too: a finding of high severity fails, a medium one warns
    other: Report
    ReportInit(&other, "x", allocator)
    ReportFindings(&other)
    ReportFinding(&other, .MEDIUM, "m")
    testing.expect_value(t, ReportStatus(&other), Status.WARN)
    ReportFinding(&other, .CRITICAL, "c")
    testing.expect_value(t, ReportStatus(&other), Status.FAIL)
}

@(test)
test_markdown_has_every_kind_of_block_and_reads_back_to_the_same_text :: proc(t: ^testing.T) {
    arena: virtual.Arena
    allocator: runtime.Allocator = arenaOpen(&arena)
    defer virtual.arena_destroy(&arena)
    report: Report
    makeSample(&report, allocator)
    markdown: string = ReportRender(&report, {format = .MARKDOWN}, allocator)
    testing.expect(t, strings.contains(markdown, "# Sample run\n"))
    testing.expect(t, strings.contains(markdown, "## biquad (against the RBJ cookbook in C)"))
    testing.expect(t, strings.contains(markdown, "| case | Odin (ns) | C (ns) | ratio |"))
    testing.expect(t, strings.contains(markdown, "| f32 block of 512 | 1.79 | 1.80 | 0.99 |"))
    testing.expect(t, strings.contains(markdown, "- [!] fft: bin 3 off by 1e-3"))
    testing.expect(t, strings.contains(markdown, "- [~] resample: slow: 3 s"))
    testing.expect(t, strings.contains(markdown, "- peak memory: 3.1 MB [warn]"))
    testing.expect(t, strings.contains(markdown, "- **high** buffer is read after free (fft.odin:88): the plan is deleted before the last transform"))
    testing.expect(t, strings.contains(markdown, "```text\nodin test dsp\n  3 failed\n```"))

    // what was written is read back: the same report renders to the same text
    again: Report
    ReportInit(&again, "", allocator)
    ReportImportMarkdown(&again, markdown)
    testing.expect_value(t, again.title, "Sample run")
    testing.expect_value(t, len(again.meta), 2)
    testing.expect_value(t, len(again.sections), 4)
    table: ^Table = &again.sections[0].blocks[0].table
    testing.expect_value(t, table.columns[1].kind, ColumnKind.NUMBER)
    testing.expect_value(t, table.columns[1].unit, "ns")
    testing.expect_value(t, table.columns[3].kind, ColumnKind.RATIO)
    testing.expect_value(t, table.columns[1].better, Better.LOWER)                     // a table with a ratio column is a benchmark: lower is better
    testing.expect_value(t, TableRowCount(table), 4)
    markdown_again: string = ReportRender(&again, {format = .MARKDOWN}, allocator)
    // the chart became a table in Markdown, so compare what is not a chart
    cut :: proc(text: string) -> string {
        end: int = strings.index(text, "## sweep")
        return text[:end] if end >= 0 else text
    }
    testing.expect_value(t, cut(markdown_again), cut(markdown))
}

@(test)
test_json_keeps_everything_and_is_compact :: proc(t: ^testing.T) {
    arena: virtual.Arena
    allocator: runtime.Allocator = arenaOpen(&arena)
    defer virtual.arena_destroy(&arena)
    report: Report
    makeSample(&report, allocator)
    json_text: string = ReportRender(&report, {format = .JSON}, allocator)
    testing.expect(t, strings.has_prefix(json_text, `{"report":"Sample run","version":1,"meta":[["machine","Windows 10, 8 cores"]`))
    testing.expect(t, strings.contains(json_text, `{"name":"Odin","unit":"ns","kind":"number","better":"lower"}`))
    testing.expect(t, strings.contains(json_text, `["f32 block of 512",1.79,1.8,0.99]`))                    // a table names its columns once, rows are plain arrays
    testing.expect(t, strings.contains(json_text, `["KissFFT"`) == false)
    testing.expect(t, strings.contains(json_text, `"ys":[898,4180,null]`))                                   // a gap is null
    testing.expect(t, !strings.contains(json_text, "\n"))

    loaded, ok, message := ReportFromJson(json_text, allocator)
    testing.expect(t, ok, message)
    // the same report: every format renders it the same
    for format in ([?]Format{.MARKDOWN, .TEXT, .XML, .JSON, .DIGEST}) {
        testing.expect_value(t, ReportRender(&loaded, {format = format}, allocator), ReportRender(&report, {format = format}, allocator))
    }
    // pretty prints say the same
    pretty: string = ReportRender(&report, {format = .JSON, pretty = true}, allocator)
    testing.expect(t, strings.contains(pretty, "\n"))
    from_pretty, pretty_ok, _ := ReportFromJson(pretty, allocator)
    testing.expect(t, pretty_ok)
    testing.expect_value(t, ReportRender(&from_pretty, {format = .JSON}, allocator), json_text)
}

@(test)
test_a_cell_with_text_and_a_status_of_its_own_survives_json :: proc(t: ^testing.T) {
    arena: virtual.Arena
    allocator: runtime.Allocator = arenaOpen(&arena)
    defer virtual.arena_destroy(&arena)
    report: Report
    ReportInit(&report, "cells", allocator)
    ReportTable(&report, "t", {{name = "name"}, {name = "value", kind = .NUMBER, better = .LOWER, limits = true, warn = 5, fail = 10}})
    ReportRow(&report, CellText("a"), CellNumberText(237, "237 (0.63)"))
    ReportRow(&report, CellText("b"), Cell{number = 1, has_number = true, status = .FAIL})                // a status the budget does not give
    ReportRow(&report, CellText("c"), CellNumber(12))                                                        // the budget gives FAIL: not written
    ReportRow(&report, CellText("d"), Cell{})
    json_text: string = ReportRender(&report, {format = .JSON}, allocator)
    testing.expect(t, strings.contains(json_text, `["a",{"n":237,"t":"237 (0.63)"}]`), json_text)                // the budget gives FAIL: not written
    testing.expect(t, strings.contains(json_text, `["b",{"n":1,"s":"fail"}]`))
    testing.expect(t, strings.contains(json_text, `["c",12]`))
    testing.expect(t, strings.contains(json_text, `["d",null]`))
    loaded, ok, _ := ReportFromJson(json_text, allocator)
    testing.expect(t, ok)
    table: ^Table = &loaded.sections[0].blocks[0].table
    testing.expect_value(t, TableCell(table, 0, 1).text, "237 (0.63)")
    testing.expect_value(t, TableCell(table, 0, 1).number, 237)
    testing.expect_value(t, TableCell(table, 1, 1).status, Status.FAIL)
    testing.expect_value(t, TableCell(table, 2, 1).status, Status.FAIL)
    testing.expect(t, !TableCell(table, 3, 1).has_number && TableCell(table, 3, 1).text == "")
}

@(test)
test_json_that_is_not_a_report_is_refused_in_words :: proc(t: ^testing.T) {
    arena: virtual.Arena
    allocator: runtime.Allocator = arenaOpen(&arena)
    defer virtual.arena_destroy(&arena)
    _, ok, message := ReportFromJson("this is not json", allocator)
    testing.expect(t, !ok && strings.contains(message, "not JSON"))
    _, ok, message = ReportFromJson(`{"title":"x"}`, allocator)
    testing.expect(t, !ok && strings.contains(message, "not a report"))
    _, ok, message = ReportFromJson(`{"report":"x","version":99}`, allocator)
    testing.expect(t, !ok && strings.contains(message, "version 99"))
    _, ok, message = ReportFromJson(`{"report":"x","version":1,"sections":[{"title":"s","blocks":[{"table":"t","columns":[{"name":"a"},{"name":"b"}],"rows":[["only one"]]}]}]}`, allocator)
    testing.expect(t, !ok && strings.contains(message, "1 cells"))
    // an empty report, a block of a kind this reader does not know, and a field it does not know are fine
    report, fine, _ := ReportFromJson(`{"report":"x","version":1,"future":true,"sections":[{"title":"s","blocks":[{"timeline":"later"},{"p":"hello"}]}]}`, allocator)
    testing.expect(t, fine)
    testing.expect_value(t, len(report.sections[0].blocks), 1)
}

@(test)
test_the_digest_says_what_stands_out :: proc(t: ^testing.T) {
    arena: virtual.Arena
    allocator: runtime.Allocator = arenaOpen(&arena)
    defer virtual.arena_destroy(&arena)
    report: Report
    makeSample(&report, allocator)
    digest: string = ReportRender(&report, {format = .DIGEST, digest_top = 1}, allocator)
    testing.expect(t, strings.has_prefix(digest, "report: Sample run [fail]\n"), digest)
    testing.expect(t, strings.contains(digest, "meta: machine=Windows 10, 8 cores; date=2026-11-17"))
    testing.expect(t, strings.contains(digest, "ratio (lower is better): geometric mean"), digest)
    testing.expect(t, strings.contains(digest, "1 better, 2 same, 1 worse"), digest)         // 0.15 better, 0.99 and 1.02 the same, 1.42 worse
    testing.expect(t, strings.contains(digest, "worst: section after section 1.42"))
    testing.expect(t, strings.contains(digest, "best: design of one peaking filter 0.15"))
    testing.expect(t, strings.contains(digest, "checks (unit tests): 1 ok, 1 warn, 1 fail, 1 not judged"))
    testing.expect(t, strings.contains(digest, "  fail fft: bin 3 off by 1e-3"))
    testing.expect(t, !strings.contains(digest, "  ok biquad"))                                 // only what is not fine is named
    // findings: all of them, the worst first
    high: int = strings.index(digest, "high buffer is read after free")
    low: int = strings.index(digest, "low name is unclear")
    testing.expect(t, high >= 0 && low > high, digest)
    testing.expect(t, strings.contains(digest, "chart fft time: 3 points, ns over size"))
    testing.expect(t, strings.contains(digest, "  Odin: 149 -> 3570"))
}

@(test)
test_the_options_choose_what_is_shown :: proc(t: ^testing.T) {
    arena: virtual.Arena
    allocator: runtime.Allocator = arenaOpen(&arena)
    defer virtual.arena_destroy(&arena)
    report: Report
    makeSample(&report, allocator)
    // one section by name, the rows sorted by the ratio, only the first two
    shown: string = ReportRender(&report, {format = .MARKDOWN, sections = {"BIQ"}, sort_column = "ratio", sort_descending = true, max_rows = 2, hide_meta = true, hide_paragraphs = true}, allocator)
    testing.expect(t, !strings.contains(shown, "## tests"))
    testing.expect(t, !strings.contains(shown, "Windows 10"))
    testing.expect(t, !strings.contains(shown, "Reading:"))
    first: int = strings.index(shown, "section after section")
    second: int = strings.index(shown, "stereo, both channels")
    testing.expect(t, first >= 0 && second > first, shown)
    testing.expect(t, !strings.contains(shown, "f32 block of 512"))                            // cut by max_rows
    // marks after the values that are better and worse (ASCII), and the heading level
    marked: string = ReportRender(&report, {format = .MARKDOWN, marks = MARKS_ASCII, heading_level = 2}, allocator)
    testing.expect(t, strings.contains(marked, "| 0.15 + |"), marked)
    testing.expect(t, strings.contains(marked, "| 1.42 - |"))
    testing.expect(t, strings.contains(marked, "## Sample run\n"))
    // precision for the columns that leave it to the renderer
    precise: string = ReportRender(&report, {format = .TEXT, precision = 3, sections = {"biquad"}}, allocator)
    testing.expect(t, strings.contains(precise, "1.790"), precise)
    // the program draws a cell itself
    custom: string = ReportRender(&report, {format = .TEXT, sections = {"biquad"}, cell = proc(column: ^Column, cell: ^Cell, user: rawptr) -> (string, bool) {
        if column.kind == .RATIO && cell.has_number { return "RATIO", true }
        return "", false
    }}, allocator)
    testing.expect(t, strings.contains(custom, "RATIO"))
    testing.expect(t, !strings.contains(custom, "0.99"))
}

@(test)
test_text_and_xml_are_readable :: proc(t: ^testing.T) {
    arena: virtual.Arena
    allocator: runtime.Allocator = arenaOpen(&arena)
    defer virtual.arena_destroy(&arena)
    report: Report
    makeSample(&report, allocator)
    text: string = ReportRender(&report, {format = .TEXT}, allocator)
    testing.expect(t, strings.has_prefix(text, "Sample run\n==========\n"))
    testing.expect(t, strings.contains(text, "  [fail] fft: bin 3 off by 1e-3"))
    testing.expect(t, strings.contains(text, "  high     buffer is read after free (fft.odin:88)"))
    xml: string = ReportRender(&report, {format = .XML}, allocator)
    testing.expect(t, strings.has_prefix(xml, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<report title=\"Sample run\" version=\"1\" status=\"fail\">"))
    testing.expect(t, strings.contains(xml, `<column name="Odin" unit="ns" kind="number" better="lower"/>`))
    testing.expect(t, strings.contains(xml, `<check name="fft" status="fail">bin 3 off by 1e-3</check>`))
    testing.expect(t, strings.contains(xml, `<finding severity="high" title="buffer is read after free" location="fft.odin:88">`))
    // what is special in XML is escaped
    other: Report
    ReportInit(&other, "a < b & \"c\"", allocator)
    testing.expect(t, strings.contains(ReportRender(&other, {format = .XML}, allocator), `title="a &lt; b &amp; &quot;c&quot;"`))
}

@(test)
test_markdown_from_an_agent_becomes_a_report :: proc(t: ^testing.T) {
    arena: virtual.Arena
    allocator: runtime.Allocator = arenaOpen(&arena)
    defer virtual.arena_destroy(&arena)
    report: Report
    ReportInit(&report, "", allocator)
    ReportImportMarkdown(&report, `# Status of the port
- branch: port
- tests: 120

## Done (the first half)
Two parts are finished. They
are tested.

**Results**

| step | time (s) | ratio |
|---|---|---|
| parse | 1.2 | 0.8 |
| link | 237 (0.63) | - |

- [x] parse: 12 files
- [ ] link
- [!] deploy: no access

## Open
- **high** race in the queue (queue.odin:9): two threads push
- **low** typo

` + "```odin\nmain :: proc() {}\n```\n")
    testing.expect_value(t, report.title, "Status of the port")
    testing.expect_value(t, ReportMetaValue(&report, "branch"), "port")
    testing.expect_value(t, len(report.sections), 2)
    done: ^Section = &report.sections[0]
    testing.expect_value(t, done.title, "Done")
    testing.expect_value(t, done.subtitle, "the first half")
    testing.expect_value(t, done.blocks[0].text, "Two parts are finished. They are tested.")        // lines are joined
    table: ^Table = &done.blocks[1].table
    testing.expect_value(t, table.title, "Results")
    testing.expect_value(t, table.columns[1].name, "time")
    testing.expect_value(t, table.columns[1].unit, "s")
    testing.expect_value(t, table.columns[1].kind, ColumnKind.NUMBER)
    testing.expect_value(t, table.columns[2].kind, ColumnKind.RATIO)
    testing.expect_value(t, TableCell(table, 1, 1).number, 237)
    testing.expect_value(t, TableCell(table, 1, 1).text, "237 (0.63)")
    testing.expect(t, !TableCell(table, 1, 2).has_number && TableCell(table, 1, 2).text == "-")
    checks: ^Block = &done.blocks[2]
    testing.expect_value(t, checks.kind, BlockKind.CHECKS)
    testing.expect_value(t, checks.checks[0].status, Status.OK)
    testing.expect_value(t, checks.checks[0].detail, "12 files")
    testing.expect_value(t, checks.checks[1].status, Status.NONE)
    testing.expect_value(t, checks.checks[2].status, Status.FAIL)
    open: ^Section = &report.sections[1]
    testing.expect_value(t, open.blocks[0].kind, BlockKind.FINDINGS)
    testing.expect_value(t, open.blocks[0].findings[0].severity, Severity.HIGH)
    testing.expect_value(t, open.blocks[0].findings[0].location, "queue.odin:9")
    testing.expect_value(t, open.blocks[0].findings[0].detail, "two threads push")
    testing.expect_value(t, open.blocks[1].kind, BlockKind.CODE)
    testing.expect_value(t, open.blocks[1].language, "odin")
    testing.expect_value(t, ReportStatus(&report), Status.FAIL)
}

@(test)
test_benchmark_lines_become_a_table_of_the_subject_against_every_reference :: proc(t: ^testing.T) {
    arena: virtual.Arena
    allocator: runtime.Allocator = arenaOpen(&arena)
    defer virtual.arena_destroy(&arena)
    odin_names, odin_values := ReportParseResults("noise\nRESULT\tcomplex 256\t149\nRESULT\tcomplex 1024\t669\nRESULT\tbroken\tx\n", allocator)
    testing.expect_value(t, len(odin_names), 2)
    c_names, c_values := ReportParseResults("RESULT\tcomplex 256|KissFFT\t898\nRESULT\tcomplex 256|FFTW\t81\nRESULT\tcomplex 1024|FFTW\t363\n", allocator)
    report: Report
    ReportInit(&report, "fft", allocator)
    ReportSection(&report, "fft")
    ReportBenchmarkTable(&report, "ns per transform", "Odin", odin_names, odin_values, c_names, c_values)
    table: ^Table = &report.sections[0].blocks[0].table
    testing.expect_value(t, len(table.columns), 6)                                           // case, Odin, then a number and a ratio for each library
    testing.expect_value(t, table.columns[2].name, "KissFFT")
    testing.expect_value(t, table.columns[3].name, "ratio KissFFT")
    testing.expect_value(t, table.columns[4].name, "FFTW")
    testing.expect(t, abs(TableCell(table, 0, 3).number - 149.0 / 898.0) < 1e-12)
    testing.expect(t, abs(TableCell(table, 0, 5).number - 149.0 / 81.0) < 1e-12)
    testing.expect(t, !TableCell(table, 1, 2).has_number, "a library that did not run the case has an empty cell")
    stats: ColumnStats = TableColumnStats(table, 5)
    testing.expect_value(t, stats.worse, 2)                                                  // Odin is slower than FFTW at both sizes
}

@(test)
test_a_comparison_names_what_got_better_and_what_got_worse :: proc(t: ^testing.T) {
    arena: virtual.Arena
    allocator: runtime.Allocator = arenaOpen(&arena)
    defer virtual.arena_destroy(&arena)
    old: Report
    makeSample(&old, allocator)
    new: Report
    makeSample(&new, allocator)
    new.title = "Sample run, later"
    // the second row got twice as fast, the fourth 60% slower, the third did not change
    table: ^Table = &new.sections[0].blocks[0].table
    TableCell(table, 1, 1).number = 1.45
    TableCell(table, 3, 1).number = 11.4
    // a check that got fixed, one that broke
    checks: ^Block = &new.sections[1].blocks[0]
    checks.checks[1].status = .OK
    checks.checks[0].status = .FAIL
    // a finding is gone, one is new
    findings: ^Block = &new.sections[2].blocks[0]
    findings.findings[1] = Finding{severity = .MEDIUM, title = "a new one", location = "x.odin:1"}
    result, summary := ReportCompare(&old, &new, {}, allocator)
    testing.expect_value(t, summary.improved, 1)
    testing.expect_value(t, summary.regressed, 1)
    testing.expect_value(t, summary.same, 6)                                                 // the Odin column: 2, the C column: 4
    testing.expect_value(t, summary.checks_fixed, 1)
    testing.expect_value(t, summary.checks_broken, 1)
    testing.expect_value(t, summary.findings_new, 1)
    testing.expect_value(t, summary.findings_gone, 1)
    testing.expect_value(t, result.sections[0].title, "summary")
    digest: string = ReportRender(&result, {format = .DIGEST}, allocator)
    testing.expect(t, strings.contains(digest, "numbers=1 improved, 1 regressed, 6 the same"), digest)
    testing.expect(t, strings.contains(digest, "fail biquad"), digest)                       // the check that broke
    testing.expect(t, strings.contains(digest, "new: a new one"))
    testing.expect(t, strings.contains(digest, "gone: buffer is read after free"))
    markdown: string = ReportRender(&result, {format = .MARKDOWN}, allocator)
    testing.expect(t, strings.contains(markdown, "| design of one peaking filter | 2.90 | 1.45 | 0.50 |"), markdown)
    // two equal reports have nothing to say
    same, same_summary := ReportCompare(&old, &old, {}, allocator)
    testing.expect_value(t, same_summary.improved + same_summary.regressed + same_summary.checks_fixed + same_summary.checks_broken + same_summary.findings_new + same_summary.findings_gone, 0)
    _ = same
}

@(test)
test_column_statistics_use_the_direction_of_the_column :: proc(t: ^testing.T) {
    arena: virtual.Arena
    allocator: runtime.Allocator = arenaOpen(&arena)
    defer virtual.arena_destroy(&arena)
    report: Report
    makeSample(&report, allocator)
    table: ^Table = &report.sections[0].blocks[0].table
    ratios: ColumnStats = TableColumnStats(table, 3)
    testing.expect_value(t, ratios.count, 4)
    testing.expect_value(t, ratios.better, 1)
    testing.expect_value(t, ratios.same, 2)
    testing.expect_value(t, ratios.worse, 1)
    testing.expect_value(t, TableRowLabel(table, ratios.best_row), "design of one peaking filter")
    testing.expect_value(t, TableRowLabel(table, ratios.worst_row), "section after section")
    testing.expect(t, abs(ratios.geometric_mean - math.pow(0.99 * 0.15 * 1.02 * 1.42, 0.25)) < 1e-12)
    testing.expect(t, abs(ratios.minimum - 0.15) < 1e-12 && abs(ratios.maximum - 1.42) < 1e-12)
}

@(test)
test_a_list_that_mixes_checks_findings_and_text_is_read_in_runs :: proc(t: ^testing.T) {
    arena: virtual.Arena
    allocator: runtime.Allocator = arenaOpen(&arena)
    defer virtual.arena_destroy(&arena)
    report: Report
    ReportInit(&report, "", allocator)
    ReportImportMarkdown(&report, "# Mixed\n## Work\n- [x] parse\n- [!] link: no symbol\n- **high** crash on exit (main.odin:9): null deref\n- just a remark\n- another remark\n- [~] docs\n")
    blocks: []Block = report.sections[0].blocks[:]
    testing.expect_value(t, len(blocks), 4)
    testing.expect_value(t, blocks[0].kind, BlockKind.CHECKS)
    testing.expect_value(t, len(blocks[0].checks), 2)
    testing.expect_value(t, blocks[1].kind, BlockKind.FINDINGS)
    testing.expect_value(t, blocks[1].findings[0].title, "crash on exit")
    testing.expect_value(t, blocks[2].kind, BlockKind.PARAGRAPH)
    testing.expect_value(t, blocks[2].text, "- just a remark\n- another remark")
    testing.expect_value(t, blocks[3].kind, BlockKind.CHECKS)
    testing.expect_value(t, blocks[3].checks[0].status, Status.WARN)
}

@(test)
test_the_digest_of_a_small_table_does_not_name_a_row_as_best_and_worst :: proc(t: ^testing.T) {
    arena: virtual.Arena
    allocator: runtime.Allocator = arenaOpen(&arena)
    defer virtual.arena_destroy(&arena)
    report: Report
    ReportInit(&report, "small", allocator)
    ReportSection(&report, "s")
    ReportTable(&report, "", {{name = "case"}, {name = "ratio", kind = .RATIO, better = .LOWER}})
    ReportRowNumbers(&report, "fast", 0.5)
    ReportRowNumbers(&report, "slow", 2)
    digest: string = ReportRender(&report, {format = .DIGEST, digest_top = 3}, allocator)
    testing.expect(t, strings.contains(digest, "worst: slow 2.00"), digest)
    testing.expect(t, strings.contains(digest, "best: fast 0.50"), digest)
    testing.expect(t, !strings.contains(digest, "worst: slow 2.00, fast"), digest)
}
