package reports

// Rendering: a report as text. One report, five ways to read it, all of them from the same options:
//   MARKDOWN  for people and for agents that read documents (and for ReportImportMarkdown: what is written here is read back)
//   TEXT      plain columns for a terminal
//   XML       every part named, for programs that want a tree
//   JSON      the canonical file (columnar: a table names its columns once), see json.odin
//   DIGEST    the shortest useful summary: what stands out, for an agent that has to read a lot of reports (digest.odin)
// What is shown is chosen with RenderOptions: which sections, how many rows, in which order, how numbers look, what marks go after a value that is
// better, worse or failing, and a proc of the program that can draw any cell its own way.

import "core:fmt"
import "core:slice"
import "core:strings"

Format :: enum u8 {
    MARKDOWN,
    TEXT,
    XML,
    JSON,
    DIGEST,
}

// Text that goes after a value to say how it stands ("" for nothing).
Marks :: struct {
    better: string,
    worse: string,
    same: string,
    ok: string,
    warn: string,
    fail: string,
}

// Marks that read in any terminal.
MARKS_ASCII :: Marks{better = " +", worse = " -", warn = " ?", fail = " !"}

// A cell the program draws itself: return the text and true, or false to let the renderer do it.
CellProc :: proc(column: ^Column, cell: ^Cell, user: rawptr) -> (text: string, handled: bool)

RenderOptions :: struct {
    format: Format,
    sections: []string,         // only the sections whose title contains one of these (case does not matter); none: all
    max_rows: int,              // rows per table, 0 for all
    sort_column: string,        // sort the rows of every table that has this column by its numbers (names when it has none)
    sort_descending: bool,
    precision: i8,              // digits after the point for the columns that leave it to the renderer: 0 about three significant digits, -1 none
    ratio_band: f64,            // a ratio this close to 1 is the same; 0 is DEFAULT_BAND
    marks: Marks,
    hide_meta: bool,
    hide_paragraphs: bool,
    pretty: bool,               // JSON with line breaks and indentation
    heading_level: int,         // Markdown: the level of the title (1 is "#"); 0 is 1
    digest_top: int,            // the digest names this many best and worst rows per table; 0 is 3
    digest_text: int,           // and cuts each paragraph at this many characters; 0 is 160
    cell: CellProc,
    user: rawptr,
}

// The report as text. The string is allocated with `allocator`.
ReportRender :: proc(report: ^Report, options: RenderOptions = {}, allocator := context.allocator) -> string {
    builder: strings.Builder
    strings.builder_init(&builder, allocator)
    switch options.format {
    case .MARKDOWN:
        renderMarkdown(&builder, report, options)
    case .TEXT:
        renderText(&builder, report, options)
    case .XML:
        renderXml(&builder, report, options)
    case .JSON:
        ReportWriteJson(&builder, report, options.pretty)
    case .DIGEST:
        renderDigest(&builder, report, options)
    }
    return strings.to_string(builder)
}

// ------------------------------------------------------------------------------------------------------------------------
// What the formats share

// Is this section wanted?
@(private)
sectionWanted :: proc(section: ^Section, options: RenderOptions) -> bool {
    if len(options.sections) == 0 { return true }
    for wanted in options.sections {
        if strings.contains(strings.to_lower(section.title, context.temp_allocator), strings.to_lower(wanted, context.temp_allocator)) { return true }
    }
    return false
}

// The text of one cell: the program's own, else the text it came with, else the number, with the marks of its verdict and status.
CellDisplay :: proc(column: ^Column, cell: ^Cell, options: RenderOptions) -> string {
    if options.cell != nil {
        if text, handled := options.cell(column, cell, options.user); handled { return text }
    }
    shown: string = cell.text
    if shown == "" && cell.has_number {
        precision: i8 = column.precision if column.precision != 0 else options.precision
        shown = FormatNumber(cell.number, precision)
    }
    mark: string
    if cell.has_number && column.kind == .RATIO {
        switch RatioVerdict(cell.number, column.better, options.ratio_band if options.ratio_band > 0 else DEFAULT_BAND) {
        case .BETTER:
            mark = options.marks.better
        case .WORSE:
            mark = options.marks.worse
        case .SAME:
            mark = options.marks.same
        case .NONE:
        }
    }
    switch cell.status {
    case .OK:
        mark = strings.concatenate({mark, options.marks.ok}, context.temp_allocator)
    case .WARN:
        mark = strings.concatenate({mark, options.marks.warn}, context.temp_allocator)
    case .FAIL:
        mark = strings.concatenate({mark, options.marks.fail}, context.temp_allocator)
    case .NONE:
    }
    if mark == "" { return shown }
    return strings.concatenate({shown, mark}, context.temp_allocator)
}

