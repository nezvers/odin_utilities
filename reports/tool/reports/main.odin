// reports: the command line of the reports library. For people, scripts and agents: turn what you have (Markdown notes, the lines of a benchmark, a JSON
// report) into a report, and read it as Markdown, text, XML, JSON or a short digest.
//
//   reports render FILE [options]          FILE is a report (.json) or Markdown (.md), "-" is the standard input (JSON if it starts with "{", else Markdown)
//   reports digest FILE [options]          = render --format digest: what stands out, in a few lines
//   reports import FILE [options]          Markdown in, a report out (JSON unless --format says otherwise)
//   reports results --odin FILE --ref FILE [options]   the RESULT lines of a benchmark and of its references as a table
//   reports diff OLD NEW [options]         two reports of the same thing: what got better, what got worse, what changed
//   reports help
//
// Options (any command): --format md|text|xml|json|digest   --out FILE (else the standard output)   --pretty (JSON with line breaks)
//   --section NAME (repeat; only sections whose title contains it)   --sort COLUMN [--desc]   --rows N (per table)   --precision N
//   --marks (+ - ? ! after values that are better, worse, warn, fail)   --no-meta   --no-notes   --top N (digest: best and worst rows per table)
//   --band 0.05 (a ratio this close to 1 is the same)   --check (exit code 3 when the report has a failure: for scripts)   --title TEXT (import)
//   results: --odin FILE|--odin-exe PROGRAM --ref FILE|--ref-exe PROGRAM --subject Odin --ref-label C --unit ns --section NAME --table TITLE --add REPORT.json
//            (a program is run and its output read; --add puts the table in that report, which is written back)
// Exit codes: 0 fine, 1 an input could not be read, 2 wrong use, 3 --check found a failure.
package main

import "base:runtime"
import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:strconv"
import "core:strings"
import reports "../.."

Arguments :: struct {
    command: string,
    files: [dynamic]string,
    options: reports.RenderOptions,
    format_given: bool,
    out: string,
    check: bool,
    title: string,
    band: f64,
    // results
    odin_file: string,
    ref_file: string,
    odin_exe: string,
    ref_exe: string,
    subject: string,
    ref_label: string,
    unit: string,
    section: string,
    table_title: string,
    add_to: string,
}

