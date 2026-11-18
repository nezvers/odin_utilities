package reports

// Reports from what already exists: a Markdown document (what an agent writes, or the results notes of a project) and the lines that a benchmark program
// prints. The Markdown that ReportRender writes is read back to the same report (headings, paragraphs, tables, task lists, findings, facts, fenced code),
// and any other Markdown with the same shapes works too.
//
//   # Title                              the title of the report; `- key: value` lines right under it are the meta
//   ## Name (what it is about)           a section; the part in parentheses at the end is the subtitle
//   a paragraph of lines                 PARAGRAPH (the lines are joined)
//   **A title**                          a line that is only bold names the table / list that follows it
//   | a | b |  with a |---| line         TABLE. A column whose header says "ratio" is a RATIO column (lower is better); a column whose cells are all
//                                        numbers is a NUMBER column (lower is better too when the table has a ratio column, as in benchmark results);
//                                        "237 (0.63)" is the number 237 shown as written; "-" and words are text. A unit in the header "time (ns)" is the unit.
//   - [x] name: detail                   CHECKS: [x] ok, [~] warn, [!] fail, [ ] not judged
//   - **high** title (place): detail     FINDINGS: severity info / low / medium / high / critical
//   - key: value                         FACTS (when every item of the list has that form)
//   ```lang ... ```                      CODE

import "core:fmt"
import "core:strconv"
import "core:strings"

// Adds what `text` holds to `report` (a title in it names the report when it has none yet).
ReportImportMarkdown :: proc(report: ^Report, text: string) {
    lines: []string = strings.split_lines(text, context.temp_allocator)
    paragraph: strings.Builder
    strings.builder_init(&paragraph, context.temp_allocator)
    pending_title: string
    in_section: bool                                     // after the first "## ": before it, "- key: value" lines are the meta of the report

    flush_paragraph :: proc(report: ^Report, paragraph: ^strings.Builder, pending_title: ^string) {
        text: string = strings.clone(strings.trim_space(strings.to_string(paragraph^)), context.temp_allocator)
        strings.builder_reset(paragraph)
        if text == "" { return }
        // a line that is only bold names the block that follows
        if strings.has_prefix(text, "**") && strings.has_suffix(text, "**") && !strings.contains(text[2:len(text) - 2], "**") {
            pending_title^ = strings.clone(text[2:len(text) - 2], context.temp_allocator)           // the builder is reused: keep a copy
            return
        }
        ReportParagraph(report, text)
    }

    i: int
    for i < len(lines) {
        line: string = strings.trim_right_space(lines[i])
        trimmed: string = strings.trim_space(line)
        switch {
        case trimmed == "":
            flush_paragraph(report, &paragraph, &pending_title)
            i += 1
        case strings.has_prefix(trimmed, "```"):
            flush_paragraph(report, &paragraph, &pending_title)
            language: string = strings.trim_space(trimmed[3:])
            code: strings.Builder
            strings.builder_init(&code, context.temp_allocator)
            i += 1
            for i < len(lines) && !strings.has_prefix(strings.trim_space(lines[i]), "```") {
                if strings.builder_len(code) > 0 { strings.write_byte(&code, '\n') }
                strings.write_string(&code, lines[i])
                i += 1
            }
            i += 1                                        // the closing fence
            ReportCode(report, strings.to_string(code), language)
        case strings.has_prefix(trimmed, "#"):
            flush_paragraph(report, &paragraph, &pending_title)
            level: int
            for level < len(trimmed) && trimmed[level] == '#' { level += 1 }
            heading: string = strings.trim_space(trimmed[level:])
            switch {
            case level == 1:
                if report.title == "" { report.title = keep(report, heading) }
            case level == 2:
                title, subtitle := splitHeading(heading)
                ReportSection(report, title, subtitle)
                in_section = true
            case:
                pending_title = heading                    // a deeper heading names what follows
            }
            i += 1
        case strings.has_prefix(trimmed, "|"):
            flush_paragraph(report, &paragraph, &pending_title)
            i = readMarkdownTable(report, lines, i, pending_title)
            pending_title = ""
        case isListItem(trimmed):
            flush_paragraph(report, &paragraph, &pending_title)
            end: int = i
            for end < len(lines) && isListItem(strings.trim_space(lines[end])) { end += 1 }
            readMarkdownList(report, lines[i:end], pending_title, in_section)
            pending_title = ""
            i = end
        case:
            if strings.builder_len(paragraph) > 0 { strings.write_byte(&paragraph, ' ') }
            strings.write_string(&paragraph, trimmed)
            i += 1
        }
    }
    flush_paragraph(report, &paragraph, &pending_title)
}