// The heading of a column: its name and, when it has one, its unit.
ColumnHeading :: proc(column: ^Column) -> string {
    if column.unit == "" { return column.name }
    return fmt.tprintf("%s (%s)", column.name, column.unit)
}

// The rows of a table in the order the options ask for, and no more than `max_rows` of them (indices into the table, temp allocator).
TableRowOrder :: proc(table: ^Table, options: RenderOptions) -> []int {
    count: int = TableRowCount(table)
    order: []int = make([]int, count, context.temp_allocator)
    for i in 0 ..< count { order[i] = i }
    column: int = TableColumnIndex(table, options.sort_column) if options.sort_column != "" else -1
    if column >= 0 {
        Sorter :: struct {
            table: ^Table,
            column: int,
            descending: bool,
        }
        sorter: Sorter = {table, column, options.sort_descending}
        context.user_ptr = &sorter
        slice.stable_sort_by(order, proc(a, b: int) -> bool {
            sorter: ^Sorter = cast(^Sorter)context.user_ptr
            left: ^Cell = TableCell(sorter.table, a, sorter.column)
            right: ^Cell = TableCell(sorter.table, b, sorter.column)
            if left.has_number != right.has_number {
                return left.has_number                       // numbers before words, whatever the direction
            }
            compared: int
            if left.has_number {
                compared = -1 if left.number < right.number else 1 if left.number > right.number else 0
            } else {
                compared = strings.compare(left.text, right.text)
            }
            return compared > 0 if sorter.descending else compared < 0
        })
    }
    if options.max_rows > 0 && count > options.max_rows {
        return order[:options.max_rows]
    }
    return order
}

@(private)
escapeMarkdownCell :: proc(text: string) -> string {
    escaped, _ := strings.replace_all(text, "|", "\\|", context.temp_allocator)
    return escaped
}

// ------------------------------------------------------------------------------------------------------------------------
// Markdown

@(private)
renderMarkdown :: proc(builder: ^strings.Builder, report: ^Report, options: RenderOptions) {
    level: int = options.heading_level if options.heading_level > 0 else 1
    heading :: proc(builder: ^strings.Builder, level: int, text: string) {
        for _ in 0 ..< level { strings.write_byte(builder, '#') }
        fmt.sbprintf(builder, " %s\n\n", text)
    }
    heading(builder, level, report.title)
    if !options.hide_meta {
        for meta in report.meta {
            fmt.sbprintf(builder, "- %s: %s\n", meta.key, meta.value)
        }
        if len(report.meta) > 0 { strings.write_byte(builder, '\n') }
    }
    for &section in report.sections {
        if !sectionWanted(&section, options) { continue }
        if section.title != "" {
            heading(builder, level + 1, fmt.tprintf("%s (%s)", section.title, section.subtitle) if section.subtitle != "" else section.title)
        }
        for &block in section.blocks {
            switch block.kind {
            case .PARAGRAPH:
                if !options.hide_paragraphs { fmt.sbprintf(builder, "%s\n\n", block.text) }
            case .CODE:
                fmt.sbprintf(builder, "```%s\n%s\n```\n\n", block.language, block.text)
            case .TABLE:
                if block.table.title != "" { fmt.sbprintf(builder, "**%s**\n\n", block.table.title) }
                markdownTable(builder, &block.table, options)
            case .FACTS:
                if block.title != "" { fmt.sbprintf(builder, "**%s**\n\n", block.title) }
                for fact in block.facts {
                    fmt.sbprintf(builder, "- %s: %s%s\n", fact.key, fact.value, fmt.tprintf(" [%s]", StatusName(fact.status)) if fact.status != .NONE else "")
                }
                strings.write_byte(builder, '\n')
            case .CHECKS:
                // `[x]` ok, `[ ]` not judged, `[~]` warn, `[!]` fail: the task list syntax that ReportImportMarkdown reads back
                if block.title != "" { fmt.sbprintf(builder, "**%s**\n\n", block.title) }
                for check in block.checks {
                    box: string = "[x]" if check.status == .OK else "[~]" if check.status == .WARN else "[!]" if check.status == .FAIL else "[ ]"
                    fmt.sbprintf(builder, "- %s %s%s\n", box, check.name, fmt.tprintf(": %s", check.detail) if check.detail != "" else "")
                }
                strings.write_byte(builder, '\n')
            case .FINDINGS:
                if block.title != "" { fmt.sbprintf(builder, "**%s**\n\n", block.title) }
                for finding in block.findings {
                    fmt.sbprintf(builder, "- **%s** %s%s%s\n", SeverityName(finding.severity), finding.title,
                        fmt.tprintf(" (%s)", finding.location) if finding.location != "" else "", fmt.tprintf(": %s", finding.detail) if finding.detail != "" else "")
                }
                strings.write_byte(builder, '\n')
            case .CHART:
                // Markdown has no charts: the numbers of the chart as a table
                if block.chart.title != "" { fmt.sbprintf(builder, "**%s**\n\n", block.chart.title) }
                markdownTable(builder, chartTable(&block.chart), options)
            }
        }
    }
}