main :: proc() {
    arguments: Arguments = {subject = "Odin", ref_label = "reference", unit = "ns"}
    sections: [dynamic]string
    for i := 1; i < len(os.args); i += 1 {
        argument: string = os.args[i]
        next :: proc(i: ^int) -> string {
            i^ += 1
            if i^ >= len(os.args) {
                fail(2, fmt.tprintf("%s needs a value (reports help)", os.args[i^ - 1]))
            }
            return os.args[i^]
        }
        switch argument {
        case "--format":
            arguments.options.format = format_of(next(&i))
            arguments.format_given = true
        case "--out":
            arguments.out = next(&i)
        case "--pretty":
            arguments.options.pretty = true
        case "--section":
            append(&sections, next(&i))
        case "--sort":
            arguments.options.sort_column = next(&i)
        case "--desc":
            arguments.options.sort_descending = true
        case "--rows":
            arguments.options.max_rows = number_of(next(&i))
        case "--precision":
            arguments.options.precision = i8(number_of(next(&i)))
        case "--marks":
            arguments.options.marks = reports.MARKS_ASCII
        case "--no-meta":
            arguments.options.hide_meta = true
        case "--no-notes":
            arguments.options.hide_paragraphs = true
        case "--top":
            arguments.options.digest_top = number_of(next(&i))
        case "--band":
            value, ok := strconv.parse_f64(next(&i))
            if !ok { fail(2, "--band needs a number such as 0.05") }
            arguments.band = value
            arguments.options.ratio_band = value
        case "--check":
            arguments.check = true
        case "--title":
            arguments.title = next(&i)
        case "--odin":
            arguments.odin_file = next(&i)
        case "--ref":
            arguments.ref_file = next(&i)
        case "--odin-exe":
            arguments.odin_exe = next(&i)
        case "--ref-exe":
            arguments.ref_exe = next(&i)
        case "--subject":
            arguments.subject = next(&i)
        case "--ref-label":
            arguments.ref_label = next(&i)
        case "--unit":
            arguments.unit = next(&i)
        case "--table":
            arguments.table_title = next(&i)
        case "--add":
            arguments.add_to = next(&i)
        case "--help", "-h":
            arguments.command = "help"
        case:
            if arguments.command == "" {
                arguments.command = argument
            } else if strings.has_prefix(argument, "--") {
                fail(2, fmt.tprintf("unknown option %s (reports help)", argument))
            } else {
                append(&arguments.files, argument)
            }
        }
    }
    if arguments.command == "results" {
        // for results the section is where the table goes, not a filter of what is shown
        if len(sections) > 0 { arguments.section = sections[0] }
    } else {
        arguments.options.sections = sections[:]
    }
    if arguments.command == "" || arguments.command == "help" {
        fmt.print(HELP)
        return
    }
    arena: virtual.Arena
    if virtual.arena_init_growing(&arena) != nil { fail(1, "no memory") }
    allocator := virtual.arena_allocator(&arena)
    context.allocator = allocator

    report: reports.Report
    status: reports.Status
    switch arguments.command {
    case "render", "digest", "import":
        if len(arguments.files) != 1 { fail(2, fmt.tprintf("%s needs one file (or - for the standard input)", arguments.command)) }
        if arguments.command == "digest" {
            arguments.options.format = .DIGEST
        } else if arguments.command == "import" && !arguments.format_given {
            arguments.options.format = .JSON
        }
        report = load(arguments.files[0], arguments.title, allocator)
    case "diff":
        if len(arguments.files) != 2 { fail(2, "diff needs two files: the old report and the new one") }
        old: reports.Report = load(arguments.files[0], "", allocator)
        new: reports.Report = load(arguments.files[1], "", allocator)
        summary: reports.CompareSummary
        report, summary = reports.ReportCompare(&old, &new, {band = arguments.band}, allocator)
        if !arguments.format_given { arguments.options.format = .DIGEST }
        if arguments.check && (summary.regressed > 0 || summary.checks_broken > 0) { status = .FAIL }
    case "results":
        report = results(&arguments, allocator)
        if !arguments.format_given && arguments.add_to == "" { arguments.options.format = .MARKDOWN }
    case:
        fail(2, fmt.tprintf("unknown command %s (reports help)", arguments.command))
    }
    text: string = reports.ReportRender(&report, arguments.options, allocator)
    if arguments.command == "results" && arguments.add_to != "" {
        // the table goes into the report of that file, which is written back as JSON
        arguments.options.format = .JSON
        text = reports.ReportRender(&report, arguments.options, allocator)
        arguments.out = arguments.add_to
    }
    if arguments.out != "" {
        if err := os.write_entire_file(arguments.out, text); err != nil { fail(1, fmt.tprintf("cannot write %s", arguments.out)) }
    } else {
        fmt.print(text)
        if !strings.has_suffix(text, "\n") { fmt.println() }
    }
    if arguments.check && (reports.ReportStatus(&report) == .FAIL || status == .FAIL) { os.exit(3) }
}

HELP :: `reports: build, read and compare reports (the reports library, see its README)

  reports render FILE [options]        FILE is a report (.json) or Markdown (.md); - is the standard input
  reports digest FILE [options]        what stands out, in a few lines (render --format digest)
  reports import FILE [options]        Markdown in (what an agent writes: # title, ## sections, tables, - [x] checks, - **high** findings), a JSON report out
  reports results --odin FILE --ref FILE [options]
                                       the lines "RESULT<TAB>case<TAB>value" of a benchmark and of its references as a table with ratios
                                       (a reference case is "case" or "case|library"); --add REPORT.json puts the table in that report
  reports diff OLD NEW [options]       what got better, what got worse (numbers, checks, findings)

options: --format md|text|xml|json|digest  --out FILE  --pretty  --section NAME (repeat)  --sort COLUMN [--desc]  --rows N  --precision N
         --marks  --no-meta  --no-notes  --top N  --band 0.05  --check (exit 3 when the report has a failure)  --title TEXT
results: --odin FILE|--odin-exe PROGRAM --ref FILE|--ref-exe PROGRAM --subject Odin --ref-label C --unit ns --section NAME --table TITLE --add REPORT.json

For an agent: write Markdown, run "reports import notes.md --out report.json", then "reports digest report.json" to see what stands out and
"reports render report.json --format md" for the user. A report in JSON is small (columnar) and keeps every number.
`

