package ui

// The layout engine. A port of the layout of Clay (https://github.com/nicbarker/clay, MIT license, Nic Barker): elements are opened and
// closed in the order they are declared, a close adds up the size of the children, UiEnd then sizes every element along x, wraps the text,
// sizes along y, and walks the tree once more to give positions and to write the commands for the style.
//
// What differs from Clay: no macros (the open/close pair is `ElementOpen` / `ElementClose`, the widgets use a deferred close), the tree is
// walked by recursion instead of an explicit stack, no text measure cache (the words are measured when needed), no transitions, no
// debug view, and the output is not a list of rectangles but a list of DrawInfo for the style procs.

LAYOUT_EPSILON :: f32(0.01)

// ------------------------------------------------------------------------------------------------------------------------
// Declaring elements

// Opens an element: everything declared until the matching ElementClose is inside of it. False when a limit was hit (see UiProblems),
// the frame then shows nothing but the program carries on.
ElementOpen :: proc(ctx: ^Context, decl: Decl) -> bool {
    if ctx.overflow { return false }
    if ctx.element_count >= len(ctx.elements) || ctx.open_count >= UI_MAX_DEPTH - 1 || ctx.clip_count >= len(ctx.clip_stack) - 2 {
        ctx.problems += {.ELEMENTS_FULL}
        ctx.overflow = true
        return false
    }
    index: i32 = i32(ctx.element_count)
    ctx.element_count += 1
    parent: i32 = -1
    seed: Id = 0
    if ctx.open_count > 0 {
        parent = ctx.open_stack[ctx.open_count - 1]
        seed = ctx.seed_stack[ctx.open_count - 1]
    }
    element: ^Element = &ctx.elements[index]
    element^ = {
        id = decl.id,
        decl = decl,
        parent = parent,
        clip = elementClipTop(ctx),
        root = ctx.root_stack[ctx.root_stack_count - 1] if ctx.root_stack_count > 0 else 0,
    }
    // the max of 0 means no limit: a number that is never reached makes the arithmetic of the layout simple
    limitSizing(&element.decl.layout.size.width)
    limitSizing(&element.decl.layout.size.height)
    ctx.open_stack[ctx.open_count] = index
    ctx.seed_stack[ctx.open_count] = decl.id if decl.id != 0 else seed
    ctx.open_count += 1
    if decl.id != 0 {
        elementRegister(ctx, decl.id, index)
    }

    floating: ^Floating = &element.decl.floating
    if floating.attach_to != .NONE {
        attached_to: i32 = parent
        clip: i32 = -1
        switch floating.attach_to {
        case .PARENT:
            clip = elementClipTop(ctx)
        case .ELEMENT_WITH_ID:
            found: i32 = elementFind(ctx, floating.parent)
            if found < 0 {
                ctx.problems += {.PARENT_NOT_FOUND}
                attached_to = 0
            } else {
                attached_to = found
                clip = ctx.elements[found].clip
            }
        case .ROOT:
            attached_to = 0
        case .NONE:
        }
        if attached_to < 0 { attached_to = 0 }
        if !floating.clip_to_parent { clip = -1 }
        element.clip = clip
        ctx.clip_stack[ctx.clip_count] = clip
        ctx.clip_count += 1
        if ctx.root_count >= UI_MAX_ROOTS {
            ctx.problems += {.ROOTS_FULL}
            ctx.overflow = true
            return false
        }
        // a floating element is drawn after the root that holds its parent, whatever its z index says
        parent_root: i32 = ctx.elements[attached_to].root
        effective_z: i16 = max(floating.z_index, ctx.roots[parent_root].effective_z)
        ctx.roots[ctx.root_count] = {element = index, parent = attached_to, clip = clip, z_index = floating.z_index, effective_z = effective_z}
        element.root = i32(ctx.root_count)
        ctx.root_stack[ctx.root_stack_count] = i32(ctx.root_count)
        ctx.root_stack_count += 1
        ctx.root_count += 1
    }
    if element.decl.clip.horizontal || element.decl.clip.vertical {
        ctx.clip_stack[ctx.clip_count] = index
        ctx.clip_count += 1
    }
    return true
}

@(private)
limitSizing :: proc(axis: ^SizingAxis) {
    if axis.kind != .PERCENT && axis.max <= 0 {
        axis.max = INFINITE
    }
}

@(private)
elementClipTop :: proc(ctx: ^Context) -> i32 {
    if ctx.clip_count > 0 { return ctx.clip_stack[ctx.clip_count - 1] }
    return -1
}

