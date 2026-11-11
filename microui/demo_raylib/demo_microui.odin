#+private file
package demo_raylib

import "core:fmt"
import rl "vendor:raylib"
import mu "vendor:microui"
import mui ".."
import mui_rl "../raylib"

@(private="package")
state_microui:State = {
    enter,
    exit,
    update,
    draw,
}

bg_colors:mu.Color = {90, 95, 100, 255}
mui_state: mui_rl.MuiState
ctx: ^mu.Context

enter :: proc() {
    ctx = mui_rl.Init(&mui_state)
}

exit :: proc() {
    mui_rl.Cleanup(&mui_state)
}

update :: proc() {
    mui_rl.Update(&mui_state)
    AllWindows(ctx)
}

draw :: proc() {
    rl.ClearBackground(transmute(rl.Color)bg_colors)
    mui_rl.Render(&mui_state)
}

AllWindows :: proc(ctx: ^mu.Context) {
	@static opts := mu.Options{.NO_CLOSE}
	mu.begin(ctx)
	defer mu.end(ctx)
	
	if mu.window(ctx, "Demo Window", {40, 40, 300, 450}, opts) {
		if .ACTIVE in mu.header(ctx, "Window Info") {
			win := mu.get_current_container(ctx)
			mu.layout_row(ctx, {54, -1}, 0)
			mu.label(ctx, "Position:")
			mu.label(ctx, fmt.tprintf("%d, %d", win.rect.x, win.rect.y))
			mu.label(ctx, "Size:")
			mu.label(ctx, fmt.tprintf("%d, %d", win.rect.w, win.rect.h))
		}
		
		if .ACTIVE in mu.header(ctx, "Window Options") {
			mu.layout_row(ctx, {120, 120, 120}, 0)
			for opt in mu.Opt {
				state := opt in opts
				if .CHANGE in mu.checkbox(ctx, fmt.tprintf("%v", opt), &state)  {
					if state {
						opts += {opt}
					} else {
						opts -= {opt}
					}
				}
			}
		}
		
		if .ACTIVE in mu.header(ctx, "Test Buttons", {.EXPANDED}) {
			mu.layout_row(ctx, {86, -110, -1})
			mu.label(ctx, "Test buttons 1:")
			if .SUBMIT in mu.button(ctx, "Button 1") { mui.LogWrite(&mui_state.log, "Pressed button 1") }
			if .SUBMIT in mu.button(ctx, "Button 2") { mui.LogWrite(&mui_state.log, "Pressed button 2") }
			mu.label(ctx, "Test buttons 2:")
			if .SUBMIT in mu.button(ctx, "Button 3") { mui.LogWrite(&mui_state.log, "Pressed button 3") }
			if .SUBMIT in mu.button(ctx, "Button 4") { mui.LogWrite(&mui_state.log, "Pressed button 4") }
		}
		
		if .ACTIVE in mu.header(ctx, "Tree and Text", {.EXPANDED}) {
			mu.layout_row(ctx, {140, -1})
			mu.layout_begin_column(ctx)
			if .ACTIVE in mu.treenode(ctx, "Test 1") {
				if .ACTIVE in mu.treenode(ctx, "Test 1a") {
					mu.label(ctx, "Hello")
					mu.label(ctx, "world")
				}
				if .ACTIVE in mu.treenode(ctx, "Test 1b") {
					if .SUBMIT in mu.button(ctx, "Button 1") { mui.LogWrite(&mui_state.log, "Pressed button 1") }
					if .SUBMIT in mu.button(ctx, "Button 2") { mui.LogWrite(&mui_state.log, "Pressed button 2") }
				}
			}
			if .ACTIVE in mu.treenode(ctx, "Test 2") {
				mu.layout_row(ctx, {53, 53})
				if .SUBMIT in mu.button(ctx, "Button 3") { mui.LogWrite(&mui_state.log, "Pressed button 3") }
				if .SUBMIT in mu.button(ctx, "Button 4") { mui.LogWrite(&mui_state.log, "Pressed button 4") }
				if .SUBMIT in mu.button(ctx, "Button 5") { mui.LogWrite(&mui_state.log, "Pressed button 5") }
				if .SUBMIT in mu.button(ctx, "Button 6") { mui.LogWrite(&mui_state.log, "Pressed button 6") }
			}
			if .ACTIVE in mu.treenode(ctx, "Test 3") {
				@static checks := [3]bool{true, false, true}
				mu.checkbox(ctx, "Checkbox 1", &checks[0])
				mu.checkbox(ctx, "Checkbox 2", &checks[1])
				mu.checkbox(ctx, "Checkbox 3", &checks[2])
				
			}
			mu.layout_end_column(ctx)
			
			mu.layout_begin_column(ctx)
			mu.layout_row(ctx, {-1})
			mu.text(ctx, 
				"Lorem ipsum dolor sit amet, consectetur adipiscing "+
				"elit. Maecenas lacinia, sem eu lacinia molestie, mi risus faucibus "+
				"ipsum, eu varius magna felis a nulla.",
		        )
			mu.layout_end_column(ctx)
		}
		
		if .ACTIVE in mu.header(ctx, "Background Colour", {.EXPANDED}) {
			mu.layout_row(ctx, {-78, -1}, 68)
			mu.layout_begin_column(ctx)
			{
				mu.layout_row(ctx, {46, -1}, 0)
				mu.label(ctx, "Red:");   mui.U8Slider(ctx, &bg_colors.r, 0, 255)
				mu.label(ctx, "Green:"); mui.U8Slider(ctx, &bg_colors.g, 0, 255)
				mu.label(ctx, "Blue:");  mui.U8Slider(ctx, &bg_colors.b, 0, 255)
			}
			mu.layout_end_column(ctx)
			
			r := mu.layout_next(ctx)
			mu.draw_rect(ctx, r, bg_colors)
			mu.draw_box(ctx, mu.expand_rect(r, 1), ctx.style.colors[.BORDER])
			mu.draw_control_text(ctx, fmt.tprintf("#%02x%02x%02x", bg_colors.r, bg_colors.g, bg_colors.b), r, .TEXT, {.ALIGN_CENTER})
		}
	}
	
	if mu.window(ctx, "Log Window", {350, 40, 300, 200}, opts) {
		mu.layout_row(ctx, {-1}, -28)
		mu.begin_panel(ctx, "Log")
		mu.layout_row(ctx, {-1}, -1)
		mu.text(ctx, mui.LogRead(&mui_state.log))
		if mui.LogIsUpdated(&mui_state.log) {
			panel := mu.get_current_container(ctx)
			panel.scroll.y = panel.content_size.y
		}
		mu.end_panel(ctx)
		
		@static buf: [128]byte
		@static buf_len: int
		submitted := false
		mu.layout_row(ctx, {-70, -1})
		if .SUBMIT in mu.textbox(ctx, buf[:], &buf_len) {
			mu.set_focus(ctx, ctx.last_id)
			submitted = true
		}
		if .SUBMIT in mu.button(ctx, "Submit") {
			submitted = true
		}
		if submitted {
			mui.LogWrite(&mui_state.log, string(buf[:buf_len]))
			buf_len = 0
		}
	}
	
	if mu.window(ctx, "Style Window", {350, 250, 300, 240}) {
		@static colors := [mu.Color_Type]string{
			.TEXT         = "text",
	        .SELECTION_BG = "selection",
			.BORDER       = "border",
			.WINDOW_BG    = "window bg",
			.TITLE_BG     = "title bg",
			.TITLE_TEXT   = "title text",
			.PANEL_BG     = "panel bg",
			.BUTTON       = "button",
			.BUTTON_HOVER = "button hover",
			.BUTTON_FOCUS = "button focus",
			.BASE         = "base",
			.BASE_HOVER   = "base hover",
			.BASE_FOCUS   = "base focus",
			.SCROLL_BASE  = "scroll base",
			.SCROLL_THUMB = "scroll thumb",
		}
		
		sw := i32(f32(mu.get_current_container(ctx).body.w) * 0.14)
		mu.layout_row(ctx, {80, sw, sw, sw, sw, -1})
		for label, col in colors {
			mu.label(ctx, label)
			mui.U8Slider(ctx, &ctx.style.colors[col].r, 0, 255)
			mui.U8Slider(ctx, &ctx.style.colors[col].g, 0, 255)
			mui.U8Slider(ctx, &ctx.style.colors[col].b, 0, 255)
			mui.U8Slider(ctx, &ctx.style.colors[col].a, 0, 255)
			mu.draw_rect(ctx, mu.layout_next(ctx), ctx.style.colors[col])
		}
	}
}