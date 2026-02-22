#+private file
package demo

import "core:fmt"
import rl "vendor:raylib"
Vector2 :: rl.Vector2
Rectangle :: rl.Rectangle
vec2i::[2]i32
rectf::[4]f32

import stbrp "vendor:stb/rect_pack"
stb_Rect:: stbrp.Rect

import "core:unicode/utf8"
import "core:strings"
import "core:slice"

@(private="package")
baking_state :State = {
    init,
    finit,
    nil,
    draw,
}

ATLAS_SIZE :vec2i: {512, 512}
Sprite :: struct {
    size: Vector2,
    tex_pos:[]Vector2,
}

// The letters to extract from the font
LETTERS_IN_FONT :: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz1234567890?!&.,_:[]-+"
FONT_HEIGHT :: 16
font_source:rl.Font
font_packed:rl.Font
letter_rects:[]rectf
letter_cstrings:[]cstring

// Used as dynamic atlas
render_texture:rl.RenderTexture
player_texture: rl.Texture2D
// Holds data about source texture
player_sprite_source:[]rectf = {
    {0, 0,16,16},
    {16,0,16,16},
    {32,0,16,16},
    {48,0,16,16},
    {64,0,16,16},
    {80,0,16,16},
    {96,0,16,16},
}
// Holds data about generated atlas texture, assigned to spawned instances
player_sprite_packed:[]rectf


reset_atlas :: proc() {
	rl.UnloadRenderTexture(render_texture)
	render_texture = rl.LoadRenderTexture(ATLAS_SIZE.x, ATLAS_SIZE.y)
}

pack_rectangles :: proc(rc: ^stbrp.Context, rect_list:[]rectf)->(ok:bool) {
    // Prepare rectangle list for packing
    pack_rects:[dynamic]stb_Rect
    defer delete(pack_rects)

    for i:int = 0; i < len(rect_list); i += 1 {
        rect:rectf = rect_list[i]
        append(&pack_rects, stb_Rect {
            id = cast(i32)i,
            w = stbrp.Coord(rect.z),
            h = stbrp.Coord(rect.w),
        })
    }

    // Packing
    rect_pack_res := stbrp.pack_rects(rc, raw_data(pack_rects), i32(len(pack_rects)))
    if rect_pack_res != 1 {
        fmt.printf("Failed packing \n")
        return false
    }

    // Read packed positions
    for i:int = 0; i < len(pack_rects); i += 1 {
        rect:^stb_Rect = &pack_rects[i]
        id:i32 = rect.id
        tex_pos:[2]f32 = {cast(f32)rect.x, cast(f32)rect.y}
        rect_list[id].xy = tex_pos
    }
    return true
}

prepare_sprite_rects :: proc() {
    // set size for packed rectangles
    player_sprite_packed = make_slice([]rectf, len(player_sprite_source))
    for i:int = 0; i < len(player_sprite_source); i += 1 {
        player_sprite_packed[i].zw = player_sprite_source[i].zw
    }
}

prepare_font_rects :: proc(font_in:^rl.Font, font_out:^rl.Font) {
    rune_data :: struct {
        glyph:rl.GlyphInfo,
        rect:rectf,
    }
    glyph_map:map[rune]rune_data // = make_map(map[rune]rune_data)
    defer delete(glyph_map)
    // Cache all glyphs in the source font
    for i:i32 = 0; i < font_in.glyphCount; i += 1 {
        glyph:rl.GlyphInfo = font_in.glyphs[i]
        rect:rectf = transmute(rectf)font_in.recs[i]
        glyph_map[glyph.value] = {glyph, rect}
    }

    // Collect rectangles for letters
    letters:[]rune = utf8.string_to_runes(LETTERS_IN_FONT)
    defer delete(letters)
    letter_rects = make([]rectf, len(letters))
    glyphs := make([]rl.GlyphInfo, len(letter_rects))
    
    for i:int = 0; i < len(letters); i += 1 {
        value, ok: = glyph_map[letters[i]]
        if !ok {
            continue
        }
        glyphs[i] = {
            value = value.glyph.value,
            offsetX = value.glyph.offsetX,
            offsetY = value.glyph.offsetY,
            advanceX = value.glyph.advanceX,
        }
        letter_rects[i] = value.rect
    }

    font_out^ = {
        baseSize = font_source.baseSize,
        glyphCount = i32(len(glyphs)),
		glyphPadding = 0,
		texture = render_texture.texture,
		recs = raw_data(transmute([]Rectangle)letter_rects),
		glyphs = raw_data(glyphs),
    }



    letter_strings:[]string = make_slice([]string, len(letters))
    defer delete(letter_strings)
    // Raylib works with cstrings
    letter_cstrings = make_slice([]cstring, len(letters))

    for i:int = 0; i < len(letters); i += 1 {
        letter_strings[i] = utf8.runes_to_string(letters[i:i+1])
        letter_cstrings[i] = strings.clone_to_cstring(letter_strings[i])

        cs:cstring = letter_cstrings[i]
        size:Vector2 = rl.MeasureTextEx(font_in^, cs, cast(f32)font_in.baseSize, 0)
        letter_rects[i].zw = size
    }
    // delete each entry at the end
    defer {
        for i:int = 0; i < len(letters); i += 1 {
            delete(letter_strings[i])
        }
    }
}

