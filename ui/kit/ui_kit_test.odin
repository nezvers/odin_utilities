#+build !js
package ui_kit

import "core:sync"
import "core:testing"
import ui ".."
import kit "../../demo_kit"

// The tests run on several threads and two of them rebind the one table of the kit
@(private = "file")
table_lock: sync.Mutex

@(private = "file")
actionsOf :: proc(keys: kit.KeySet, mouse: kit.MouseButtons = {}) -> ui.Actions {
    ctx: kit.Context
    ctx.input.keys_pressed = keys
    ctx.input.keys_down = keys
    ctx.input.mouse_pressed = mouse
    return InputFrom(&ctx).actions
}

// One test: the table of the kit is a global
@(test)
test_the_default_hotkeys_are_the_keys_that_were_fixed_before_and_can_be_rebound :: proc(t: ^testing.T) {
    sync.mutex_lock(&table_lock)
    defer sync.mutex_unlock(&table_lock)
    KeyMapOf()^ = KeyMapDefault()
    defer KeyMapOf()^ = KeyMapDefault()
    testing.expect_value(t, actionsOf({.ENTER}), ui.Actions{.ACCEPT})
    testing.expect_value(t, actionsOf({.SPACE}), ui.Actions{.ACCEPT, .SELECT})
    testing.expect_value(t, actionsOf({.ESCAPE}), ui.Actions{.CANCEL})
    testing.expect_value(t, actionsOf({.TAB}), ui.Actions{.FOCUS_NEXT})
    testing.expect_value(t, actionsOf({.TAB, .LEFT_SHIFT}), ui.Actions{.FOCUS_PREV})
    testing.expect_value(t, actionsOf({.UP}), ui.Actions{.UP})
    testing.expect_value(t, actionsOf({.LEFT}), ui.Actions{.LEFT})
    testing.expect_value(t, actionsOf({.LEFT, .LEFT_SHIFT}), ui.Actions{.LEFT})                // Shift extends a selection: the arrow is still the arrow
    testing.expect_value(t, actionsOf({.PAGE_DOWN}), ui.Actions{.PAGE_DOWN})
    testing.expect_value(t, actionsOf({.HOME}), ui.Actions{.HOME})
    testing.expect_value(t, actionsOf({.F2}), ui.Actions{.RENAME})
    testing.expect_value(t, actionsOf({.C}), ui.Actions{})
    testing.expect_value(t, actionsOf({.C, .LEFT_CTRL}), ui.Actions{.COPY})
    testing.expect_value(t, actionsOf({.X, .LEFT_CTRL}), ui.Actions{.CUT})
    testing.expect_value(t, actionsOf({.V, .LEFT_CTRL}), ui.Actions{.PASTE})
    testing.expect_value(t, actionsOf({.A, .LEFT_CTRL}), ui.Actions{.SELECT_ALL})
    testing.expect_value(t, actionsOf({.D, .LEFT_CTRL}), ui.Actions{.DUPLICATE})
    testing.expect_value(t, actionsOf({.Z, .LEFT_CTRL}), ui.Actions{.UNDO})
    testing.expect_value(t, actionsOf({.Z, .LEFT_CTRL, .LEFT_SHIFT}), ui.Actions{.REDO})
    testing.expect_value(t, actionsOf({.Y, .LEFT_CTRL}), ui.Actions{.REDO})
    // Alt and a letter are the commands of the editors, Alt and an arrow turn and are no arrow; with Ctrl as well they are arrows
    testing.expect_value(t, actionsOf({.I, .LEFT_ALT}), ui.Actions{.INVERT})
    testing.expect_value(t, actionsOf({.R, .RIGHT_ALT}), ui.Actions{.REVERSE})
    testing.expect_value(t, actionsOf({.D, .LEFT_ALT}), ui.Actions{.REPEAT})
    testing.expect_value(t, actionsOf({.LEFT, .LEFT_ALT}), ui.Actions{.ROTATE_LEFT})
    testing.expect_value(t, actionsOf({.RIGHT, .LEFT_ALT}), ui.Actions{.ROTATE_RIGHT})
    testing.expect_value(t, actionsOf({.LEFT, .LEFT_ALT, .LEFT_CTRL}), ui.Actions{.LEFT})
    testing.expect_value(t, actionsOf({.D, .LEFT_ALT, .LEFT_CTRL}), ui.Actions{.DUPLICATE})

    // rebinding: Copy on K (with Ctrl), the old key goes with the old binding; a mouse button does Cancel; the accept key is gone
    table: ^ui.KeyMap = KeyMapOf()
    ui.KeyMapClear(table, .COPY)
    ui.KeyMapSet(table, .COPY, 0, {device = .KEYBOARD, code = u16(kit.Key.K), ctrl = .YES})
    testing.expect_value(t, actionsOf({.C, .LEFT_CTRL}), ui.Actions{})
    testing.expect_value(t, actionsOf({.K, .LEFT_CTRL}), ui.Actions{.COPY})
    testing.expect_value(t, actionsOf({}, {.RIGHT}), ui.Actions{})
    ui.KeyMapSet(table, .CANCEL, 1, {device = .MOUSE, code = u16(kit.MouseButton.RIGHT)})
    testing.expect_value(t, actionsOf({}, {.RIGHT}), ui.Actions{.CANCEL})
    testing.expect_value(t, actionsOf({.ESCAPE}), ui.Actions{.CANCEL})
    ui.KeyMapClear(table, .ACCEPT)
    testing.expect_value(t, actionsOf({.ENTER}), ui.Actions{})
    testing.expect_value(t, actionsOf({.SPACE}), ui.Actions{.SELECT})
}

