package main

// The report of what is left to do, printed from the TODO files of this repository: `odin run tool/todo` (from odin_utilities).
//
//     odin run tool/todo                          the report of the category that is being worked on (next, limits, state, log)
//     odin run tool/todo -- next [category]       the open tasks, high reward first; when there are none, those of the neighbouring categories
//     odin run tool/todo -- limits [category]     what the widgets of the category do not do (the `Limits:` lines of their sources): the seed of improvements to suggest
//     odin run tool/todo -- log [category] [n]    the last n commits that touched the category (what was done)
//     odin run tool/todo -- state                 git: uncommitted files, commits that are not pushed
//     odin run tool/todo -- categories            every category with its numbers of open tasks
//     add --deferred to next to list the deferred tasks too
//
// A task is a line `- [ ] text` of `TODO.md` or `<category>/TODO.md` (more indented lines go on with it). Its value is a tag at the start of the text: `(high)`,
// `(medium)` (what an item without a tag is) or `(low)`. A task is deferred, and left out of the report while there are tasks that are not, when it starts with
// `(later)` or `(low priority)`, says "out of scope" or "waiting for approval", or stands under a heading with "low priority", "later", "deferred" or "waiting" in it.
// The category is the argument, else the one the uncommitted changes (or the last commit) are mostly in. Neighbouring categories are in `neighbours.txt`.

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"

NEIGHBOURS :: #load("neighbours.txt", string)
MAX_LISTED :: 6                     // tasks of one category in a report
MAX_SUMMARY :: 170                  // characters of a task in a report

Value :: enum u8 {
    HIGH,
    MEDIUM,
    LOW,
}

Item :: struct {
    text: string,
    done: bool,
    value: Value,
    deferred: bool,
    section: string,
    line: int,
}

Category :: struct {
    name: string,
    items: [dynamic]Item,
}

VALUE_NAMES: [Value]string = {.HIGH = "high", .MEDIUM = "medium", .LOW = "low"}

// ------------------------------------------------------------------------------------------------------------------------
// Reading a TODO file

@(private)
hasWord :: proc(text: string, words: []string) -> bool {
    lower: string = strings.to_lower(text, context.temp_allocator)
    for word in words {
        if strings.contains(lower, word) { return true }
    }
    return false
}

// A task is deferred by what it says (its text) or by where it stands (its heading)
@(private)
isDeferred :: proc(text: string, section: string) -> bool {
    return hasWord(text, {"(later)", "(low priority)", "out of scope", "waiting for approval"}) || hasWord(section, {"low priority", "later", "deferred", "waiting"})
}

parseTodo :: proc(text: string, allocator := context.allocator) -> [dynamic]Item {
    items: [dynamic]Item
    items.allocator = allocator
    section: string
    current: int = -1
    for raw, number in strings.split_lines(text, context.temp_allocator) {
        line: string = strings.trim_right(raw, "\r")
        switch {
        case strings.has_prefix(line, "## "):
            section = strings.clone(strings.trim_space(line[3:]), allocator)
            current = -1
        case strings.has_prefix(line, "# "):
            current = -1
        case strings.has_prefix(line, "- [ ] ") || strings.has_prefix(line, "- [x] "):
            item: Item = {done = line[3] == 'x', value = .MEDIUM, section = section, line = number + 1}
            body: string = strings.trim_space(line[6:])
            // the tags at the start: the value and "later"
            for {
                tagged: bool
                for tag in ([?]struct { prefix: string, value: Value, defers: bool }{
                    {"(high)", .HIGH, false}, {"(medium)", .MEDIUM, false}, {"(low priority)", .LOW, true}, {"(low)", .LOW, false}, {"(later)", .LOW, true},
                }) {
                    if strings.has_prefix(body, tag.prefix) {
                        item.value = tag.value
                        item.deferred = item.deferred || tag.defers
                        body = strings.trim_space(body[len(tag.prefix):])
                        tagged = true
                        break
                    }
                }
                if !tagged { break }
            }
            item.text = strings.clone(body, allocator)
            item.deferred = item.deferred || isDeferred(body, section)
            append(&items, item)
            current = len(items) - 1
        case len(line) > 0 && (line[0] == ' ' || line[0] == '\t') && current >= 0:
            more: ^Item = &items[current]
            more.text = fmt.aprintf("%s %s", more.text, strings.trim_space(line), allocator = allocator)
            more.deferred = more.deferred || isDeferred(more.text, more.section)
        case:
            current = -1
        }
    }
    return items
}

