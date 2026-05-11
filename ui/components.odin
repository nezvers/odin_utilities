package element_ui



NeighborsComponent :: struct {
    next: ^Element,
    previous: ^Element,
    right: ^Element,
    left: ^Element,
    up: ^Element,
    down: ^Element,
}


GroupComponent :: struct {
    cursor: vec2, // mouse or virtual cursor that can be teleported over buttons
    input_down: bool, // cursor input
    // references to elements occupying states
    down: ^Element, // like slider drag outside it's rect or not released button press
    hover: ^Element,
    pressed: ^Element,
    released: ^Element,
    selected: ^Element,
}

CallbackComponent :: struct {
    down: proc(^Element), // like slider drag outside it's rect or not released button press
    hover: proc(^Element),
    pressed: proc(^Element),
    released: proc(^Element),
    selected: proc(^Element),
}