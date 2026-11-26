#+build !js
package ui_figma

// Writes Odin source that builds a design with the ui library: one procedure per top level frame, `Name :: proc(c: ^ui.Context, s: ^NameState)`. What the design says about layout becomes the layout of the
// calls (auto layout direction, gap, padding, alignment, fixed / hug / fill sizing); frames with a fill, a stroke or a corner radius become `UiPanel`, the others `UiRow` / `UiColumn`; text becomes `UiLabel`.
// A frame (or component instance) named like a widget becomes that widget: Button, Checkbox / Toggle, Switch, Slider, Progress, TextField / Input, Separator / Divider (the first letters of the name, case and
// punctuation ignored, so "Button / Primary" and "button=hover" both match). The values those widgets work on (a slider's number, a toggle, the text of a field, "was the button clicked") are fields of the
// generated `NameState` struct that the program keeps.
//
// Limits: colors, fonts, shadows, images, vectors and free (non auto layout) positions are not carried over: the style of the ui library draws, the generator keeps the structure. Colors can be written next to
// the text with `text_colors`. A node the generator cannot place becomes a comment line and a warning.

import "core:fmt"
import "core:strings"
import "base:runtime"

Options :: struct {
    package_name: string,       // the package of the generated file ("design")
    ui_import: string,          // the import path of the ui package, as written in the generated file ("../ui")
    frames: []string,           // names of the top level frames to write; none: every top level frame
    source_label: string,       // said in the header (the name of the file or the design)
    text_colors: bool,          // text with a solid fill is drawn with that color (`UiLabelColored`); otherwise the theme's text color
}

@(private)
Generator :: struct {
    out: strings.Builder,
    state: strings.Builder,             // the fields of the state struct of the frame being written
    state_fields: int,
    names: map[string]int,              // field names used in the frame: a second one gets a number
    warnings: [dynamic]string,
    options: Options,
    allocator: runtime.Allocator,
}

@(private)
warn :: proc(g: ^Generator, format: string, args: ..any) {
    append(&g.warnings, fmt.aprintf(format, ..args, allocator = g.allocator))
}

// A Odin string literal for any text
@(private)
quote :: proc(text: string, allocator := context.temp_allocator) -> string {
    builder: strings.Builder = strings.builder_make(allocator)
    strings.write_byte(&builder, '"')
    for character in text {
        switch character {
        case '"': strings.write_string(&builder, "\\\"")
        case '\\': strings.write_string(&builder, "\\\\")
        case '\n': strings.write_string(&builder, "\\n")
        case '\r':
        case '\t': strings.write_string(&builder, "\\t")
        case: strings.write_rune(&builder, character)
        }
    }
    strings.write_byte(&builder, '"')
    return strings.to_string(builder)
}

// The letters of a name in lower case, nothing else: "Text Field" and "text_field" are the same
@(private)
compact :: proc(name: string) -> string {
    builder: strings.Builder = strings.builder_make(context.temp_allocator)
    for character in name {
        if character >= 'A' && character <= 'Z' { strings.write_rune(&builder, character + 32) }
        else if character >= 'a' && character <= 'z' { strings.write_rune(&builder, character) }
    }
    return strings.to_string(builder)
}

@(private)
snake :: proc(name: string, allocator := context.temp_allocator) -> string {
    builder: strings.Builder = strings.builder_make(allocator)
    last_underscore: bool = true
    for character in name {
        c: rune = character
        if c >= 'A' && c <= 'Z' { c += 32 }
        if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') {
            strings.write_rune(&builder, c)
            last_underscore = false
        } else if !last_underscore {
            strings.write_byte(&builder, '_')
            last_underscore = true
        }
    }
    result: string = strings.trim_right(strings.to_string(builder), "_")
    if result == "" { return "node" }
    if result[0] >= '0' && result[0] <= '9' { return strings.concatenate({"n", result}, allocator) }
    return result
}

