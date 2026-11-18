package reports

// A report: a title, some facts about it (meta), and sections made of blocks: paragraphs, tables, lists of facts, checks (pass / fail), findings
// (issues with a severity), charts (series over sizes, runs, parameters) and code. It is for anything that is measured, checked or found: benchmark
// results, test runs, size and time budgets, comparisons between two versions, the progress of a task, the findings of a review. It is read by
// people (Markdown, text), by programs and agents (JSON, XML, a digest) and shown by the ui library (reports/view).
//
//   report: Report
//   ReportInit(&report, "Benchmarks", arena_allocator)           // one allocator for everything: give it an arena, nothing is freed one by one
//   ReportMeta(&report, "machine", "Windows 10, 8 cores")
//   ReportSection(&report, "biquad", "against the RBJ cookbook in C")
//   ReportTable(&report, "", {{name = "case"}, {name = "Odin", unit = "ns", kind = .NUMBER, better = .LOWER}, {name = "C", unit = "ns", kind = .NUMBER, better = .LOWER},
//                             {name = "ratio", kind = .RATIO, better = .LOWER}})
//   ReportRowNumbers(&report, "f32 block of 512", 1.79, 1.80, 1.79 / 1.80)
//   ReportParagraph(&report, "Reading: equally fast loops.")
//   ReportChecks(&report, "tests"); ReportCheck(&report, "biquad", .OK); ReportCheck(&report, "fft", .FAIL, "bin 3 off by 1e-3")
//   text := ReportRender(&report, {format = .MARKDOWN})          // or .TEXT .XML .JSON .DIGEST; ReportSave / ReportLoad for files
//
// Strings given to the builder are copied into the allocator of the report, so temporary strings are fine.

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:strings"

REPORT_VERSION :: 1

ColumnKind :: enum u8 {
    TEXT,               // a name, a note
    NUMBER,             // a measurement
    RATIO,              // a measurement divided by a reference: 1 is equal (`better` says which side is good)
}

// Which way is good for a column: less time is better, more throughput is better.
Better :: enum u8 {
    NONE,               // no opinion
    LOWER,
    HIGHER,
}

// How a value, a check or a whole report stands.
Status :: enum u8 {
    NONE,               // not judged
    OK,
    WARN,
    FAIL,
}

Severity :: enum u8 {
    INFO,
    LOW,
    MEDIUM,
    HIGH,
    CRITICAL,
}

Column :: struct {
    name: string,
    unit: string,       // "ns/sample"; "" for none
    kind: ColumnKind,
    better: Better,
    precision: i8,      // digits after the point; 0 is automatic (about three significant digits), -1 is none (an integer)
    // A budget: with `limits` set a value past `warn` is a warning and past `fail` a failure, in the bad direction (above for LOWER, below for HIGHER).
    limits: bool,
    warn: f64,
    fail: f64,
}

// A value. A number that came with its own text ("237 (0.63)") keeps both: the number is what is compared and sorted, the text is what is shown.
Cell :: struct {
    text: string,
    number: f64,
    has_number: bool,
    status: Status,     // from the limits of the column when it has them, or set by the program
}

CellText :: proc(text: string) -> Cell {
    return {text = text}
}

CellNumber :: proc(value: f64) -> Cell {
    return {number = value, has_number = true}
}

// A number that is shown as `text`.
CellNumberText :: proc(value: f64, text: string) -> Cell {
    return {number = value, has_number = true, text = text}
}

Table :: struct {
    title: string,
    columns: [dynamic]Column,
    cells: [dynamic]Cell,       // the rows one after another, len(columns) cells each
}

Fact :: struct {
    key: string,
    value: string,
    status: Status,
}

// One thing that was checked: a test, a rule, a step of a task.
Check :: struct {
    name: string,
    status: Status,
    detail: string,
}

// One thing that was found: a defect, a risk, a remark.
Finding :: struct {
    severity: Severity,
    title: string,
    location: string,           // "file.odin:42", a name, a place
    detail: string,
}

ChartKind :: enum u8 {
    LINE,               // values over x: sizes, runs, parameters
    BARS,               // values per label
}

Series :: struct {
    name: string,
    ys: [dynamic]f64,           // one value per x (or label), nan for a gap
}

// Values of one or more series over `xs` (numbers) or over `labels` (names). `log_y` is a hint for a reader that draws it.
Chart :: struct {
    title: string,
    kind: ChartKind,
    x_label: string,
    y_label: string,
    log_y: bool,
    xs: [dynamic]f64,
    labels: [dynamic]string,
    series: [dynamic]Series,
}

