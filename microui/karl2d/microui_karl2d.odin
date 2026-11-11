package microui_karl2d

import "core:slice"
import "core:unicode/utf8"
import "../../karl2d"
import mu "vendor:microui"
import mui ".."

// Everything the glue needs, place it in a global or your own struct
MuiState :: struct {
    ctx: mu.Context,
    log: mui.MuiLog,
    atlas_buffer: [mui.ATLAS_PIXELS][4]u8,
    atlas_texture: karl2d.Texture,
}

// Call after karl2d.init
Init :: proc(state: ^MuiState) -> ^mu.Context {
    mui.AtlasToRGBA(&state.atlas_buffer)

    // Karl2D default point filtering keeps the atlas sharp
    state.atlas_texture = karl2d.load_texture_from_bytes_raw(
        slice.reinterpret([]u8, state.atlas_buffer[:]),
        mu.DEFAULT_ATLAS_WIDTH,
        mu.DEFAULT_ATLAS_HEIGHT,
        .RGBA_8_Norm,
    )

    ctx: ^mu.Context = &state.ctx
    mu.init(ctx)
    ctx.text_width = mu.default_atlas_text_width
    ctx.text_height = mu.default_atlas_text_height
    return ctx
}

Cleanup :: proc(state: ^MuiState) {
    karl2d.destroy_texture(state.atlas_texture)
}

// Feed karl2d input to microui, call before mu.begin
Update :: proc(state: ^MuiState) {
    ctx: ^mu.Context = &state.ctx

    // text input
    text_input: [512]byte = ---
    text_input_offset: int = 0
    for typed in karl2d.get_typed_runes() {
        // Skip control characters
        if typed < 32 || typed == 127 {
            continue
        }
        b, w: = utf8.encode_rune(typed)
        if text_input_offset + w > len(text_input) {
            break
        }
        copy(text_input[text_input_offset:], b[:w])
        text_input_offset += w
    }
    mu.input_text(ctx, string(text_input[:text_input_offset]))

    // mouse coordinates
    mouse_position: karl2d.Vec2 = karl2d.get_mouse_position()
    mouse_pos: [2]i32 = {i32(mouse_position.x), i32(mouse_position.y)}
    mu.input_mouse_move(ctx, mouse_pos.x, mouse_pos.y)
    mu.input_scroll(ctx, 0, i32(karl2d.get_mouse_wheel_delta() * -30))

    // mouse buttons
    @(static) buttons_to_key := [?]struct{
        k2_button: karl2d.Mouse_Button,
        mu_button: mu.Mouse,
    }{
        {.Left, .LEFT},
        {.Right, .RIGHT},
        {.Middle, .MIDDLE},
    }
    for button in buttons_to_key {
        if karl2d.mouse_button_went_down(button.k2_button) {
            mu.input_mouse_down(ctx, mouse_pos.x, mouse_pos.y, button.mu_button)
        } else if karl2d.mouse_button_went_up(button.k2_button) {
            mu.input_mouse_up(ctx, mouse_pos.x, mouse_pos.y, button.mu_button)
        }
    }

    // keyboard, repeat makes holding backspace erase text
    @(static) keys_to_check := [?]struct{
        k2_key: karl2d.Keyboard_Key,
        mu_key: mu.Key,
    }{
        {.Left_Shift,    .SHIFT},
        {.Right_Shift,   .SHIFT},
        {.Left_Control,  .CTRL},
        {.Right_Control, .CTRL},
        {.Left_Alt,      .ALT},
        {.Right_Alt,     .ALT},
        {.Enter,         .RETURN},
        {.NP_Enter,      .RETURN},
        {.Backspace,     .BACKSPACE},
    }
    for key in keys_to_check {
        if karl2d.key_went_down(key.k2_key, allow_repeat = true) {
            mu.input_key_down(ctx, key.mu_key)
        } else if karl2d.key_went_up(key.k2_key) {
            mu.input_key_up(ctx, key.mu_key)
        }
    }
}

// Draw microui commands
Render :: proc(state: ^MuiState) {
    ctx: ^mu.Context = &state.ctx
    screen_size: karl2d.Vec2 = karl2d.get_screen_size()

    karl2d.set_scissor_rect(nil)
    defer karl2d.set_scissor_rect(nil)

    command_backing: ^mu.Command
    for variant in mu.next_command_iterator(ctx, &command_backing) {
        switch cmd in variant {
        case ^mu.Command_Text:
            pos: [2]i32 = {cmd.pos.x, cmd.pos.y}
            for ch in cmd.str do if ch&0xc0 != 0x80 {
                r: int = min(int(ch), 127)
                rect: mu.Rect = mu.default_atlas[mu.DEFAULT_ATLAS_FONT + r]
                RenderTexture(state, rect, pos, cmd.color)
                pos.x += rect.w
            }
        case ^mu.Command_Rect:
            rect: karl2d.Rect = {f32(cmd.rect.x), f32(cmd.rect.y), f32(cmd.rect.w), f32(cmd.rect.h)}
            karl2d.draw_rect(rect, transmute(karl2d.Color)cmd.color)
        case ^mu.Command_Icon:
            rect: mu.Rect = mu.default_atlas[cmd.id]
            x: i32 = cmd.rect.x + (cmd.rect.w - rect.w) / 2
            y: i32 = cmd.rect.y + (cmd.rect.h - rect.h) / 2
            RenderTexture(state, rect, {x, y}, cmd.color)
        case ^mu.Command_Clip:
            // microui uses a huge rectangle for "no clipping", keep scissor inside of the screen
            left: f32 = clamp(f32(cmd.rect.x), 0, screen_size.x)
            top: f32 = clamp(f32(cmd.rect.y), 0, screen_size.y)
            right: f32 = clamp(f32(cmd.rect.x) + f32(cmd.rect.w), 0, screen_size.x)
            bottom: f32 = clamp(f32(cmd.rect.y) + f32(cmd.rect.h), 0, screen_size.y)
            karl2d.set_scissor_rect(karl2d.Rect{left, top, right - left, bottom - top})
        case ^mu.Command_Jump:
            unreachable()
        }
    }
}

@(private="file")
RenderTexture :: proc(state: ^MuiState, rect: mu.Rect, pos: [2]i32, color: mu.Color) {
    source: karl2d.Rect = {f32(rect.x), f32(rect.y), f32(rect.w), f32(rect.h)}
    position: karl2d.Vec2 = {f32(pos.x), f32(pos.y)}
    karl2d.draw_texture_rect(state.atlas_texture, source, position, tint = transmute(karl2d.Color)color)
}
