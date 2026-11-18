package reports

// The file format of a report: JSON, columnar, so it is small and an agent (or a program) can read it without a schema in hand. A table names its
// columns once and its rows are plain arrays; a number is a number, a text is a string, nothing repeats keys per cell. Version 1:
//
//   {"report":"Title","version":1,
//    "meta":[["machine","Windows 10"],["date","2026-11-17"]],
//    "sections":[{"title":"biquad","subtitle":"against the RBJ cookbook in C","blocks":[
//      {"p":"A paragraph."},
//      {"code":"text with\nline breaks","lang":"odin"},
//      {"table":"title","columns":[{"name":"case"},{"name":"Odin","unit":"ns","kind":"number","better":"lower","limits":[5,10]},{"name":"ratio","kind":"ratio","better":"lower"}],
//       "rows":[["f32 block",1.79,0.99],["a note",null,{"n":237,"t":"237 (0.63)","s":"warn"}]]},
//      {"facts":"title","items":[["files","12","ok"]]},
//      {"checks":"title","items":[["biquad","ok","detail"]]},
//      {"findings":"title","items":[["high","title","file.odin:42","detail"]]},
//      {"chart":"title","kind":"line","x":"size","y":"ns","log":true,"xs":[256,1024],"series":[{"name":"Odin","ys":[149,669]}]}   // or "labels":["a","b"] instead of "xs"
//   ]}]}
//
// A cell is a number, a string, null (empty), or {"n":number,"t":text,"s":status} when it has a text next to its number or a status that its column's limits do
// not give. A gap in a chart is null. Fields that are empty or default are left out. Unknown fields are ignored when reading, so the format can grow.

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:strings"

// ------------------------------------------------------------------------------------------------------------------------
// Writing

// The report as JSON into `builder`: one line, or (`pretty`) a line per section, block and row.
ReportWriteJson :: proc(builder: ^strings.Builder, report: ^Report, pretty: bool = false) {
    newline :: proc(builder: ^strings.Builder, pretty: bool, depth: int) {
        if !pretty { return }
        strings.write_byte(builder, '\n')
        for _ in 0 ..< depth { strings.write_string(builder, "  ") }
    }
    fmt.sbprintf(builder, "{{\"report\":%s,\"version\":%d", jsonString(report.title), REPORT_VERSION)
    newline(builder, pretty, 1)
    strings.write_string(builder, ",\"meta\":[")
    for meta, i in report.meta {
        fmt.sbprintf(builder, "%s[%s,%s]", "," if i > 0 else "", jsonString(meta.key), jsonString(meta.value))
    }
    strings.write_string(builder, "]")
    newline(builder, pretty, 1)
    strings.write_string(builder, ",\"sections\":[")
    for &section, s in report.sections {
        newline(builder, pretty, 2)
        fmt.sbprintf(builder, "%s{{\"title\":%s", "," if s > 0 else "", jsonString(section.title))
        if section.subtitle != "" { fmt.sbprintf(builder, ",\"subtitle\":%s", jsonString(section.subtitle)) }
        strings.write_string(builder, ",\"blocks\":[")
        for &block, b in section.blocks {
            newline(builder, pretty, 3)
            strings.write_string(builder, "," if b > 0 else "")
            writeBlockJson(builder, &block, pretty, newline)
        }
        strings.write_string(builder, "]}")
    }
    strings.write_string(builder, "]")
    newline(builder, pretty, 0)
    strings.write_string(builder, "}")
    if pretty { strings.write_byte(builder, '\n') }
}