@(test)
test_the_glyphs_of_the_kit_name_keys_and_pad_buttons_and_take_a_texture_when_set :: proc(t: ^testing.T) {
    GlyphTextures = {}
    defer GlyphTextures = {}
    glyph: ui.Glyph = GlyphOf(nil, {device = .KEYBOARD, code = u16(kit.Key.SPACE)})
    testing.expect_value(t, glyph.shape, ui.GlyphShape.KEY)
    testing.expect_value(t, glyph.label, "Space")
    testing.expect_value(t, GlyphOf(nil, {device = .KEYBOARD, code = u16(kit.Key.N5)}).label, "5")
    testing.expect_value(t, GlyphOf(nil, {device = .KEYBOARD, code = u16(kit.Key.Q)}).label, "Q")
    testing.expect_value(t, GlyphOf(nil, {device = .MOUSE, code = u16(kit.MouseButton.RIGHT)}).label, "RMB")
    a: ui.Glyph = GlyphOf(nil, {device = .GAMEPAD, code = u16(kit.PadButton.FACE_DOWN)})
    testing.expect_value(t, a.shape, ui.GlyphShape.FACE)
    testing.expect_value(t, a.label, "A")
    testing.expect_value(t, a.texture, u32(0))
    testing.expect_value(t, GlyphOf(nil, {device = .GAMEPAD, code = u16(kit.PadButton.LEFT_TRIGGER)}).shape, ui.GlyphShape.TRIGGER)
    testing.expect_value(t, GlyphOf(nil, {device = .GAMEPAD, code = u16(kit.PadButton.DPAD_UP)}).label, "U")
    testing.expect_value(t, GlyphOf(nil, {}).shape, ui.GlyphShape.KEY)
    GlyphTextures[.FACE_DOWN] = {kit.Texture(9), {0, 0, 32, 32}}
    a = GlyphOf(nil, {device = .GAMEPAD, code = u16(kit.PadButton.FACE_DOWN)})
    testing.expect_value(t, a.texture, u32(9))
    testing.expect_value(t, a.source, ui.Rect{0, 0, 32, 32})
    testing.expect_value(t, a.label, "A")                       // the label stays: a program that draws no texture still has a name
    testing.expect_value(t, GlyphOf(nil, {device = .GAMEPAD, code = u16(kit.PadButton.FACE_UP)}).texture, u32(0))
}

@(test)
test_the_pressed_binding_is_the_pad_then_the_key_then_the_mouse_and_a_pad_button_does_a_ui_action :: proc(t: ^testing.T) {
    sync.mutex_lock(&table_lock)
    defer sync.mutex_unlock(&table_lock)
    input: kit.Input
    testing.expect_value(t, BindingPressed(&input), ui.Binding{})
    input.keys_pressed = {.K}
    testing.expect_value(t, BindingPressed(&input), ui.Binding{device = .KEYBOARD, code = u16(kit.Key.K)})
    input.mouse_pressed = {.LEFT}
    testing.expect_value(t, BindingPressed(&input).device, ui.InputDevice.KEYBOARD)
    input.keys_pressed = {}
    testing.expect_value(t, BindingPressed(&input), ui.Binding{device = .MOUSE, code = u16(kit.MouseButton.LEFT)})
    input.pad_pressed = {.START}
    testing.expect_value(t, BindingPressed(&input), ui.Binding{device = .GAMEPAD, code = u16(kit.PadButton.START)})
    // a table binding on a pad button works through the probe of the kit
    KeyMapOf()^ = KeyMapDefault()
    defer KeyMapOf()^ = KeyMapDefault()
    ui.KeyMapSet(KeyMapOf(), .ACCEPT, 3, {device = .GAMEPAD, code = u16(kit.PadButton.START)})
    ctx: kit.Context
    ctx.input.pad_pressed = {.START}
    testing.expect_value(t, InputFrom(&ctx).actions, ui.Actions{.ACCEPT})
    ctx.input.pad_pressed = {.BACK}
    testing.expect_value(t, InputFrom(&ctx).actions, ui.Actions{})
}
