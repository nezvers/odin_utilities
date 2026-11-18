# reports

A report is a title, some facts, and sections made of blocks: paragraphs, tables, lists of facts, checks (pass / fail), findings (issues with a severity), charts and code. It is for anything that is
measured, checked or found: benchmark results, test runs, time and size budgets, the comparison of two versions, the progress of a task, the findings of a review, the history of a measurement.
Build it in code, import it from Markdown or from the lines a benchmark prints, save it as JSON, read it as Markdown, text, XML or a short digest, compare two of them, and show it with the ui library.

- Library (`reports/`): framework agnostic, no file access (the tool and the demos read and write files), one allocator for a whole report (give it an arena, nothing is freed one by one).
- `tool/reports`: the command line, for scripts and agents.
- `view/`: the viewer, drawn with `odin_utilities/ui` (`ViewDraw`).
- Demos: `viewer` (a real set of benchmark results), `compare` (two runs compared), `status` (a report built with the API, nothing to do with benchmarks).

## Building a report
```odin
report: reports.Report
reports.ReportInit(&report, "Status of the port", arena_allocator)
reports.ReportMeta(&report, "branch", "port")

reports.ReportSection(&report, "tests")
reports.ReportChecks(&report, "unit tests")
reports.ReportCheck(&report, "kernel table is symmetric", .OK)
reports.ReportCheck(&report, "stopband of LOW", .FAIL, "measured -81 dB, expected below -88 dB")

reports.ReportSection(&report, "budgets")
reports.ReportTable(&report, "time per output sample", {
    {name = "mode"},
    {name = "ns", kind = .NUMBER, better = .LOWER, limits = true, warn = 30, fail = 60},   // a number past `warn` warns, past `fail` fails
})
reports.ReportRowNumbers(&report, "HIGH 96 -> 44.1", 71.0)                                  // FAIL: the budget gave the status

reports.ReportSection(&report, "review")
reports.ReportFindings(&report, "found in the diff")
reports.ReportFinding(&report, .HIGH, "the history buffer is read before it is filled", "resample.odin:212", "the first taps read garbage")

reports.ReportChart(&report, "HIGH quality over the runs", {1, 2, 3}, "run", "ns")          // ReportChartLabels for names instead of numbers
reports.ReportSeries(&report, "this port", {74, 71, 68})
```
Every string is copied into the allocator of the report, so temporary strings are fine. `ReportRow(report, cells...)` takes `CellText`, `CellNumber` and `CellNumberText` (a number that is shown as its own text,
`237 (0.63)`), `ReportRowNumbers(report, label, numbers...)` is the short way. `ReportTable` and the other `Report...` procs that start a block return or use the *current* block of the *current* section: add the rows and
items right after starting it.

A **column** has a `kind` (TEXT, NUMBER, RATIO), a `unit`, a direction `better` (LOWER, HIGHER: less time is better, more throughput is better), a `precision` and optional `limits` (a budget). A **ratio** column is a
number divided by a reference: 1 is equal, `RatioVerdict(ratio, better, band)` says better, worse or the same (within 5% by default). `ReportStatus(report)` is the worst thing in the report (budgets, checks, facts, findings).

## Reading a report
`ReportRender(&report, options)` gives the text in one of five formats, all from the same `RenderOptions`:

| Format | For | Notes |
|---|---|---|
| `.MARKDOWN` | people, agents that read documents | what is written is read back by `ReportImportMarkdown` |
| `.TEXT` | a terminal | aligned columns |
| `.XML` | programs that want a tree | every part named; about 40% bigger than JSON |
| `.JSON` | the canonical file | columnar: a table names its columns once, rows are plain arrays; `ReportFromJson` reads it back |
| `.DIGEST` | an agent that has to read a lot | what stands out only (below) |

