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
    delta_time: f32,
    down: ^Element, // like slider drag outside it's rect or not released button press
    hover: ^Element,
    pressed: ^Element,
    released: ^Element,
    selected: ^Element,
}