@(private)
markdownTable :: proc(builder: ^strings.Builder, table: ^Table, options: RenderOptions) {
    strings.write_string(builder, "|")
    for &column in table.columns {
        fmt.sbprintf(builder, " %s |", escapeMarkdownCell(ColumnHeading(&column)))
    }
    strings.write_string(builder, "\n|")
    for _ in table.columns {
        strings.write_string(builder, "---|")
    }
    strings.write_byte(builder, '\n')
    for row in TableRowOrder(table, options) {
        strings.write_string(builder, "|")
        for &column, c in table.columns {
            fmt.sbprintf(builder, " %s |", escapeMarkdownCell(CellDisplay(&column, TableCell(table, row, c), options)))
        }
        strings.write_byte(builder, '\n')
    }
    strings.write_byte(builder, '\n')
}

// The numbers of a chart as a table: a column for x (or the names) and one for every series (temp allocator).
@(private)
chartTable :: proc(chart: ^Chart) -> ^Table {
    table: ^Table = new(Table, context.temp_allocator)
    table.columns = make([dynamic]Column, 0, 1 + len(chart.series), context.temp_allocator)
    append(&table.columns, Column{name = chart.x_label if chart.x_label != "" else "x", kind = .NUMBER if len(chart.labels) == 0 else .TEXT})
    for series in chart.series {
        append(&table.columns, Column{name = series.name, unit = chart.y_label, kind = .NUMBER})
    }
    table.cells = make([dynamic]Cell, 0, ChartPoints(chart) * len(table.columns), context.temp_allocator)
    for i in 0 ..< ChartPoints(chart) {
        append(&table.cells, Cell{text = chart.labels[i]} if len(chart.labels) > 0 else CellNumber(chart.xs[i]))
        for series in chart.series {
            append(&table.cells, CellNumber(series.ys[i]) if i < len(series.ys) else Cell{})
        }
    }
    return table
}

// ------------------------------------------------------------------------------------------------------------------------
// Text

