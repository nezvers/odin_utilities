package microui_raylib

import "core:unicode/utf8"
import rl "vendor:raylib"
import mu "vendor:microui"
import mui ".."

// Everything the glue needs, place it in a global or your own struct
MuiState :: struct {
    ctx: mu.Context,
    log: mui.MuiLog,
    atlas_buffer: [mui.ATLAS_PIXELS][4]u8,
    atlas_texture: rl.Texture2D,
}

// Call after the window is created
Init :: proc(state: ^MuiState) -> ^mu.Context {
    mui.AtlasToRGBA(&state.atlas_buffer)

    image: rl.Image = {
        data = cast(rawptr)&state.atlas_buffer[0],
        width = mu.DEFAULT_ATLAS_WIDTH,
        height = mu.DEFAULT_ATLAS_HEIGHT,
        mipmaps = 1,
        format = .UNCOMPRESSED_R8G8B8A8,
    }
    state.atlas_texture = rl.LoadTextureFromImage(image)

    ctx: ^mu.Context = &state.ctx
    mu.init(ctx)
    ctx.text_width = mu.default_atlas_text_width
    ctx.text_height = mu.default_atlas_text_height
    return ctx
}

Cleanup :: proc(state: ^MuiState) {
    rl.UnloadTexture(state.atlas_texture)
}

// Feed raylib input to microui, call before mu.begin
Update :: proc(state: ^MuiState) {
    ctx: ^mu.Context = &state.ctx

    // text input
    text_input: [512]byte = ---
    text_input_offset: int = 0
    for text_input_offset < len(text_input) {
        ch: rune = rl.GetCharPressed()
        if ch == 0 {
            break
        }
        b, w: = utf8.encode_rune(ch)
        copy(text_input[text_input_offset:], b[:w])
        text_input_offset += w
    }
    mu.input_text(ctx, string(text_input[:text_input_offset]))

    // mouse coordinates
    mouse_pos: [2]i32 = {rl.GetMouseX(), rl.GetMouseY()}
    mu.input_mouse_move(ctx, mouse_pos.x, mouse_pos.y)
    mu.input_scroll(ctx, 0, i32(rl.GetMouseWheelMove() * -30))

    // mouse buttons
    @(static) buttons_to_key := [?]struct{
        rl_button: rl.MouseButton,
        mu_button: mu.Mouse,
    }{
        {.LEFT, .LEFT},
        {.RIGHT, .RIGHT},
        {.MIDDLE, .MIDDLE},
    }
    for button in buttons_to_key {
        if rl.IsMouseButtonPressed(button.rl_button) {
            mu.input_mouse_down(ctx, mouse_pos.x, mouse_pos.y, button.mu_button)
        } else if rl.IsMouseButtonReleased(button.rl_button) {
            mu.input_mouse_up(ctx, mouse_pos.x, mouse_pos.y, button.mu_button)
        }
    }

    // keyboard
    @(static) keys_to_check := [?]struct{
        rl_key: rl.KeyboardKey,
        mu_key: mu.Key,
    }{
        {.LEFT_SHIFT,    .SHIFT},
        {.RIGHT_SHIFT,   .SHIFT},
        {.LEFT_CONTROL,  .CTRL},
        {.RIGHT_CONTROL, .CTRL},
        {.LEFT_ALT,      .ALT},
        {.RIGHT_ALT,     .ALT},
        {.ENTER,         .RETURN},
        {.KP_ENTER,      .RETURN},
        {.BACKSPACE,     .BACKSPACE},
    }
    for key in keys_to_check {
        if rl.IsKeyPressed(key.rl_key) {
            mu.input_key_down(ctx, key.mu_key)
        } else if rl.IsKeyReleased(key.rl_key) {
            mu.input_key_up(ctx, key.mu_key)
        }
    }
}

// Draw microui commands, call between rl.BeginDrawing and rl.EndDrawing
Render :: proc(state: ^MuiState) {
    ctx: ^mu.Context = &state.ctx

    rl.BeginScissorMode(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight())
    defer rl.EndScissorMode()

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
            rl.DrawRectangle(cmd.rect.x, cmd.rect.y, cmd.rect.w, cmd.rect.h, transmute(rl.Color)cmd.color)
        case ^mu.Command_Icon:
            rect: mu.Rect = mu.default_atlas[cmd.id]
            x: i32 = cmd.rect.x + (cmd.rect.w - rect.w) / 2
            y: i32 = cmd.rect.y + (cmd.rect.h - rect.h) / 2
            RenderTexture(state, rect, {x, y}, cmd.color)
        case ^mu.Command_Clip:
            rl.EndScissorMode()
            rl.BeginScissorMode(cmd.rect.x, cmd.rect.y, cmd.rect.w, cmd.rect.h)
        case ^mu.Command_Jump:
            unreachable()
        }
    }
}

@(private="file")
RenderTexture :: proc(state: ^MuiState, rect: mu.Rect, pos: [2]i32, color: mu.Color) {
    source: rl.Rectangle = {f32(rect.x), f32(rect.y), f32(rect.w), f32(rect.h)}
    position: rl.Vector2 = {f32(pos.x), f32(pos.y)}
    rl.DrawTextureRec(state.atlas_texture, source, position, transmute(rl.Color)color)
}