Options: `sections` (only those whose title contains a text), `max_rows`, `sort_column` / `sort_descending`, `precision`, `ratio_band`, `marks` (`MARKS_ASCII` puts + - ? ! after values that are better, worse, warn, fail),
`hide_meta`, `hide_paragraphs`, `pretty` (JSON), `heading_level` (Markdown), `digest_top`, `digest_text`, and `cell` + `user`: a proc that draws any cell its own way. Numbers are written with about three significant
digits unless a column says otherwise (`FormatNumber`).

**The digest** is the shortest useful text. Per section: the notes cut short, and for every table the geometric mean of a ratio column with how many rows are better / the same / worse and the best and worst rows by
name, the rows over a budget, the numbers of a column that has no ratio; checks give their counts and name the ones that failed; findings are all listed, the worst first; a chart gives the start, the end and the range of every
series. The start says `[fail]` / `[warn]` / `[ok]` for the whole report. For a set of results of 30 KB of Markdown (14 sections, 16 tables) the digest is 14 KB, 6 KB without the notes (`--no-notes`).

## JSON, version 1
```json
{"report":"Title","version":1,"meta":[["machine","Windows 10"]],
 "sections":[{"title":"biquad","subtitle":"against the RBJ cookbook in C","blocks":[
   {"p":"A paragraph."},
   {"code":"text","lang":"odin"},
   {"table":"title","columns":[{"name":"case"},{"name":"Odin","unit":"ns","kind":"number","better":"lower","limits":[5,10]},{"name":"ratio","kind":"ratio","better":"lower"}],
    "rows":[["f32 block",1.79,0.99],["a note",null,{"n":237,"t":"237 (0.63)","s":"warn"}]]},
   {"facts":"title","items":[["files","12","ok"]]},
   {"checks":"title","items":[["biquad","ok","detail"]]},
   {"findings":"title","items":[["high","title","file.odin:42","detail"]]},
   {"chart":"title","kind":"line","x":"size","y":"ns","log":true,"xs":[256,1024],"series":[{"name":"Odin","ys":[149,669]}]}
 ]}]}
```
A cell is a number, a string, `null`, or `{"n":number,"t":text,"s":status}` (a text next to its number, or a status that the budget of its column does not give). A gap in a chart is `null`. Chart `"labels":[...]` replaces
`"xs"` for names. Empty fields are left out, unknown fields and unknown block kinds are ignored when reading, so the format can grow; a newer `version` is refused in words. Compared with the Markdown of the same data it is a
little bigger (structure), compared with XML 30% smaller; it is one line unless `pretty`.

## Import
- `ReportImportMarkdown(&report, text)`: `# title`, `- key: value` lines under it (meta), `## name (what it is about)` (section and subtitle), paragraphs, a bold line (`**Results**`) that names the table or list after it, tables (a
  `ratio` column is a RATIO column; a column of numbers is a NUMBER column, lower is better when the table has a ratio column; `237 (0.63)` is the number 237 shown as written; a unit in the heading, `time (ns)`), task lists
  (`- [x]` ok, `- [~]` warn, `- [!]` fail, `- [ ]` not judged, `name: detail`), findings (`- **high** title (place): detail`), facts (`- key: value`), fenced code. A list that mixes kinds is read in runs. This is what an agent
  can write without knowing any API.
- `ReportParseResults(text)` + `ReportBenchmarkTable(...)`: the lines `RESULT<TAB>case<TAB>value` of a benchmark program become a table of the subject and of every reference with a ratio (a reference case is `case` or
  `case|library`: several libraries can answer one case).

## Comparing
`ReportCompare(&old, &new, {band}, allocator)` returns a report and a `CompareSummary`: for every table the numbers that have a direction, old and new side by side with new / old (a ratio: green when better); for every
list of checks the ones whose status changed; for every list of findings the new and the gone ones; a `summary` section first. Sections are matched by title, tables by position, rows by their first cell, columns by name.

