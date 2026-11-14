// Loads resources by name through web_build.ResourceLoad and shows them: textures, a font and a text file.
// Desktop only: raylib in a browser needs emscripten, which is outside of what web_build does (the karl2d demo has the web build).
package demo_raylib

import "core:os"
import "core:strings"
import rl "vendor:raylib"
import web_build ".."

// The resource folder relative to the executable. Change it with -define:RESOURCE_PATH=...
DEMO_RESOURCE_PATH :: #config(RESOURCE_PATH, "../assets")

TEXTURE_NAMES :: [4]string{
	"textures/dust_4_strip.png",
	"textures/player_sheet.png",
	"textures/palette_journey.png",
	"textures/tileset_template.png",
}

main :: proc() {
	working_dir, err: = os.get_working_directory(context.allocator)
	defer delete(working_dir)
	// Return user to original directory in case project change it
	defer os.change_directory(working_dir)
	if err != nil {
		return
	}
	executable_directory:string
	executable_directory, err = os.get_executable_directory(context.allocator)
	defer delete(executable_directory)
	if err != nil {
		return
	}
	os.change_directory(executable_directory)

	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1280, 720, "web_build resources")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	resources: web_build.ResourceSet = {directory = DEMO_RESOURCE_PATH}

	names: [4]string = TEXTURE_NAMES
	textures: [4]rl.Texture2D
	texture_ok: [4]bool
	for name, i in names {
		data, ok := web_build.ResourceLoad(resources, name)
		if !ok { continue }
		// the file type is the extension, the image has its own copy of the pixels
		image: rl.Image = rl.LoadImageFromMemory(".png", raw_data(data.data), i32(len(data.data)))
		web_build.ResourceFree(data)
		textures[i] = rl.LoadTextureFromImage(image)
		rl.UnloadImage(image)
		texture_ok[i] = rl.IsTextureValid(textures[i])
	}

	font: rl.Font = rl.GetFontDefault()
	font_data, font_found := web_build.ResourceLoad(resources, "fonts/pixellocale-v-1-4.ttf")
	if font_found {
		font = rl.LoadFontFromMemory(".ttf", raw_data(font_data.data), i32(len(font_data.data)), 24, nil, 0)
		web_build.ResourceFree(font_data)
	}

	lines: [dynamic]string
	defer delete(lines)
	csv, csv_found := web_build.ResourceLoad(resources, "data/localization.csv")
	text_source: string
	if csv_found {
		text_source = strings.clone(string(csv.data))
		web_build.ResourceFree(csv)
		remaining: string = text_source
		for line in strings.split_lines_iterator(&remaining) {
			append(&lines, line)
		}
	}
	defer delete(text_source)

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		rl.ClearBackground({32, 36, 48, 255})
		rl.DrawTextEx(font, strings.clone_to_cstring(strings.concatenate({"files from ", DEMO_RESOURCE_PATH}, context.temp_allocator), context.temp_allocator), {20, 16}, 28, 1, rl.WHITE)

		x: f32 = 20
		for name, i in names {
			if !texture_ok[i] {
				rl.DrawText(strings.clone_to_cstring(strings.concatenate({"missing ", name}, context.temp_allocator), context.temp_allocator), i32(x), 80, 18, rl.RED)
				continue
			}
			width: f32 = f32(textures[i].width)
			height: f32 = f32(textures[i].height)
			scale: f32 = min(280 / width, 280 / height, 16)
			target: rl.Rectangle = {x, 80, width * scale, height * scale}
			rl.DrawRectangleRec({target.x - 2, target.y - 2, target.width + 4, target.height + 4}, {70, 76, 96, 255})
			rl.DrawTexturePro(textures[i], {0, 0, width, height}, target, {}, 0, rl.WHITE)
			rl.DrawText(strings.clone_to_cstring(name, context.temp_allocator), i32(x), i32(target.y + target.height + 8), 16, rl.LIGHTGRAY)
			x += 300
		}

		rl.DrawTextEx(font, "data/localization.csv", {20, 420}, 22, 1, rl.WHITE)
		for line, i in lines {
			if i >= 8 { break }
			rl.DrawTextEx(font, strings.clone_to_cstring(line, context.temp_allocator), {20, 460 + f32(i) * 24}, 20, 1, rl.LIGHTGRAY)
		}
		rl.EndDrawing()
		free_all(context.temp_allocator)
	}

	for texture, i in textures {
		if texture_ok[i] { rl.UnloadTexture(texture) }
	}
	if font_found { rl.UnloadFont(font) }
}