// The open tasks that are not deferred (or that are: `deferred`), the high ones first, the order of the file within a value
open :: proc(category: ^Category, deferred: bool) -> [dynamic]Item {
    result: [dynamic]Item
    result.allocator = context.temp_allocator
    for item in category.items {
        if !item.done && item.deferred == deferred { append(&result, item) }
    }
    slice.sort_by(result[:], proc(a: Item, b: Item) -> bool {
        if a.value != b.value { return a.value < b.value }
        return a.line < b.line
    })
    return result
}

// A task in a line: the start of its text, cut at a sentence or a word
summary :: proc(text: string) -> string {
    if len(text) <= MAX_SUMMARY { return text }
    cut: int = MAX_SUMMARY
    if stop := strings.index(text[:MAX_SUMMARY], ". "); stop > 40 { return text[:stop + 1] }
    for cut > 40 && text[cut] != ' ' { cut -= 1 }
    return fmt.tprintf("%s ...", text[:cut])
}

// ------------------------------------------------------------------------------------------------------------------------
// The report

findCategory :: proc(categories: []Category, name: string) -> ^Category {
    for &category in categories {
        if category.name == name { return &category }
    }
    return nil
}

// The neighbouring categories of `name` from the text of neighbours.txt (`name: a b c`); without a line for it, every other category that has a TODO file
neighbours :: proc(text: string, categories: []Category, name: string) -> [dynamic]string {
    result: [dynamic]string
    result.allocator = context.temp_allocator
    for raw in strings.split_lines(text, context.temp_allocator) {
        line: string = strings.trim_space(raw)
        if line == "" || line[0] == '#' { continue }
        colon: int = strings.index_byte(line, ':')
        if colon < 0 || strings.trim_space(line[:colon]) != name { continue }
        for word in strings.fields(line[colon + 1:], context.temp_allocator) { append(&result, word) }
        return result
    }
    for category in categories {
        if category.name != name { append(&result, category.name) }
    }
    return result
}

@(private)
listItems :: proc(builder: ^strings.Builder, items: []Item, limit: int, indent: string) {
    for item, i in items {
        if i == limit {
            fmt.sbprintfln(builder, "%s... and %d more", indent, len(items) - limit)
            break
        }
        fmt.sbprintfln(builder, "%s%d. [%s] %s", indent, i + 1, VALUE_NAMES[item.value], summary(item.text))
    }
}

