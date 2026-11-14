package box2d_odin
import "core:testing"

// Framework agnostic input snapshot. The demo of each framework fills it once per frame.
MouseButton :: enum {
    LEFT,
    RIGHT,
    MIDDLE,
}

// Keys used by the Box2D samples and the sample browser
Key :: enum {
    NONE,
    A, B, C, D, E, F, G, L, O, P, Q, R, S, W, X, Z,
    N0, N1, N2, N3, N4, N5, N6, N7, N8, N9,
    SPACE,
    COMMA,
    PERIOD,
    TAB,
    ESCAPE,
    LEFT, RIGHT, UP, DOWN,
    LEFT_SHIFT, RIGHT_SHIFT,
    LEFT_CONTROL, RIGHT_CONTROL,
}

Input :: struct {
    mouse: Vec2,            // screen pixels
    mouse_delta: Vec2,
    wheel: f32,             // positive = scroll up
    mouse_down: [MouseButton]bool,
    mouse_pressed: [MouseButton]bool,
    mouse_released: [MouseButton]bool,
    key_down: [Key]bool,
    key_pressed: [Key]bool,
}

InputShift :: proc(input: ^Input) -> bool {
    return input.key_down[.LEFT_SHIFT] || input.key_down[.RIGHT_SHIFT]
}

InputControl :: proc(input: ^Input) -> bool {
    return input.key_down[.LEFT_CONTROL] || input.key_down[.RIGHT_CONTROL]
}

// --- Tests ---

@(test)
test_input_modifiers :: proc(t: ^testing.T) {
    input: Input
    testing.expect(t, !InputShift(&input) && !InputControl(&input))
    input.key_down[.LEFT_SHIFT] = true
    testing.expect(t, InputShift(&input))
    testing.expect(t, !InputControl(&input))
    input.key_down[.LEFT_SHIFT] = false
    input.key_down[.RIGHT_SHIFT] = true
    testing.expect(t, InputShift(&input), "either shift counts")
    input.key_down[.RIGHT_CONTROL] = true
    testing.expect(t, InputControl(&input), "either control counts")
}
