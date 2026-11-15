package microui_kit

// microui over the demo kit (odin_utilities/demo_kit): the same glue as raylib/ and karl2d/, but through kit.Context, so a demo written
// against the kit shows microui on any backend and a script can click its widgets.
//
//     state: MuiState
//     mu_ctx := Init(&state, ctx)           // in the init of the demo
//     Update(&state, ctx)                   // before mu.begin: feeds the input of the kit
//     ... build the windows with mu.window / mu.button ...
//     Render(&state, ctx)                   // draws the commands
//     Cleanup(&state, ctx)

import "core:slice"
import mu "vendor:microui"
import mui ".."
import kit "../../demo_kit"

// Everything the glue needs, place it in a global or your own struct
MuiState :: struct {
    ctx: mu.Context,
    log: mui.MuiLog,
    atlas_buffer: [mui.ATLAS_PIXELS][4]u8,
    atlas_texture: kit.Texture,
}

Init :: proc(state: ^MuiState, kctx: ^kit.Context) -> ^mu.Context {
    mui.AtlasToRGBA(&state.atlas_buffer)
    state.atlas_texture = kit.TextureFromPixels(kctx, mu.DEFAULT_ATLAS_WIDTH, mu.DEFAULT_ATLAS_HEIGHT, slice.to_bytes(state.atlas_buffer[:]))

    ctx: ^mu.Context = &state.ctx
    mu.init(ctx)
    ctx.text_width = mu.default_atlas_text_width
    ctx.text_height = mu.default_atlas_text_height
    return ctx
}

Cleanup :: proc(state: ^MuiState, kctx: ^kit.Context) {
    kit.TextureUnload(kctx, state.atlas_texture)
}

// Feed the input of the kit to microui, call before mu.begin
Update :: proc(state: ^MuiState, kctx: ^kit.Context) {
    ctx: ^mu.Context = &state.ctx
    input: ^kit.Input = &kctx.input

    // text input
    mu.input_text(ctx, kit.InputText(input))

    // mouse
    mouse: [2]i32 = {i32(input.mouse_position.x), i32(input.mouse_position.y)}
    mu.input_mouse_move(ctx, mouse.x, mouse.y)
    mu.input_scroll(ctx, 0, i32(input.mouse_wheel * -30))

    buttons: [3]struct { kit_button: kit.MouseButton, mu_button: mu.Mouse } = {
        {.LEFT, .LEFT},
        {.RIGHT, .RIGHT},
        {.MIDDLE, .MIDDLE},
    }
    for button in buttons {
        if kit.MousePressed(input, button.kit_button) {
            mu.input_mouse_down(ctx, mouse.x, mouse.y, button.mu_button)
        } else if kit.MouseReleased(input, button.kit_button) {
            mu.input_mouse_up(ctx, mouse.x, mouse.y, button.mu_button)
        }
    }

    // keyboard
    keys: [9]struct { kit_key: kit.Key, mu_key: mu.Key } = {
        {.LEFT_SHIFT, .SHIFT},
        {.RIGHT_SHIFT, .SHIFT},
        {.LEFT_CTRL, .CTRL},
        {.RIGHT_CTRL, .CTRL},
        {.LEFT_ALT, .ALT},
        {.RIGHT_ALT, .ALT},
        {.ENTER, .RETURN},
        {.ENTER, .RETURN},
        {.BACKSPACE, .BACKSPACE},
    }
    for key in keys {
        if kit.KeyPressed(input, key.kit_key) {
            mu.input_key_down(ctx, key.mu_key)
        } else if kit.KeyReleased(input, key.kit_key) {
            mu.input_key_up(ctx, key.mu_key)
        }
    }
}

// Draw the commands of microui
Render :: proc(state: ^MuiState, kctx: ^kit.Context) {
    ctx: ^mu.Context = &state.ctx
    kit.ClipBegin(kctx, {0, 0, kctx.screen.x, kctx.screen.y})
    defer kit.ClipEnd(kctx)

    command_backing: ^mu.Command
    for variant in mu.next_command_iterator(ctx, &command_backing) {
        switch cmd in variant {
        case ^mu.Command_Text:
            pos: [2]i32 = {cmd.pos.x, cmd.pos.y}
            for ch in cmd.str do if ch & 0xc0 != 0x80 {
                r: int = min(int(ch), 127)
                rect: mu.Rect = mu.default_atlas[mu.DEFAULT_ATLAS_FONT + r]
                renderTexture(state, kctx, rect, pos, cmd.color)
                pos.x += rect.w
            }
        case ^mu.Command_Rect:
            kit.DrawRect(kctx, {f32(cmd.rect.x), f32(cmd.rect.y), f32(cmd.rect.w), f32(cmd.rect.h)}, transmute(kit.Color)cmd.color)
        case ^mu.Command_Icon:
            rect: mu.Rect = mu.default_atlas[cmd.id]
            x: i32 = cmd.rect.x + (cmd.rect.w - rect.w) / 2
            y: i32 = cmd.rect.y + (cmd.rect.h - rect.h) / 2
            renderTexture(state, kctx, rect, {x, y}, cmd.color)
        case ^mu.Command_Clip:
            kit.ClipEnd(kctx)
            kit.ClipBegin(kctx, {f32(cmd.rect.x), f32(cmd.rect.y), f32(cmd.rect.w), f32(cmd.rect.h)})
        case ^mu.Command_Jump:
            unreachable()
        }
    }
}

@(private)
renderTexture :: proc(state: ^MuiState, kctx: ^kit.Context, rect: mu.Rect, pos: [2]i32, color: mu.Color) {
    source: kit.Rect = {f32(rect.x), f32(rect.y), f32(rect.w), f32(rect.h)}
    kit.DrawTextureRect(kctx, state.atlas_texture, source, {f32(pos.x), f32(pos.y), source.z, source.w}, {}, 0, transmute(kit.Color)color)
}