@(private)
pascal :: proc(name: string, allocator := context.temp_allocator) -> string {
    builder: strings.Builder = strings.builder_make(allocator)
    upper: bool = true
    for character in name {
        c: rune = character
        if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') {
            if upper && c >= 'a' && c <= 'z' { c -= 32 }
            strings.write_rune(&builder, c)
            upper = false
        } else {
            upper = true
        }
    }
    result: string = strings.to_string(builder)
    if result == "" { return "Design" }
    if result[0] >= '0' && result[0] <= '9' { return strings.concatenate({"Design", result}, allocator) }
    return result
}

@(private)
oneLine :: proc(text: string) -> string {
    result, _ := strings.replace_all(text, "\n", " ", context.temp_allocator)
    return result
}

@(private)
Widget :: enum u8 {
    NONE,
    BUTTON,
    TOGGLE,
    SWITCH,
    SLIDER,
    PROGRESS,
    TEXT_FIELD,
    SEPARATOR,
}

@(private)
WIDGET_NAMES :: [?]struct{prefix: string, widget: Widget}{
    {"button", .BUTTON},
    {"checkbox", .TOGGLE},
    {"toggle", .TOGGLE},
    {"switch", .SWITCH},
    {"slider", .SLIDER},
    {"progress", .PROGRESS},
    {"textfield", .TEXT_FIELD},
    {"textinput", .TEXT_FIELD},
    {"input", .TEXT_FIELD},
    {"separator", .SEPARATOR},
    {"divider", .SEPARATOR},
}

@(private)
widgetOf :: proc(node: Node) -> Widget {
    if node.kind == .LINE { return .SEPARATOR }
    if node.kind != .FRAME { return .NONE }
    name: string = compact(node.name)
    for entry in WIDGET_NAMES {
        if strings.has_prefix(name, entry.prefix) { return entry.widget }
    }
    // "Volume Slider": the kind at the end of the name, when no kind starts it
    for entry in WIDGET_NAMES {
        if strings.has_suffix(name, entry.prefix) { return entry.widget }
    }
    return .NONE
}

// The text of the first TEXT inside a node (the label of a button)
@(private)
firstText :: proc(node: Node) -> string {
    for child in node.children {
        if !child.visible { continue }
        if child.kind == .TEXT && child.characters != "" { return child.characters }
        if inner: string = firstText(child); inner != "" { return inner }
    }
    return ""
}

@(private)
Axis :: enum u8 { HORIZONTAL, VERTICAL }

// fixed / hug / fill of one axis: what the file says, or (old files) what the older fields say
@(private)
sizingOf :: proc(node: Node, parent: ^Node, axis: Axis) -> Sizing {
    explicit: Sizing = node.sizing_horizontal if axis == .HORIZONTAL else node.sizing_vertical
    if explicit != .UNSET { return explicit }
    if parent != nil && parent.layout != .NONE {
        along: bool = (parent.layout == .HORIZONTAL) == (axis == .HORIZONTAL)
        if along && node.grow > 0 { return .FILL }
        if !along && node.stretch { return .FILL }
    }
    if node.kind == .TEXT { return .FIXED if node.text_fixed_width && axis == .HORIZONTAL else .HUG }
    if node.kind == .FRAME && node.layout != .NONE {
        primary: bool = (node.layout == .HORIZONTAL) == (axis == .HORIZONTAL)
        if (primary && node.primary_auto) || (!primary && node.counter_auto) { return .HUG }
    }
    return .FIXED
}

@(private)
axisText :: proc(node: Node, parent: ^Node, axis: Axis) -> string {
    switch sizingOf(node, parent, axis) {
    case .HUG: return "ui.Fit()"
    case .FILL: return "ui.Grow()"
    case .FIXED, .UNSET:
        length: f32 = node.width if axis == .HORIZONTAL else node.height
        if length <= 0 { return "ui.Fit()" }
        return fmt.aprintf("ui.Fixed(%v)", length, allocator = context.temp_allocator)
    }
    return "ui.Fit()"
}

