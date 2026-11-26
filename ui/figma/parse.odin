#+build !js
package ui_figma

// Reads the JSON of a Figma file (`GET /v1/files/:key`, or `GET /v1/files/:key/nodes?ids=...`, or a saved copy of either) into a tree of `Node`. Only what the generator needs is kept: the kind, the auto layout
// (direction, gap, padding, alignment, sizing), the size, the first visible solid fill, the corner radius and the text. This package imports nothing but `core`, so the folder can be copied to another project
// (odin_plug has its own copy of the ui library: copy `figma/` next to it and give `Options.ui_import` the path of that one).
//
//     document, ok := Parse(json_bytes, arena_allocator)
//
// Everything the tree points to is made with the allocator that is given: use an arena and free it at once.

import "core:encoding/json"
import "core:strings"

Kind :: enum u8 {
    OTHER,          // anything the generator has no use for (vectors, boolean operations, stars ...)
    DOCUMENT,
    CANVAS,         // a page
    FRAME,          // FRAME, GROUP, SECTION, COMPONENT, COMPONENT_SET, INSTANCE
    TEXT,
    RECTANGLE,
    LINE,
    ELLIPSE,
}

LayoutMode :: enum u8 {
    NONE,           // no auto layout: the children have free positions, which the generator cannot keep
    HORIZONTAL,
    VERTICAL,
}

Sizing :: enum u8 {
    UNSET,          // the file does not say (old files): the generator works it out from the older fields
    FIXED,
    HUG,
    FILL,
}

Align :: enum u8 {
    MIN,
    CENTER,
    MAX,
    SPACE_BETWEEN,
}

Color :: [4]u8

Node :: struct {
    id: string,
    name: string,
    type: string,               // the type as Figma writes it ("FRAME", "INSTANCE" ...)
    kind: Kind,
    visible: bool,
    children: []Node,

    // frames
    layout: LayoutMode,
    spacing: f32,
    padding: [4]f32,            // left, right, top, bottom
    primary_align: Align,
    counter_align: Align,
    primary_auto: bool,         // primaryAxisSizingMode AUTO: the frame shrinks to its children along the layout
    counter_auto: bool,
    sizing_horizontal: Sizing,
    sizing_vertical: Sizing,
    grow: f32,                  // layoutGrow: 1 takes what is left of the parent's layout direction
    stretch: bool,              // layoutAlign STRETCH: fills the parent across its layout direction
    width: f32,
    height: f32,

    // looks
    has_fill: bool,
    fill: Color,
    has_stroke: bool,
    radius: f32,

    // text
    characters: string,
    font_size: f32,
    font_family: string,
    text_align: string,         // "LEFT", "CENTER", "RIGHT", "JUSTIFIED"
    text_fixed_width: bool,     // textAutoResize is not WIDTH_AND_HEIGHT: the text wraps inside its width
}

Document :: struct {
    roots: []Node,              // the DOCUMENT of a file, or the documents of the nodes of a `nodes` answer
}

@(private)
field :: proc(value: json.Value, key: string) -> (result: json.Value, ok: bool) {
    object, is_object := value.(json.Object)
    if !is_object { return nil, false }
    return object[key]
}

@(private)
text_of :: proc(value: json.Value, key: string, allocator := context.allocator) -> string {
    found, ok := field(value, key)
    if !ok { return "" }
    text, is_text := found.(json.String)
    if !is_text { return "" }
    return strings.clone(string(text), allocator)
}

@(private)
number_of :: proc(value: json.Value, key: string) -> f32 {
    found, ok := field(value, key)
    if !ok { return 0 }
    #partial switch number in found {
    case json.Float: return f32(number)
    case json.Integer: return f32(number)
    }
    return 0
}

@(private)
flag_of :: proc(value: json.Value, key: string, default: bool) -> bool {
    found, ok := field(value, key)
    if !ok { return default }
    flag, is_flag := found.(json.Boolean)
    if !is_flag { return default }
    return bool(flag)
}

@(private)
unit_to_byte :: proc(value: f32) -> u8 {
    clamped: f32 = clamp(value, 0, 1)
    return u8(clamped * 255 + 0.5)
}

// The first visible SOLID paint of a list ("fills" or "strokes"), its opacity folded into the alpha
@(private)
solid_of :: proc(node: json.Value, key: string) -> (color: Color, found: bool) {
    paints, ok := field(node, key)
    if !ok { return {}, false }
    list, is_list := paints.(json.Array)
    if !is_list { return {}, false }
    for paint in list {
        kind, _ := field(paint, "type")
        text, is_text := kind.(json.String)
        if !is_text || text != "SOLID" || !flag_of(paint, "visible", true) { continue }
        rgb, has_color := field(paint, "color")
        if !has_color { continue }
        opacity: f32 = 1
        if _, has_opacity := field(paint, "opacity"); has_opacity { opacity = number_of(paint, "opacity") }
        alpha: f32 = opacity
        if _, has_alpha := field(rgb, "a"); has_alpha { alpha *= number_of(rgb, "a") }
        return {unit_to_byte(number_of(rgb, "r")), unit_to_byte(number_of(rgb, "g")), unit_to_byte(number_of(rgb, "b")), unit_to_byte(alpha)}, true
    }
    return {}, false
}

