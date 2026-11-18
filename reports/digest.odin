package reports

// The digest: the shortest text that still says what stands out. For an agent (or a person) that has to read many reports and decide what to look at:
// a line for the state of the whole report, then per section only what is notable. Tables are not repeated: a ratio column gives its geometric mean,
// how many rows are better, the same and worse, and the best and worst rows by name; a column with a budget names the rows that are over it; checks give
// their counts and name the ones that failed; findings are all listed, the worst first; a chart gives the start, the end and the range of every series.
// Numbers are written with the same rules as everywhere else (FormatNumber), so the digest of a report is stable from run to run.

import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"

@(private)
renderDigest :: proc(builder: ^strings.Builder, report: ^Report, options: RenderOptions) {
    top: int = options.digest_top if options.digest_top > 0 else 3
    cut: int = options.digest_text if options.digest_text > 0 else 160
    band: f64 = options.ratio_band if options.ratio_band > 0 else DEFAULT_BAND
    status: Status = ReportStatus(report)
    fmt.sbprintf(builder, "report: %s%s\n", report.title, fmt.tprintf(" [%s]", StatusName(status)) if status != .NONE else "")
    if !options.hide_meta && len(report.meta) > 0 {
        strings.write_string(builder, "meta: ")
        for meta, i in report.meta {
            fmt.sbprintf(builder, "%s%s=%s", "; " if i > 0 else "", meta.key, meta.value)
        }
        strings.write_byte(builder, '\n')
    }
    for &section in report.sections {
        if !sectionWanted(&section, options) { continue }
        if section.title != "" {
            fmt.sbprintf(builder, "\n## %s%s\n", section.title, fmt.tprintf(": %s", section.subtitle) if section.subtitle != "" else "")
        }
        table_number: int
        for &block in section.blocks {
            switch block.kind {
            case .PARAGRAPH:
                if !options.hide_paragraphs { fmt.sbprintf(builder, "note: %s\n", shorten(block.text, cut)) }
            case .CODE:
                fmt.sbprintf(builder, "code%s: %s\n", fmt.tprintf(" (%s)", block.language) if block.language != "" else "", shorten(block.text, cut))
            case .TABLE:
                table_number += 1
                digestTable(builder, &block.table, table_number, top, band, options)
            case .FACTS:
                fmt.sbprintf(builder, "facts%s: ", fmt.tprintf(" (%s)", block.title) if block.title != "" else "")
                for fact, i in block.facts {
                    fmt.sbprintf(builder, "%s%s=%s%s", "; " if i > 0 else "", fact.key, fact.value, fmt.tprintf(" [%s]", StatusName(fact.status)) if fact.status != .NONE else "")
                }
                strings.write_byte(builder, '\n')
            case .CHECKS:
                digestChecks(builder, &block, cut)
            case .FINDINGS:
                digestFindings(builder, &block, cut)
            case .CHART:
                digestChart(builder, &block.chart)
            }
        }
    }
}

// Text cut at `limit` bytes on a character boundary, on one line.
@(private)
shorten :: proc(text: string, limit: int) -> string {
    one_line, _ := strings.replace_all(strings.trim_space(text), "\n", " ", context.temp_allocator)
    if len(one_line) <= limit { return one_line }
    end: int = limit
    for end > 0 && one_line[end] & 0xC0 == 0x80 { end -= 1 }
    return fmt.tprintf("%s...", one_line[:end])
}

@(private)
digestTable :: proc(builder: ^strings.Builder, table: ^Table, number: int, top: int, band: f64, options: RenderOptions) {
    rows: int = TableRowCount(table)
    fmt.sbprintf(builder, "table %s: %d rows\n", table.title if table.title != "" else fmt.tprintf("#%d", number), rows)
    // a table with a ratio column is a comparison: the ratio says what the numbers behind it say, so they are not repeated
    has_ratio: bool
    for column in table.columns {
        if column.kind == .RATIO && column.better != .NONE { has_ratio = true }
    }
    for &column, c in table.columns {
        if column.kind == .TEXT { continue }
        if has_ratio && column.kind == .NUMBER && !column.limits { continue }
        stats: ColumnStats = TableColumnStats(table, c, band)
        if stats.count == 0 { continue }
        direction: string = " (lower is better)" if column.better == .LOWER else " (higher is better)" if column.better == .HIGHER else ""
        switch {
        case column.kind == .RATIO && column.better != .NONE:
            fmt.sbprintf(builder, "  %s%s: geometric mean %s, %d better, %d same, %d worse (within %.0f%% is the same)\n", ColumnHeading(&column), direction, FormatNumber(stats.geometric_mean, 2), stats.better, stats.same, stats.worse, band * 100)
            digestExtremes(builder, table, c, top, column.better == .HIGHER)
        case column.limits:
            digestLimits(builder, table, c, &column, direction)
        case:
            fmt.sbprintf(builder, "  %s%s: %s to %s, mean %s", ColumnHeading(&column), direction, FormatNumber(stats.minimum, column.precision), FormatNumber(stats.maximum, column.precision), FormatNumber(stats.mean, column.precision))
            if column.better != .NONE && stats.best_row >= 0 {
                fmt.sbprintf(builder, "; best %s, worst %s", TableRowLabel(table, stats.best_row), TableRowLabel(table, stats.worst_row))
            }
            strings.write_byte(builder, '\n')
        }
    }
}