@(private)
sizeText :: proc(node: Node, parent: ^Node) -> string {
    return fmt.aprintf("ui.Size{{width = %s, height = %s}}", axisText(node, parent, .HORIZONTAL), axisText(node, parent, .VERTICAL), allocator = context.temp_allocator)
}

@(private)
alignText :: proc(align: Align, horizontal: bool) -> string {
    switch align {
    case .MIN, .SPACE_BETWEEN: return ".LEFT" if horizontal else ".TOP"
    case .CENTER: return ".CENTER"
    case .MAX: return ".RIGHT" if horizontal else ".BOTTOM"
    }
    return ".LEFT" if horizontal else ".TOP"
}

@(private)
layoutText :: proc(g: ^Generator, node: Node, parent: ^Node) -> string {
    builder: strings.Builder = strings.builder_make(context.temp_allocator)
    fmt.sbprintf(&builder, "ui.Layout{{size = %s", sizeText(node, parent))
    padding: [4]f32 = node.padding
    if padding != {} { fmt.sbprintf(&builder, ", padding = {{%v, %v, %v, %v}}", padding[0], padding[1], padding[2], padding[3]) }
    if node.spacing != 0 { fmt.sbprintf(&builder, ", gap = %v", node.spacing) }
    horizontal: bool = node.layout == .HORIZONTAL
    x_align: Align = node.primary_align if horizontal else node.counter_align
    y_align: Align = node.counter_align if horizontal else node.primary_align
    if node.layout == .NONE { x_align, y_align = .MIN, .MIN }
    if node.primary_align == .SPACE_BETWEEN { warn(g, "%q: space between is not kept (the children sit at the start); put a Spacer frame between them", node.name) }
    if x_align != .MIN || y_align != .MIN { fmt.sbprintf(&builder, ", align = {{x = %s, y = %s}}", alignText(x_align, true), alignText(y_align, false)) }
    if horizontal { fmt.sbprintf(&builder, ", direction = .LEFT_TO_RIGHT") }
    fmt.sbprintf(&builder, ", exact = true}}")
    return strings.to_string(builder)
}

// A field of the state struct with a name that is not used yet in this frame
@(private)
fieldAdd :: proc(g: ^Generator, node: Node, suffix: string, type: string, initial: string = "") -> string {
    base: string = strings.concatenate({snake(node.name), "_", suffix}, context.temp_allocator)
    count: int = g.names[base]
    g.names[base] = count + 1
    name: string = base if count == 0 else fmt.aprintf("%s_%d", base, count + 1, allocator = context.temp_allocator)
    if initial == "" { fmt.sbprintf(&g.state, "    %s: %s,\n", name, type) }
    else { fmt.sbprintf(&g.state, "    %s: %s = %s,\n", name, type, initial) }
    g.state_fields += 1
    return name
}

@(private)
indent :: proc(g: ^Generator, depth: int) {
    for _ in 0 ..< depth { strings.write_string(&g.out, "    ") }
}

@(private)
idName :: proc(node: Node, shown: string) -> string {
    return quote(strings.concatenate({shown, "##", node.id}, context.temp_allocator))
}