fail :: proc(code: int, message: string) {
    fmt.eprintln("reports:", message)
    os.exit(code)
}

format_of :: proc(name: string) -> reports.Format {
    switch name {
    case "md", "markdown":
        return .MARKDOWN
    case "text", "txt":
        return .TEXT
    case "xml":
        return .XML
    case "json":
        return .JSON
    case "digest":
        return .DIGEST
    }
    fail(2, fmt.tprintf("--format is md, text, xml, json or digest, not %s", name))
    return .MARKDOWN
}

number_of :: proc(text: string) -> int {
    value, ok := strconv.parse_int(text)
    if !ok || value < -1 { fail(2, fmt.tprintf("%s is not a number", text)) }
    return value
}

// A file (or the standard input) as a report: JSON when it is one, else Markdown.
load :: proc(path: string, title: string, allocator: runtime.Allocator) -> reports.Report {
    data: []byte
    if path == "-" {
        buffer: [4096]byte
        collected: [dynamic]byte
        for {
            count, err := os.read(os.stdin, buffer[:])
            if count > 0 { append(&collected, ..buffer[:count]) }
            if err != nil || count == 0 { break }
        }
        data = collected[:]
    } else {
        read, err := os.read_entire_file(path, allocator)
        if err != nil { fail(1, fmt.tprintf("cannot read %s", path)) }
        data = read
    }
    text: string = string(data)
    report: reports.Report
    if strings.has_prefix(strings.trim_space(text), "{") {
        loaded, ok, message := reports.ReportFromJson(text, allocator)
        if !ok { fail(1, fmt.tprintf("%s: %s", path, message)) }
        report = loaded
        if title != "" { report.title = title }
    } else {
        reports.ReportInit(&report, title, allocator)
        reports.ReportImportMarkdown(&report, text)
        if report.title == "" { report.title = path }
    }
    return report
}

// The text of a benchmark: a file that holds what it printed, or the program itself (it is run, its standard output is the text).
lines_of :: proc(file: string, program: string, allocator: runtime.Allocator) -> string {
    if program != "" {
        state, stdout, stderr, err := os.process_exec({command = {program}}, allocator)
        if err != nil || state.exit_code != 0 { fail(1, fmt.tprintf("%s failed (exit %d): %s", program, state.exit_code, string(stderr))) }
        return string(stdout)
    }
    data, err := os.read_entire_file(file, allocator)
    if err != nil { fail(1, fmt.tprintf("cannot read %s", file)) }
    return string(data)
}

// The table of a benchmark and its references, alone or added to the report of a file.
results :: proc(arguments: ^Arguments, allocator: runtime.Allocator) -> reports.Report {
    if arguments.odin_file == "" && arguments.odin_exe == "" || arguments.ref_file == "" && arguments.ref_exe == "" {
        fail(2, "results needs the lines RESULT<TAB>case<TAB>value of the subject and of the reference: --odin FILE or --odin-exe PROGRAM, and --ref FILE or --ref-exe PROGRAM")
    }
    subject_text: string = lines_of(arguments.odin_file, arguments.odin_exe, allocator)
    reference_text: string = lines_of(arguments.ref_file, arguments.ref_exe, allocator)
    subject_names, subject_values := reports.ReportParseResults(subject_text, allocator)
    reference_names, reference_values := reports.ReportParseResults(reference_text, allocator)
    if len(subject_names) == 0 { fail(1, "no RESULT lines from the subject") }
    report: reports.Report
    if arguments.add_to != "" && os.exists(arguments.add_to) {
        report = load(arguments.add_to, "", allocator)
    } else {
        reports.ReportInit(&report, arguments.title if arguments.title != "" else "Benchmark results", allocator)
    }
    section: string = arguments.section if arguments.section != "" else "results"
    if found := reports.ReportFindSection(&report, section); found == nil {
        reports.ReportSection(&report, section)
    } else {
        // what is added goes after the last block of that section: make it the current one by moving it last
        for i in 0 ..< len(report.sections) {
            if &report.sections[i] == found && i != len(report.sections) - 1 {
                moved: reports.Section = report.sections[i]
                ordered_remove(&report.sections, i)
                append(&report.sections, moved)
                break
            }
        }
    }
    reports.ReportBenchmarkTable(&report, arguments.table_title, arguments.subject, subject_names, subject_values, reference_names, reference_values, arguments.unit, arguments.ref_label)
    return report
}
