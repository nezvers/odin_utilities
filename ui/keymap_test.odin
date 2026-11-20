#+build !js
package ui

import "core:testing"

// A pretend frame: the inputs that went down are a list
@(private = "file")
Down :: struct {
    keys: [8]u16,
    count: int,
    pad: [4]u16,
    pad_count: int,
    mouse: [2]u16,
    mouse_count: int,
}

@(private = "file")
probe :: proc(user: rawptr, device: InputDevice, code: u16) -> bool {
    down: ^Down = cast(^Down)user
    switch device {
    case .KEYBOARD:
        for i in 0 ..< down.count { if down.keys[i] == code { return true } }
    case .GAMEPAD:
        for i in 0 ..< down.pad_count { if down.pad[i] == code { return true } }
    case .MOUSE:
        for i in 0 ..< down.mouse_count { if down.mouse[i] == code { return true } }
    case .NONE:
    }
    return false
}

@(test)
test_a_key_map_turns_what_went_down_into_actions_by_its_modifiers :: proc(t: ^testing.T) {
    KEY_TAB, KEY_C, KEY_A :: 9, 67, 65
    table: KeyMap
    KeyMapSet(&table, .FOCUS_NEXT, 0, {device = .KEYBOARD, code = KEY_TAB, shift = .NO})
    KeyMapSet(&table, .FOCUS_PREV, 0, {device = .KEYBOARD, code = KEY_TAB, shift = .YES})
    KeyMapSet(&table, .COPY, 0, {device = .KEYBOARD, code = KEY_C, ctrl = .YES})
    KeyMapSet(&table, .ACCEPT, 0, {device = .KEYBOARD, code = KEY_A})
    KeyMapSet(&table, .ACCEPT, 1, {device = .GAMEPAD, code = 7})
    KeyMapSet(&table, .CANCEL, 2, {device = .MOUSE, code = 1})                // a slot that is not the first
    down: Down = {keys = {0 = KEY_TAB}, count = 1}
    testing.expect_value(t, KeyMapActions(&table, probe, &down, {}), Actions{.FOCUS_NEXT})
    testing.expect_value(t, KeyMapActions(&table, probe, &down, {.SHIFT}), Actions{.FOCUS_PREV})
    down = {keys = {0 = KEY_C}, count = 1}
    testing.expect_value(t, KeyMapActions(&table, probe, &down, {}), Actions{})
    testing.expect_value(t, KeyMapActions(&table, probe, &down, {.CTRL}), Actions{.COPY})
    testing.expect_value(t, KeyMapActions(&table, probe, &down, {.CTRL, .ALT, .SHIFT}), Actions{.COPY})     // ANY modifiers do not matter
    // any one of the bindings of an action does it, from any device; two keys together are two actions
    down = {pad = {0 = 7}, pad_count = 1}
    testing.expect_value(t, KeyMapActions(&table, probe, &down, {}), Actions{.ACCEPT})
    down = {keys = {0 = KEY_A, 1 = KEY_C}, count = 2, pad = {0 = 7}, pad_count = 1, mouse = {0 = 1}, mouse_count = 1}
    testing.expect_value(t, KeyMapActions(&table, probe, &down, {.CTRL}), Actions{.ACCEPT, .COPY, .CANCEL})
    // an empty slot never matches, whatever the probe says
    down = {keys = {0 = 0}, count = 1}
    testing.expect_value(t, KeyMapActions(&table, probe, &down, {}), Actions{})
    // clear and set
    KeyMapClear(&table, .ACCEPT)
    down = {keys = {0 = KEY_A}, count = 1}
    testing.expect_value(t, KeyMapActions(&table, probe, &down, {}), Actions{})
    KeyMapSet(&table, .ACCEPT, 9, {device = .KEYBOARD, code = KEY_A})               // a slot that is not there: nothing happens
    testing.expect_value(t, KeyMapActions(&table, probe, &down, {}), Actions{})
    testing.expect_value(t, KeyMapFreeSlot(&table, .ACCEPT), 0)
    KeyMapSet(&table, .ACCEPT, 0, {device = .KEYBOARD, code = KEY_A})
    testing.expect_value(t, KeyMapFreeSlot(&table, .ACCEPT), 1)
    // conflicts: the same binding on another action
    other, found := KeyMapConflict(&table, {device = .KEYBOARD, code = KEY_A}, .CANCEL)
    testing.expect(t, found && other == .ACCEPT)
    _, found = KeyMapConflict(&table, {device = .KEYBOARD, code = KEY_A}, .ACCEPT)
    testing.expect(t, !found, "not with itself")
    _, found = KeyMapConflict(&table, {device = .KEYBOARD, code = KEY_C}, .CANCEL)
    testing.expect(t, !found, "a binding with other modifiers is another binding")
    _, found = KeyMapConflict(&table, {}, .CANCEL)
    testing.expect(t, !found, "an empty binding conflicts with nothing")
}