// Closes the element that was opened last: its size is the sum of its children
ElementClose :: proc(ctx: ^Context) {
    if ctx.overflow { return }
    if ctx.open_count <= 0 {
        ctx.problems += {.UNBALANCED}
        return
    }
    index: i32 = ctx.open_stack[ctx.open_count - 1]
    element: ^Element = &ctx.elements[index]
    layout: ^Layout = &element.decl.layout
    clip_horizontal: bool = element.decl.clip.horizontal
    clip_vertical: bool = element.decl.clip.vertical
    is_floating: bool = element.decl.floating.attach_to != .NONE
    if clip_horizontal || clip_vertical {
        ctx.clip_count -= 1
    }
    if is_floating {
        ctx.clip_count -= 1
        ctx.root_stack_count -= 1
    }

    padding_x: f32 = layout.padding.left + layout.padding.right
    padding_y: f32 = layout.padding.top + layout.padding.bottom

    // the children, in the order they were declared, move from the buffer of open parents to their own place
    element.children_start = i32(ctx.children_count)
    count: int = int(element.children_count)
    first: int = ctx.child_buffer_count - count
    if layout.direction == .LEFT_TO_RIGHT {
        element.size.x = padding_x
        element.min_size.x = padding_x
        for i in 0 ..< count {
            child_index: i32 = ctx.child_buffer[first + i]
            child: ^Element = &ctx.elements[child_index]
            element.size.x += child.size.x
            element.size.y = max(element.size.y, child.size.y + padding_y)
            // a clipping container can shrink, so what its children need does not count
            if !clip_horizontal { element.min_size.x += child.min_size.x }
            if !clip_vertical { element.min_size.y = max(element.min_size.y, child.min_size.y + padding_y) }
            ctx.children[ctx.children_count] = child_index
            ctx.children_count += 1
        }
        gap: f32 = f32(max(count - 1, 0)) * layout.gap
        element.size.x += gap
        if !clip_horizontal { element.min_size.x += gap }
    } else {
        element.size.y = padding_y
        element.min_size.y = padding_y
        for i in 0 ..< count {
            child_index: i32 = ctx.child_buffer[first + i]
            child: ^Element = &ctx.elements[child_index]
            element.size.y += child.size.y
            element.size.x = max(element.size.x, child.size.x + padding_x)
            if !clip_vertical { element.min_size.y += child.min_size.y }
            if !clip_horizontal { element.min_size.x = max(element.min_size.x, child.min_size.x + padding_x) }
            ctx.children[ctx.children_count] = child_index
            ctx.children_count += 1
        }
        gap: f32 = f32(max(count - 1, 0)) * layout.gap
        element.size.y += gap
        if !clip_vertical { element.min_size.y += gap }
    }
    ctx.child_buffer_count -= count

    // the size limits of the declaration
    if layout.size.width.kind != .PERCENT {
        element.size.x = min(max(element.size.x, layout.size.width.min), layout.size.width.max)
        element.min_size.x = min(max(element.min_size.x, layout.size.width.min), layout.size.width.max)
    } else {
        element.size.x = 0
    }
    if layout.size.height.kind != .PERCENT {
        element.size.y = min(max(element.size.y, layout.size.height.min), layout.size.height.max)
        element.min_size.y = min(max(element.min_size.y, layout.size.height.min), layout.size.height.max)
    } else {
        element.size.y = 0
    }
    aspectUpdate(element)

    ctx.open_count -= 1
    if ctx.open_count > 0 {
        parent: ^Element = &ctx.elements[ctx.open_stack[ctx.open_count - 1]]
        if is_floating {
            parent.floating_children += 1
            return
        }
        parent.children_count += 1
        ctx.child_buffer[ctx.child_buffer_count] = index
        ctx.child_buffer_count += 1
    }
}

// A text as an element of its own, a child of the open element. It is wrapped to the width its parent gives it.
TextOpen :: proc(ctx: ^Context, text: string, config: TextConfig = {}) {
    if ctx.overflow || ctx.open_count == 0 { return }
    if ctx.element_count >= len(ctx.elements) {
        ctx.problems += {.ELEMENTS_FULL}
        ctx.overflow = true
        return
    }
    index: i32 = i32(ctx.element_count)
    ctx.element_count += 1
    parent_index: i32 = ctx.open_stack[ctx.open_count - 1]
    parent: ^Element = &ctx.elements[parent_index]

    text_config: TextConfig = config
    if text_config.font_size <= 0 { text_config.font_size = ctx.style.metrics.font_size if ctx.style != nil else 16 }
    if text_config.kind == .NONE { text_config.kind = .LABEL }

    element: ^Element = &ctx.elements[index]
    element^ = {
        is_text = true,
        parent = parent_index,
        clip = elementClipTop(ctx),
        root = ctx.root_stack[ctx.root_stack_count - 1] if ctx.root_stack_count > 0 else 0,
        text = {text = text, config = text_config},
    }
    ctx.child_buffer[ctx.child_buffer_count] = index
    ctx.child_buffer_count += 1

    preferred, min_width, newlines := textMeasure(ctx, text, text_config)
    line_height: f32 = text_config.line_height if text_config.line_height > 0 else preferred.y
    element.text.preferred = preferred
    element.text.contains_newlines = newlines
    element.size = {preferred.x, line_height}
    element.min_size = {min_width, line_height}
    parent.children_count += 1
}