@(private)
writeBlockJson :: proc(builder: ^strings.Builder, block: ^Block, pretty: bool, newline: proc(builder: ^strings.Builder, pretty: bool, depth: int)) {
    switch block.kind {
    case .PARAGRAPH:
        fmt.sbprintf(builder, "{{\"p\":%s}}", jsonString(block.text))
    case .CODE:
        fmt.sbprintf(builder, "{{\"code\":%s", jsonString(block.text))
        if block.language != "" { fmt.sbprintf(builder, ",\"lang\":%s", jsonString(block.language)) }
        strings.write_string(builder, "}")
    case .TABLE:
        table: ^Table = &block.table
        fmt.sbprintf(builder, "{{\"table\":%s,\"columns\":[", jsonString(table.title))
        for column, c in table.columns {
            fmt.sbprintf(builder, "%s{{\"name\":%s", "," if c > 0 else "", jsonString(column.name))
            if column.unit != "" { fmt.sbprintf(builder, ",\"unit\":%s", jsonString(column.unit)) }
            if column.kind != .TEXT { fmt.sbprintf(builder, ",\"kind\":\"%s\"", kindName(column.kind)) }
            if column.better != .NONE { fmt.sbprintf(builder, ",\"better\":\"%s\"", betterName(column.better)) }
            if column.precision != 0 { fmt.sbprintf(builder, ",\"precision\":%d", column.precision) }
            if column.limits { fmt.sbprintf(builder, ",\"limits\":[%s,%s]", jsonNumber(column.warn), jsonNumber(column.fail)) }
            strings.write_string(builder, "}")
        }
        strings.write_string(builder, "],\"rows\":[")
        for row in 0 ..< TableRowCount(table) {
            newline(builder, pretty, 4)
            strings.write_string(builder, "," if row > 0 else "")
            strings.write_string(builder, "[")
            for c in 0 ..< len(table.columns) {
                cell: Cell = TableCell(table, row, c)^
                strings.write_string(builder, "," if c > 0 else "")
                writeCellJson(builder, &table.columns[c], cell)
            }
            strings.write_string(builder, "]")
        }
        strings.write_string(builder, "]}")
    case .FACTS:
        fmt.sbprintf(builder, "{{\"facts\":%s,\"items\":[", jsonString(block.title))
        for fact, i in block.facts {
            fmt.sbprintf(builder, "%s[%s,%s", "," if i > 0 else "", jsonString(fact.key), jsonString(fact.value))
            if fact.status != .NONE { fmt.sbprintf(builder, ",\"%s\"", StatusName(fact.status)) }
            strings.write_string(builder, "]")
        }
        strings.write_string(builder, "]}")
    case .CHECKS:
        fmt.sbprintf(builder, "{{\"checks\":%s,\"items\":[", jsonString(block.title))
        for check, i in block.checks {
            fmt.sbprintf(builder, "%s[%s,\"%s\"", "," if i > 0 else "", jsonString(check.name), StatusName(check.status))
            if check.detail != "" { fmt.sbprintf(builder, ",%s", jsonString(check.detail)) }
            strings.write_string(builder, "]")
        }
        strings.write_string(builder, "]}")
    case .FINDINGS:
        fmt.sbprintf(builder, "{{\"findings\":%s,\"items\":[", jsonString(block.title))
        for finding, i in block.findings {
            fmt.sbprintf(builder, "%s[\"%s\",%s,%s,%s]", "," if i > 0 else "", SeverityName(finding.severity), jsonString(finding.title), jsonString(finding.location), jsonString(finding.detail))
        }
        strings.write_string(builder, "]}")
    case .CHART:
        chart: ^Chart = &block.chart
        fmt.sbprintf(builder, "{{\"chart\":%s,\"kind\":\"%s\"", jsonString(chart.title), "line" if chart.kind == .LINE else "bars")
        if chart.x_label != "" { fmt.sbprintf(builder, ",\"x\":%s", jsonString(chart.x_label)) }
        if chart.y_label != "" { fmt.sbprintf(builder, ",\"y\":%s", jsonString(chart.y_label)) }
        if chart.log_y { strings.write_string(builder, ",\"log\":true") }
        if len(chart.labels) > 0 {
            strings.write_string(builder, ",\"labels\":[")
            for label, i in chart.labels { fmt.sbprintf(builder, "%s%s", "," if i > 0 else "", jsonString(label)) }
        } else {
            strings.write_string(builder, ",\"xs\":[")
            for x, i in chart.xs { fmt.sbprintf(builder, "%s%s", "," if i > 0 else "", jsonNumber(x)) }
        }
        strings.write_string(builder, "],\"series\":[")
        for series, i in chart.series {
            fmt.sbprintf(builder, "%s{{\"name\":%s,\"ys\":[", "," if i > 0 else "", jsonString(series.name))
            for y, j in series.ys { fmt.sbprintf(builder, "%s%s", "," if j > 0 else "", jsonNumber(y)) }
            strings.write_string(builder, "]}")
        }
        strings.write_string(builder, "]}")
    }
}

@(private)
writeCellJson :: proc(builder: ^strings.Builder, column: ^Column, cell: Cell) {
    // a status the limits of the column would give again is not written
    own_status: bool = cell.status != .NONE && cell.status != CellStatus(column, cell)
    switch {
    case own_status || cell.has_number && cell.text != "":
        strings.write_string(builder, "{")
        wrote: bool
        if cell.has_number {
            fmt.sbprintf(builder, "\"n\":%s", jsonNumber(cell.number))
            wrote = true
        }
        if cell.text != "" {
            fmt.sbprintf(builder, "%s\"t\":%s", "," if wrote else "", jsonString(cell.text))
            wrote = true
        }
        if own_status { fmt.sbprintf(builder, "%s\"s\":\"%s\"", "," if wrote else "", StatusName(cell.status)) }
        strings.write_string(builder, "}")
    case cell.has_number:
        strings.write_string(builder, jsonNumber(cell.number))
    case cell.text != "":
        strings.write_string(builder, jsonString(cell.text))
    case:
        strings.write_string(builder, "null")
    }
}

