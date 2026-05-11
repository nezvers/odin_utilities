package element_ui

ElementStates :: enum {
    Hover,
    Pressed,
    Down,
    Released,
    Selected,
}
ElementStatesSet :: bit_set[ElementStates]

Element :: struct {
    rect: rectf,
    type: int,
    state: ElementStatesSet,
    previous_state: ElementStatesSet,
    text: string,
    children: []Element,
    ctx: rawptr, // Add your own data, plug in your element component system :D
    update: proc(^Element), // Return new state
    draw: proc(^Element),
}

// Use as object pool or dedicated buffers for specific ui layout
ElementBuffer :: struct($N:int) {
    buffer: [N]Element,
    count:int,
}

// Take a slice from pool
ElementPop :: proc(element_buffer: ^ElementBuffer($N), count:int)->(list:[]Element) {
    assert(element_buffer.count + count <= N)
    i:int = element_buffer.count
    end:int = i + count
    list = element_buffer.buffer[i:end]
    element_buffer.count = end
    return
}

// Reset buffer counter
ElementReset :: proc(element_buffer: ^ElementBuffer($N)) {
    element_buffer.count = 0
}

// Recursive, from leaves update, minimal stack use    
// sibiligs - slice where the element is inside    
// index - for the element itself inside the sibilings slice      
Update :: proc(element: ^Element, sibilings: []Element, index:int) {
    if len(element.children) > 0 {
        Update(&element.children[0], element.children, 0)
    }

    element.previous_state = element.state
    // Update after children had chance to capture input
    if element.update != nil {element.update(element)}

    if index + 1 < len(sibilings) {
        Update(&sibilings[index + 1], sibilings, index + 1)
    }
}


Draw :: proc(element: ^Element, sibilings: []Element, index:int) {
    // Draw before children
    if element.draw != nil {element.draw(element)}

    if len(element.children) > 0 {
        Draw(&element.children[0], element.children, 0)
    }

    i:int = index + 1
    if i < len(sibilings) {
        Draw(&sibilings[i], sibilings, i)
    }
}