// An element finds its place in the table by its id
@(private)
elementRegister :: proc(ctx: ^Context, id: Id, index: i32) {
    slot: int = int(u32(id) % u32(len(ctx.element_slots)))
    for _ in 0 ..< len(ctx.element_slots) {
        other: i32 = ctx.element_slots[slot]
        if other == 0 {
            ctx.element_slots[slot] = index + 1
            return
        }
        if ctx.elements[other - 1].id == id {
            ctx.problems += {.DUPLICATE_ID}
            return
        }
        slot = (slot + 1) % len(ctx.element_slots)
    }
}

@(private)
elementFind :: proc(ctx: ^Context, id: Id) -> i32 {
    if id == 0 { return -1 }
    slot: int = int(u32(id) % u32(len(ctx.element_slots)))
    for _ in 0 ..< len(ctx.element_slots) {
        other: i32 = ctx.element_slots[slot]
        if other == 0 { return -1 }
        if ctx.elements[other - 1].id == id { return other - 1 }
        slot = (slot + 1) % len(ctx.element_slots)
    }
    return -1
}

@(private)
aspectUpdate :: proc(element: ^Element) {
    if element.decl.aspect_ratio != 0 {
        if element.size.x == 0 && element.size.y != 0 {
            element.size.x = element.size.y * element.decl.aspect_ratio
        } else if element.size.x != 0 && element.size.y == 0 {
            element.size.y = element.size.x / element.decl.aspect_ratio
        }
    }
}

// ------------------------------------------------------------------------------------------------------------------------
// Measuring text

@(private)
Word :: struct {
    start: int,
    length: int,        // with the space that ends the word, 0 for a new line
    width: f32,
}

// The next word of a text from `position`, or false at the end. A word ends at a space (the space is part of it) or at a new line
// (which is a word of length 0). Words are measured when they are needed: there is no cache.
@(private)
textNextWord :: proc(ctx: ^Context, text: string, position: int, font_size: f32, space_width: f32) -> (word: Word, position_after: int, ok: bool) {
    if position >= len(text) { return {}, position, false }
    end: int = position
    for end < len(text) && text[end] != ' ' && text[end] != '\n' {
        end += 1
    }
    measured: f32 = 0
    if end > position {
        measured = ctx.measure(ctx, text[position:end], font_size).x
    }
    if end >= len(text) {
        return {start = position, length = end - position, width = measured}, end, true
    }
    if text[end] == ' ' {
        return {start = position, length = end - position + 1, width = measured + space_width}, end + 1, true
    }
    // a new line: the text before it first (as a word without the end), the new line itself next time
    if end > position {
        return {start = position, length = end - position, width = measured}, end, true
    }
    return {start = end + 1, length = 0, width = 0}, end + 1, true
}

// How a text measures as one line (the longest line when it has new lines), and the width of its longest word
@(private)
textMeasure :: proc(ctx: ^Context, text: string, config: TextConfig) -> (preferred: Vec2, min_width: f32, newlines: bool) {
    if ctx.measure == nil {
        ctx.problems += {.NO_MEASURE}
        return {}, 0, false
    }
    space_width: f32 = ctx.measure(ctx, " ", config.font_size).x
    line_width: f32 = 0
    widest: f32 = 0
    height: f32 = ctx.measure(ctx, "A", config.font_size).y
    position: int = 0
    for {
        word, next, ok := textNextWord(ctx, text, position, config.font_size, space_width)
        if !ok { break }
        position = next
        if word.length == 0 {
            newlines = true
            widest = max(widest, line_width)
            line_width = 0
            continue
        }
        // the space at the end of a word does not count for the longest word
        word_width: f32 = word.width
        if text[word.start + word.length - 1] == ' ' { word_width -= space_width }
        min_width = max(min_width, word_width)
        line_width += word.width
    }
    widest = max(widest, line_width)
    return {widest, height}, min_width, newlines
}

// ------------------------------------------------------------------------------------------------------------------------
// The calculation of the frame: sizes, text lines, positions, commands

@(private)
sizingOf :: proc(element: ^Element, x_axis: bool) -> SizingAxis {
    if element.is_text { return {} }
    return element.decl.layout.size.width if x_axis else element.decl.layout.size.height
}

@(private)
sizeAxisOf :: proc(element: ^Element, x_axis: bool) -> ^f32 {
    return &element.size.x if x_axis else &element.size.y
}