@(private)
nodeEmit :: proc(g: ^Generator, node: Node, parent: ^Node, depth: int, root: bool) {
    if !node.visible { return }
    node := node
    switch node.kind {
    case .DOCUMENT, .CANVAS, .OTHER:
        indent(g, depth)
        fmt.sbprintf(&g.out, "// skipped %s %q: not supported\n", node.type, oneLine(node.name))
        warn(g, "%s %q is skipped (no ui widget for it)", node.type, node.name)
    case .TEXT:
        indent(g, depth)
        wrap: string = ".WORDS" if node.text_fixed_width else ".NONE"
        if g.options.text_colors && node.has_fill {
            fmt.sbprintf(&g.out, "ui.UiLabelColored(c, %s, ui.Color{{%d, %d, %d, %d}}, %s)\n", quote(node.characters), node.fill[0], node.fill[1], node.fill[2], node.fill[3], wrap)
        } else {
            align: string = ".LEFT"
            switch node.text_align {
            case "CENTER": align = ".CENTER"
            case "RIGHT": align = ".RIGHT"
            }
            fmt.sbprintf(&g.out, "ui.UiLabel(c, %s, %s, %s)\n", quote(node.characters), wrap, align)
        }
    case .ELLIPSE:
        indent(g, depth)
        fmt.sbprintf(&g.out, "// skipped ELLIPSE %q: the ui library has no ellipse element\n", oneLine(node.name))
        warn(g, "ELLIPSE %q is skipped", node.name)
    case .RECTANGLE:
        indent(g, depth)
        fmt.sbprintf(&g.out, "if ui.UiPanel(c, %s, %s, false) {{\n", idName(node, node.name), layoutText(g, node, parent))
        indent(g, depth)
        strings.write_string(&g.out, "}\n")
    case .LINE:
        indent(g, depth)
        strings.write_string(&g.out, "ui.UiSeparator(c)\n")
    case .FRAME:
        frameEmit(g, node, parent, depth, root)
    }
}

@(private)
frameEmit :: proc(g: ^Generator, node: Node, parent: ^Node, depth: int, root: bool) {
    widget: Widget = widgetOf(node) if !root else .NONE
    size: string = sizeText(node, parent)
    shown: string = firstText(node)
    switch widget {
    case .BUTTON:
        field: string = fieldAdd(g, node, "clicked", "bool")
        label: string = shown if shown != "" else node.name
        indent(g, depth)
        fmt.sbprintf(&g.out, "s.%s = ui.UiButton(c, %s, %s)\n", field, idName(node, label), size)
        return
    case .TOGGLE:
        field: string = fieldAdd(g, node, "on", "bool")
        indent(g, depth)
        fmt.sbprintf(&g.out, "_ = ui.UiToggle(c, %s, &s.%s, %s)\n", idName(node, shown if shown != "" else node.name), field, size)
        return
    case .SWITCH:
        field: string = fieldAdd(g, node, "on", "bool")
        indent(g, depth)
        fmt.sbprintf(&g.out, "_ = ui.UiSwitch(c, %s, &s.%s, %s)\n", idName(node, shown if shown != "" else node.name), field, size)
        return
    case .SLIDER:
        field: string = fieldAdd(g, node, "value", "f32")
        indent(g, depth)
        fmt.sbprintf(&g.out, "_ = ui.UiSlider(c, %s, &s.%s, 0, 1, %s)\n", idName(node, node.name), field, size)
        return
    case .PROGRESS:
        field: string = fieldAdd(g, node, "fraction", "f32")
        indent(g, depth)
        fmt.sbprintf(&g.out, "ui.UiProgress(c, %s, s.%s, 0, 1, %s)\n", idName(node, node.name), field, size)
        return
    case .TEXT_FIELD:
        buffer: string = fieldAdd(g, node, "text", "[128]u8")
        length: string = fieldAdd(g, node, "length", "int")
        indent(g, depth)
        fmt.sbprintf(&g.out, "_, _ = ui.UiTextField(c, %s, s.%s[:], &s.%s, %s)\n", idName(node, node.name), buffer, length, size)
        return
    case .SEPARATOR:
        indent(g, depth)
        strings.write_string(&g.out, "ui.UiSeparator(c)\n")
        return
    case .NONE:
    }

    if node.layout == .NONE && len(node.children) > 0 {
        warn(g, "FRAME %q has no auto layout: its children are stacked in a column, their free positions are lost", node.name)
    }
    drawn: bool = root || node.has_fill || node.has_stroke || node.radius > 0
    layout: string = layoutText(g, node, parent)
    if len(node.children) == 0 && !root {
        indent(g, depth)
        if drawn { fmt.sbprintf(&g.out, "if ui.UiPanel(c, %s, %s, false) {{\n", idName(node, node.name), layout); indent(g, depth); strings.write_string(&g.out, "}\n") }
        else { fmt.sbprintf(&g.out, "ui.UiSpacer(c, %s)\n", size) }
        return
    }
    indent(g, depth)
    if drawn { fmt.sbprintf(&g.out, "if ui.UiPanel(c, %s, %s) {{\n", idName(node, node.name), layout) }
    else if node.layout == .HORIZONTAL { fmt.sbprintf(&g.out, "if ui.UiRow(c, %s) {{\n", layout) }
    else { fmt.sbprintf(&g.out, "if ui.UiColumn(c, %s) {{\n", layout) }
    own: Node = node
    for child in node.children { nodeEmit(g, child, &own, depth + 1, false) }
    indent(g, depth)
    strings.write_string(&g.out, "}\n")
}