// The rows with the worst and the best values of a ratio column, by name.
@(private)
digestExtremes :: proc(builder: ^strings.Builder, table: ^Table, column: int, top: int, higher_is_better: bool) {
    Entry :: struct {
        row: int,
        value: f64,
    }
    entries: [dynamic]Entry
    entries.allocator = context.temp_allocator
    for row in 0 ..< TableRowCount(table) {
        cell: ^Cell = TableCell(table, row, column)
        if cell.has_number && !math.is_nan(cell.number) { append(&entries, Entry{row, cell.number}) }
    }
    slice.stable_sort_by(entries[:], proc(a, b: Entry) -> bool { return a.value < b.value })
    if higher_is_better { slice.reverse(entries[:]) }
    // entries are now best first
    list :: proc(builder: ^strings.Builder, table: ^Table, entries: []Entry, label: string) {
        fmt.sbprintf(builder, "    %s: ", label)
        for entry, i in entries {
            fmt.sbprintf(builder, "%s%s %s", ", " if i > 0 else "", TableRowLabel(table, entry.row), FormatNumber(entry.value, 2))
        }
        strings.write_byte(builder, '\n')
    }
    count: int = min(top, max(len(entries) / 2, 1))                  // best and worst do not name the same rows
    if count == 0 { return }
    worst: [dynamic]Entry
    worst.allocator = context.temp_allocator
    for i := len(entries) - 1; i >= len(entries) - count; i -= 1 { append(&worst, entries[i]) }
    list(builder, table, worst[:], "worst")
    list(builder, table, entries[:count], "best")
}

// The rows over the budget of a column.
@(private)
digestLimits :: proc(builder: ^strings.Builder, table: ^Table, column: int, spec: ^Column, direction: string) {
    fails, warns, oks: int
    for row in 0 ..< TableRowCount(table) {
        switch TableCell(table, row, column).status {
        case .FAIL:
            fails += 1
        case .WARN:
            warns += 1
        case .OK:
            oks += 1
        case .NONE:
        }
    }
    fmt.sbprintf(builder, "  %s%s budget (warn %s, fail %s): %d ok, %d warn, %d fail\n", ColumnHeading(spec), direction, FormatNumber(spec.warn, spec.precision), FormatNumber(spec.fail, spec.precision), oks, warns, fails)
    for row in 0 ..< TableRowCount(table) {
        cell: ^Cell = TableCell(table, row, column)
        if cell.status == .FAIL || cell.status == .WARN {
            fmt.sbprintf(builder, "    %s %s: %s\n", StatusName(cell.status), TableRowLabel(table, row), FormatNumber(cell.number, spec.precision))
        }
    }
}

@(private)
digestChecks :: proc(builder: ^strings.Builder, block: ^Block, cut: int) {
    counts: [Status]int
    for check in block.checks { counts[check.status] += 1 }
    fmt.sbprintf(builder, "checks%s: %d ok, %d warn, %d fail, %d not judged\n", fmt.tprintf(" (%s)", block.title) if block.title != "" else "", counts[.OK], counts[.WARN], counts[.FAIL], counts[.NONE])
    for check in block.checks {
        if check.status == .FAIL || check.status == .WARN {
            fmt.sbprintf(builder, "  %s %s%s\n", StatusName(check.status), check.name, fmt.tprintf(": %s", shorten(check.detail, cut)) if check.detail != "" else "")
        }
    }
}

// Every finding, the worst first (the order inside a severity stays).
@(private)
digestFindings :: proc(builder: ^strings.Builder, block: ^Block, cut: int) {
    fmt.sbprintf(builder, "findings%s: %d\n", fmt.tprintf(" (%s)", block.title) if block.title != "" else "", len(block.findings))
    order: []int = make([]int, len(block.findings), context.temp_allocator)
    for i in 0 ..< len(order) { order[i] = i }
    context.user_ptr = block
    slice.stable_sort_by(order, proc(a, b: int) -> bool {
        findings: []Finding = (cast(^Block)context.user_ptr).findings[:]
        return findings[a].severity > findings[b].severity
    })
    for i in order {
        finding: Finding = block.findings[i]
        fmt.sbprintf(builder, "  %s %s%s%s\n", SeverityName(finding.severity), finding.title, fmt.tprintf(" (%s)", finding.location) if finding.location != "" else "", fmt.tprintf(": %s", shorten(finding.detail, cut)) if finding.detail != "" else "")
    }
}

@(private)
digestChart :: proc(builder: ^strings.Builder, chart: ^Chart) {
    fmt.sbprintf(builder, "chart %s: %d points%s\n", chart.title, ChartPoints(chart), fmt.tprintf(", %s over %s", chart.y_label, chart.x_label) if chart.y_label != "" && chart.x_label != "" else "")
    for series in chart.series {
        if len(series.ys) == 0 { continue }
        first, last: f64 = series.ys[0], series.ys[len(series.ys) - 1]
        low, high: f64 = math.INF_F64, -math.INF_F64
        for value in series.ys {
            if math.is_nan(value) { continue }
            low, high = min(low, value), max(high, value)
        }
        fmt.sbprintf(builder, "  %s: %s -> %s (%s%s), range %s to %s\n", series.name, FormatNumber(first, 0), FormatNumber(last, 0), "x" if first != 0 else "", FormatNumber(last / first if first != 0 else 0, 2) if first != 0 else "", FormatNumber(low, 0), FormatNumber(high, 0))
    }
}