init :: proc(){
    reset_atlas()
    player_texture = rl.LoadTexture("../assets/textures/player_sheet.png")
    font_source = rl.LoadFont("../assets/fonts/font.ttf")

    prepare_sprite_rects()
    prepare_font_rects(&font_source, &font_packed)

    // Init packer
    rc: stbrp.Context
    rc_nodes: [ATLAS_SIZE.x]stbrp.Node
    stbrp.init_target(&rc, ATLAS_SIZE.x, ATLAS_SIZE.x, raw_data(rc_nodes[:]), ATLAS_SIZE.x)

    // Optimally pack everything in one go
    if !pack_rectangles(&rc, player_sprite_packed[:]) {
        assert(false, "Failed packing")
    }
    if !pack_rectangles(&rc, letter_rects[:]) {
        assert(false, "Failed packing")
    }

    // Raylib's render texture is flipped vertically
    // Use temporary first then draw it on target render texture
    temp_render_texture: = rl.LoadRenderTexture(ATLAS_SIZE.x, ATLAS_SIZE.y)
    defer rl.UnloadRenderTexture(temp_render_texture)

    // Draw sprite tiles to render target
    rl.BeginTextureMode(temp_render_texture)
    // Render player sprites on generated atlas
    for i:int = 0; i < len(player_sprite_source); i += 1 {
        source_rect:rectf = player_sprite_source[i]
        dest_pos:Vector2 = player_sprite_packed[i].xy
        rl.DrawTextureRec(player_texture, transmute(Rectangle)source_rect, dest_pos, rl.WHITE)
    }

    for i:int = 0; i < len(letter_rects); i += 1 {
        rl.DrawTextEx(font_source, letter_cstrings[i], letter_rects[i].xy, cast(f32)font_source.baseSize, 0, rl.WHITE)
    }

    rl.EndTextureMode()

    // Transfer to target render_texture to flip it correclty
    rl.BeginTextureMode(render_texture)
    rl.DrawTexture(temp_render_texture.texture, 0, 0, rl.WHITE)
    rl.EndTextureMode()
}

finit :: proc() {
	rl.UnloadRenderTexture(render_texture)
    rl.UnloadTexture(player_texture)
    rl.UnloadFont(font_source)
    
    delete(player_sprite_packed)
    delete(letter_rects)
    delete(slice.from_ptr(font_packed.glyphs, int(font_packed.glyphCount)))
    for i:int = 0; i < len(letter_cstrings); i += 1 {
        delete(letter_cstrings[i])
    }
    delete(letter_cstrings)
}

draw :: proc(){
    rect:Rectangle = {10, 10, cast(f32)ATLAS_SIZE.x, cast(f32)ATLAS_SIZE.y}
    source_rect:Rectangle = {0, 0, rect.width, rect.height}
    dest_rect:Rectangle = {10, 10, rect.width, rect.height}

    rl.DrawRectangleLinesEx(rect, 1, rl.BLACK)
    rl.DrawRectangleRec(rect, rl.LIGHTGRAY)
    rl.DrawTexturePro(render_texture.texture, source_rect, dest_rect, {0,0}, 0.0, rl.WHITE)

    // Test player tex_pos
    // Spawned instance
    rect_player:Rectangle = transmute(Rectangle)player_sprite_packed[0]
    rl.DrawRectangleLinesEx({530, 10, rect_player.width, rect_player.height}, 1, rl.BLACK)
    rl.DrawTextureRec(render_texture.texture, rect_player, {530, 10}, rl.WHITE)
}