// "biquad (against the RBJ cookbook)" -> "biquad", "against the RBJ cookbook". A heading without a closing parenthesis has no subtitle.
@(private)
splitHeading :: proc(heading: string) -> (title: string, subtitle: string) {
    if strings.has_suffix(heading, ")") {
        if open := strings.index(heading, " ("); open > 0 {
            return heading[:open], heading[open + 2:len(heading) - 1]
        }
    }
    return heading, ""
}

@(private)
isListItem :: proc(trimmed: string) -> bool {
    return strings.has_prefix(trimmed, "- ") || strings.has_prefix(trimmed, "* ")
}

// A table: the header, the line of dashes, the rows. Returns the index of the first line after it.
@(private)
readMarkdownTable :: proc(report: ^Report, lines: []string, start: int, title: string) -> int {
    end: int = start
    for end < len(lines) && strings.has_prefix(strings.trim_space(lines[end]), "|") { end += 1 }
    if end - start < 2 {
        ReportParagraph(report, strings.trim_space(lines[start]))                // a lone pipe line is not a table
        return end
    }
    split_row :: proc(line: string) -> []string {
        body: string = strings.trim_space(line)
        body = strings.trim_prefix(body, "|")
        body = strings.trim_suffix(body, "|")
        cells: [dynamic]string
        cells.allocator = context.temp_allocator
        current: strings.Builder
        strings.builder_init(&current, context.temp_allocator)
        for i := 0; i < len(body); i += 1 {
            if body[i] == '\\' && i + 1 < len(body) && body[i + 1] == '|' {
                strings.write_byte(&current, '|')                                 // an escaped pipe is part of the cell
                i += 1
            } else if body[i] == '|' {
                append(&cells, strings.clone(strings.trim_space(strings.to_string(current)), context.temp_allocator))      // the builder is reused: keep a copy
                strings.builder_reset(&current)
            } else {
                strings.write_byte(&current, body[i])
            }
        }
        append(&cells, strings.clone(strings.trim_space(strings.to_string(current)), context.temp_allocator))
        return cells[:]
    }
    header: []string = split_row(lines[start])
    separator: []string = split_row(lines[start + 1])
    is_separator: bool = len(separator) > 0
    for cell in separator {
        if cell == "" || strings.trim(cell, "-: ") != "" { is_separator = false }
    }
    first_row: int = start + 2 if is_separator else start + 1
    rows: [dynamic][]string
    rows.allocator = context.temp_allocator
    for row in first_row ..< end {
        cells: []string = split_row(lines[row])
        for len(cells) < len(header) { cells = append_text(cells, "") }
        append(&rows, cells[:len(header)])
    }
    // what each column is
    has_ratio: bool
    for name in header {
        if strings.contains(strings.to_lower(name, context.temp_allocator), "ratio") { has_ratio = true }
    }
    columns: [dynamic]Column
    columns.allocator = context.temp_allocator
    for name, c in header {
        column: Column = {name = name}
        if open := strings.last_index(name, " ("); open > 0 && strings.has_suffix(name, ")") {
            column.name = name[:open]
            column.unit = name[open + 2:len(name) - 1]
        }
        if c > 0 {
            all_numbers: bool = len(rows) > 0
            for row in rows {
                if row[c] == "" || row[c] == "-" { continue }
                if _, is_number := parseCellNumber(row[c]); !is_number { all_numbers = false }
            }
            switch {
            case strings.contains(strings.to_lower(name, context.temp_allocator), "ratio") && all_numbers:
                column.kind = .RATIO
                column.better = .LOWER
            case all_numbers:
                column.kind = .NUMBER
                column.better = .LOWER if has_ratio else .NONE
            }
        }
        append(&columns, column)
    }
    ReportTable(report, title, columns[:])
    for row in rows {
        cells: [dynamic]Cell
        cells.allocator = context.temp_allocator
        for text, c in row {
            if columns[c].kind != .TEXT {
                if number, is_number := parseCellNumber(text); is_number {
                    // the number alone when the usual formatting gives the same text back (the file stays small), else the text as it was written
                    append(&cells, CellNumber(number) if FormatNumber(number, 0) == strings.trim(text, "` *") else CellNumberText(number, text))
                    continue
                }
            }
            append(&cells, CellText(text))
        }
        ReportRow(report, ..cells[:])
    }
    return end
}

