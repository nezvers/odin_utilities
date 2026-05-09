package retained_ui

rectf :: [4]f32
vec2 :: [2]f32

Element :: struct {
    rect: rectf,
    type: int,
    state:int,
    text: string,
    children: []Element,
    ctx: ^ElementContext,
    update: proc(^Element),
    draw: proc(^Element),
}

// Use as object pool or dedicated buffers for specific ui layout
ElementBuffer :: struct($N:int) {
    buffer: [N]Element,
    count:int,
}

ElementContext :: struct {
    held: ^Element, // like slider drag outside it's rect
    hover: ^Element,
}

ElementPop :: proc(element_buffer: ^ElementBuffer($N), count:int)->(list:[]Element) {
    assert(element_buffer.count + count <= N)
    i:int = element_buffer.count
    end:int = i + count
    list = element_buffer.buffer[i:end]
    element_buffer.count = end
    return
}

ElementReset :: proc(element_buffer: ^ElementBuffer($N)) {
    element_buffer.count = 0
}

// TODO: handle information about held element
Update :: proc(element: ^Element, sibilings: []Element, index:int, ctx: ^ElementContext) {
    if len(element.children) > 0 {
        Update(&element.children[0], element.children, 0, ctx)
    }
    // Update after children had chance to capture input
    if element.update != nil {element.update(element)}

    i:int = index + 1
    if i < len(sibilings) {
        Update(&sibilings[i], sibilings, i, ctx)
    }
}


Draw :: proc(element: ^Element, sibilings: []Element, index:int, ctx: ^ElementContext) {
    // Draw children on top
    if element.draw != nil {element.draw(element)}

    if len(element.children) > 0 {
        Draw(&element.children[0], element.children, 0, ctx)
    }

    i:int = index + 1
    if i < len(sibilings) {
        Draw(&sibilings[i], sibilings, i, ctx)
    }
}