## The tool
```
reports render FILE [options]      FILE is a report (.json) or Markdown; - is the standard input
reports digest FILE [options]      what stands out (render --format digest)
reports import FILE [options]      Markdown in, a JSON report out
reports results --odin FILE|--odin-exe PROGRAM --ref FILE|--ref-exe PROGRAM [--add REPORT.json] [options]
reports diff OLD NEW [options]
```
Options: `--format md|text|xml|json|digest`, `--out FILE`, `--pretty`, `--section NAME` (repeat), `--sort COLUMN [--desc]`, `--rows N`, `--precision N`, `--marks`, `--no-meta`, `--no-notes`, `--top N`, `--band 0.05`,
`--check` (exit code 3 when the report has a failure, for scripts), `--title TEXT`; for `results`: `--subject Odin --ref-label C --unit ns --section NAME --table TITLE`. Exit codes: 0 fine, 1 an input could not be read,
2 wrong use, 3 `--check` found a failure. `odin run reports/tool/reports -- help` prints it all.

**For an agent that reports to a person:** write Markdown (a title, sections, tables, `- [x]` checks, `- **high**` findings), then `reports import notes.md --out report.json`, `reports digest report.json` to see what the
report says in a few lines, `reports render report.json --format md` for the person. To keep a record, keep the JSON: it is small, keeps every number, and `reports diff old.json new.json` says what changed. A benchmark that
prints `RESULT<TAB>case<TAB>value` lines (any program) is `reports results --odin-exe bench_odin.exe --ref-exe bench_c.exe --add run.report.json --section fft`.

## The viewer and the demos
`reports/view` (`reports_view.ViewDraw(&ctx, &view, &report)`) draws a report with `odin_utilities/ui`: a split with the sections on the left (coloured by their status) and the blocks of the chosen section on the right. Tables
are columns sized to their text whose headings sort them (first click ascending, second descending, third back to the order of the report), ratio columns carry a bar from 0 to 2 (always at the left, the same size in every row) and the number in the colour of its verdict, in a box as wide as the widest number and aligned to the right; the numbers of a column have the same decimals (1.79, 7.10, 118.00) and are aligned to the right, budgets and checks are coloured by status, findings by severity,
charts are plotted (a log scale is plotted as logarithms), a filter field keeps the rows whose first cell contains a text. The view keeps only what the person chose; the report is the program's, and a report that changes
between frames is fine. The ui storage needs room for the tables (a cell is two to four elements): the demos use `ui.Storage(6144, 12288, 1024, 65536)`.

Demos (`odin run reports/demo_raylib` or `reports/demo_karl2d`, written once against `demo_kit`): `viewer` shows `demo_common/bench_results.report.json`, the results of an audio DSP library against C references (made
from its notes with `reports import`: 14 sections, 16 tables), `compare` shows a comparison of two runs of it (the second is the first with its numbers moved by a pattern, plus checks and findings), `status` shows a
report built with the API: facts, checks, budgets, a history chart, findings, a log. Each has a script (a click on a section, three clicks on a heading: ascending, descending, the order of the report, typing in the filter, and checks of the numbers
and of the statuses) that runs headless: `odin test reports/demo_common`.

## Commands (from odin_utilities)
```
odin test reports -strict-style -vet                 # the library tests (16)
odin test reports/demo_common -strict-style -vet     # the scripts of the demos, headless
odin run reports/tool/reports -- help                # the command line
odin run reports/demo_raylib                         # the demos
```

## Limits
- A report is read whole into memory; one table is meant for people (tens or hundreds of rows), not for a million samples.
- Markdown import follows the shapes above; free prose stays a paragraph. A markdown table whose cells are not plain numbers stays text. Header units are taken from a trailing `(...)` of a column name.
- `ReportCompare` matches tables by position: two reports with a different set of tables per section compare only the first ones in common.
- The viewer draws what the ui library has: no zoom or axes on charts, no editing. Wide tables scroll with the section.
- The direction of an imported NUMBER column is a guess (lower is better when the table has a ratio column, none otherwise): set `better` when building a report for a different meaning, or edit the JSON.
