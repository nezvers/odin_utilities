package reports

// Two reports of the same thing (two versions, two machines, yesterday and today) compared: for every table the numbers that have a direction (a time is
// better lower, a throughput higher) side by side with the ratio new / old; for every list of checks the ones whose status changed; for every list of
// findings the ones that appeared and the ones that are gone. The result is a report like any other: render it, save it, show it.
// Sections are matched by title, tables by their position in the section, rows by their first cell, columns by name.

import "core:fmt"
import "core:strings"

CompareSummary :: struct {
    improved: int,              // numbers that got better by more than the band
    regressed: int,             // and worse
    same: int,
    checks_fixed: int,          // checks that went from fail / warn to ok
    checks_broken: int,         // and from ok to warn / fail
    findings_new: int,
    findings_gone: int,
}

CompareOptions :: struct {
    band: f64,                  // within this of 1 is the same; 0 is DEFAULT_BAND
}

// The comparison of `old` and `new` as a report (allocated with `allocator`), and the totals.
ReportCompare :: proc(old: ^Report, new: ^Report, options: CompareOptions = {}, allocator := context.allocator) -> (result: Report, summary: CompareSummary) {
    band: f64 = options.band if options.band > 0 else DEFAULT_BAND
    ReportInit(&result, fmt.tprintf("%s: new against old", new.title), allocator)
    ReportMeta(&result, "old", old.title)
    ReportMeta(&result, "new", new.title)
    // the sections of the comparison are made first, the summary goes in front of them at the end
    for &section in new.sections {
        old_section: ^Section = ReportFindSection(old, section.title)
        if old_section == nil { continue }
        ReportSection(&result, section.title, section.subtitle)
        new_tables: int
        for &block in section.blocks {
            switch block.kind {
            case .TABLE:
                old_table: ^Table = nthTable(old_section, new_tables)
                new_tables += 1
                if old_table != nil { compareTable(&result, old_table, &block.table, band, &summary) }
            case .CHECKS:
                compareChecks(&result, old_section, &block, &summary)
            case .FINDINGS:
                compareFindings(&result, old_section, &block, &summary)
            case .PARAGRAPH, .CODE, .FACTS, .CHART:
            }
        }
    }
    // the summary first
    totals: Report
    ReportInit(&totals, "", allocator)
    ReportSection(&totals, "summary")
    ReportFacts(&totals)
    ReportFact(&totals, "numbers", fmt.tprintf("%d improved, %d regressed, %d the same (within %.0f%%)", summary.improved, summary.regressed, summary.same, band * 100), .FAIL if summary.regressed > 0 else .OK)
    if summary.checks_fixed + summary.checks_broken > 0 {
        ReportFact(&totals, "checks", fmt.tprintf("%d fixed, %d broken", summary.checks_fixed, summary.checks_broken), .FAIL if summary.checks_broken > 0 else .OK)
    }
    if summary.findings_new + summary.findings_gone > 0 {
        ReportFact(&totals, "findings", fmt.tprintf("%d new, %d gone", summary.findings_new, summary.findings_gone), .WARN if summary.findings_new > 0 else .OK)
    }
    inject: [dynamic]Section
    inject.allocator = allocator
    append(&inject, totals.sections[0])
    append(&inject, ..result.sections[:])
    result.sections = inject
    return
}

@(private)
nthTable :: proc(section: ^Section, index: int) -> ^Table {
    count: int
    for &block in section.blocks {
        if block.kind == .TABLE {
            if count == index { return &block.table }
            count += 1
        }
    }
    return nil
}