@(private)
floatEqual :: proc(a: f32, b: f32) -> bool {
    return abs(a - b) < LAYOUT_EPSILON
}

// Sizes the children of `parent_index` along one axis and then the children of those: fit stays, percent takes its part, grow takes the
// rest, and when there is too little room everything that may shrink does (the biggest first)
@(private)
sizeChildren :: proc(ctx: ^Context, parent_index: i32, x_axis: bool) {
    parent: ^Element = &ctx.elements[parent_index]
    layout: ^Layout = &parent.decl.layout
    count: int = int(parent.children_count)
    children: []i32 = ctx.children[parent.children_start:int(parent.children_start) + count]

    parent_size: f32 = sizeAxisOf(parent, x_axis)^
    padding: f32 = layout.padding.left + layout.padding.right if x_axis else layout.padding.top + layout.padding.bottom
    inner_content: f32 = 0
    padding_and_gaps: f32 = padding
    along_axis: bool = (x_axis && layout.direction == .LEFT_TO_RIGHT) || (!x_axis && layout.direction == .TOP_TO_BOTTOM)
    clips_axis: bool = (x_axis && parent.decl.clip.horizontal) || (!x_axis && parent.decl.clip.vertical)
    grow_count: int = 0
    resizable: []i32 = ctx.scratch
    resizable_count: int = 0
    first: bool = true

    for child_index in children {
        child: ^Element = &ctx.elements[child_index]
        sizing: SizingAxis = sizingOf(child, x_axis)
        child_size: f32 = sizeAxisOf(child, x_axis)^
        if sizing.kind != .PERCENT && sizing.kind != .FIXED && (!child.is_text || child.text.config.wrap == .WORDS) {
            resizable[resizable_count] = child_index
            resizable_count += 1
        }
        if along_axis {
            inner_content += 0 if sizing.kind == .PERCENT else child_size
            if sizing.kind == .GROW { grow_count += 1 }
            if !first {
                inner_content += layout.gap
                padding_and_gaps += layout.gap
            }
        } else {
            inner_content = max(child_size, inner_content)
        }
        first = false
    }

    // percentages of what is inside
    for child_index in children {
        child: ^Element = &ctx.elements[child_index]
        sizing: SizingAxis = sizingOf(child, x_axis)
        if sizing.kind == .PERCENT {
            size: ^f32 = sizeAxisOf(child, x_axis)
            size^ = (parent_size - padding_and_gaps) * sizing.percent
            if along_axis { inner_content += size^ }
            aspectUpdate(child)
        }
    }

    if along_axis {
        to_distribute: f32 = parent_size - padding - inner_content
        if to_distribute < 0 {
            // too much content: shrink what may shrink, the biggest first. A clipping container lets its content be bigger.
            if !clips_axis {
                for to_distribute < -LAYOUT_EPSILON && resizable_count > 0 {
                    largest: f32 = 0
                    second_largest: f32 = 0
                    to_add: f32 = to_distribute
                    for i in 0 ..< resizable_count {
                        child_size: f32 = sizeAxisOf(&ctx.elements[resizable[i]], x_axis)^
                        if floatEqual(child_size, largest) { continue }
                        if child_size > largest {
                            second_largest = largest
                            largest = child_size
                        }
                        if child_size < largest {
                            second_largest = max(second_largest, child_size)
                            to_add = second_largest - largest
                        }
                    }
                    to_add = max(to_add, to_distribute / f32(resizable_count))
                    for i := 0; i < resizable_count; i += 1 {
                        child: ^Element = &ctx.elements[resizable[i]]
                        size: ^f32 = sizeAxisOf(child, x_axis)
                        min_size: f32 = child.min_size.x if x_axis else child.min_size.y
                        previous: f32 = size^
                        if floatEqual(size^, largest) {
                            size^ += to_add
                            if size^ <= min_size {
                                size^ = min_size
                                resizable_count -= 1
                                resizable[i] = resizable[resizable_count]
                                i -= 1
                            }
                            to_distribute -= size^ - previous
                        }
                    }
                }
            }
        } else if to_distribute > 0 && grow_count > 0 {
            // room left: the smallest grow elements grow first, until all are even or at their max
            for i := 0; i < resizable_count; i += 1 {
                if sizingOf(&ctx.elements[resizable[i]], x_axis).kind != .GROW {
                    resizable_count -= 1
                    resizable[i] = resizable[resizable_count]
                    i -= 1
                }
            }
            for to_distribute > LAYOUT_EPSILON && resizable_count > 0 {
                smallest: f32 = INFINITE
                second_smallest: f32 = INFINITE
                to_add: f32 = to_distribute
                for i in 0 ..< resizable_count {
                    child_size: f32 = sizeAxisOf(&ctx.elements[resizable[i]], x_axis)^
                    if floatEqual(child_size, smallest) { continue }
                    if child_size < smallest {
                        second_smallest = smallest
                        smallest = child_size
                    }
                    if child_size > smallest {
                        second_smallest = min(second_smallest, child_size)
                        to_add = second_smallest - smallest
                    }
                }
                to_add = min(to_add, to_distribute / f32(resizable_count))
                for i := 0; i < resizable_count; i += 1 {
                    child: ^Element = &ctx.elements[resizable[i]]
                    size: ^f32 = sizeAxisOf(child, x_axis)
                    max_size: f32 = sizingOf(child, x_axis).max
                    previous: f32 = size^
                    if floatEqual(size^, smallest) {
                        size^ += to_add
                        if size^ >= max_size {
                            size^ = max_size
                            resizable_count -= 1
                            resizable[i] = resizable[resizable_count]
                            i -= 1
                        }
                        to_distribute -= size^ - previous
                    }
                }
            }
        }
    } else {
        // across the layout direction: grow takes all the room, everything stays inside (a clipping container may be exceeded)
        for i in 0 ..< resizable_count {
            child: ^Element = &ctx.elements[resizable[i]]
            sizing: SizingAxis = sizingOf(child, x_axis)
            min_size: f32 = child.min_size.x if x_axis else child.min_size.y
            size: ^f32 = sizeAxisOf(child, x_axis)
            max_size: f32 = parent_size - padding
            if clips_axis { max_size = max(max_size, inner_content) }
            if sizing.kind == .GROW {
                size^ = min(max_size, sizing.max)
            }
            size^ = max(min_size, min(size^, max_size))
        }
    }

    for child_index in children {
        child: ^Element = &ctx.elements[child_index]
        if !child.is_text && child.children_count > 0 {
            sizeChildren(ctx, child_index, x_axis)
        }
    }
}