// A number as JSON: the shortest text that reads back as the same f64; nan and infinity are null (JSON has no such numbers).
@(private)
jsonNumber :: proc(value: f64) -> string {
    if math.is_nan(value) || math.is_inf(value) { return "null" }
    return fmt.tprintf("%v", value)
}

@(private)
jsonString :: proc(text: string) -> string {
    builder: strings.Builder
    strings.builder_init(&builder, context.temp_allocator)
    strings.write_byte(&builder, '"')
    for i in 0 ..< len(text) {
        c: u8 = text[i]
        switch c {
        case '"':
            strings.write_string(&builder, "\\\"")
        case '\\':
            strings.write_string(&builder, "\\\\")
        case '\n':
            strings.write_string(&builder, "\\n")
        case '\r':
            strings.write_string(&builder, "\\r")
        case '\t':
            strings.write_string(&builder, "\\t")
        case:
            if c < 32 {
                fmt.sbprintf(&builder, "\\u%04x", int(c))
            } else {
                strings.write_byte(&builder, c)
            }
        }
    }
    strings.write_byte(&builder, '"')
    return strings.to_string(builder)
}

// ------------------------------------------------------------------------------------------------------------------------
// Reading

// A report from JSON text, into `allocator`. `message` says what was wrong when `ok` is false (the report is then empty).
ReportFromJson :: proc(text: string, allocator := context.allocator) -> (report: Report, ok: bool, message: string) {
    value, parse_error := json.parse(transmute([]byte)text, .JSON, false, context.temp_allocator)
    if parse_error != .None {
        return {}, false, fmt.tprintf("not JSON (%v)", parse_error)
    }
    root, is_object := value.(json.Object)
    if !is_object {
        return {}, false, "a report is a JSON object"
    }
    title, has_title := root["report"].(json.String)
    if !has_title {
        return {}, false, "no \"report\" title: this is not a report file"
    }
    version, _ := root["version"].(json.Float)
    if int(version) > REPORT_VERSION {
        return {}, false, fmt.tprintf("the file is version %d, this reader knows up to %d", int(version), REPORT_VERSION)
    }
    ReportInit(&report, title, allocator)
    if meta, is_array := root["meta"].(json.Array); is_array {
        for entry in meta {
            pair, is_pair := entry.(json.Array)
            if is_pair && len(pair) >= 2 { ReportMeta(&report, jsonText(pair[0]), jsonText(pair[1])) }
        }
    }
    sections, _ := root["sections"].(json.Array)
    for section_value in sections {
        section_object, is_section := section_value.(json.Object)
        if !is_section { continue }
        ReportSection(&report, jsonText(section_object["title"]), jsonText(section_object["subtitle"]))
        blocks, _ := section_object["blocks"].(json.Array)
        for block_value in blocks {
            block_object, is_block := block_value.(json.Object)
            if is_block {
                if message = readBlockJson(&report, block_object); message != "" {
                    return {}, false, message
                }
            }
        }
    }
    return report, true, ""
}

// The text of a JSON value that should be a string (numbers are written out, null is empty).
@(private)
jsonText :: proc(value: json.Value) -> string {
    #partial switch v in value {
    case json.String:
        return string(v)
    case json.Float:
        return fmt.tprintf("%v", f64(v))
    case json.Boolean:
        return "true" if bool(v) else "false"
    }
    return ""
}

@(private)
jsonNumberOf :: proc(value: json.Value) -> (number: f64, ok: bool) {
    #partial switch v in value {
    case json.Float:
        return f64(v), true
    }
    return 0, false
}

@(private)
parseStatus :: proc(text: string) -> Status {
    switch text {
    case "ok":
        return .OK
    case "warn":
        return .WARN
    case "fail":
        return .FAIL
    }
    return .NONE
}

@(private)
parseSeverity :: proc(text: string) -> Severity {
    switch text {
    case "low":
        return .LOW
    case "medium":
        return .MEDIUM
    case "high":
        return .HIGH
    case "critical":
        return .CRITICAL
    }
    return .INFO
}