@(private)
compareTable :: proc(result: ^Report, old: ^Table, new: ^Table, band: f64, summary: ^CompareSummary) {
    // the columns that have a direction and are in both tables
    Pair :: struct {
        old_column: int,
        new_column: int,
    }
    pairs: [dynamic]Pair
    pairs.allocator = context.temp_allocator
    for column, c in new.columns {
        // a ratio says nothing the two numbers behind it do not say, so only the numbers are compared
        if column.kind != .NUMBER || column.better == .NONE { continue }
        if other := TableColumnIndex(old, column.name); other >= 0 && old.columns[other].kind == .NUMBER {
            append(&pairs, Pair{other, c})
        }
    }
    if len(pairs) == 0 { return }
    columns: [dynamic]Column
    columns.allocator = context.temp_allocator
    append(&columns, Column{name = new.columns[0].name})
    for pair in pairs {
        column: Column = new.columns[pair.new_column]
        append(&columns, Column{name = strings.concatenate({column.name, " old"}, context.temp_allocator), unit = column.unit, kind = .NUMBER, better = column.better, precision = column.precision})
        append(&columns, Column{name = strings.concatenate({column.name, " new"}, context.temp_allocator), unit = column.unit, kind = .NUMBER, better = column.better, precision = column.precision})
        append(&columns, Column{name = strings.concatenate({column.name, " new/old"}, context.temp_allocator), kind = .RATIO, better = column.better, limits = false})
    }
    ReportTable(result, new.title, columns[:])
    for row in 0 ..< TableRowCount(new) {
        label: string = TableRowLabel(new, row)
        old_row: int = -1
        for candidate in 0 ..< TableRowCount(old) {
            if TableRowLabel(old, candidate) == label { old_row = candidate; break }
        }
        if old_row < 0 { continue }
        cells: [dynamic]Cell
        cells.allocator = context.temp_allocator
        append(&cells, CellText(label))
        for pair in pairs {
            before: ^Cell = TableCell(old, old_row, pair.old_column)
            after: ^Cell = TableCell(new, row, pair.new_column)
            append(&cells, CellNumber(before.number) if before.has_number else Cell{})
            append(&cells, CellNumber(after.number) if after.has_number else Cell{})
            if before.has_number && after.has_number && before.number > 0 {
                ratio: f64 = after.number / before.number
                append(&cells, CellNumber(ratio))
                switch RatioVerdict(ratio, new.columns[pair.new_column].better, band) {
                case .BETTER:
                    summary.improved += 1
                case .WORSE:
                    summary.regressed += 1
                case .SAME:
                    summary.same += 1
                case .NONE:
                }
            } else {
                append(&cells, Cell{})
            }
        }
        ReportRow(result, ..cells[:])
    }
}

// The checks of `new` whose status differs from the check of the same name in the old section.
@(private)
compareChecks :: proc(result: ^Report, old_section: ^Section, block: ^Block, summary: ^CompareSummary) {
    started: bool
    for check in block.checks {
        before: Status = .NONE
        found: bool
        for &old_block in old_section.blocks {
            if old_block.kind != .CHECKS { continue }
            for old_check in old_block.checks {
                if old_check.name == check.name { before, found = old_check.status, true }
            }
        }
        if !found || before == check.status { continue }
        if !started {
            ReportChecks(result, fmt.tprintf("%s: checks that changed", block.title) if block.title != "" else "checks that changed")
            started = true
        }
        ReportCheck(result, check.name, check.status, fmt.tprintf("was %s%s", StatusName(before) if before != .NONE else "not judged", fmt.tprintf("; %s", check.detail) if check.detail != "" else ""))
        if check.status == .OK { summary.checks_fixed += 1 }
        if check.status >= .WARN && before <= .OK { summary.checks_broken += 1 }
    }
}

// The findings of `new` that the old section did not have, and the findings of the old section that are gone (same title and place).
@(private)
compareFindings :: proc(result: ^Report, old_section: ^Section, block: ^Block, summary: ^CompareSummary) {
    has :: proc(findings: []Finding, finding: Finding) -> bool {
        for other in findings {
            if other.title == finding.title && other.location == finding.location { return true }
        }
        return false
    }
    old_findings: [dynamic]Finding
    old_findings.allocator = context.temp_allocator
    for &old_block in old_section.blocks {
        if old_block.kind == .FINDINGS { append(&old_findings, ..old_block.findings[:]) }
    }
    started: bool
    for finding in block.findings {
        if has(old_findings[:], finding) { continue }
        if !started {
            ReportFindings(result, "findings that changed")
            started = true
        }
        ReportFinding(result, finding.severity, strings.concatenate({"new: ", finding.title}, context.temp_allocator), finding.location, finding.detail)
        summary.findings_new += 1
    }
    for finding in old_findings {
        if has(block.findings[:], finding) { continue }
        if !started {
            ReportFindings(result, "findings that changed")
            started = true
        }
        ReportFinding(result, .INFO, strings.concatenate({"gone: ", finding.title}, context.temp_allocator), finding.location, "")
        summary.findings_gone += 1
    }
}