// All the roots along one axis: a floating root first takes the size of the element it is attached to when it grows or has a percent
@(private)
sizeAxis :: proc(ctx: ^Context, x_axis: bool) {
    for r in 0 ..< ctx.root_count {
        root: Root = ctx.roots[r]
        element: ^Element = &ctx.elements[root.element]
        layout: ^Layout = &element.decl.layout
        sizing: SizingAxis = layout.size.width if x_axis else layout.size.height
        size: ^f32 = sizeAxisOf(element, x_axis)
        if element.decl.floating.attach_to != .NONE && root.parent >= 0 {
            parent_size: f32 = sizeAxisOf(&ctx.elements[root.parent], x_axis)^
            #partial switch sizing.kind {
            case .GROW: size^ = parent_size
            case .PERCENT: size^ = parent_size * sizing.percent
            }
        }
        if sizing.kind != .PERCENT {
            size^ = min(max(size^, sizing.min), sizing.max)
        }
        sizeChildren(ctx, root.element, x_axis)
    }
}

// Breaks the text elements into lines for the width they got, and grows their height to the lines
@(private)
textWrapAll :: proc(ctx: ^Context) {
    for i in 0 ..< ctx.element_count {
        element: ^Element = &ctx.elements[i]
        if !element.is_text { continue }
        data: ^TextData = &element.text
        config: TextConfig = data.config
        data.line_start = i32(ctx.line_count)
        data.line_count = 0
        line_height: f32 = config.line_height if config.line_height > 0 else data.preferred.y

        if !data.contains_newlines && data.preferred.x <= element.size.x + LAYOUT_EPSILON {
            if ctx.line_count < len(ctx.lines) {
                ctx.lines[ctx.line_count] = {start = 0, length = i32(len(data.text)), width = data.preferred.x}
                ctx.line_count += 1
                data.line_count = 1
            } else {
                ctx.problems += {.LINES_FULL}
            }
            element.size.y = line_height
            continue
        }

        space_width: f32 = ctx.measure(ctx, " ", config.font_size).x
        line_width: f32 = 0
        line_length: int = 0
        line_start: int = 0
        position: int = 0
        word, next, has_word := textNextWord(ctx, data.text, 0, config.font_size, space_width)
        position = next
        for has_word {
            if ctx.line_count >= len(ctx.lines) {
                ctx.problems += {.LINES_FULL}
                break
            }
            if line_length == 0 && line_width + word.width > element.size.x {
                // one word that is wider than the line: shown anyway
                textAddLine(ctx, data, word.start, word.length, word.width)
                line_start = word.start + word.length
                word, next, has_word = textNextWord(ctx, data.text, position, config.font_size, space_width)
                position = next
            } else if word.length == 0 || line_width + word.width > element.size.x {
                // the line is full (or ends with a new line): written without the space at its end
                final_space: bool = line_length > 0 && data.text[line_start + line_length - 1] == ' '
                textAddLine(ctx, data, line_start, line_length - (1 if final_space else 0), line_width - (space_width if final_space else 0))
                line_start = word.start
                if line_length == 0 || word.length == 0 {
                    word, next, has_word = textNextWord(ctx, data.text, position, config.font_size, space_width)
                    position = next
                }
                line_width = 0
                line_length = 0
            } else {
                line_width += word.width
                line_length += word.length
                word, next, has_word = textNextWord(ctx, data.text, position, config.font_size, space_width)
                position = next
            }
        }
        if line_length > 0 && ctx.line_count < len(ctx.lines) {
            textAddLine(ctx, data, line_start, line_length, line_width)
        }
        element.size.y = line_height * f32(data.line_count)
    }
}