@(private)
append_text :: proc(cells: []string, text: string) -> []string {
    list: [dynamic]string
    list.allocator = context.temp_allocator
    append(&list, ..cells)
    append(&list, text)
    return list[:]
}

// A number in a cell: "1.79", "237 (0.63)" (the number is the 237), "`12`". Not "-", not a word, not "25 000" (a number with a space is a word here).
@(private)
parseCellNumber :: proc(text: string) -> (value: f64, ok: bool) {
    cleaned: string = strings.trim(text, "` *")
    if strings.has_suffix(cleaned, ")") {
        if open := strings.index(cleaned, " ("); open > 0 { cleaned = cleaned[:open] }
    }
    if cleaned == "" { return 0, false }
    return strconv.parse_f64(cleaned)
}

// What one item of a list is.
@(private)
ListKind :: enum u8 {
    PLAIN,
    CHECK,
    FINDING,
    FACT,
}

@(private)
listKind :: proc(text: string) -> ListKind {
    switch {
    case isCheckItem(text):
        return .CHECK
    case isFindingItem(text):
        return .FINDING
    case isFactItem(text):
        return .FACT
    }
    return .PLAIN
}

// A list is read in runs: consecutive items of one kind are one block, so a list that mixes checks and findings (as an agent writes it) is both.
// Facts before the first section are the meta of the report. Anything else stays text.
@(private)
readMarkdownList :: proc(report: ^Report, items: []string, title: string, in_section: bool) {
    texts: [dynamic]string
    texts.allocator = context.temp_allocator
    for item in items {
        append(&texts, strings.trim_space(strings.trim_space(item)[2:]))
    }
    start: int
    first_block: bool = true
    for start < len(texts) {
        kind: ListKind = listKind(texts[start])
        end: int = start + 1
        for end < len(texts) && listKind(texts[end]) == kind { end += 1 }
        run: []string = texts[start:end]
        block_title: string = title if first_block else ""
        first_block = false
        switch kind {
        case .CHECK:
            ReportChecks(report, block_title)
            for text in run {
                status: Status
                switch text[:3] {
                case "[x]", "[X]":
                    status = .OK
                case "[~]":
                    status = .WARN
                case "[!]":
                    status = .FAIL
                }
                rest: string = strings.trim_space(text[3:])
                name, detail := rest, ""
                if colon := strings.index(rest, ": "); colon >= 0 {
                    name, detail = rest[:colon], rest[colon + 2:]
                }
                ReportCheck(report, name, status, detail)
            }
        case .FINDING:
            ReportFindings(report, block_title)
            for text in run {
                close: int = strings.index(text[2:], "**") + 2
                severity: Severity = parseSeverity(strings.to_lower(text[2:close], context.temp_allocator))
                rest: string = strings.trim_space(text[close + 2:])
                name, location, detail := rest, "", ""
                if open := strings.index(rest, " ("); open >= 0 {
                    if close_paren := strings.index(rest[open:], ")"); close_paren > 0 {
                        name = rest[:open]
                        location = rest[open + 2:open + close_paren]
                        detail = strings.trim_prefix(strings.trim_space(rest[open + close_paren + 1:]), ": ")
                    }
                } else if colon := strings.index(rest, ": "); colon >= 0 {
                    name, detail = rest[:colon], rest[colon + 2:]
                }
                ReportFinding(report, severity, name, location, detail)
            }
        case .FACT:
            if !in_section {
                for text in run {
                    colon: int = strings.index(text, ": ")
                    ReportMeta(report, text[:colon], text[colon + 2:])
                }
            } else {
                ReportFacts(report, block_title)
                for text in run {
                    colon: int = strings.index(text, ": ")
                    value: string = text[colon + 2:]
                    status: Status
                    // the status ReportRender writes after a value: " [ok]", " [warn]", " [fail]"
                    for candidate in ([?]Status{.OK, .WARN, .FAIL}) {
                        suffix: string = fmt.tprintf(" [%s]", StatusName(candidate))
                        if strings.has_suffix(value, suffix) {
                            value = value[:len(value) - len(suffix)]
                            status = candidate
                        }
                    }
                    ReportFact(report, text[:colon], value, status)
                }
            }
        case .PLAIN:
            joined: strings.Builder
            strings.builder_init(&joined, context.temp_allocator)
            for text, i in run {
                if i > 0 { strings.write_byte(&joined, '\n') }
                strings.write_string(&joined, "- ")
                strings.write_string(&joined, text)
            }
            ReportParagraph(report, strings.to_string(joined))
        }
        start = end
    }
}