// What is left for the category, high reward first. A category without open tasks says so and gives the tasks of its neighbours instead. Deferred tasks are only
// named when nothing else is left anywhere that was looked at, or when `show_deferred`.
nextReport :: proc(builder: ^strings.Builder, categories: []Category, name: string, neighbour_text: string, show_deferred: bool = false) {
    category: ^Category = findCategory(categories, name)
    normal: [dynamic]Item
    deferred: [dynamic]Item
    if category != nil {
        normal = open(category, false)
        deferred = open(category, true)
    }
    if len(normal) > 0 {
        fmt.sbprintfln(builder, "Open for %s (%d), the most valuable first:", name, len(normal))
        listItems(builder, normal[:], MAX_LISTED, "  ")
        if show_deferred && len(deferred) > 0 {
            fmt.sbprintfln(builder, "Deferred (%d):", len(deferred))
            listItems(builder, deferred[:], MAX_LISTED, "  ")
        }
        return
    }
    fmt.sbprintfln(builder, "%s has no open tasks.", name)
    others: [dynamic]string = neighbours(neighbour_text, categories, name)
    found: bool
    all_deferred: [dynamic]string
    all_deferred.allocator = context.temp_allocator
    fmt.sbprintln(builder, "Neighbouring categories:")
    for other in others {
        other_category: ^Category = findCategory(categories, other)
        other_normal: [dynamic]Item
        if other_category != nil {
            other_normal = open(other_category, false)
            for item in open(other_category, true) { append(&all_deferred, fmt.tprintf("%s: %s", other, summary(item.text))) }
        }
        if len(other_normal) == 0 {
            fmt.sbprintfln(builder, "  %s: clear", other)
            continue
        }
        found = true
        fmt.sbprintfln(builder, "  %s (%d):", other, len(other_normal))
        listItems(builder, other_normal[:], 3, "    ")
    }
    for item in deferred { append(&all_deferred, fmt.tprintf("%s: %s", name, summary(item.text))) }
    if !found && len(all_deferred) > 0 {
        fmt.sbprintfln(builder, "Nothing else is open, only deferred work (%d):", len(all_deferred))
        for text in all_deferred { fmt.sbprintfln(builder, "  - %s", text) }
    } else if show_deferred && len(all_deferred) > 0 {
        fmt.sbprintfln(builder, "Deferred (%d):", len(all_deferred))
        for text in all_deferred { fmt.sbprintfln(builder, "  - %s", text) }
    }
}

// The limits of the widgets in a source file: the text of its `// Limits:` comment (the lines that go on are indented more), one for each point
limitsOf :: proc(stem: string, source: string, allocator := context.temp_allocator) -> [dynamic]string {
    result: [dynamic]string
    result.allocator = allocator
    inside: bool
    for raw in strings.split_lines(source, context.temp_allocator) {
        line: string = strings.trim_right(raw, "\r ")
        switch {
        case strings.has_prefix(line, "// Limits: "):
            append(&result, fmt.aprintf("%s: %s", stem, strings.trim_space(line[len("// Limits: "):]), allocator = allocator))
            inside = true
        case inside && strings.has_prefix(line, "//     "):
            append(&result, fmt.aprintf("%s: %s", stem, strings.trim_space(line[2:]), allocator = allocator))
        case:
            inside = false
        }
    }
    return result
}

// ------------------------------------------------------------------------------------------------------------------------
// git and the files

gitLines :: proc(command: []string) -> [dynamic]string {
    lines: [dynamic]string
    lines.allocator = context.temp_allocator
    state, stdout, _, err := os.process_exec({command = command}, context.temp_allocator)
    if err != nil || state.exit_code != 0 { return lines }
    for line in strings.split_lines(string(stdout), context.temp_allocator) {
        text: string = strings.trim_right(line, "\r")
        if text != "" { append(&lines, text) }
    }
    return lines
}

loadCategories :: proc() -> [dynamic]Category {
    categories: [dynamic]Category
    categories.allocator = context.temp_allocator
    for path in gitLines({"git", "ls-files", "--", "TODO.md", "*/TODO.md"}) {
        bytes, err := os.read_entire_file(path, context.temp_allocator)
        if err != nil { continue }
        name: string = "general"
        if slash := strings.index_byte(path, '/'); slash > 0 { name = path[:slash] }
        append(&categories, Category{name = name, items = parseTodo(string(bytes), context.temp_allocator)})
    }
    return categories
}

// The category that is being worked on: the library the uncommitted changes are mostly in, else the one of the last commit
currentCategory :: proc() -> (name: string, why: string) {
    counts: map[string]int
    counts.allocator = context.temp_allocator
    for line in gitLines({"git", "status", "--short"}) {
        if len(line) < 4 { continue }
        if component := firstDirectory(line[3:]); component != "" { counts[component] += 1 }
    }
    why = "from the uncommitted changes"
    if len(counts) == 0 {
        for line in gitLines({"git", "show", "--name-only", "--pretty=format:", "HEAD"}) {
            if component := firstDirectory(line); component != "" { counts[component] += 1 }
        }
        why = "from the last commit"
    }
    best: int
    for key, count in counts {
        if count > best || (count == best && key < name) { name, best = key, count }
    }
    return name, why
}