@(private)
textAddLine :: proc(ctx: ^Context, data: ^TextData, start: int, length: int, width: f32) {
    if ctx.line_count >= len(ctx.lines) { return }
    ctx.lines[ctx.line_count] = {start = i32(start), length = i32(max(length, 0)), width = width}
    ctx.line_count += 1
    data.line_count += 1
}

// After text is wrapped and aspect ratios are scaled the heights of the parents have to follow
@(private)
heightsPropagate :: proc(ctx: ^Context, index: i32) {
    element: ^Element = &ctx.elements[index]
    if element.is_text || element.children_count == 0 { return }
    count: int = int(element.children_count)
    children: []i32 = ctx.children[element.children_start:int(element.children_start) + count]
    for child_index in children {
        heightsPropagate(ctx, child_index)
    }
    layout: ^Layout = &element.decl.layout
    padding_y: f32 = layout.padding.top + layout.padding.bottom
    if layout.direction == .LEFT_TO_RIGHT {
        for child_index in children {
            child: ^Element = &ctx.elements[child_index]
            with_padding: f32 = max(child.size.y + padding_y, element.size.y)
            element.size.y = min(max(with_padding, layout.size.height.min), layout.size.height.max)
        }
    } else {
        content: f32 = padding_y
        for child_index in children {
            content += ctx.elements[child_index].size.y
        }
        content += f32(max(count - 1, 0)) * layout.gap
        element.size.y = min(max(content, layout.size.height.min), layout.size.height.max)
    }
}

@(private)
attachFactor :: proc(point: AttachPoint) -> Vec2 {
    switch point {
    case .LEFT_TOP: return {0, 0}
    case .LEFT_CENTER: return {0, 0.5}
    case .LEFT_BOTTOM: return {0, 1}
    case .CENTER_TOP: return {0.5, 0}
    case .CENTER_CENTER: return {0.5, 0.5}
    case .CENTER_BOTTOM: return {0.5, 1}
    case .RIGHT_TOP: return {1, 0}
    case .RIGHT_CENTER: return {1, 0.5}
    case .RIGHT_BOTTOM: return {1, 1}
    }
    return {0, 0}
}

// Does everything UiEnd needs of the layout: sizes, positions, the commands and the hit boxes for the pointer of the next frame
LayoutCalculate :: proc(ctx: ^Context) {
    sizeAxis(ctx, true)
    textWrapAll(ctx)
    for i in 0 ..< ctx.element_count {
        element: ^Element = &ctx.elements[i]
        if !element.is_text && element.decl.aspect_ratio != 0 {
            element.size.y = element.size.x / element.decl.aspect_ratio
            element.decl.layout.size.height.max = element.size.y
        }
    }
    for r in 0 ..< ctx.root_count {
        heightsPropagate(ctx, ctx.roots[r].element)
    }
    sizeAxis(ctx, false)
    for i in 0 ..< ctx.element_count {
        element: ^Element = &ctx.elements[i]
        if !element.is_text && element.decl.aspect_ratio != 0 {
            element.size.x = element.decl.aspect_ratio * element.size.y
        }
    }

    // the layers by z index, equal ones keep the order they were declared in (insertion sort: there are only a few)
    for i in 1 ..< ctx.root_count {
        current: Root = ctx.roots[i]
        j: int = i - 1
        for j >= 0 && ctx.roots[j].effective_z > current.effective_z {
            ctx.roots[j + 1] = ctx.roots[j]
            j -= 1
        }
        ctx.roots[j + 1] = current
    }

    ctx.command_count = 0
    ctx.hit_count = 0
    screen_rect: Rect = {0, 0, ctx.screen.x, ctx.screen.y}
    for r in 0 ..< ctx.root_count {
        root: Root = ctx.roots[r]
        element: ^Element = &ctx.elements[root.element]
        position: Vec2 = {}
        clip_rect: Rect = RECT_INFINITE
        if element.decl.floating.attach_to != .NONE && root.parent >= 0 {
            floating: Floating = element.decl.floating
            parent: Rect = ctx.elements[root.parent].rect
            parent_factor: Vec2 = attachFactor(floating.parent_point)
            element_factor: Vec2 = attachFactor(floating.element_point)
            position = {
                parent.x + parent.z * parent_factor.x - element.size.x * element_factor.x + floating.offset.x,
                parent.y + parent.w * parent_factor.y - element.size.y * element_factor.y + floating.offset.y,
            }
        }
        clipped: bool = false
        if root.clip >= 0 {
            clip_rect = ctx.elements[root.clip].clip_rect
            clipped = true
            layoutPushClip(ctx, RectIntersect(clip_rect, screen_rect))
        }
        placeElement(ctx, root.element, position, clip_rect)
        if clipped {
            layoutPopClip(ctx)
        }
    }
}