BlockKind :: enum u8 {
    PARAGRAPH,
    TABLE,
    FACTS,
    CHECKS,
    FINDINGS,
    CHART,
    CODE,
}

// One block of a section: the fields of its kind are used, the others stay empty.
Block :: struct {
    kind: BlockKind,
    title: string,              // FACTS, CHECKS, FINDINGS (a table and a chart have their own)
    text: string,               // PARAGRAPH, CODE
    language: string,           // CODE
    table: Table,
    facts: [dynamic]Fact,
    checks: [dynamic]Check,
    findings: [dynamic]Finding,
    chart: Chart,
}

Section :: struct {
    title: string,
    subtitle: string,           // what the title is about: "against the RBJ cookbook in C"
    blocks: [dynamic]Block,
}

Meta :: struct {
    key: string,
    value: string,
}

Report :: struct {
    title: string,
    meta: [dynamic]Meta,
    sections: [dynamic]Section,
    allocator: runtime.Allocator,
}

// ------------------------------------------------------------------------------------------------------------------------
// Building

// An empty report. Everything it holds is allocated with `allocator` (an arena is the natural choice: the whole report goes away together).
ReportInit :: proc(report: ^Report, title: string, allocator := context.allocator) {
    report^ = {allocator = allocator}
    report.title = strings.clone(title, allocator)
    report.meta = make([dynamic]Meta, 0, 8, allocator)
    report.sections = make([dynamic]Section, 0, 8, allocator)
}

@(private)
keep :: proc(report: ^Report, text: string) -> string {
    return strings.clone(text, report.allocator)
}

// A fact about the report ("machine", "date", "compiler"). Facts keep their order.
ReportMeta :: proc(report: ^Report, key: string, value: string) {
    append(&report.meta, Meta{key = keep(report, key), value = keep(report, value)})
}

// Starts a section: what is added next goes in it.
ReportSection :: proc(report: ^Report, title: string, subtitle: string = "") -> ^Section {
    append(&report.sections, Section{title = keep(report, title), subtitle = keep(report, subtitle), blocks = make([dynamic]Block, 0, 4, report.allocator)})
    return &report.sections[len(report.sections) - 1]
}

// The section that gets what is added: the last one, made when there is none (a report of one untitled section).
@(private)
currentSection :: proc(report: ^Report) -> ^Section {
    if len(report.sections) == 0 {
        return ReportSection(report, "")
    }
    return &report.sections[len(report.sections) - 1]
}

// A new block at the end of the current section. The pointer is good until the next block is added to the section.
@(private)
addBlock :: proc(report: ^Report, kind: BlockKind, title: string = "") -> ^Block {
    section: ^Section = currentSection(report)
    append(&section.blocks, Block{kind = kind, title = keep(report, title)})
    return &section.blocks[len(section.blocks) - 1]
}

// The last block of the current section, which has to be of `kind`: what the Row / Check / Fact / Finding / Series procs add to.
@(private)
lastBlock :: proc(report: ^Report, kind: BlockKind) -> ^Block {
    assert(len(report.sections) > 0, "nothing was started in this report")
    section: ^Section = &report.sections[len(report.sections) - 1]
    assert(len(section.blocks) > 0 && section.blocks[len(section.blocks) - 1].kind == kind, "the last block of the section is not of the kind that is added to")
    return &section.blocks[len(section.blocks) - 1]
}

ReportParagraph :: proc(report: ^Report, text: string) {
    block: ^Block = addBlock(report, .PARAGRAPH)
    block.text = keep(report, text)
}

// Text that keeps its line breaks and spacing: a log, a command, a few lines of code.
ReportCode :: proc(report: ^Report, text: string, language: string = "") {
    block: ^Block = addBlock(report, .CODE)
    block.text = keep(report, text)
    block.language = keep(report, language)
}

// Starts a table in the current section: ReportRow adds to it.
ReportTable :: proc(report: ^Report, title: string, columns: []Column) -> ^Table {
    assert(len(columns) > 0)
    block: ^Block = addBlock(report, .TABLE)
    table: ^Table = &block.table
    table.title = keep(report, title)
    table.columns = make([dynamic]Column, 0, len(columns), report.allocator)
    for column in columns {
        copy: Column = column
        copy.name = keep(report, column.name)
        copy.unit = keep(report, column.unit)
        append(&table.columns, copy)
    }
    table.cells = make([dynamic]Cell, 0, 8 * len(columns), report.allocator)
    return table
}

