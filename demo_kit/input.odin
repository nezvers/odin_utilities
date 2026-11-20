package demo_kit

// The input of one frame, as plain data. A backend fills it from the real devices, a Player (sim.odin) can fill it from a script, so
// the demo code does not know which one it is reading. Written like the rest of the kit: no allocations, no pointers.

Vec2 :: [2]f32
Rect :: [4]f32          // x, y, width, height
Color :: [4]u8

Key :: enum u8 {
    None,
    A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z,
    N0, N1, N2, N3, N4, N5, N6, N7, N8, N9,
    SPACE, ENTER, ESCAPE, TAB, BACKSPACE, DELETE, INSERT,
    LEFT, RIGHT, UP, DOWN,
    HOME, END, PAGE_UP, PAGE_DOWN,
    LEFT_SHIFT, RIGHT_SHIFT, LEFT_CTRL, RIGHT_CTRL, LEFT_ALT, RIGHT_ALT,
    COMMA, PERIOD, MINUS, EQUAL, SLASH, LEFT_BRACKET, RIGHT_BRACKET,
    F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,
}
KeySet :: bit_set[Key; u128]

MouseButton :: enum u8 {
    LEFT,
    RIGHT,
    MIDDLE,
}
MouseButtons :: bit_set[MouseButton; u8]

// The buttons of the first gamepad, named by where they are (a face button is "down" for the A of an Xbox pad and the cross of a PlayStation pad)
PadButton :: enum u8 {
    DPAD_UP, DPAD_DOWN, DPAD_LEFT, DPAD_RIGHT,
    FACE_DOWN, FACE_RIGHT, FACE_LEFT, FACE_UP,
    LEFT_SHOULDER, RIGHT_SHOULDER, LEFT_TRIGGER, RIGHT_TRIGGER,
    LEFT_STICK, RIGHT_STICK,
    BACK, START,
}
PadButtons :: bit_set[PadButton; u32]

TEXT_CAPACITY :: 16

Input :: struct {
    keys_down: KeySet,                  // held now
    keys_pressed: KeySet,               // went down this frame
    keys_released: KeySet,              // went up this frame
    mouse_position: Vec2,               // in pixels of the window
    mouse_delta: Vec2,
    mouse_wheel: f32,                   // lines scrolled this frame, up is positive
    mouse_down: MouseButtons,
    mouse_pressed: MouseButtons,
    mouse_released: MouseButtons,
    pad_down: PadButtons,               // buttons of the first gamepad: held now
    pad_pressed: PadButtons,            // went down this frame
    text: [TEXT_CAPACITY]u8,            // characters typed this frame (ASCII), for text fields
    text_count: u8,
}

KeyDown :: proc(input: ^Input, key: Key) -> bool {
    return key in input.keys_down
}

KeyPressed :: proc(input: ^Input, key: Key) -> bool {
    return key in input.keys_pressed
}

KeyReleased :: proc(input: ^Input, key: Key) -> bool {
    return key in input.keys_released
}

MouseDown :: proc(input: ^Input, button: MouseButton = .LEFT) -> bool {
    return button in input.mouse_down
}

MousePressed :: proc(input: ^Input, button: MouseButton = .LEFT) -> bool {
    return button in input.mouse_pressed
}

MouseReleased :: proc(input: ^Input, button: MouseButton = .LEFT) -> bool {
    return button in input.mouse_released
}

// The typed characters of this frame
InputText :: proc(input: ^Input) -> string {
    return string(input.text[:input.text_count])
}

// -1, 0 or 1 from a pair of keys: AxisKeys(input, .A, .D) is -1 while A is held
AxisKeys :: proc(input: ^Input, negative: Key, positive: Key) -> f32 {
    value: f32 = 0
    if negative in input.keys_down { value -= 1 }
    if positive in input.keys_down { value += 1 }
    return value
}

// What changed between the held state of the last frame and this one. A backend that only knows what is held now calls this.
InputFromHeld :: proc(input: ^Input, previous_keys: KeySet, previous_mouse: MouseButtons) {
    input.keys_pressed = input.keys_down - previous_keys
    input.keys_released = previous_keys - input.keys_down
    input.mouse_pressed = input.mouse_down - previous_mouse
    input.mouse_released = previous_mouse - input.mouse_down
}

// A keyboard key is shifted/ctrl: the demos want "any of the two"
ShiftDown :: proc(input: ^Input) -> bool {
    return .LEFT_SHIFT in input.keys_down || .RIGHT_SHIFT in input.keys_down
}

CtrlDown :: proc(input: ^Input) -> bool {
    return .LEFT_CTRL in input.keys_down || .RIGHT_CTRL in input.keys_down
}

PointInRect :: proc(point: Vec2, rect: Rect) -> bool {
    return point.x >= rect.x && point.x <= rect.x + rect.z && point.y >= rect.y && point.y <= rect.y + rect.w
}