@(private)
layoutPushClip :: proc(ctx: ^Context, rect: Rect) {
    layoutCommand(ctx, {kind = .CLIP_BEGIN, info = {rect = rect}})
}

@(private)
layoutPopClip :: proc(ctx: ^Context) {
    layoutCommand(ctx, {kind = .CLIP_END})
}

@(private)
layoutCommand :: proc(ctx: ^Context, command: Command) {
    if ctx.command_count >= len(ctx.commands) {
        ctx.problems += {.COMMANDS_FULL}
        return
    }
    ctx.commands[ctx.command_count] = command
    ctx.command_count += 1
}

// Gives the element its place and writes what the style needs to draw it, then does the same for its children
@(private)
placeElement :: proc(ctx: ^Context, index: i32, position: Vec2, clip_rect: Rect) {
    element: ^Element = &ctx.elements[index]
    rect: Rect = {position.x, position.y, element.size.x, element.size.y}
    screen_rect: Rect = {0, 0, ctx.screen.x, ctx.screen.y}
    element.rect = rect
    element.clip_rect = clip_rect

    if element.is_text {
        textCommands(ctx, element, rect, clip_rect)
        return
    }

    layout: ^Layout = &element.decl.layout
    clips: bool = element.decl.clip.horizontal || element.decl.clip.vertical
    own_clip: Rect = clip_rect
    if clips {
        // a container that clips only one way keeps the other way open
        limit: Rect = rect
        if !element.decl.clip.horizontal { limit.x = RECT_INFINITE.x; limit.z = INFINITE }
        if !element.decl.clip.vertical { limit.y = RECT_INFINITE.y; limit.w = INFINITE }
        own_clip = RectIntersect(clip_rect, limit)
        element.clip_rect = own_clip
    }
    // a floating element is bigger than its content by `expand`: the children stay where they are
    shown: Rect = rect
    floating: Floating = element.decl.floating
    if floating.attach_to != .NONE {
        shown = {rect.x - floating.expand.x, rect.y - floating.expand.y, rect.z + floating.expand.x * 2, rect.w + floating.expand.y * 2}
        element.rect = shown
    }

    // hit box for the pointer of the next frame
    kinds: HitKinds = element.decl.hit
    if floating.attach_to != .NONE && floating.capture { kinds += {.BLOCKER} }
    if kinds != {} && ctx.hit_count < len(ctx.hits) {
        ctx.hits[ctx.hit_count] = {id = element.id, rect = shown, clip_rect = own_clip, kinds = kinds}
        ctx.hit_count += 1
    }

    info: DrawInfo = element.decl.draw
    visible: bool = !ctx.culling || RectOverlaps(shown, RectIntersect(own_clip, {0, 0, ctx.screen.x, ctx.screen.y}))
    if clips {
        layoutPushClip(ctx, RectIntersect(own_clip, screen_rect))
    }
    if info.kind != .NONE && visible {
        info.id = element.id
        info.rect = shown
        drawInfoInteraction(ctx, &info)
        layoutCommand(ctx, {kind = .DRAW, info = info})
    }

    // children: the alignment of the free room, then one after the other
    count: int = int(element.children_count)
    children: []i32 = ctx.children[element.children_start:int(element.children_start) + count]
    gap_total: f32 = f32(max(count - 1, 0)) * layout.gap
    content: Vec2 = {}
    if layout.direction == .LEFT_TO_RIGHT {
        for child_index in children {
            child: ^Element = &ctx.elements[child_index]
            content.x += child.size.x
            content.y = max(content.y, child.size.y)
        }
        content.x += gap_total
    } else {
        for child_index in children {
            child: ^Element = &ctx.elements[child_index]
            content.x = max(content.x, child.size.x)
            content.y += child.size.y
        }
        content.y += gap_total
    }
    next: Vec2 = {layout.padding.left, layout.padding.top}
    if layout.direction == .LEFT_TO_RIGHT {
        extra: f32 = element.size.x - layout.padding.left - layout.padding.right - content.x
        switch layout.align.x {
        case .LEFT: extra = 0
        case .CENTER: extra *= 0.5
        case .RIGHT:
        }
        next.x += max(0, extra)
    } else {
        extra: f32 = element.size.y - layout.padding.top - layout.padding.bottom - content.y
        switch layout.align.y {
        case .TOP: extra = 0
        case .CENTER: extra *= 0.5
        case .BOTTOM:
        }
        next.y += max(0, extra)
    }
    element.content_size = {content.x + layout.padding.left + layout.padding.right, content.y + layout.padding.top + layout.padding.bottom}
    state: ^WidgetState = stateFind(ctx, element.id)
    if state != nil && element.decl.hit != {} {
        state.rect = shown
        state.content_size = element.content_size
    }

    scroll: Vec2 = element.decl.clip.offset if clips else {}
    for child_index in children {
        child: ^Element = &ctx.elements[child_index]
        // across the direction of the layout: the alignment inside of the free room
        if layout.direction == .LEFT_TO_RIGHT {
            next.y = layout.padding.top
            around: f32 = element.size.y - layout.padding.top - layout.padding.bottom - child.size.y
            switch layout.align.y {
            case .TOP:
            case .CENTER: next.y += around * 0.5
            case .BOTTOM: next.y += around
            }
        } else {
            next.x = layout.padding.left
            around: f32 = element.size.x - layout.padding.left - layout.padding.right - child.size.x
            switch layout.align.x {
            case .LEFT:
            case .CENTER: next.x += around * 0.5
            case .RIGHT: next.x += around
            }
        }
        child_position: Vec2 = {rect.x + next.x + scroll.x, rect.y + next.y + scroll.y}
        placeElement(ctx, child_index, child_position, own_clip)
        if layout.direction == .LEFT_TO_RIGHT {
            next.x += child.size.x + layout.gap
        } else {
            next.y += child.size.y + layout.gap
        }
    }

    // a scrolling area shows how far it is scrolled, inside of its own clip
    if info.kind == .SCROLL_AREA && clips && element.decl.clip.vertical && visible {
        view: f32 = shown.w
        content_height: f32 = element.content_size.y
        if content_height > view + LAYOUT_EPSILON {
            width: f32 = ctx.style.metrics.scrollbar_width
            range: f32 = content_height - view
            bar: DrawInfo = {
                kind = .SCROLLBAR,
                id = element.id,
                rect = {shown.x + shown.z - width, shown.y, width, shown.w},
                value = clamp(-element.decl.clip.offset.y / range, 0, 1),
                ratio = clamp(view / content_height, 0, 1),
            }
            layoutCommand(ctx, {kind = .DRAW, info = bar})
        }
    }
    if clips {
        layoutPopClip(ctx)
    }
}