// The top level frames: the frames of the pages of a file, or the frame / page a `nodes` answer holds
@(private)
roots :: proc(document: Document, options: Options) -> [dynamic]Node {
    found: [dynamic]Node = make([dynamic]Node, 0, 8, context.temp_allocator)
    wanted :: proc(options: Options, node: Node) -> bool {
        if len(options.frames) == 0 { return true }
        for name in options.frames { if name == node.name || name == node.id { return true } }
        return false
    }
    pageScan :: proc(found: ^[dynamic]Node, options: Options, page: Node) {
        for child in page.children {
            if child.kind == .FRAME && child.visible && wanted(options, child) { append(found, child) }
        }
    }
    for top in document.roots {
        #partial switch top.kind {
        case .DOCUMENT:
            for page in top.children { if page.kind == .CANVAS { pageScan(&found, options, page) } }
        case .CANVAS: pageScan(&found, options, top)
        case .FRAME: if wanted(options, top) { append(&found, top) }
        }
    }
    return found
}

// The source of the design, and what the generator could not carry over. Both are made with `allocator`.
Generate :: proc(document: Document, options: Options, allocator := context.allocator) -> (source: string, warnings: []string) {
    g: Generator
    g.options = options
    g.allocator = allocator
    g.out = strings.builder_make(allocator)
    g.warnings = make([dynamic]string, 0, 8, allocator)
    package_name: string = options.package_name if options.package_name != "" else "design"
    ui_import: string = options.ui_import if options.ui_import != "" else "../ui"
    fmt.sbprintf(&g.out, "package %s\n\n", package_name)
    fmt.sbprintf(&g.out, "// Generated by ui/figma from %s. Do not edit: change the design and generate again.\n", options.source_label if options.source_label != "" else "a Figma design")
    fmt.sbprintf(&g.out, "// Every frame is a procedure that builds its layout in the ui frame (`ui.UiBegin` ... `ui.UiEnd`); the widgets keep what they work on in the state struct of the frame.\n\n")
    fmt.sbprintf(&g.out, "import ui %s\n", quote(ui_import))
    list: [dynamic]Node = roots(document, options)
    if len(list) == 0 { warn(&g, "no frame found%s", " with that name" if len(options.frames) > 0 else "") }
    for frame in list {
        g.names = make(map[string]int, context.temp_allocator)
        g.state = strings.builder_make(context.temp_allocator)
        g.state_fields = 0
        body: strings.Builder = g.out
        g.out = strings.builder_make(allocator)
        nodeEmit(&g, frame, nil, 1, true)
        frame_body: string = strings.to_string(g.out)
        g.out = body
        name: string = pascal(frame.name)
        strings.write_string(&g.out, "\n")
        if g.state_fields > 0 {
            fmt.sbprintf(&g.out, "%sState :: struct {{\n%s}}\n\n", name, strings.to_string(g.state))
            fmt.sbprintf(&g.out, "// %q (%v x %v)\n%s :: proc(c: ^ui.Context, s: ^%sState) {{\n%s}}\n", frame.name, frame.width, frame.height, name, name, frame_body)
        } else {
            fmt.sbprintf(&g.out, "// %q (%v x %v)\n%s :: proc(c: ^ui.Context) {{\n%s}}\n", frame.name, frame.width, frame.height, name, frame_body)
        }
    }
    return strings.to_string(g.out), g.warnings[:]
}