@(private)
renderText :: proc(builder: ^strings.Builder, report: ^Report, options: RenderOptions) {
    fmt.sbprintf(builder, "%s\n%s\n", report.title, strings.repeat("=", len(report.title), context.temp_allocator))
    if !options.hide_meta {
        for meta in report.meta {
            fmt.sbprintf(builder, "%s: %s\n", meta.key, meta.value)
        }
    }
    for &section in report.sections {
        if !sectionWanted(&section, options) { continue }
        if section.title != "" {
            head: string = fmt.tprintf("%s (%s)", section.title, section.subtitle) if section.subtitle != "" else section.title
            fmt.sbprintf(builder, "\n%s\n%s\n", head, strings.repeat("-", len(head), context.temp_allocator))
        }
        for &block in section.blocks {
            switch block.kind {
            case .PARAGRAPH:
                if !options.hide_paragraphs { fmt.sbprintf(builder, "\n%s\n", block.text) }
            case .CODE:
                fmt.sbprintf(builder, "\n%s\n", block.text)
            case .TABLE:
                if block.table.title != "" { fmt.sbprintf(builder, "\n%s\n", block.table.title) }
                textTable(builder, &block.table, options)
            case .FACTS:
                if block.title != "" { fmt.sbprintf(builder, "\n%s\n", block.title) }
                for fact in block.facts {
                    fmt.sbprintf(builder, "  %s: %s%s\n", fact.key, fact.value, fmt.tprintf(" [%s]", StatusName(fact.status)) if fact.status != .NONE else "")
                }
            case .CHECKS:
                if block.title != "" { fmt.sbprintf(builder, "\n%s\n", block.title) }
                for check in block.checks {
                    fmt.sbprintf(builder, "  [%-4s] %s%s\n", StatusName(check.status), check.name, fmt.tprintf(": %s", check.detail) if check.detail != "" else "")
                }
            case .FINDINGS:
                if block.title != "" { fmt.sbprintf(builder, "\n%s\n", block.title) }
                for finding in block.findings {
                    fmt.sbprintf(builder, "  %-8s %s%s%s\n", SeverityName(finding.severity), finding.title,
                        fmt.tprintf(" (%s)", finding.location) if finding.location != "" else "", fmt.tprintf(": %s", finding.detail) if finding.detail != "" else "")
                }
            case .CHART:
                if block.chart.title != "" { fmt.sbprintf(builder, "\n%s\n", block.chart.title) }
                textTable(builder, chartTable(&block.chart), options)
            }
        }
    }
}

@(private)
textTable :: proc(builder: ^strings.Builder, table: ^Table, options: RenderOptions) {
    order: []int = TableRowOrder(table, options)
    widths: []int = make([]int, len(table.columns), context.temp_allocator)
    for &column, c in table.columns {
        widths[c] = len(ColumnHeading(&column))
    }
    for row in order {
        for &column, c in table.columns {
            widths[c] = max(widths[c], len(CellDisplay(&column, TableCell(table, row, c), options)))
        }
    }
    pad :: proc(builder: ^strings.Builder, text: string, width: int, right: bool) {
        gap: int = max(width - len(text), 0)
        if right { for _ in 0 ..< gap { strings.write_byte(builder, ' ') } }
        strings.write_string(builder, text)
        if !right { for _ in 0 ..< gap { strings.write_byte(builder, ' ') } }
    }
    for &column, c in table.columns {
        strings.write_string(builder, "  " if c > 0 else "")
        pad(builder, ColumnHeading(&column), widths[c], column.kind != .TEXT)
    }
    strings.write_byte(builder, '\n')
    for row in order {
        for &column, c in table.columns {
            strings.write_string(builder, "  " if c > 0 else "")
            pad(builder, CellDisplay(&column, TableCell(table, row, c), options), widths[c], column.kind != .TEXT)
        }
        strings.write_byte(builder, '\n')
    }
}

// ------------------------------------------------------------------------------------------------------------------------
// XML

@(private)
xmlEscape :: proc(text: string) -> string {
    result: string = text
    result, _ = strings.replace_all(result, "&", "&amp;", context.temp_allocator)
    result, _ = strings.replace_all(result, "<", "&lt;", context.temp_allocator)
    result, _ = strings.replace_all(result, ">", "&gt;", context.temp_allocator)
    result, _ = strings.replace_all(result, "\"", "&quot;", context.temp_allocator)
    return result
}