@(private)
firstDirectory :: proc(path: string) -> string {
    slash: int = strings.index_byte(path, '/')
    if slash <= 0 { return "" }
    first: string = path[:slash]
    return "" if first == "tool" || first == "assets" || first == "templates" || first == "references" else first
}

stateReport :: proc(builder: ^strings.Builder) {
    changed: [dynamic]string = gitLines({"git", "status", "--short"})
    ahead: [dynamic]string = gitLines({"git", "log", "--oneline", "@{u}..HEAD"})
    switch {
    case len(changed) == 0 && len(ahead) == 0: fmt.sbprintln(builder, "git: clean, everything is pushed")
    case len(changed) == 0: fmt.sbprintfln(builder, "git: clean, %d commit%s not pushed", len(ahead), " is" if len(ahead) == 1 else "s are")
    case: fmt.sbprintfln(builder, "git: %d file%s not committed, %d commit%s not pushed", len(changed), " is" if len(changed) == 1 else "s are", len(ahead), " is" if len(ahead) == 1 else "s are")
    }
}

limitsReport :: proc(builder: ^strings.Builder, category: string, limit: int = 0) {
    points: [dynamic]string
    points.allocator = context.temp_allocator
    for path in gitLines({"git", "ls-files", "--", fmt.tprintf("%s/*.odin", category)}) {
        if strings.contains(path[len(category) + 1:], "/") { continue }
        bytes, err := os.read_entire_file(path, context.temp_allocator)
        if err != nil { continue }
        stem: string = path[len(category) + 1:len(path) - len(".odin")]
        for point in limitsOf(stem, string(bytes)) { append(&points, point) }
    }
    if len(points) == 0 {
        fmt.sbprintfln(builder, "No `Limits:` lines in %s: improvements to suggest are the ones that come from using it.", category)
        return
    }
    fmt.sbprintfln(builder, "What %s does not do yet (not tasks: candidates to suggest, most of them cost little to lift):", category)
    for point, i in points {
        if limit > 0 && i == limit {
            fmt.sbprintfln(builder, "  ... and %d more (odin run tool/todo -- limits %s)", len(points) - limit, category)
            break
        }
        fmt.sbprintfln(builder, "  - %s", point)
    }
}

logReport :: proc(builder: ^strings.Builder, category: string, count: int) {
    lines: [dynamic]string = gitLines({"git", "log", fmt.tprintf("-%d", count), "--pretty=format:%h %s", "--", category})
    fmt.sbprintfln(builder, "Last commits in %s:", category)
    for line in lines { fmt.sbprintfln(builder, "  %s", line) }
}

categoriesReport :: proc(builder: ^strings.Builder, categories: []Category) {
    fmt.sbprintfln(builder, "%-20s %8s %9s %6s", "category", "open", "deferred", "done")
    for &category in categories {
        done: int
        for item in category.items { if item.done { done += 1 } }
        fmt.sbprintfln(builder, "%-20s %8d %9d %6d", category.name, len(open(&category, false)), len(open(&category, true)), done)
    }
}

// ------------------------------------------------------------------------------------------------------------------------