// A row of the current table: one cell per column. A cell without a status gets the one the limits of its column give.
ReportRow :: proc(report: ^Report, cells: ..Cell) {
    table: ^Table = &lastBlock(report, .TABLE).table
    assert(len(cells) == len(table.columns), "ReportRow: one cell per column")
    for cell, i in cells {
        copy: Cell = cell
        copy.text = keep(report, cell.text)
        if copy.status == .NONE {
            copy.status = CellStatus(&table.columns[i], copy)
        }
        append(&table.cells, copy)
    }
}

// A row that starts with a text (the name of the case) and goes on with numbers.
ReportRowNumbers :: proc(report: ^Report, label: string, values: ..f64) {
    table: ^Table = &lastBlock(report, .TABLE).table
    assert(1 + len(values) == len(table.columns), "ReportRowNumbers: a label and one number per other column")
    append(&table.cells, Cell{text = keep(report, label)})
    for value, i in values {
        cell: Cell = CellNumber(value)
        cell.status = CellStatus(&table.columns[i + 1], cell)
        append(&table.cells, cell)
    }
}

// A list of facts: "files: 12", "peak memory: 3.1 MB". Add them with ReportFact.
ReportFacts :: proc(report: ^Report, title: string = "") {
    block: ^Block = addBlock(report, .FACTS, title)
    block.facts = make([dynamic]Fact, 0, 8, report.allocator)
}

ReportFact :: proc(report: ^Report, key: string, value: string, status: Status = .NONE) {
    block: ^Block = lastBlock(report, .FACTS)
    append(&block.facts, Fact{key = keep(report, key), value = keep(report, value), status = status})
}

// A list of checks: tests, rules, the steps of a task. Add them with ReportCheck.
ReportChecks :: proc(report: ^Report, title: string = "") {
    block: ^Block = addBlock(report, .CHECKS, title)
    block.checks = make([dynamic]Check, 0, 8, report.allocator)
}

ReportCheck :: proc(report: ^Report, name: string, status: Status, detail: string = "") {
    block: ^Block = lastBlock(report, .CHECKS)
    append(&block.checks, Check{name = keep(report, name), status = status, detail = keep(report, detail)})
}

// A list of findings. Add them with ReportFinding.
ReportFindings :: proc(report: ^Report, title: string = "") {
    block: ^Block = addBlock(report, .FINDINGS, title)
    block.findings = make([dynamic]Finding, 0, 8, report.allocator)
}

ReportFinding :: proc(report: ^Report, severity: Severity, title: string, location: string = "", detail: string = "") {
    block: ^Block = lastBlock(report, .FINDINGS)
    append(&block.findings, Finding{severity = severity, title = keep(report, title), location = keep(report, location), detail = keep(report, detail)})
}

// A chart over numbers `xs` (sizes, runs): add the lines with ReportSeries.
ReportChart :: proc(report: ^Report, title: string, xs: []f64, x_label: string = "", y_label: string = "", kind: ChartKind = .LINE, log_y: bool = false) {
    block: ^Block = addBlock(report, .CHART)
    chart: ^Chart = &block.chart
    chart.title = keep(report, title)
    chart.kind = kind
    chart.x_label = keep(report, x_label)
    chart.y_label = keep(report, y_label)
    chart.log_y = log_y
    chart.xs = make([dynamic]f64, 0, len(xs), report.allocator)
    append(&chart.xs, ..xs)
    chart.labels = make([dynamic]string, 0, 0, report.allocator)
    chart.series = make([dynamic]Series, 0, 4, report.allocator)
}

// A chart over names (one bar or point per name).
ReportChartLabels :: proc(report: ^Report, title: string, labels: []string, y_label: string = "", kind: ChartKind = .BARS, log_y: bool = false) {
    block: ^Block = addBlock(report, .CHART)
    chart: ^Chart = &block.chart
    chart.title = keep(report, title)
    chart.kind = kind
    chart.y_label = keep(report, y_label)
    chart.log_y = log_y
    chart.xs = make([dynamic]f64, 0, 0, report.allocator)
    chart.labels = make([dynamic]string, 0, len(labels), report.allocator)
    for label in labels {
        append(&chart.labels, keep(report, label))
    }
    chart.series = make([dynamic]Series, 0, 4, report.allocator)
}

// A line (or a set of bars) of the current chart: one value per x or label, math.nan for a gap.
ReportSeries :: proc(report: ^Report, name: string, ys: []f64) {
    chart: ^Chart = &lastBlock(report, .CHART).chart
    assert(len(ys) == ChartPoints(chart), "ReportSeries: one value per x (or per label)")
    series: Series = {name = keep(report, name)}
    series.ys = make([dynamic]f64, 0, len(ys), report.allocator)
    append(&series.ys, ..ys)
    append(&chart.series, series)
}

// How many x values (or labels) the chart has.
ChartPoints :: proc(chart: ^Chart) -> int {
    return len(chart.labels) if len(chart.labels) > 0 else len(chart.xs)
}