// What the context knows of a widget that the declaration does not: the pointer, the keyboard and the fades
@(private)
drawInfoInteraction :: proc(ctx: ^Context, info: ^DrawInfo) {
    if info.id == 0 { return }
    if ctx.hover == info.id && (ctx.active == 0 || ctx.active == info.id) { info.flags += {.HOVERED} }
    if ctx.active == info.id { info.flags += {.PRESSED} }
    if ctx.focus == info.id { info.flags += {.FOCUSED} }
    state: ^WidgetState = stateFind(ctx, info.id)
    if state != nil {
        info.hover = state.hover
        info.press = state.press
    }
}

// A text element is one command per line
@(private)
textCommands :: proc(ctx: ^Context, element: ^Element, rect: Rect, clip_rect: Rect) {
    data: ^TextData = &element.text
    visible: bool = !ctx.culling || RectOverlaps(rect, RectIntersect(clip_rect, {0, 0, ctx.screen.x, ctx.screen.y}))
    if !visible { return }
    config: TextConfig = data.config
    natural_height: f32 = data.preferred.y
    line_height: f32 = config.line_height if config.line_height > 0 else natural_height
    y: f32 = (line_height - natural_height) * 0.5
    for i in 0 ..< int(data.line_count) {
        line: TextLine = ctx.lines[int(data.line_start) + i]
        if line.length == 0 {
            y += line_height
            continue
        }
        offset: f32 = rect.z - line.width
        switch config.align {
        case .LEFT: offset = 0
        case .CENTER: offset *= 0.5
        case .RIGHT:
        }
        text: string = data.text[line.start:line.start + line.length]
        layoutCommand(ctx, {kind = .DRAW, info = {
            kind = config.kind,
            rect = {rect.x + offset, rect.y + y, line.width, natural_height},
            text = text,
            name = data.text,
            font_size = config.font_size,
            align = config.align,
            user = config.user,
        }})
        y += line_height
    }
}