main :: proc() {
    arguments: [dynamic]string
    show_deferred: bool
    for argument in os.args[1:] {
        if argument == "--deferred" { show_deferred = true } else { append(&arguments, argument) }
    }
    command: string = "report"
    if len(arguments) > 0 {
        switch arguments[0] {
        case "report", "next", "limits", "log", "state", "categories":
            command = arguments[0]
            ordered_remove(&arguments, 0)
        }
    }
    categories: [dynamic]Category = loadCategories()
    builder: strings.Builder
    strings.builder_init(&builder, context.temp_allocator)
    name: string
    why: string
    if len(arguments) > 0 {
        name, why = arguments[0], "as asked"
        ordered_remove(&arguments, 0)
    } else if command != "state" && command != "categories" {
        name, why = currentCategory()
    }
    if name == "" && command != "state" && command != "categories" {
        fmt.println("No category: name one (odin run tool/todo -- next ui).")
        os.exit(2)
    }
    switch command {
    case "next":
        nextReport(&builder, categories[:], name, NEIGHBOURS, show_deferred)
    case "limits":
        limitsReport(&builder, name)
    case "log":
        count: int = 8
        if len(arguments) > 0 { count = max(parseInt(arguments[0]), 1) }
        logReport(&builder, name, count)
    case "state":
        stateReport(&builder)
    case "categories":
        categoriesReport(&builder, categories[:])
    case:
        fmt.sbprintfln(&builder, "Category: %s (%s)", name, why)
        nextReport(&builder, categories[:], name, NEIGHBOURS, show_deferred)
        fmt.sbprintln(&builder)
        limitsReport(&builder, name, 8)
        fmt.sbprintln(&builder)
        logReport(&builder, name, 5)
        fmt.sbprintln(&builder)
        stateReport(&builder)
    }
    fmt.print(strings.to_string(builder))
}

@(private)
parseInt :: proc(text: string) -> (value: int) {
    for character in transmute([]u8)text {
        if character < '0' || character > '9' { break }
        value = value * 10 + int(character - '0')
    }
    return
}

// ------------------------------------------------------------------------------------------------------------------------
// Tests

@(private = "file")
SAMPLE :: `# TODO

Tick an item.

## Libraries
- [x] done thing
- [ ] plain task that goes
      on over two lines
- [ ] (high) the important one
- [ ] (low) a small one
- [ ] (later) deferred by its tag
- [ ] (low priority) deferred by another tag
- [ ] needs a window system and is out of scope

## Low priority
- [ ] deferred by its heading
`

@(test)
test_a_todo_file_is_read_with_its_values_and_deferred_tasks :: proc(t: ^testing.T) {
    items: [dynamic]Item = parseTodo(SAMPLE, context.temp_allocator)
    testing.expect_value(t, len(items), 8)
    testing.expect(t, items[0].done && items[0].text == "done thing")
    testing.expect_value(t, items[1].text, "plain task that goes on over two lines")
    testing.expect(t, items[1].value == .MEDIUM && !items[1].deferred && items[1].line == 7)
    testing.expect(t, items[2].value == .HIGH && items[2].text == "the important one")
    testing.expect(t, items[3].value == .LOW && !items[3].deferred)
    testing.expect(t, items[4].deferred && items[4].text == "deferred by its tag")
    testing.expect(t, items[5].deferred && items[5].value == .LOW)
    testing.expect(t, items[6].deferred, "out of scope")
    testing.expect(t, items[7].deferred && items[7].section == "Low priority", "by its heading")
    // the open ones, the high first and the file order in a value
    category: Category = {name = "x", items = items}
    normal: [dynamic]Item = open(&category, false)
    testing.expect_value(t, len(normal), 3)
    testing.expect(t, normal[0].text == "the important one" && normal[1].text == "plain task that goes on over two lines" && normal[2].text == "a small one")
    testing.expect_value(t, len(open(&category, true)), 4)
    // nothing stands for a line that is not a task
    testing.expect_value(t, len(parseTodo("just text\n- a bullet\n", context.temp_allocator)), 0)
    testing.expect_value(t, summary("short"), "short")
    long: string = strings.repeat("word ", 60, context.temp_allocator)
    testing.expect(t, len(summary(long)) < MAX_SUMMARY + 6 && strings.has_suffix(summary(long), "..."))
    testing.expect_value(t, summary(strings.concatenate({"A first sentence that is a little long to stand alone here. ", strings.repeat("and on ", 30, context.temp_allocator)}, context.temp_allocator)), "A first sentence that is a little long to stand alone here.")
}