@(private)
isCheckItem :: proc(text: string) -> bool {
    return len(text) >= 3 && text[0] == '[' && text[2] == ']' && (text[1] == 'x' || text[1] == 'X' || text[1] == ' ' || text[1] == '~' || text[1] == '!')
}

@(private)
isFindingItem :: proc(text: string) -> bool {
    if !strings.has_prefix(text, "**") { return false }
    close: int = strings.index(text[2:], "**")
    if close < 0 { return false }
    switch strings.to_lower(text[2:2 + close], context.temp_allocator) {
    case "info", "low", "medium", "high", "critical":
        return true
    }
    return false
}

// "key: value" where the key is a short plain name.
@(private)
isFactItem :: proc(text: string) -> bool {
    colon: int = strings.index(text, ": ")
    return colon > 0 && colon <= 40 && !strings.contains(text[:colon], "*") && !strings.contains(text[:colon], "[")
}

// ------------------------------------------------------------------------------------------------------------------------
// The lines of a benchmark

// The numbers of a benchmark program that prints `RESULT<TAB>case<TAB>value` (any other line is ignored): the names and the values, in order.
ReportParseResults :: proc(text: string, allocator := context.allocator) -> (names: []string, values: []f64) {
    name_list: [dynamic]string
    name_list.allocator = allocator
    value_list: [dynamic]f64
    value_list.allocator = allocator
    for line in strings.split_lines(text, context.temp_allocator) {
        parts: []string = strings.split(strings.trim_space(line), "\t", context.temp_allocator)
        if len(parts) != 3 || parts[0] != "RESULT" { continue }
        value, ok := strconv.parse_f64(strings.trim_space(parts[2]))
        if !ok { continue }
        append(&name_list, strings.clone(parts[1], allocator))
        append(&value_list, value)
    }
    return name_list[:], value_list[:]
}

// A table of one subject against references that ran the same cases: the case, the subject's number, and for every reference its number and the
// ratio (subject / reference, lower is better: below 1 the subject is faster). A reference case is named `case` or `case|library`: several
// libraries can answer one case, each gets its own pair of columns. Cases the reference did not run are left empty. Time numbers are the point, so
// the columns are `better = .LOWER`.
ReportBenchmarkTable :: proc(report: ^Report, title: string, subject: string, subject_names: []string, subject_values: []f64, reference_names: []string, reference_values: []f64, unit: string = "ns", reference_label: string = "reference") {
    libraries: [dynamic]string
    libraries.allocator = context.temp_allocator
    for name in reference_names {
        library: string = reference_label
        if bar := strings.index_byte(name, '|'); bar >= 0 { library = name[bar + 1:] }
        found: bool
        for known in libraries { if known == library { found = true } }
        if !found { append(&libraries, library) }
    }
    columns: [dynamic]Column
    columns.allocator = context.temp_allocator
    append(&columns, Column{name = "case"})
    append(&columns, Column{name = subject, unit = unit, kind = .NUMBER, better = .LOWER})
    for library in libraries {
        append(&columns, Column{name = library, unit = unit, kind = .NUMBER, better = .LOWER})
        append(&columns, Column{name = len(libraries) > 1 ? strings.concatenate({"ratio ", library}, context.temp_allocator) : "ratio", kind = .RATIO, better = .LOWER})
    }
    ReportTable(report, title, columns[:])
    for name, i in subject_names {
        cells: [dynamic]Cell
        cells.allocator = context.temp_allocator
        append(&cells, CellText(name))
        append(&cells, CellNumber(subject_values[i]))
        for library in libraries {
            reference: f64
            found: bool
            for reference_name, j in reference_names {
                base, lib: string = reference_name, reference_label
                if bar := strings.index_byte(reference_name, '|'); bar >= 0 { base, lib = reference_name[:bar], reference_name[bar + 1:] }
                if base == name && lib == library {
                    reference, found = reference_values[j], true
                    break
                }
            }
            if found && reference > 0 {
                append(&cells, CellNumber(reference))
                append(&cells, CellNumber(subject_values[i] / reference))
            } else {
                append(&cells, Cell{})
                append(&cells, Cell{})
            }
        }
        ReportRow(report, ..cells[:])
    }
}