// One block into the current section. "" when it was fine, else what is wrong with it.
@(private)
readBlockJson :: proc(report: ^Report, object: json.Object) -> string {
    switch {
    case "p" in object:
        ReportParagraph(report, jsonText(object["p"]))
    case "code" in object:
        ReportCode(report, jsonText(object["code"]), jsonText(object["lang"]))
    case "table" in object:
        columns_value, _ := object["columns"].(json.Array)
        columns: [dynamic]Column
        columns.allocator = context.temp_allocator
        for column_value in columns_value {
            column_object, _ := column_value.(json.Object)
            column: Column = {name = jsonText(column_object["name"]), unit = jsonText(column_object["unit"])}
            switch jsonText(column_object["kind"]) {
            case "number":
                column.kind = .NUMBER
            case "ratio":
                column.kind = .RATIO
            }
            switch jsonText(column_object["better"]) {
            case "lower":
                column.better = .LOWER
            case "higher":
                column.better = .HIGHER
            }
            if precision, has := jsonNumberOf(column_object["precision"]); has { column.precision = i8(precision) }
            if limits, has := column_object["limits"].(json.Array); has && len(limits) >= 2 {
                column.warn, _ = jsonNumberOf(limits[0])
                column.fail, _ = jsonNumberOf(limits[1])
                column.limits = true
            }
            append(&columns, column)
        }
        if len(columns) == 0 { return "a table without columns" }
        ReportTable(report, jsonText(object["table"]), columns[:])
        rows, _ := object["rows"].(json.Array)
        for row_value in rows {
            row, is_row := row_value.(json.Array)
            if !is_row || len(row) != len(columns) { return fmt.tprintf("a row of table \"%s\" has %d cells, the table has %d columns", jsonText(object["table"]), len(row), len(columns)) }
            cells: [dynamic]Cell
            cells.allocator = context.temp_allocator
            for cell_value in row {
                append(&cells, readCellJson(cell_value))
            }
            ReportRow(report, ..cells[:])
        }
    case "facts" in object:
        ReportFacts(report, jsonText(object["facts"]))
        items, _ := object["items"].(json.Array)
        for item in items {
            entry, _ := item.(json.Array)
            if len(entry) >= 2 {
                ReportFact(report, jsonText(entry[0]), jsonText(entry[1]), parseStatus(jsonText(entry[2])) if len(entry) >= 3 else .NONE)
            }
        }
    case "checks" in object:
        ReportChecks(report, jsonText(object["checks"]))
        items, _ := object["items"].(json.Array)
        for item in items {
            entry, _ := item.(json.Array)
            if len(entry) >= 2 {
                ReportCheck(report, jsonText(entry[0]), parseStatus(jsonText(entry[1])), jsonText(entry[2]) if len(entry) >= 3 else "")
            }
        }
    case "findings" in object:
        ReportFindings(report, jsonText(object["findings"]))
        items, _ := object["items"].(json.Array)
        for item in items {
            entry, _ := item.(json.Array)
            if len(entry) >= 2 {
                ReportFinding(report, parseSeverity(jsonText(entry[0])), jsonText(entry[1]), jsonText(entry[2]) if len(entry) >= 3 else "", jsonText(entry[3]) if len(entry) >= 4 else "")
            }
        }
    case "chart" in object:
        kind: ChartKind = .BARS if jsonText(object["kind"]) == "bars" else .LINE
        log_y: bool = jsonText(object["log"]) == "true"
        points: int
        if labels, has := object["labels"].(json.Array); has {
            names: [dynamic]string
            names.allocator = context.temp_allocator
            for label in labels { append(&names, jsonText(label)) }
            ReportChartLabels(report, jsonText(object["chart"]), names[:], jsonText(object["y"]), kind, log_y)
            points = len(names)
        } else {
            xs: [dynamic]f64
            xs.allocator = context.temp_allocator
            list, _ := object["xs"].(json.Array)
            for x in list {
                number, _ := jsonNumberOf(x)
                append(&xs, number)
            }
            ReportChart(report, jsonText(object["chart"]), xs[:], jsonText(object["x"]), jsonText(object["y"]), kind, log_y)
            points = len(xs)
        }
        series_list, _ := object["series"].(json.Array)
        for series_value in series_list {
            series_object, _ := series_value.(json.Object)
            ys: [dynamic]f64
            ys.allocator = context.temp_allocator
            values, _ := series_object["ys"].(json.Array)
            for value in values {
                number, has := jsonNumberOf(value)
                append(&ys, number if has else math.nan_f64())
            }
            if len(ys) != points { return fmt.tprintf("the series \"%s\" has %d values for %d points", jsonText(series_object["name"]), len(ys), points) }
            ReportSeries(report, jsonText(series_object["name"]), ys[:])
        }
    }
    return ""                                                   // a block of a kind this reader does not know is skipped: the format can grow
}

@(private)
readCellJson :: proc(value: json.Value) -> Cell {
    #partial switch v in value {
    case json.Float:
        return CellNumber(f64(v))
    case json.String:
        return CellText(string(v))
    case json.Object:
        cell: Cell
        if number, has := jsonNumberOf(v["n"]); has {
            cell.number = number
            cell.has_number = true
        }
        cell.text = jsonText(v["t"])
        cell.status = parseStatus(jsonText(v["s"]))
        return cell
    }
    return {}
}