// ------------------------------------------------------------------------------------------------------------------------
// Reading

TableRowCount :: proc(table: ^Table) -> int {
    if len(table.columns) == 0 { return 0 }
    return len(table.cells) / len(table.columns)
}

TableCell :: proc(table: ^Table, row: int, column: int) -> ^Cell {
    return &table.cells[row * len(table.columns) + column]
}

// The column called `name` (case does not matter), -1 when there is none.
TableColumnIndex :: proc(table: ^Table, name: string) -> int {
    for column, i in table.columns {
        if strings.equal_fold(column.name, name) { return i }
    }
    return -1
}

// The section whose title is `title` (case does not matter), nil when there is none.
ReportFindSection :: proc(report: ^Report, title: string) -> ^Section {
    for &section in report.sections {
        if strings.equal_fold(section.title, title) { return &section }
    }
    return nil
}

// The value of a fact, "" when there is none.
ReportMetaValue :: proc(report: ^Report, key: string) -> string {
    for meta in report.meta {
        if strings.equal_fold(meta.key, key) { return meta.value }
    }
    return ""
}

// ------------------------------------------------------------------------------------------------------------------------
// Numbers and status

// A number as a person reads it. `precision` 0: about three significant digits (1.79, 12.5, 118, 25000), -1: no digits after the point, else that many.
FormatNumber :: proc(value: f64, precision: i8 = 0, allocator := context.temp_allocator) -> string {
    if math.is_nan(value) { return "nan" }
    if math.is_inf(value) { return "inf" if value > 0 else "-inf" }
    digits: int
    switch {
    case precision > 0:
        digits = int(precision)
    case precision < 0:
        digits = 0
    case:
        magnitude: f64 = abs(value)
        switch {
        case magnitude == 0, magnitude >= 100:
            digits = 0
        case magnitude >= 10:
            digits = 1
        case:
            digits = 2
        }
    }
    return fmt.aprintf("%.*f", digits, value, allocator = allocator)
}

// What the budget of the column says about a number: past `fail` a failure, past `warn` a warning, else OK. NONE without limits or without a number.
CellStatus :: proc(column: ^Column, cell: Cell) -> Status {
    if !column.limits || !cell.has_number || column.kind == .TEXT || column.better == .NONE {
        return .NONE
    }
    past :: proc(value: f64, limit: f64, better: Better) -> bool {
        return value > limit if better == .LOWER else value < limit
    }
    switch {
    case past(cell.number, column.fail, column.better):
        return .FAIL
    case past(cell.number, column.warn, column.better):
        return .WARN
    }
    return .OK
}

// The worse of two statuses (FAIL over WARN over OK over NONE).
StatusWorse :: proc(a: Status, b: Status) -> Status {
    return max(a, b)
}

// The status of a finding for the summary of a report: critical and high fail it, medium warns, the rest only inform.
FindingStatus :: proc(severity: Severity) -> Status {
    switch severity {
    case .CRITICAL, .HIGH:
        return .FAIL
    case .MEDIUM:
        return .WARN
    case .LOW, .INFO:
        return .NONE
    }
    return .NONE
}

// How a whole report stands: the worst of everything that was judged (cells with limits, facts, checks, findings).
ReportStatus :: proc(report: ^Report) -> Status {
    result: Status
    for &section in report.sections {
        for &block in section.blocks {
            result = StatusWorse(result, BlockStatus(&block))
        }
    }
    return result
}

BlockStatus :: proc(block: ^Block) -> Status {
    result: Status
    switch block.kind {
    case .PARAGRAPH, .CODE, .CHART:
    case .TABLE:
        for cell in block.table.cells {
            result = StatusWorse(result, cell.status)
        }
    case .FACTS:
        for fact in block.facts {
            result = StatusWorse(result, fact.status)
        }
    case .CHECKS:
        for check in block.checks {
            result = StatusWorse(result, check.status)
        }
    case .FINDINGS:
        for finding in block.findings {
            result = StatusWorse(result, FindingStatus(finding.severity))
        }
    }
    return result
}

StatusName :: proc(status: Status) -> string {
    switch status {
    case .NONE:
        return ""
    case .OK:
        return "ok"
    case .WARN:
        return "warn"
    case .FAIL:
        return "fail"
    }
    return ""
}

SeverityName :: proc(severity: Severity) -> string {
    switch severity {
    case .INFO:
        return "info"
    case .LOW:
        return "low"
    case .MEDIUM:
        return "medium"
    case .HIGH:
        return "high"
    case .CRITICAL:
        return "critical"
    }
    return ""
}