@(private)
kind_of :: proc(type: string) -> Kind {
    switch type {
    case "DOCUMENT": return .DOCUMENT
    case "CANVAS": return .CANVAS
    case "FRAME", "GROUP", "SECTION", "COMPONENT", "COMPONENT_SET", "INSTANCE": return .FRAME
    case "TEXT": return .TEXT
    case "RECTANGLE": return .RECTANGLE
    case "LINE": return .LINE
    case "ELLIPSE": return .ELLIPSE
    }
    return .OTHER
}

@(private)
sizing_of :: proc(value: json.Value, key: string) -> Sizing {
    switch text_of(value, key, context.temp_allocator) {
    case "FIXED": return .FIXED
    case "HUG": return .HUG
    case "FILL": return .FILL
    }
    return .UNSET
}

@(private)
align_of :: proc(value: json.Value, key: string) -> Align {
    switch text_of(value, key, context.temp_allocator) {
    case "CENTER": return .CENTER
    case "MAX": return .MAX
    case "SPACE_BETWEEN": return .SPACE_BETWEEN
    }
    return .MIN
}

@(private)
nodeRead :: proc(value: json.Value, allocator := context.allocator) -> Node {
    node: Node
    node.id = text_of(value, "id", allocator)
    node.name = text_of(value, "name", allocator)
    node.type = text_of(value, "type", allocator)
    node.kind = kind_of(node.type)
    node.visible = flag_of(value, "visible", true)
    switch text_of(value, "layoutMode", context.temp_allocator) {
    case "HORIZONTAL": node.layout = .HORIZONTAL
    case "VERTICAL": node.layout = .VERTICAL
    }
    node.spacing = number_of(value, "itemSpacing")
    node.padding = {number_of(value, "paddingLeft"), number_of(value, "paddingRight"), number_of(value, "paddingTop"), number_of(value, "paddingBottom")}
    node.primary_align = align_of(value, "primaryAxisAlignItems")
    node.counter_align = align_of(value, "counterAxisAlignItems")
    node.primary_auto = text_of(value, "primaryAxisSizingMode", context.temp_allocator) == "AUTO"
    node.counter_auto = text_of(value, "counterAxisSizingMode", context.temp_allocator) == "AUTO"
    node.sizing_horizontal = sizing_of(value, "layoutSizingHorizontal")
    node.sizing_vertical = sizing_of(value, "layoutSizingVertical")
    node.grow = number_of(value, "layoutGrow")
    node.stretch = text_of(value, "layoutAlign", context.temp_allocator) == "STRETCH"
    if box, has_box := field(value, "absoluteBoundingBox"); has_box {
        node.width, node.height = number_of(box, "width"), number_of(box, "height")
    } else if size, has_size := field(value, "size"); has_size {
        node.width, node.height = number_of(size, "x"), number_of(size, "y")
    }
    node.fill, node.has_fill = solid_of(value, "fills")
    _, node.has_stroke = solid_of(value, "strokes")
    node.radius = number_of(value, "cornerRadius")
    node.characters = text_of(value, "characters", allocator)
    if style, has_style := field(value, "style"); has_style {
        node.font_size = number_of(style, "fontSize")
        node.font_family = text_of(style, "fontFamily", allocator)
        node.text_align = text_of(style, "textAlignHorizontal", allocator)
        resize: string = text_of(style, "textAutoResize", context.temp_allocator)
        node.text_fixed_width = resize != "" && resize != "WIDTH_AND_HEIGHT"
    }
    if list, has_children := field(value, "children"); has_children {
        if array, is_array := list.(json.Array); is_array {
            node.children = make([]Node, len(array), allocator)
            for child, index in array { node.children[index] = nodeRead(child, allocator) }
        }
    }
    return node
}

// Reads a file. False when the bytes are not JSON or hold neither a `document` nor `nodes`.
Parse :: proc(source: []u8, allocator := context.allocator) -> (document: Document, ok: bool) {
    value, error := json.parse(source, .JSON, false, context.temp_allocator)
    if error != .None { return {}, false }
    if found, has_document := field(value, "document"); has_document {
        document.roots = make([]Node, 1, allocator)
        document.roots[0] = nodeRead(found, allocator)
        return document, true
    }
    if found, has_nodes := field(value, "nodes"); has_nodes {
        object, is_object := found.(json.Object)
        if !is_object { return {}, false }
        document.roots = make([]Node, 0, allocator)
        list: [dynamic]Node = make([dynamic]Node, 0, len(object), allocator)
        for _, entry in object {
            if inner, has_inner := field(entry, "document"); has_inner { append(&list, nodeRead(inner, allocator)) }
        }
        document.roots = list[:]
        return document, len(list) > 0
    }
    return {}, false
}