@(private)
renderXml :: proc(builder: ^strings.Builder, report: ^Report, options: RenderOptions) {
    fmt.sbprintf(builder, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<report title=\"%s\" version=\"%d\" status=\"%s\">\n", xmlEscape(report.title), REPORT_VERSION, StatusName(ReportStatus(report)))
    if !options.hide_meta {
        for meta in report.meta {
            fmt.sbprintf(builder, "  <meta key=\"%s\">%s</meta>\n", xmlEscape(meta.key), xmlEscape(meta.value))
        }
    }
    for &section in report.sections {
        if !sectionWanted(&section, options) { continue }
        fmt.sbprintf(builder, "  <section title=\"%s\" subtitle=\"%s\">\n", xmlEscape(section.title), xmlEscape(section.subtitle))
        for &block in section.blocks {
            switch block.kind {
            case .PARAGRAPH:
                if !options.hide_paragraphs { fmt.sbprintf(builder, "    <p>%s</p>\n", xmlEscape(block.text)) }
            case .CODE:
                fmt.sbprintf(builder, "    <code language=\"%s\">%s</code>\n", xmlEscape(block.language), xmlEscape(block.text))
            case .TABLE:
                table: ^Table = &block.table
                fmt.sbprintf(builder, "    <table title=\"%s\">\n      <columns>\n", xmlEscape(table.title))
                for column in table.columns {
                    fmt.sbprintf(builder, "        <column name=\"%s\" unit=\"%s\" kind=\"%s\" better=\"%s\"/>\n", xmlEscape(column.name), xmlEscape(column.unit), kindName(column.kind), betterName(column.better))
                }
                strings.write_string(builder, "      </columns>\n")
                for row in TableRowOrder(table, options) {
                    strings.write_string(builder, "      <row>")
                    for &column, c in table.columns {
                        cell: ^Cell = TableCell(table, row, c)
                        number: string = fmt.tprintf(" number=\"%v\"", cell.number) if cell.has_number else ""
                        status: string = fmt.tprintf(" status=\"%s\"", StatusName(cell.status)) if cell.status != .NONE else ""
                        fmt.sbprintf(builder, "<c%s%s>%s</c>", number, status, xmlEscape(CellDisplay(&column, cell, RenderOptions{precision = options.precision, cell = options.cell, user = options.user})))
                    }
                    strings.write_string(builder, "</row>\n")
                }
                strings.write_string(builder, "    </table>\n")
            case .FACTS:
                fmt.sbprintf(builder, "    <facts title=\"%s\">\n", xmlEscape(block.title))
                for fact in block.facts {
                    fmt.sbprintf(builder, "      <fact key=\"%s\" status=\"%s\">%s</fact>\n", xmlEscape(fact.key), StatusName(fact.status), xmlEscape(fact.value))
                }
                strings.write_string(builder, "    </facts>\n")
            case .CHECKS:
                fmt.sbprintf(builder, "    <checks title=\"%s\">\n", xmlEscape(block.title))
                for check in block.checks {
                    fmt.sbprintf(builder, "      <check name=\"%s\" status=\"%s\">%s</check>\n", xmlEscape(check.name), StatusName(check.status), xmlEscape(check.detail))
                }
                strings.write_string(builder, "    </checks>\n")
            case .FINDINGS:
                fmt.sbprintf(builder, "    <findings title=\"%s\">\n", xmlEscape(block.title))
                for finding in block.findings {
                    fmt.sbprintf(builder, "      <finding severity=\"%s\" title=\"%s\" location=\"%s\">%s</finding>\n", SeverityName(finding.severity), xmlEscape(finding.title), xmlEscape(finding.location), xmlEscape(finding.detail))
                }
                strings.write_string(builder, "    </findings>\n")
            case .CHART:
                chart: ^Chart = &block.chart
                fmt.sbprintf(builder, "    <chart title=\"%s\" kind=\"%s\" x=\"%s\" y=\"%s\" log=\"%v\">\n", xmlEscape(chart.title), "line" if chart.kind == .LINE else "bars", xmlEscape(chart.x_label), xmlEscape(chart.y_label), chart.log_y)
                for i in 0 ..< ChartPoints(chart) {
                    fmt.sbprintf(builder, "      <point %s=\"%s\">", "label" if len(chart.labels) > 0 else "x", xmlEscape(chart.labels[i]) if len(chart.labels) > 0 else fmt.tprintf("%v", chart.xs[i]))
                    for series in chart.series {
                        fmt.sbprintf(builder, "<v series=\"%s\">%v</v>", xmlEscape(series.name), series.ys[i] if i < len(series.ys) else 0)
                    }
                    strings.write_string(builder, "</point>\n")
                }
                strings.write_string(builder, "    </chart>\n")
            }
        }
        strings.write_string(builder, "  </section>\n")
    }
    strings.write_string(builder, "</report>\n")
}

@(private)
kindName :: proc(kind: ColumnKind) -> string {
    switch kind {
    case .TEXT:
        return "text"
    case .NUMBER:
        return "number"
    case .RATIO:
        return "ratio"
    }
    return "text"
}

@(private)
betterName :: proc(better: Better) -> string {
    switch better {
    case .NONE:
        return ""
    case .LOWER:
        return "lower"
    case .HIGHER:
        return "higher"
    }
    return ""
}
