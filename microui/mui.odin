package microui_raylib

import "core:unicode/utf8"
import rl "vendor:raylib"
import mu "vendor:microui"

MuiState :: struct {
	mu_ctx: mu.Context,
	log_buf:         [1<<16]byte,
	log_buf_len:     int,
	log_buf_updated: bool,
	
    atlas_buffer:[mu.DEFAULT_ATLAS_WIDTH*mu.DEFAULT_ATLAS_HEIGHT][4]u8,
	atlas_texture: rl.Texture2D,
}

mui_state:MuiState


init :: proc() -> ^mu.Context {
	for alpha, i in mu.default_atlas_alpha {
		mui_state.atlas_buffer[i] = {0xff, 0xff, 0xff, alpha}
	}
		
	image := rl.Image{
		data = cast(rawptr)&mui_state.atlas_buffer[0],
		width   = mu.DEFAULT_ATLAS_WIDTH,
		height  = mu.DEFAULT_ATLAS_HEIGHT,
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	}
	mui_state.atlas_texture = rl.LoadTextureFromImage(image)

    ctx := &mui_state.mu_ctx
	mu.init(ctx)
	
	ctx.text_width = mu.default_atlas_text_width
	ctx.text_height = mu.default_atlas_text_height

    return ctx
}

cleanup :: proc(){
    rl.UnloadTexture(mui_state.atlas_texture)
}

update :: proc(ctx: ^mu.Context){
    { // text input
        text_input: [512]byte = ---
        text_input_offset := 0
        for text_input_offset < len(text_input) {
            ch := rl.GetCharPressed()
            if ch == 0 {
                break
            }
            b, w := utf8.encode_rune(ch)
            copy(text_input[text_input_offset:], b[:w])
            text_input_offset += w
        }
        mu.input_text(ctx, string(text_input[:text_input_offset]))
    }
    
    // mouse coordinates
    mouse_pos := [2]i32{rl.GetMouseX(), rl.GetMouseY()}
    mu.input_mouse_move(ctx, mouse_pos.x, mouse_pos.y)
    mu.input_scroll(ctx, 0, i32(rl.GetMouseWheelMove() * -30))
    
    // mouse buttons
    @static buttons_to_key := [?]struct{
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
    @static keys_to_check := [?]struct{
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

render :: proc(ctx: ^mu.Context) {
	render_texture :: proc(rect: mu.Rect, pos: [2]i32, color: mu.Color) {
		source := rl.Rectangle{
			f32(rect.x),
			f32(rect.y),
			f32(rect.w),
			f32(rect.h),
		}
		position := rl.Vector2{f32(pos.x), f32(pos.y)}
		
		rl.DrawTextureRec(mui_state.atlas_texture, source, position, transmute(rl.Color)color)
	}
	
	rl.BeginScissorMode(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight())
	defer rl.EndScissorMode()
	
	command_backing: ^mu.Command
	for variant in mu.next_command_iterator(ctx, &command_backing) {
		switch cmd in variant {
		case ^mu.Command_Text:
			pos := [2]i32{cmd.pos.x, cmd.pos.y}
			for ch in cmd.str do if ch&0xc0 != 0x80 {
				r := min(int(ch), 127)
				rect := mu.default_atlas[mu.DEFAULT_ATLAS_FONT + r]
				render_texture(rect, pos, cmd.color)
				pos.x += rect.w
			}
		case ^mu.Command_Rect:
			rl.DrawRectangle(cmd.rect.x, cmd.rect.y, cmd.rect.w, cmd.rect.h, transmute(rl.Color)cmd.color)
		case ^mu.Command_Icon:
			rect := mu.default_atlas[cmd.id]
			x := cmd.rect.x + (cmd.rect.w - rect.w)/2
			y := cmd.rect.y + (cmd.rect.h - rect.h)/2
			render_texture(rect, {x, y}, cmd.color)
		case ^mu.Command_Clip:
			rl.EndScissorMode()
			rl.BeginScissorMode(cmd.rect.x, cmd.rect.y, cmd.rect.w, cmd.rect.h)
		case ^mu.Command_Jump: 
			unreachable()
		}
	}
}


u8_slider :: proc(ctx: ^mu.Context, val: ^u8, lo, hi: u8) -> (res: mu.Result_Set) {
	mu.push_id(ctx, uintptr(val))
	
	@static tmp: mu.Real
	tmp = mu.Real(val^)
	res = mu.slider(ctx, &tmp, mu.Real(lo), mu.Real(hi), 0, "%.0f", {.ALIGN_CENTER})
	val^ = u8(tmp)
	mu.pop_id(ctx)
	return
}

write_log :: proc(str: string) {
	mui_state.log_buf_len += copy(mui_state.log_buf[mui_state.log_buf_len:], str)
	mui_state.log_buf_len += copy(mui_state.log_buf[mui_state.log_buf_len:], "\n")
	mui_state.log_buf_updated = true
}

is_log_buffer_updated :: proc() -> bool {
    if mui_state.log_buf_updated {
        mui_state.log_buf_updated = false
        return true
    }
    return false
}

read_log :: proc() -> string {
	return string(mui_state.log_buf[:mui_state.log_buf_len])
}

reset_log :: proc() {
	mui_state.log_buf_updated = true
	mui_state.log_buf_len = 0
}