@(test)
test_the_report_gives_the_tasks_then_the_neighbours_and_deferred_ones_last :: proc(t: ^testing.T) {
    categories: [dynamic]Category
    categories.allocator = context.temp_allocator
    append(&categories, Category{name = "ui", items = parseTodo("- [ ] (low) small\n- [ ] (high) big\n- [ ] (later) wait\n", context.temp_allocator)})
    append(&categories, Category{name = "font", items = parseTodo("- [x] done\n", context.temp_allocator)})
    append(&categories, Category{name = "icons", items = parseTodo("- [ ] draw more\n- [ ] (later) never\n", context.temp_allocator)})
    NEIGHBOUR_TEXT :: "# c\nui: font icons\nfont: ui icons\nicons: ui\n"
    builder: strings.Builder
    strings.builder_init(&builder, context.temp_allocator)
    // normal tasks: only them, the deferred one is not mentioned
    nextReport(&builder, categories[:], "ui", NEIGHBOUR_TEXT)
    text: string = strings.to_string(builder)
    testing.expect(t, strings.contains(text, "Open for ui (2)") && strings.contains(text, "1. [high] big") && strings.contains(text, "2. [low] small"), text)
    testing.expect(t, !strings.contains(text, "wait") && !strings.contains(text, "Neighbouring"), text)
    // asked for
    strings.builder_reset(&builder)
    nextReport(&builder, categories[:], "ui", NEIGHBOUR_TEXT, true)
    testing.expect(t, strings.contains(strings.to_string(builder), "Deferred (1)") && strings.contains(strings.to_string(builder), "wait"))
    // a clear category: its neighbours, those that are clear said so, deferred work not named while a neighbour has a task
    strings.builder_reset(&builder)
    nextReport(&builder, categories[:], "font", NEIGHBOUR_TEXT)
    text = strings.to_string(builder)
    testing.expect(t, strings.contains(text, "font has no open tasks") && strings.contains(text, "ui (2):") && strings.contains(text, "[high] big"), text)
    testing.expect(t, strings.contains(text, "icons (1):") && strings.contains(text, "draw more"), text)
    testing.expect(t, !strings.contains(text, "wait") && !strings.contains(text, "never") && !strings.contains(text, "deferred work"), text)
    // everything clear around it: now the deferred work is named
    categories[0].items[0].done = true
    categories[0].items[1].done = true
    categories[2].items[0].done = true
    strings.builder_reset(&builder)
    nextReport(&builder, categories[:], "font", NEIGHBOUR_TEXT)
    text = strings.to_string(builder)
    testing.expect(t, strings.contains(text, "ui: clear") && strings.contains(text, "only deferred work (2)") && strings.contains(text, "ui: wait") && strings.contains(text, "icons: never"), text)
    // a category that has no TODO file is clear, and a category without a line in the neighbours has every other one
    strings.builder_reset(&builder)
    nextReport(&builder, categories[:], "tween", "")
    testing.expect(t, strings.contains(strings.to_string(builder), "tween has no open tasks") && strings.contains(strings.to_string(builder), "ui: clear"))
    testing.expect_value(t, len(neighbours("ui: a b\nfont: c", categories[:], "ui")), 2)
    testing.expect_value(t, len(neighbours("", categories[:], "ui")), 2)
}

@(test)
test_the_limits_of_a_source_file_are_found :: proc(t: ^testing.T) {
    source :: `package ui

// A widget.
//
// Limits: first limit, with a comma
//     second one
//     third one
//
// Credit line.

Thing :: struct {}
// Limits: a later one
`
    points: [dynamic]string = limitsOf("thing", source)
    testing.expect_value(t, len(points), 4)
    testing.expect(t, points[0] == "thing: first limit, with a comma" && points[1] == "thing: second one" && points[2] == "thing: third one" && points[3] == "thing: a later one")
    testing.expect_value(t, len(limitsOf("x", "package x\n// nothing here\n")), 0)
}
